// 認証。ローカルのID・パスワードと、OIDC（Google・Entra ID・Keycloak など）の2本立て。
// OIDC は .env に issuer / client id / secret を書くだけで有効になる。
import crypto from 'node:crypto';
import { db, nowIso } from '../db/index.js';
import { config, oidcEnabled } from '../config.js';
import { id, hashPassword, verifyPassword } from '../lib/util.js';
import { ensurePrivateLog } from '../lib/private-log.js';

export function parseCookies(req) {
  const out = {};
  for (const part of (req.headers.cookie || '').split(';')) {
    const i = part.indexOf('=');
    if (i > 0) out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}

export async function currentUser(req) {
  const token = parseCookies(req).cutlog_session;
  if (!token) return null;
  const row = await db.get(
    `SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id
      WHERE s.token = ? AND s.expires_at > ? AND u.disabled = 0`,
    [token, nowIso()],
  );
  return row || null;
}

export function setSessionCookie(res, token) {
  const maxAge = config.auth.sessionDays * 24 * 60 * 60;
  const bits = [
    `cutlog_session=${token}`, 'HttpOnly', 'SameSite=Lax', 'Path=/', `Max-Age=${maxAge}`,
  ];
  if (config.auth.cookieSecure) bits.push('Secure');
  res.setHeader('Set-Cookie', bits.join('; '));
}

export async function createSession(res, userId, userAgent) {
  const token = crypto.randomBytes(24).toString('base64url');
  const expires = new Date(Date.now() + config.auth.sessionDays * 864e5).toISOString();
  await db.run('INSERT INTO sessions (token, user_id, user_agent, created_at, expires_at) VALUES (?,?,?,?,?)',
    [token, userId, (userAgent || '').slice(0, 200), nowIso(), expires]);
  setSessionCookie(res, token);
  return token;
}

export function requireAuth(req, res, next) {
  currentUser(req).then((user) => {
    if (!user) return res.status(401).json({ error: 'ログインしてください' });
    req.user = user;
    return next();
  }).catch(next);
}

export function requireAdmin(req, res, next) {
  if (!req.user?.is_admin) return res.status(403).json({ error: '管理者だけが使えます' });
  return next();
}

export function publicUser(u) {
  return {
    id: u.id,
    username: u.username,
    displayName: u.display_name,
    email: u.email || null,
    isAdmin: !!u.is_admin,
    provider: u.auth_provider,
  };
}

async function isFirstUser() {
  const row = await db.get('SELECT COUNT(*) AS n FROM users');
  return Number(row.n) === 0;
}

export async function createLocalUser({ username, password, displayName, email }) {
  const first = await isFirstUser();
  const admin = first || config.instance.admins.includes(username);
  const uid = id('u_');
  await db.run(
    `INSERT INTO users (id, username, display_name, email, password_hash, auth_provider, is_admin, created_at, updated_at)
     VALUES (?,?,?,?,?,?,?,?,?)`,
    [uid, username, displayName || username, email || null, hashPassword(password), 'local', admin ? 1 : 0,
      nowIso(), nowIso()],
  );
  await db.run('INSERT INTO reminders (user_id, mode, updated_at) VALUES (?,?,?)', [uid, 'off', nowIso()]);
  await ensurePrivateLog(uid);
  return db.get('SELECT * FROM users WHERE id = ?', [uid]);
}

export async function loginLocal(username, password) {
  const u = await db.get('SELECT * FROM users WHERE username = ?', [username]);
  if (!u || u.disabled) return null;
  if (!verifyPassword(password, u.password_hash)) return null;
  return u;
}

// ── OIDC ───────────────────────────────────────────────
let oidcConfigPromise = null;

async function getOidcConfig() {
  if (!oidcEnabled) return null;
  if (!oidcConfigPromise) {
    oidcConfigPromise = (async () => {
      const client = await import('openid-client');
      return client.discovery(
        new URL(config.auth.oidc.issuer),
        config.auth.oidc.clientId,
        config.auth.oidc.clientSecret,
      );
    })().catch((err) => {
      console.error('[oidc] 設定を読めませんでした:', err.message);
      oidcConfigPromise = null;
      return null;
    });
  }
  return oidcConfigPromise;
}

export const oidcState = new Map(); // state -> { verifier, nonce, createdAt }

// 認証の入口は誰でも叩けるので、古い state を捨てないと際限なく溜まる。
const OIDC_STATE_TTL_MS = 10 * 60 * 1000;
const OIDC_STATE_MAX = 5000;

function pruneOidcState() {
  const now = Date.now();
  for (const [k, v] of oidcState) {
    if (now - v.createdAt > OIDC_STATE_TTL_MS) oidcState.delete(k);
  }
  // それでも多いときは、古いものから捨てる（Mapは入れた順に並ぶ）
  while (oidcState.size > OIDC_STATE_MAX) {
    const oldest = oidcState.keys().next().value;
    if (oldest === undefined) break;
    oidcState.delete(oldest);
  }
}

export async function oidcAuthUrl() {
  const cfg = await getOidcConfig();
  if (!cfg) return null;
  const client = await import('openid-client');
  const verifier = client.randomPKCECodeVerifier();
  const challenge = await client.calculatePKCECodeChallenge(verifier);
  const state = client.randomState();
  const nonce = client.randomNonce();
  pruneOidcState();
  oidcState.set(state, { verifier, nonce, createdAt: Date.now() });
  const url = client.buildAuthorizationUrl(cfg, {
    redirect_uri: `${config.baseUrl}/api/auth/oidc/callback`,
    scope: config.auth.oidc.scope,
    code_challenge: challenge,
    code_challenge_method: 'S256',
    state,
    nonce,
  });
  return url.href;
}

export async function oidcCallback(currentUrl, state) {
  const cfg = await getOidcConfig();
  if (!cfg) throw new Error('OIDCが設定されていません');
  const saved = oidcState.get(state);
  if (!saved) throw new Error('stateが一致しません');
  oidcState.delete(state);
  if (Date.now() - saved.createdAt > OIDC_STATE_TTL_MS) throw new Error('時間が経ちすぎました。もう一度お試しください');
  const client = await import('openid-client');
  const tokens = await client.authorizationCodeGrant(cfg, currentUrl, {
    pkceCodeVerifier: saved.verifier,
    expectedNonce: saved.nonce,
    expectedState: state,
  });
  const claims = tokens.claims();
  const email = String(claims.email || '').toLowerCase();
  const domain = email.split('@')[1] || '';
  const allow = config.auth.oidc.allowedDomains.map((d) => d.toLowerCase());
  if (allow.length && !allow.includes(domain)) {
    throw new Error(`このドメイン（${domain || '不明'}）は許可されていません`);
  }
  const sub = String(claims.sub);
  let user = await db.get('SELECT * FROM users WHERE auth_provider = ? AND external_id = ?', ['oidc', sub]);
  // ★メールアドレスだけで既にある利用者へ結び付けるのは、そのアドレスの確認が取れているときに限る。
  // 確認の取れていないアドレスを許すと、他人のアドレスを名乗ってその利用者になれてしまう。
  if (!user && email && claims.email_verified !== false) {
    user = await db.get('SELECT * FROM users WHERE email = ?', [email]);
  }
  if (!user) {
    if (!config.auth.oidc.autoCreateUsers) throw new Error('このアカウントは登録されていません');
    const first = await isFirstUser();
    const base = (claims.preferred_username || email.split('@')[0] || `user${Date.now()}`)
      .replace(/[^a-zA-Z0-9._-]/g, '').slice(0, 30) || `user${Date.now()}`;
    let username = base;
    let n = 1;
    // eslint-disable-next-line no-await-in-loop
    while (await db.get('SELECT 1 AS ok FROM users WHERE username = ?', [username])) {
      username = `${base}${n}`;
      n += 1;
    }
    const uid = id('u_');
    await db.run(
      `INSERT INTO users (id, username, display_name, email, auth_provider, external_id, is_admin, created_at, updated_at)
       VALUES (?,?,?,?,?,?,?,?,?)`,
      [uid, username, claims.name || username, email || null, 'oidc', sub, first ? 1 : 0, nowIso(), nowIso()],
    );
    await db.run('INSERT INTO reminders (user_id, mode, updated_at) VALUES (?,?,?)', [uid, 'off', nowIso()]);
    await ensurePrivateLog(uid);
    user = await db.get('SELECT * FROM users WHERE id = ?', [uid]);
  } else if (user.auth_provider !== 'oidc') {
    await db.run('UPDATE users SET auth_provider = ?, external_id = ?, updated_at = ? WHERE id = ?',
      ['oidc', sub, nowIso(), user.id]);
  }
  return user;
}

export { oidcEnabled };
