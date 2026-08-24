import express from 'express';
import multer from 'multer';
import archiver from 'archiver';
import webpush from 'web-push';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { db, nowIso } from '../db/index.js';
import { config, paths, oidcEnabled } from '../config.js';
import { storage } from '../storage/index.js';
import {
  requireAuth, requireAdmin, currentUser, createSession, createLocalUser, loginLocal,
  publicUser, parseCookies, oidcAuthUrl, oidcCallback,
} from '../auth/index.js';
import {
  id, inviteCode, hashPassword, verifyPassword, ffprobe, makeThumb, makeSquare, localDateOf, sha256File, asyncRoute,
} from '../lib/util.js';
import { enqueue, getJob } from '../jobs/queue.js';
import { ensurePrivateLog, isPrivate } from '../lib/private-log.js';
import { normalizeStyle, DEFAULT_STYLE } from '../lib/render-style.js';
import { fcmReady, sendToToken } from '../lib/fcm.js';

export const api = express.Router();

const upload = multer({ dest: paths.tmp, limits: { fileSize: config.media.maxUploadMb * 1024 * 1024 } });

// ── アップロードの受け取り ──────────────────────────────
// multer が投げるエラーは、そのままにすると 500 と英語の文（File too large）で返る。
// 他のAPIと同じように、状態コードと日本語の文をここで決める。
// 文にはサーバの中の様子（パス・呼び出し履歴）を入れない。
const UPLOAD_ERRORS = {
  LIMIT_FILE_SIZE: {
    status: 413,
    message: () => `ファイルが大きすぎます。1件あたり${config.media.maxUploadMb}MBまで上げられます。`
      + '短く撮り直すか、画質を下げてから送ってください。',
  },
  LIMIT_UNEXPECTED_FILE: {
    status: 400,
    message: () => 'ファイルの項目名が違います。file という名前で1件だけ送ってください。',
  },
  LIMIT_FILE_COUNT: { status: 400, message: () => 'ファイルは1件だけ送ってください。' },
  LIMIT_PART_COUNT: { status: 400, message: () => '送られた項目が多すぎます。file と meta だけ送ってください。' },
  LIMIT_FIELD_COUNT: { status: 400, message: () => '送られた項目が多すぎます。file と meta だけ送ってください。' },
  LIMIT_FIELD_KEY: { status: 400, message: () => '項目の名前が長すぎます。file と meta だけ送ってください。' },
  LIMIT_FIELD_VALUE: { status: 413, message: () => 'meta が長すぎます。短くしてから送ってください。' },
};

function uploadFile(field = 'file') {
  const single = upload.single(field);
  return (req, res, next) => single(req, res, (err) => {
    if (!err) return next();
    // 途中まで書けた一時ファイルを残さない
    if (req.file?.path) fsp.unlink(req.file.path).catch(() => {});
    const known = UPLOAD_ERRORS[err.code];
    if (known) return res.status(known.status).json({ error: known.message() });
    // multipart として読めなかったとき（項目の見出しが壊れている・途中で切れた など）
    console.error('[upload]', err.code || err.name, err.message);
    return res.status(400).json({
      error: '送られたデータを読めませんでした。multipart/form-data で file と meta を送ってください。',
    });
  });
}

// ── 相手のIPを決める ────────────────────────────────────
// ★X-Forwarded-For は送ってくる側が自由に書ける。逆向きのプロキシの後ろに置いていると
// 分かっているとき（TRUST_PROXY=true）だけ読む。そうでなければ接続元のアドレスだけを使う。
// これを分けないと、ヘッダを書き換えるだけで監査ログのIPを偽れて、回数制限も回り込める。
export function clientIp(req) {
  if (config.trustProxy) {
    const fwd = req.headers['x-forwarded-for'];
    const first = (Array.isArray(fwd) ? fwd[0] : fwd || '').toString().split(',')[0].trim();
    if (first) return first.slice(0, 60);
  }
  return (req.socket?.remoteAddress || '').toString().slice(0, 60);
}

// ── 監査ログ ────────────────────────────────────────────
async function audit(req, action, target, detail) {
  await db.run('INSERT INTO audit_log (id, user_id, action, target, detail, ip, created_at) VALUES (?,?,?,?,?,?,?)',
    [id('a_'), req.user?.id || null, action, target || null,
      detail ? JSON.stringify(detail).slice(0, 1000) : null,
      clientIp(req), nowIso()])
    .catch(() => {});
}

// ── 書き込みの回数制限（1IPあたり） ──────────────────────
const hits = new Map();
api.use((req, res, next) => {
  if (req.method === 'GET' || req.method === 'HEAD') return next();
  const key = clientIp(req) || 'x';
  const now = Date.now();
  const win = hits.get(key)?.filter((t) => now - t < 60_000) || [];
  win.push(now);
  hits.set(key, win);
  if (win.length > config.limits.writePerMinute) {
    return res.status(429).json({ error: 'リクエストが多すぎます。少し待ってください' });
  }
  return next();
});

// ── インスタンスの情報 ──────────────────────────────────
api.get('/config', (req, res) => {
  res.json({
    instanceName: config.instance.name,
    localAuth: config.auth.localEnabled,
    openSignup: config.auth.openSignup,
    oidc: oidcEnabled ? { enabled: true, label: config.auth.oidc.buttonLabel } : { enabled: false },
    vapidPublicKey: config.push.publicKey || null,
    // アプリ（iOS / Android）へ通知を出せる設えになっているか
    fcmEnabled: fcmReady(),
    cutSecondsDefault: config.media.cutSecondsDefault,
    mapTileUrl: config.map.tileUrl,
    mapCredit: config.map.credit,
    maxUploadMb: config.media.maxUploadMb,
    renderEnabled: config.ffmpeg.enabled,
  });
});

// 死活。★SELECT 1 はテーブルへ触らないので、DBのファイルが壊れていても通ってしまう。
// 実際にあるテーブルへ軽く問い合わせて、読めることまで確かめる。
// 保存先（ストレージ）はここで確かめない。死活は速く返ることが大事で、
// S3互換の保存先だと外への通信が入って遅くなり、監視の間隔で毎回それを行うのは重いためである。
// 保存先が書けるかどうかは、アップロードと書き出しの経路で分かる。
api.get('/healthz', async (req, res) => {
  try {
    const row = await db.get('SELECT COUNT(*) AS n FROM schema_migrations');
    if (!row || !Number.isFinite(Number(row.n))) throw new Error('schema_migrations を読めません');
    return res.json({
      ok: true, db: db.driver, storage: storage.driver, migrations: Number(row.n), time: nowIso(),
    });
  } catch (err) {
    console.error('[healthz] データベースを読めません:', err.message);
    return res.status(503).json({
      ok: false,
      db: db.driver,
      storage: storage.driver,
      error: 'データベースを読めません。保存先のファイルと接続の設定を確かめてください',
      time: nowIso(),
    });
  }
});

// ── 認証 ───────────────────────────────────────────────
api.post('/auth/signup', asyncRoute(async (req, res) => {
  if (!config.auth.localEnabled) return res.status(403).json({ error: 'このサーバはIDとパスワードでの登録を止めています' });
  const { username, password, displayName, email } = req.body || {};
  const count = await db.get('SELECT COUNT(*) AS n FROM users');
  const first = Number(count.n) === 0;
  if (!config.auth.openSignup && !first) return res.status(403).json({ error: '新規登録は閉じています' });
  if (!/^[a-zA-Z0-9._-]{3,30}$/.test(username || '')) {
    return res.status(400).json({ error: 'ユーザー名は英数字と . _ - で3〜30文字にしてください' });
  }
  if (String(password || '').length < 8) return res.status(400).json({ error: 'パスワードは8文字以上にしてください' });
  if (await db.get('SELECT 1 AS ok FROM users WHERE username = ?', [username])) {
    return res.status(409).json({ error: 'そのユーザー名は使われています' });
  }
  const user = await createLocalUser({ username, password, displayName, email });
  await createSession(res, user.id, req.headers['user-agent']);
  return res.json({ user: publicUser(user) });
}));

// ── ログインの連続失敗を止める ────────────────────────────
// 1分あたりの書き込み制限だけでは、1つのアカウントへ何万回も試せてしまう。
// 利用者名ごと・IPごとに失敗を数え、続けて外したらしばらく受け付けない。
const LOGIN_LOCK_MS = 15 * 60 * 1000;
// アカウントごとは厳しく、IPごとは緩くする。
// 同じ事務所から全員が1つのIPで出ていく形が普通なので、IPを厳しくすると無関係な人まで入れなくなる。
const LOGIN_FAIL_MAX = { u: 10, i: 50 };
const loginFails = new Map();

function loginFailKeys(req, username) {
  const ip = clientIp(req) || 'x';
  return [`u:${String(username).toLowerCase()}`, `i:${ip}`];
}

function loginLocked(keys) {
  const now = Date.now();
  for (const k of keys) {
    const rec = loginFails.get(k);
    if (!rec) continue;
    if (now - rec.last > LOGIN_LOCK_MS) { loginFails.delete(k); continue; }
    if (rec.n >= LOGIN_FAIL_MAX[k[0]]) return Math.ceil((LOGIN_LOCK_MS - (now - rec.last)) / 60000);
  }
  return 0;
}

function noteLoginFail(keys) {
  const now = Date.now();
  for (const k of keys) {
    const rec = loginFails.get(k);
    if (!rec || now - rec.last > LOGIN_LOCK_MS) loginFails.set(k, { n: 1, last: now });
    else { rec.n += 1; rec.last = now; }
  }
  // 覚えっぱなしにしない（古い記録を捨てる）
  if (loginFails.size > 5000) {
    for (const [k, v] of loginFails) if (now - v.last > LOGIN_LOCK_MS) loginFails.delete(k);
  }
}

api.post('/auth/login', asyncRoute(async (req, res) => {
  if (!config.auth.localEnabled) return res.status(403).json({ error: 'IDとパスワードでのログインは止まっています' });
  const username = req.body?.username || '';
  const keys = loginFailKeys(req, username);
  const waitMin = loginLocked(keys);
  if (waitMin) {
    await audit(req, 'auth.login.locked', null, { username: String(username).slice(0, 60) });
    return res.status(429).json({ error: `ログインの失敗が続いたので、${waitMin}分ほど待ってからやり直してください` });
  }
  const user = await loginLocal(username, req.body?.password || '');
  if (!user) {
    noteLoginFail(keys);
    await audit(req, 'auth.login.fail', null, { username: String(username).slice(0, 60) });
    return res.status(401).json({ error: 'ユーザー名かパスワードが違います' });
  }
  for (const k of keys) loginFails.delete(k);
  await createSession(res, user.id, req.headers['user-agent']);
  return res.json({ user: publicUser(user) });
}));

api.post('/auth/logout', asyncRoute(async (req, res) => {
  const token = parseCookies(req).cutlog_session;
  if (token) await db.run('DELETE FROM sessions WHERE token = ?', [token]);
  const clear = ['cutlog_session=', 'HttpOnly', 'SameSite=Lax', 'Path=/', 'Max-Age=0'];
  if (config.auth.cookieSecure) clear.push('Secure');
  res.setHeader('Set-Cookie', clear.join('; '));
  res.json({ ok: true });
}));

api.get('/auth/oidc/start', asyncRoute(async (req, res) => {
  const url = await oidcAuthUrl();
  if (!url) return res.status(400).send('OIDCが設定されていません');
  return res.redirect(url);
}));

api.get('/auth/oidc/callback', asyncRoute(async (req, res) => {
  try {
    const full = new URL(req.originalUrl, config.baseUrl);
    const user = await oidcCallback(full, req.query.state);
    await createSession(res, user.id, req.headers['user-agent']);
    res.redirect('/');
  } catch (err) {
    res.status(400).send(`ログインできませんでした: ${err.message}`);
  }
}));

api.get('/me', asyncRoute(async (req, res) => {
  const u = await currentUser(req);
  if (!u) return res.status(401).json({ error: 'ログインしてください' });
  const reminder = await db.get('SELECT * FROM reminders WHERE user_id = ?', [u.id]);
  const priv = await ensurePrivateLog(u.id);
  const defaultLogId = await resolveDefaultLog(u);
  let renderStyle = DEFAULT_STYLE;
  try { if (u.render_prefs) renderStyle = normalizeStyle(JSON.parse(u.render_prefs)); } catch { /* 既定のまま */ }
  return res.json({
    user: publicUser(u), reminder, privateLogId: priv.id, defaultLogId, renderStyle,
  });
}));

api.patch('/me', requireAuth, asyncRoute(async (req, res) => {
  const name = String(req.body?.displayName || req.user.display_name).slice(0, 60);
  await db.run('UPDATE users SET display_name = ?, updated_at = ? WHERE id = ?', [name, nowIso(), req.user.id]);

  // 既定の記録先。null を渡すとプライベートへ戻る。
  if (req.body?.defaultLogId !== undefined) {
    const wanted = req.body.defaultLogId;
    if (wanted === null || wanted === '') {
      await db.run('UPDATE users SET default_log_id = NULL WHERE id = ?', [req.user.id]);
    } else {
      if (!await memberOf(String(wanted), req.user.id)) {
        return res.status(400).json({ error: 'そのログのメンバーではありません' });
      }
      await db.run('UPDATE users SET default_log_id = ? WHERE id = ?', [String(wanted), req.user.id]);
    }
  }
  if (req.body?.renderStyle !== undefined) {
    await db.run('UPDATE users SET render_prefs = ? WHERE id = ?',
      [JSON.stringify(normalizeStyle(req.body.renderStyle)), req.user.id]);
  }

  const fresh = await db.get('SELECT * FROM users WHERE id = ?', [req.user.id]);
  let renderStyle = DEFAULT_STYLE;
  try { if (fresh.render_prefs) renderStyle = normalizeStyle(JSON.parse(fresh.render_prefs)); } catch { /* 既定のまま */ }
  return res.json({
    user: publicUser(fresh),
    defaultLogId: await resolveDefaultLog(fresh),
    renderStyle,
  });
}));

// ── ログ（グループ） ────────────────────────────────────
async function memberOf(logId, userId) {
  return db.get('SELECT * FROM memberships WHERE log_id = ? AND user_id = ?', [logId, userId]);
}

// 行き先を指定せずに撮ったカットが入るログ。
// 利用者が選んだログを使い、選んでいない・もう入れないなら、プライベートへ入る。
async function resolveDefaultLog(user) {
  if (user.default_log_id && await memberOf(user.default_log_id, user.id)) return user.default_log_id;
  const priv = await ensurePrivateLog(user.id);
  return priv.id;
}

function requireMember(req, res, next) {
  const logId = req.params.logId || req.body?.logId;
  memberOf(logId, req.user.id).then((m) => {
    if (!m) return res.status(403).json({ error: 'このログのメンバーではありません' });
    req.membership = m;
    return next();
  }).catch(next);
}

api.get('/logs', requireAuth, asyncRoute(async (req, res) => {
  // 前からいる利用者にも、ここで一度だけプライベートのログができる
  await ensurePrivateLog(req.user.id);
  const rows = await db.all(
    `SELECT l.*, m.role,
            (SELECT u.display_name FROM users u WHERE u.id = l.owner_id) AS owner_name,
            (SELECT COUNT(*) FROM memberships mm WHERE mm.log_id = l.id) AS member_count,
            (SELECT COUNT(*) FROM cuts c WHERE c.log_id = l.id AND c.deleted_at IS NULL) AS cut_count,
            (SELECT c.id FROM cuts c WHERE c.log_id = l.id AND c.deleted_at IS NULL
              ORDER BY c.taken_at DESC LIMIT 1) AS latest_cut_id,
            (SELECT c.thumb_key FROM cuts c WHERE c.log_id = l.id AND c.deleted_at IS NULL
              ORDER BY c.taken_at DESC LIMIT 1) AS latest_thumb_key,
            (SELECT c.taken_at FROM cuts c WHERE c.log_id = l.id AND c.deleted_at IS NULL
              ORDER BY c.taken_at DESC LIMIT 1) AS latest_taken_at
       FROM logs l JOIN memberships m ON m.log_id = l.id
      WHERE m.user_id = ?
      ORDER BY CASE WHEN l.kind = 'private' THEN 0 ELSE 1 END, l.created_at DESC`, [req.user.id],
  );
  // 一覧に「最後に撮ったカット」の見本を出すため、あればその小さい画像の場所を添える。
  res.json({
    logs: rows.map((l) => ({
      ...l,
      ownerName: l.owner_name || null,
      latestCutId: l.latest_cut_id || null,
      latestThumbUrl: l.latest_thumb_key ? `/api/media/${l.latest_cut_id}?thumb=1` : null,
      latestTakenAt: l.latest_taken_at || null,
    })),
  });
}));

api.post('/logs', requireAuth, asyncRoute(async (req, res) => {
  const name = String(req.body?.name || '').trim().slice(0, 80) || 'マイログ';
  const seconds = Math.min(30, Math.max(1, Number(req.body?.cutSeconds) || config.media.cutSecondsDefault));
  const lid = id('l_');
  await db.run(
    'INSERT INTO logs (id, name, owner_id, invite_code, cut_seconds, created_at, updated_at) VALUES (?,?,?,?,?,?,?)',
    [lid, name, req.user.id, inviteCode(), seconds, nowIso(), nowIso()],
  );
  await db.run('INSERT INTO memberships (log_id, user_id, role, joined_at) VALUES (?,?,?,?)',
    [lid, req.user.id, 'owner', nowIso()]);
  await audit(req, 'log.create', lid, { name });
  res.json({ log: await db.get('SELECT * FROM logs WHERE id = ?', [lid]) });
}));

api.post('/logs/join', requireAuth, asyncRoute(async (req, res) => {
  const code = String(req.body?.code || '').trim().toUpperCase();
  const log = await db.get('SELECT * FROM logs WHERE invite_code = ?', [code]);
  if (!log || isPrivate(log)) return res.status(404).json({ error: 'その招待コードは見つかりません' });
  if (!await memberOf(log.id, req.user.id)) {
    await db.run('INSERT INTO memberships (log_id, user_id, role, joined_at) VALUES (?,?,?,?)',
      [log.id, req.user.id, 'member', nowIso()]);
    await audit(req, 'log.join', log.id);
  }
  return res.json({ log });
}));

api.get('/logs/:logId', requireAuth, requireMember, asyncRoute(async (req, res) => {
  const log = await db.get('SELECT * FROM logs WHERE id = ?', [req.params.logId]);
  const members = await db.all(
    `SELECT u.id, u.username, u.display_name, m.role FROM memberships m
       JOIN users u ON u.id = m.user_id WHERE m.log_id = ? ORDER BY m.joined_at`, [log.id],
  );
  const days = await db.all(
    `SELECT local_date AS date, COUNT(*) AS n FROM cuts
      WHERE log_id = ? AND deleted_at IS NULL GROUP BY local_date ORDER BY local_date DESC`, [log.id],
  );
  res.json({ log, members, days, role: req.membership.role });
}));

api.patch('/logs/:logId', requireAuth, requireMember, asyncRoute(async (req, res) => {
  if (req.membership.role !== 'owner') return res.status(403).json({ error: 'オーナーだけが変えられます' });
  const log = await db.get('SELECT * FROM logs WHERE id = ?', [req.params.logId]);
  const name = String(req.body?.name ?? log.name).trim().slice(0, 80) || log.name;
  const seconds = Math.min(30, Math.max(1, Number(req.body?.cutSeconds ?? log.cut_seconds)));
  await db.run('UPDATE logs SET name = ?, cut_seconds = ?, updated_at = ? WHERE id = ?',
    [name, seconds, nowIso(), log.id]);
  return res.json({ log: await db.get('SELECT * FROM logs WHERE id = ?', [log.id]) });
}));

api.post('/logs/:logId/invite/rotate', requireAuth, requireMember, asyncRoute(async (req, res) => {
  if (req.membership.role !== 'owner') return res.status(403).json({ error: 'オーナーだけが変えられます' });
  const target = await db.get('SELECT * FROM logs WHERE id = ?', [req.params.logId]);
  if (isPrivate(target)) return res.status(400).json({ error: 'プライベートには誰も招待できません' });
  const code = inviteCode();
  await db.run('UPDATE logs SET invite_code = ?, updated_at = ? WHERE id = ?', [code, nowIso(), req.params.logId]);
  res.json({ inviteCode: code });
}));

api.delete('/logs/:logId/members/:userId', requireAuth, requireMember, asyncRoute(async (req, res) => {
  const target = await db.get('SELECT * FROM logs WHERE id = ?', [req.params.logId]);
  if (isPrivate(target)) return res.status(400).json({ error: 'プライベートからは抜けられません' });
  const self = req.params.userId === req.user.id;
  if (!self && req.membership.role !== 'owner') return res.status(403).json({ error: 'オーナーだけが外せます' });
  await db.run('DELETE FROM memberships WHERE log_id = ? AND user_id = ?', [req.params.logId, req.params.userId]);
  res.json({ ok: true });
}));

// ── カット ─────────────────────────────────────────────
function cutRow(c) {
  return {
    id: c.id,
    logId: c.log_id,
    userId: c.user_id,
    author: c.display_name || null,
    kind: c.kind,
    url: `/api/media/${c.id}`,
    thumbUrl: c.thumb_key ? `/api/media/${c.id}?thumb=1` : null,
    mime: c.mime,
    bytes: c.bytes,
    durationMs: c.duration_ms,
    width: c.width,
    height: c.height,
    facing: c.facing,
    source: c.source,
    takenAt: c.taken_at,
    tzOffset: c.tz_offset,
    localDate: c.local_date,
    note: c.note,
    hidden: !!Number(c.hidden || 0),
    commentCount: Number(c.comment_count || 0),
    // 撮った場所。分からないときは null のままにする。
    lat: c.lat ?? null,
    lon: c.lon ?? null,
    placeAccuracy: c.place_accuracy ?? null,
    tags: c.tags ? String(c.tags).split(',').filter(Boolean) : [],
    checksum: c.checksum,
    createdAt: c.created_at,
    updatedAt: c.updated_at,
  };
}

api.get('/logs/:logId/cuts', requireAuth, requireMember, asyncRoute(async (req, res) => {
  const { from, to, date, author, tag, q } = req.query;
  let sql = `SELECT c.*, u.display_name,
                (SELECT COUNT(*) FROM comments cm WHERE cm.cut_id = c.id AND cm.deleted_at IS NULL) AS comment_count
               FROM cuts c JOIN users u ON u.id = c.user_id
              WHERE c.log_id = ? AND c.deleted_at IS NULL`;
  const args = [req.params.logId];
  if (date) { sql += ' AND c.local_date = ?'; args.push(date); }
  if (from) { sql += ' AND c.local_date >= ?'; args.push(from); }
  if (to) { sql += ' AND c.local_date <= ?'; args.push(to); }
  if (author) { sql += ' AND c.user_id = ?'; args.push(author); }
  if (tag) { sql += " AND c.tags LIKE ?"; args.push(`%${tag}%`); }
  if (q) { sql += ' AND c.note LIKE ?'; args.push(`%${q}%`); }
  sql += ' ORDER BY c.taken_at ASC';
  const rows = await db.all(sql, args);
  res.json({ cuts: rows.map(cutRow) });
}));

// 自分が入っている全てのログを横断して、カットを新しい順に返す。
// 「全カット」の画面（写真アプリのような並び）が使う。
// ログをまたぐので requireMember は使えない。memberships と内側で突き合わせて絞る。
api.get('/cuts', requireAuth, asyncRoute(async (req, res) => {
  const { date, q, kind, before, author } = req.query;
  const limit = Math.min(500, Math.max(1, Number(req.query.limit) || 200));
  let sql = `SELECT c.*, u.display_name, l.name AS log_name, l.kind AS log_kind
               FROM cuts c
               JOIN users u ON u.id = c.user_id
               JOIN logs l ON l.id = c.log_id
               JOIN memberships m ON m.log_id = c.log_id AND m.user_id = ?
              WHERE c.deleted_at IS NULL`;
  const args = [req.user.id];
  if (date) { sql += ' AND c.local_date = ?'; args.push(date); }
  if (kind === 'photo' || kind === 'video') { sql += ' AND c.kind = ?'; args.push(kind); }
  if (author) { sql += ' AND c.user_id = ?'; args.push(author); }
  if (q) { sql += ' AND c.note LIKE ?'; args.push(`%${q}%`); }
  // 続きを読むための目印。同じ時刻が並んだときに取りこぼさないよう、idも見る。
  if (before) { sql += ' AND (c.taken_at < ? OR (c.taken_at = ? AND c.id < ?))'; args.push(before, before, req.query.beforeId || ''); }
  sql += ' ORDER BY c.taken_at DESC, c.id DESC LIMIT ?';
  args.push(limit);
  const rows = await db.all(sql, args);
  const cuts = rows.map((r) => ({ ...cutRow(r), logName: r.log_name, logKind: r.log_kind }));
  const last = rows.length === limit ? rows[rows.length - 1] : null;
  res.json({ cuts, nextBefore: last ? last.taken_at : null, nextBeforeId: last ? last.id : null });
}));

// 端末から届いた数を、決めた範囲に収まるものだけ通す
function numOrNull(v, min, max) {
  const n = Number(v);
  if (!Number.isFinite(n) || n < min || n > max) return null;
  return n;
}

async function createCut(req, res, logId) {
  if (!req.file) return res.status(400).json({ error: 'ファイルがありません' });
  let meta = {};
  try { meta = JSON.parse(req.body.meta || '{}'); } catch { meta = {}; }
  const kind = meta.kind === 'photo' ? 'photo' : 'video';
  const ext = kind === 'photo'
    ? (req.file.mimetype.includes('png') ? 'png' : 'jpg')
    : (req.file.mimetype.includes('mp4') ? 'mp4' : 'webm');
  const cid = id('c_');
  const key = `${cid}.${ext}`;
  const tmpFile = req.file.path;

  const probe = await ffprobe(tmpFile);
  const checksum = await sha256File(tmpFile).catch(() => null);
  const thumbKey = `${cid}_thumb.jpg`;
  const thumbTmp = path.join(paths.tmp, thumbKey);
  const gotThumb = await makeThumb(tmpFile, thumbTmp);

  await storage.put(key, tmpFile);
  if (gotThumb) await storage.put(thumbKey, thumbTmp);
  await fsp.unlink(tmpFile).catch(() => {});
  await fsp.unlink(thumbTmp).catch(() => {});

  const takenAt = meta.takenAt || nowIso();
  const tz = Number.isFinite(meta.tzOffset) ? Number(meta.tzOffset) : new Date().getTimezoneOffset();
  await db.run(
    `INSERT INTO cuts (id, log_id, user_id, kind, storage_key, thumb_key, mime, bytes, duration_ms, width, height,
      facing, source, taken_at, tz_offset, local_date, note, tags, checksum, lat, lon, place_accuracy, created_at, updated_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
    [cid, logId, req.user.id, kind, key, gotThumb ? thumbKey : null,
      sanitizeMediaType(req.file.mimetype, key), req.file.size,
      meta.durationMs ?? probe.durationMs, probe.width, probe.height,
      meta.facing || null, meta.source === 'upload' ? 'upload' : 'camera',
      takenAt, tz, localDateOf(takenAt, tz),
      meta.note ? String(meta.note).slice(0, 500) : null,
      Array.isArray(meta.tags) ? meta.tags.join(',').slice(0, 200) : null,
      checksum,
      // 撮った場所。端末が出せたときだけ入る。おかしな値は捨てる。
      numOrNull(meta.lat, -90, 90), numOrNull(meta.lon, -180, 180), numOrNull(meta.accuracy, 0, 100000),
      nowIso(), nowIso()],
  );
  const row = await db.get(
    'SELECT c.*, u.display_name FROM cuts c JOIN users u ON u.id = c.user_id WHERE c.id = ?', [cid],
  );
  await audit(req, 'cut.create', cid, { logId, kind });
  return res.json({ cut: cutRow(row) });
}

api.post('/logs/:logId/cuts', requireAuth, requireMember, uploadFile('file'),
  asyncRoute((req, res) => createCut(req, res, req.params.logId)));

// 行き先を指定しないで撮ったカット。既定の記録先（初期値はプライベート）へ入る。
api.post('/cuts', requireAuth, uploadFile('file'), asyncRoute(async (req, res) => {
  const logId = await resolveDefaultLog(req.user);
  return createCut(req, res, logId);
}));

async function cutWithAccess(cutId, userId) {
  const c = await db.get(
    'SELECT c.*, u.display_name FROM cuts c JOIN users u ON u.id = c.user_id WHERE c.id = ?', [cutId],
  );
  if (!c) return null;
  if (!await memberOf(c.log_id, userId)) return null;
  return c;
}

api.get('/cuts/:cutId', requireAuth, asyncRoute(async (req, res) => {
  const c = await cutWithAccess(req.params.cutId, req.user.id);
  if (!c) return res.status(404).json({ error: '見つかりません' });
  const reactions = await db.all(
    'SELECT emoji, COUNT(*) AS n FROM reactions WHERE cut_id = ? GROUP BY emoji', [c.id],
  );
  const mine = await db.all('SELECT emoji FROM reactions WHERE cut_id = ? AND user_id = ?', [c.id, req.user.id]);
  const comments = await db.all(
    `SELECT cm.*, u.display_name, u.avatar_key FROM comments cm JOIN users u ON u.id = cm.user_id
      WHERE cm.cut_id = ? AND cm.deleted_at IS NULL ORDER BY cm.created_at`, [c.id],
  );
  return res.json({
    cut: cutRow(c),
    reactions,
    myReactions: mine.map((m) => m.emoji),
    comments: comments.map((x) => ({
      id: x.id,
      body: x.body,
      author: x.display_name,
      userId: x.user_id,
      avatarUrl: x.avatar_key ? `/api/avatar/${x.user_id}` : null,
      createdAt: x.created_at,
    })),
  });
}));

api.patch('/cuts/:cutId', requireAuth, asyncRoute(async (req, res) => {
  const c = await cutWithAccess(req.params.cutId, req.user.id);
  if (!c) return res.status(404).json({ error: '見つかりません' });
  const note = req.body?.note !== undefined ? String(req.body.note).slice(0, 500) : c.note;
  const tags = Array.isArray(req.body?.tags) ? req.body.tags.join(',').slice(0, 200) : c.tags;
  // 非表示は「そのログでこのカットを出すか」の状態。消すこととは別に持つ。
  const hidden = req.body?.hidden !== undefined ? (req.body.hidden ? 1 : 0) : Number(c.hidden || 0);
  await db.run('UPDATE cuts SET note = ?, tags = ?, hidden = ?, updated_at = ? WHERE id = ?',
    [note, tags, hidden, nowIso(), c.id]);
  const row = await db.get(
    'SELECT c.*, u.display_name FROM cuts c JOIN users u ON u.id = c.user_id WHERE c.id = ?', [c.id],
  );
  return res.json({ cut: cutRow(row) });
}));

api.delete('/cuts/:cutId', requireAuth, asyncRoute(async (req, res) => {
  const c = await cutWithAccess(req.params.cutId, req.user.id);
  if (!c) return res.status(404).json({ error: '見つかりません' });
  const m = await memberOf(c.log_id, req.user.id);
  if (c.user_id !== req.user.id && m.role !== 'owner' && !req.user.is_admin) {
    return res.status(403).json({ error: '自分のカットだけ消せます' });
  }
  await db.run('UPDATE cuts SET deleted_at = ? WHERE id = ?', [nowIso(), c.id]);
  await audit(req, 'cut.delete', c.id);
  return res.json({ ok: true });
}));

// ── カットの付け替え ────────────────────────────────────
// 撮ったあとで「このカットはどのログのものか」を変えられる。
// ★動かせるのは自分で撮ったカットだけである。オーナーでも他の人のカットは動かせない
// （動かした先が自分のプライベートなら、撮った本人が二度と見られなくなるため）。
async function moveCuts(req, cutIds, toLogId) {
  const moved = [];
  const skipped = [];
  for (const cutId of cutIds) {
    // eslint-disable-next-line no-await-in-loop
    const c = await db.get('SELECT * FROM cuts WHERE id = ?', [cutId]);
    if (!c) { skipped.push({ cutId, reason: '見つかりません' }); continue; }
    // eslint-disable-next-line no-await-in-loop
    const from = await memberOf(c.log_id, req.user.id);
    if (!from) { skipped.push({ cutId, reason: '元のログのメンバーではありません' }); continue; }
    if (c.user_id !== req.user.id) {
      skipped.push({ cutId, reason: '自分が撮ったカットだけ動かせます' });
      continue;
    }
    if (c.log_id === toLogId) { skipped.push({ cutId, reason: 'すでにこのログにあります' }); continue; }
    // 共有リンクはログごとに作るので、動かしたカットは元の共有から外す
    // eslint-disable-next-line no-await-in-loop
    await db.run('DELETE FROM share_cuts WHERE cut_id = ?', [cutId]);
    // eslint-disable-next-line no-await-in-loop
    await db.run('UPDATE cuts SET log_id = ?, updated_at = ? WHERE id = ?', [toLogId, nowIso(), cutId]);
    // eslint-disable-next-line no-await-in-loop
    await audit(req, 'cut.move', cutId, { from: c.log_id, to: toLogId });
    moved.push(cutId);
  }
  return { moved, skipped };
}

// 1件だけ動かす。
api.post('/cuts/:cutId/move', requireAuth, asyncRoute(async (req, res) => {
  const toLogId = String(req.body?.logId || '');
  if (!await memberOf(toLogId, req.user.id)) {
    return res.status(403).json({ error: '移す先のログのメンバーではありません' });
  }
  const { moved, skipped } = await moveCuts(req, [req.params.cutId], toLogId);
  if (!moved.length) return res.status(400).json({ error: skipped[0]?.reason || '動かせませんでした' });
  const row = await db.get(
    'SELECT c.*, u.display_name FROM cuts c JOIN users u ON u.id = c.user_id WHERE c.id = ?', [req.params.cutId],
  );
  return res.json({ cut: cutRow(row) });
}));

// まとめて動かす。:logId が移す先である。
api.post('/logs/:logId/cuts/move', requireAuth, requireMember, asyncRoute(async (req, res) => {
  const cutIds = Array.isArray(req.body?.cutIds) ? req.body.cutIds.map(String) : [];
  if (!cutIds.length) return res.status(400).json({ error: 'カットを選んでください' });
  const result = await moveCuts(req, cutIds, req.params.logId);
  return res.json(result);
}));

api.post('/cuts/:cutId/restore', requireAuth, asyncRoute(async (req, res) => {
  const c = await cutWithAccess(req.params.cutId, req.user.id);
  if (!c) return res.status(404).json({ error: '見つかりません' });
  await db.run('UPDATE cuts SET deleted_at = NULL WHERE id = ?', [c.id]);
  await audit(req, 'cut.restore', c.id, { logId: c.log_id });
  return res.json({ ok: true });
}));

api.get('/logs/:logId/trash', requireAuth, requireMember, asyncRoute(async (req, res) => {
  const rows = await db.all(
    `SELECT c.*, u.display_name FROM cuts c JOIN users u ON u.id = c.user_id
      WHERE c.log_id = ? AND c.deleted_at IS NOT NULL ORDER BY c.deleted_at DESC LIMIT 200`, [req.params.logId],
  );
  res.json({ cuts: rows.map(cutRow) });
}));

api.post('/cuts/:cutId/reactions', requireAuth, asyncRoute(async (req, res) => {
  const c = await cutWithAccess(req.params.cutId, req.user.id);
  if (!c) return res.status(404).json({ error: '見つかりません' });
  const emoji = String(req.body?.emoji || '').slice(0, 8);
  if (!emoji) return res.status(400).json({ error: '絵文字がありません' });
  const existing = await db.get('SELECT * FROM reactions WHERE cut_id = ? AND user_id = ? AND emoji = ?',
    [c.id, req.user.id, emoji]);
  if (existing) await db.run('DELETE FROM reactions WHERE id = ?', [existing.id]);
  else {
    await db.run('INSERT INTO reactions (id, cut_id, user_id, emoji, created_at) VALUES (?,?,?,?,?)',
      [id('r_'), c.id, req.user.id, emoji, nowIso()]);
  }
  const reactions = await db.all('SELECT emoji, COUNT(*) AS n FROM reactions WHERE cut_id = ? GROUP BY emoji', [c.id]);
  return res.json({ reactions });
}));

api.post('/cuts/:cutId/comments', requireAuth, asyncRoute(async (req, res) => {
  const c = await cutWithAccess(req.params.cutId, req.user.id);
  if (!c) return res.status(404).json({ error: '見つかりません' });
  const body = String(req.body?.body || '').trim().slice(0, 500);
  if (!body) return res.status(400).json({ error: '本文がありません' });
  await db.run('INSERT INTO comments (id, cut_id, user_id, body, created_at) VALUES (?,?,?,?,?)',
    [id('cm_'), c.id, req.user.id, body, nowIso()]);
  return res.json({ ok: true });
}));

api.delete('/comments/:commentId', requireAuth, asyncRoute(async (req, res) => {
  const cm = await db.get('SELECT * FROM comments WHERE id = ?', [req.params.commentId]);
  if (!cm) return res.status(404).json({ error: '見つかりません' });
  if (cm.user_id !== req.user.id && !req.user.is_admin) return res.status(403).json({ error: '自分のコメントだけ消せます' });
  await db.run('UPDATE comments SET deleted_at = ? WHERE id = ?', [nowIso(), cm.id]);
  return res.json({ ok: true });
}));

// ── メディア配信 ────────────────────────────────────────
// ★配信するときの Content-Type は、この一覧に載っている型だけにする。
// 送ってきた側が申告した型をそのまま返すと、.html や .svg を上げるだけで
// このサイトと同じオリジンにスクリプトを置けてしまう（保存型のXSSになる）。
const SAFE_MEDIA_TYPES = new Set([
  'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/avif',
  'image/heic', 'image/heif', 'image/bmp', 'image/tiff',
  'video/mp4', 'video/webm', 'video/quicktime', 'video/ogg', 'video/x-matroska',
  'audio/mpeg', 'audio/mp4', 'audio/ogg', 'audio/wav', 'audio/webm',
]);

const EXT_MEDIA_TYPES = {
  jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', gif: 'image/gif',
  webp: 'image/webp', avif: 'image/avif', heic: 'image/heic', heif: 'image/heif',
  mp4: 'video/mp4', webm: 'video/webm', mov: 'video/quicktime', ogv: 'video/ogg',
};

// ★動画は「途中から」読めないと再生できない。
// Safari は範囲取り（Range）に応えないサーバの <video> を再生しない。
// プロキシを挟んだときも同じで、頭出しや早送りにも要る。
// ここで Range を受け取り、求められた分だけ 206 で返す。
export function parseRange(header, size) {
  const m = /^bytes=(\d*)-(\d*)$/.exec(String(header || '').trim());
  if (!m || !size) return null;
  const [, rawStart, rawEnd] = m;
  let start;
  let end;
  if (rawStart === '') {
    // 「末尾から N バイト」の形
    const n = Number(rawEnd);
    if (!Number.isFinite(n) || n <= 0) return null;
    start = Math.max(0, size - n);
    end = size - 1;
  } else {
    start = Number(rawStart);
    end = rawEnd === '' ? size - 1 : Number(rawEnd);
  }
  if (!Number.isFinite(start) || !Number.isFinite(end)) return null;
  if (start < 0 || start >= size || end < start) return null;
  return { start, end: Math.min(end, size - 1) };
}

async function sendMaybeRanged(req, res, key) {
  const size = await storage.size(key);
  res.setHeader('Accept-Ranges', 'bytes');
  const range = parseRange(req.headers.range, size);
  if (req.headers.range && !range && size) {
    // 読めない範囲を指定されたときは、その旨を返す（黙って全部返さない）
    res.setHeader('Content-Range', `bytes */${size}`);
    return res.status(416).end();
  }
  if (range) {
    res.status(206);
    res.setHeader('Content-Range', `bytes ${range.start}-${range.end}/${size}`);
    res.setHeader('Content-Length', String(range.end - range.start + 1));
    const part = await storage.stream(key, range);
    return part.pipe(res);
  }
  if (size) res.setHeader('Content-Length', String(size));
  const body = await storage.stream(key);
  return body.pipe(res);
}

// 保存するときに型をそろえる。一覧に無い型は、拡張子から決め直す。
export function sanitizeMediaType(declared, storageKey) {
  const bare = String(declared || '').split(';')[0].trim().toLowerCase();
  if (SAFE_MEDIA_TYPES.has(bare)) return bare;
  const ext = String(storageKey || '').split('.').pop().toLowerCase();
  return EXT_MEDIA_TYPES[ext] || 'application/octet-stream';
}

api.get('/media/:cutId', asyncRoute(async (req, res) => {
  const cut = await db.get('SELECT * FROM cuts WHERE id = ?', [req.params.cutId]);
  if (!cut) return res.status(404).end();
  let allowed = false;
  const user = await currentUser(req);
  if (user && await memberOf(cut.log_id, user.id)) allowed = true;
  if (!allowed && req.query.s) {
    const share = await validShare(req.query.s);
    // ★ゴミ箱へ入れたカットは、共有リンクからは配らない（公開ページの一覧からは既に消えている）
    if (share && !cut.deleted_at && shareUnlocked(req, share)) {
      const inShare = await db.get('SELECT 1 AS ok FROM share_cuts WHERE share_id = ? AND cut_id = ?',
        [share.id, cut.id]);
      if (inShare) allowed = true;
    }
  }
  if (!allowed) return res.status(403).end();
  const key = req.query.thumb && cut.thumb_key ? cut.thumb_key : cut.storage_key;
  const type = req.query.thumb ? 'image/jpeg' : sanitizeMediaType(cut.mime, cut.storage_key);
  res.setHeader('Content-Type', type);
  res.setHeader('X-Content-Type-Options', 'nosniff');
  // 万一この先で型を取りこぼしても、置かれたファイルからスクリプトが動かないようにする
  res.setHeader('Content-Security-Policy', "default-src 'none'; sandbox");
  res.setHeader('Cache-Control', 'private, max-age=86400');
  if (req.query.download || type === 'application/octet-stream') {
    res.setHeader('Content-Disposition', `attachment; filename="${key}"`);
  }
  return sendMaybeRanged(req, res, key);
}));

// ── アカウントの顔 ──────────────────────────────────────
// 上げた画像は、正方形の小さなJPEGに直してから置く（大きな絵をそのまま抱えない）。
api.post('/me/avatar', requireAuth, uploadFile('file'), asyncRoute(async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'ファイルがありません' });
  if (!String(req.file.mimetype || '').startsWith('image/')) {
    await fsp.unlink(req.file.path).catch(() => {});
    return res.status(400).json({ error: '画像を選んでください' });
  }
  const key = `av_${req.user.id}.jpg`;
  const tmp = path.join(paths.tmp, key);
  const ok = await makeSquare(req.file.path, tmp);
  await fsp.unlink(req.file.path).catch(() => {});
  if (!ok) return res.status(400).json({ error: 'この画像は読めませんでした' });
  await storage.put(key, tmp);
  await fsp.unlink(tmp).catch(() => {});
  await db.run('UPDATE users SET avatar_key = ? WHERE id = ?', [key, req.user.id]);
  const u = await db.get('SELECT * FROM users WHERE id = ?', [req.user.id]);
  return res.json({ user: publicUser(u) });
}));

api.delete('/me/avatar', requireAuth, asyncRoute(async (req, res) => {
  await db.run('UPDATE users SET avatar_key = NULL WHERE id = ?', [req.user.id]);
  const u = await db.get('SELECT * FROM users WHERE id = ?', [req.user.id]);
  return res.json({ user: publicUser(u) });
}));

// 顔の絵は、ログインしている人にだけ配る（誰の顔かはIDで指す）。
api.get('/avatar/:userId', requireAuth, asyncRoute(async (req, res) => {
  const u = await db.get('SELECT avatar_key FROM users WHERE id = ?', [req.params.userId]);
  if (!u || !u.avatar_key) return res.status(404).end();
  res.setHeader('Content-Type', 'image/jpeg');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Content-Security-Policy', "default-src 'none'; sandbox");
  res.setHeader('Cache-Control', 'private, max-age=3600');
  const body = await storage.stream(u.avatar_key);
  return body.pipe(res);
}));

// まとめ動画のファイル。★ファイル名を知っているだけでは落とせない。
// このファイルを作ったジョブを引き、そのログのメンバーだけに配る。
api.get('/renders/file/:name', requireAuth, asyncRoute(async (req, res) => {
  const name = path.basename(req.params.name);
  const job = await db.get(
    `SELECT * FROM jobs WHERE kind = 'render_timeline' AND result LIKE ? ORDER BY created_at DESC`,
    [`%"filename":"${name}"%`],
  );
  if (!job) return res.status(404).end();
  if (job.log_id && !await memberOf(job.log_id, req.user.id) && !req.user.is_admin) {
    return res.status(403).json({ error: 'このまとめ動画を見る権限がありません' });
  }
  const file = path.join(paths.renders, name);
  if (!fs.existsSync(file)) return res.status(404).end();
  res.setHeader('Content-Disposition', `attachment; filename="${name}"`);
  res.setHeader('X-Content-Type-Options', 'nosniff');
  return res.sendFile(file);
}));

// ── まとめ動画 ─────────────────────────────────────────
api.post('/logs/:logId/renders', requireAuth, requireMember, asyncRoute(async (req, res) => {
  if (!config.ffmpeg.enabled) return res.status(400).json({ error: 'このサーバはまとめ動画を止めています' });
  const asked = Array.isArray(req.body?.cutIds) ? req.body.cutIds.map(String) : [];
  if (!asked.length) return res.status(400).json({ error: 'カットを選んでください' });
  // ★このログに属するカットだけに絞る（IDを知っているだけでは他のログのカットを混ぜられない）
  const owned = await db.all(
    `SELECT id FROM cuts WHERE log_id = ? AND deleted_at IS NULL
      AND id IN (${asked.map(() => '?').join(',')})`,
    [req.params.logId, ...asked],
  );
  const cutIds = owned.map((r) => r.id);
  if (!cutIds.length) return res.status(400).json({ error: 'このログのカットを選んでください' });
  // 見た目は毎回渡せる。渡さなければ前に使った設定を使う。
  let style;
  if (req.body?.style) {
    style = normalizeStyle(req.body.style);
    await db.run('UPDATE users SET render_prefs = ? WHERE id = ?', [JSON.stringify(style), req.user.id]);
  } else {
    let saved = null;
    try { saved = req.user.render_prefs ? JSON.parse(req.user.render_prefs) : null; } catch { saved = null; }
    style = normalizeStyle(saved || { time: { show: !!req.body?.burnTime } });
  }
  const jobId = await enqueue('render_timeline', {
    cutIds, style, label: String(req.body?.label || 'まとめ'),
  }, { logId: req.params.logId, userId: req.user.id });
  return res.json({ jobId, style });
}));

api.get('/jobs/:jobId', requireAuth, asyncRoute(async (req, res) => {
  const job = await getJob(req.params.jobId);
  if (!job) return res.status(404).json({ error: '見つかりません' });
  if (job.log_id && !await memberOf(job.log_id, req.user.id)) return res.status(403).json({ error: '権限がありません' });
  return res.json({
    job: {
      id: job.id, kind: job.kind, status: job.status, message: job.message,
      result: job.result ? JSON.parse(job.result) : null, createdAt: job.created_at,
    },
  });
}));

api.get('/logs/:logId/renders', requireAuth, requireMember, asyncRoute(async (req, res) => {
  const rows = await db.all(
    `SELECT * FROM jobs WHERE log_id = ? AND kind = 'render_timeline' ORDER BY created_at DESC LIMIT 30`,
    [req.params.logId],
  );
  res.json({
    renders: rows.map((j) => {
      const parsed = j.result ? JSON.parse(j.result) : null;
      return {
        id: j.id,
        label: JSON.parse(j.payload).label || 'まとめ',
        status: j.status,
        message: j.message,
        url: parsed?.url || null,
        cutCount: parsed?.cutCount || JSON.parse(j.payload).cutIds?.length || 0,
        createdAt: j.created_at,
      };
    }),
  });
}));

// ── 書き出し ───────────────────────────────────────────
// ★ GET でも同じものを返す。ブラウザに「保存」を任せるには、
//   リンクをそのまま踏ませるのがいちばん確実で、POST では踏めない。
//   中身は本文ではなく問い合わせ文字列から拾う（cutIds はカンマ区切り）。
api.get('/logs/:logId/export', requireAuth, requireMember, asyncRoute(async (req, res) => {
  req.body = {
    cutIds: String(req.query.cutIds || '').split(',').filter(Boolean),
    includeMetadata: req.query.meta !== '0',
  };
  return exportZip(req, res);
}));

api.post('/logs/:logId/export', requireAuth, requireMember, asyncRoute(exportZip));

async function exportZip(req, res) {
  const cutIds = Array.isArray(req.body?.cutIds) ? req.body.cutIds : [];
  const includeMetadata = req.body?.includeMetadata !== false;
  if (!cutIds.length) return res.status(400).json({ error: 'カットを選んでください' });
  const rows = [];
  for (const cid of cutIds) {
    // eslint-disable-next-line no-await-in-loop
    const c = await db.get(
      `SELECT c.*, u.display_name FROM cuts c JOIN users u ON u.id = c.user_id
        WHERE c.id = ? AND c.log_id = ? AND c.deleted_at IS NULL`, [cid, req.params.logId],
    );
    if (c) rows.push(c);
  }
  if (!rows.length) return res.status(400).json({ error: '書き出せるカットがありません' });

  const log = await db.get('SELECT * FROM logs WHERE id = ?', [req.params.logId]);
  const stamp = new Date().toISOString().slice(0, 19).replace(/[:T-]/g, '');
  res.setHeader('Content-Type', 'application/zip');
  res.setHeader('Content-Disposition', `attachment; filename="cutlog_${stamp}.zip"`);
  const zip = archiver('zip', { zlib: { level: 6 } });
  zip.on('error', (err) => { throw err; });
  zip.pipe(res);
  for (const c of rows) {
    // eslint-disable-next-line no-await-in-loop
    const body = await storage.stream(c.storage_key);
    zip.append(body, { name: `media/${c.local_date}/${c.storage_key}` });
    if (c.thumb_key) {
      // eslint-disable-next-line no-await-in-loop
      const th = await storage.stream(c.thumb_key);
      zip.append(th, { name: `thumbs/${c.thumb_key}` });
    }
  }
  if (includeMetadata) {
    zip.append(JSON.stringify({
      app: 'cutlog',
      schema: 1,
      exportedAt: nowIso(),
      exportedBy: publicUser(req.user),
      log: { id: log.id, name: log.name, cutSeconds: log.cut_seconds },
      cuts: rows.map((c) => ({ ...cutRow(c), file: `media/${c.local_date}/${c.storage_key}` })),
    }, null, 2), { name: 'cuts.json' });
    const head = 'id,localDate,takenAt,tzOffset,author,kind,durationMs,width,height,facing,source,bytes,checksum,note,tags';
    const csv = [head].concat(rows.map((c) => [
      c.id, c.local_date, c.taken_at, c.tz_offset, c.display_name, c.kind, c.duration_ms ?? '',
      c.width ?? '', c.height ?? '', c.facing ?? '', c.source, c.bytes, c.checksum ?? '',
      JSON.stringify(c.note || ''), JSON.stringify(c.tags || ''),
    ].join(','))).join('\n');
    zip.append(csv, { name: 'cuts.csv' });
    zip.append(`# cutlog エクスポート\n\n- 書き出し: ${nowIso()}\n- ログ: ${log.name}\n- カット数: ${rows.length}\n\n`
      + 'media/ に元ファイル、thumbs/ にサムネイル、cuts.json と cuts.csv にメタデータが入っています。\n',
    { name: 'README.md' });
  }
  await audit(req, 'export', req.params.logId, { count: rows.length, includeMetadata });
  await zip.finalize();
  return undefined;
}

// ── 共有リンク ─────────────────────────────────────────
async function validShare(token) {
  const s = await db.get('SELECT * FROM shares WHERE token = ?', [token]);
  if (!s || s.revoked_at) return null;
  if (s.expires_at) {
    const t = new Date(s.expires_at).getTime();
    // 日付として読めない値が入っていたら、期限切れとして扱う（黙って期限なしにしない）
    if (!Number.isFinite(t) || t < Date.now()) return null;
  }
  return s;
}

// パスワード付きの共有は、パスワードを通した人にだけ配る。
// 公開ページでパスワードが合った時点でこの値をCookieへ入れ、実体の配信でも同じ値を求める。
// （この値は password_hash から作るので、パスワードを知らない人には作れない）
function shareGrantValue(share) {
  return crypto.createHash('sha256')
    .update(`cutlog-share|${share.id}|${share.password_hash}`).digest('base64url');
}

const shareCookieName = (share) => `cutlog_share_${share.id}`;

function grantShare(res, share) {
  const bits = [
    `${shareCookieName(share)}=${shareGrantValue(share)}`,
    'HttpOnly', 'SameSite=Lax', 'Path=/', 'Max-Age=86400',
  ];
  if (config.auth.cookieSecure) bits.push('Secure');
  res.append('Set-Cookie', bits.join('; '));
}

function shareUnlocked(req, share) {
  if (!share.password_hash) return true;
  return parseCookies(req)[shareCookieName(share)] === shareGrantValue(share);
}

api.post('/logs/:logId/shares', requireAuth, requireMember, asyncRoute(async (req, res) => {
  const cutIds = Array.isArray(req.body?.cutIds) ? req.body.cutIds : [];
  if (!cutIds.length) return res.status(400).json({ error: 'カットを選んでください' });
  // 期限は日付として読める値だけ受ける（読めない値を黙って「期限なし」にしない）
  let expiresAt = null;
  if (req.body?.expiresAt !== undefined && req.body.expiresAt !== null && req.body.expiresAt !== '') {
    const t = new Date(req.body.expiresAt).getTime();
    if (!Number.isFinite(t)) {
      return res.status(400).json({ error: '期限は日付として読める形で渡してください（例: 2026-09-01T00:00:00.000Z）' });
    }
    expiresAt = new Date(t).toISOString();
  }
  const sid = id('sh_');
  const token = crypto.randomBytes(12).toString('base64url');
  await db.run(
    `INSERT INTO shares (id, log_id, token, title, password_hash, expires_at, allow_download, created_by, created_at)
     VALUES (?,?,?,?,?,?,?,?,?)`,
    [sid, req.params.logId, token, String(req.body?.title || '共有').slice(0, 80),
      req.body?.password ? hashPassword(String(req.body.password)) : null,
      expiresAt, req.body?.allowDownload === false ? 0 : 1, req.user.id, nowIso()],
  );
  for (const cid of cutIds) {
    // eslint-disable-next-line no-await-in-loop
    const owned = await db.get('SELECT 1 AS ok FROM cuts WHERE id = ? AND log_id = ?', [cid, req.params.logId]);
    // eslint-disable-next-line no-await-in-loop
    if (owned) await db.run('INSERT INTO share_cuts (share_id, cut_id) VALUES (?,?)', [sid, cid]);
  }
  await audit(req, 'share.create', sid, { count: cutIds.length });
  res.json({ share: { id: sid, token, url: `${config.baseUrl}/s/${token}`, path: `/s/${token}` } });
}));

api.get('/logs/:logId/shares', requireAuth, requireMember, asyncRoute(async (req, res) => {
  const rows = await db.all(
    `SELECT s.*, (SELECT COUNT(*) FROM share_cuts sc WHERE sc.share_id = s.id) AS n
       FROM shares s WHERE s.log_id = ? ORDER BY s.created_at DESC`, [req.params.logId],
  );
  res.json({
    shares: rows.map((s) => ({
      id: s.id, title: s.title, url: `${config.baseUrl}/s/${s.token}`, path: `/s/${s.token}`,
      cutCount: Number(s.n), expiresAt: s.expires_at, hasPassword: !!s.password_hash,
      allowDownload: !!s.allow_download, revoked: !!s.revoked_at, viewCount: s.view_count,
      createdAt: s.created_at,
    })),
  });
}));

api.delete('/shares/:shareId', requireAuth, asyncRoute(async (req, res) => {
  const s = await db.get('SELECT * FROM shares WHERE id = ?', [req.params.shareId]);
  if (!s || !await memberOf(s.log_id, req.user.id)) return res.status(404).json({ error: '見つかりません' });
  await db.run('UPDATE shares SET revoked_at = ? WHERE id = ?', [nowIso(), s.id]);
  return res.json({ ok: true });
}));

api.get('/public/:token/meta', asyncRoute(async (req, res) => {
  const s = await validShare(req.params.token);
  if (!s) return res.status(404).json({ error: 'この共有リンクは使えません' });
  return res.json({ title: s.title, needPassword: !!s.password_hash, allowDownload: !!s.allow_download });
}));

api.post('/public/:token', asyncRoute(async (req, res) => {
  const s = await validShare(req.params.token);
  if (!s) return res.status(404).json({ error: 'この共有リンクは使えません' });
  if (s.password_hash && !verifyPassword(String(req.body?.password || ''), s.password_hash)) {
    return res.status(401).json({ error: 'パスワードが違います', needPassword: true });
  }
  if (s.password_hash) grantShare(res, s);
  await db.run('UPDATE shares SET view_count = view_count + 1 WHERE id = ?', [s.id]);
  const cuts = await db.all(
    `SELECT c.*, u.display_name FROM share_cuts sc JOIN cuts c ON c.id = sc.cut_id
       JOIN users u ON u.id = c.user_id
      WHERE sc.share_id = ? AND c.deleted_at IS NULL ORDER BY c.taken_at`, [s.id],
  );
  return res.json({
    title: s.title,
    allowDownload: !!s.allow_download,
    cuts: cuts.map((c) => ({
      ...cutRow(c),
      url: `/api/media/${c.id}?s=${req.params.token}`,
      thumbUrl: c.thumb_key ? `/api/media/${c.id}?thumb=1&s=${req.params.token}` : null,
    })),
  });
}));

// ── 通知 ───────────────────────────────────────────────
if (config.push.publicKey && config.push.privateKey) {
  webpush.setVapidDetails(config.push.subject, config.push.publicKey, config.push.privateKey);
}

// iOS / Android のアプリは、Firebase がくれた札を預ける。
// ★ ブラウザの購読と同じ表に、種類を添えて置く。送るときにそこで分ける。
api.post('/push/fcm', requireAuth, asyncRoute(async (req, res) => {
  const token = String(req.body?.token || '').trim();
  if (!token) return res.status(400).json({ error: '札がありません' });
  const existing = await db.get('SELECT * FROM push_subs WHERE endpoint = ?', [token]);
  if (existing) {
    await db.run('UPDATE push_subs SET user_id = ?, kind = ? WHERE endpoint = ?',
      [req.user.id, 'fcm', token]);
  } else {
    await db.run(
      'INSERT INTO push_subs (id, user_id, endpoint, p256dh, auth, kind, created_at) VALUES (?,?,?,?,?,?,?)',
      [id('ps_'), req.user.id, token, '', '', 'fcm', nowIso()],
    );
  }
  return res.json({ ok: true });
}));

api.post('/push/subscribe', requireAuth, asyncRoute(async (req, res) => {
  const sub = req.body?.subscription;
  if (!sub?.endpoint) return res.status(400).json({ error: '購読の情報がありません' });
  const existing = await db.get('SELECT * FROM push_subs WHERE endpoint = ?', [sub.endpoint]);
  if (existing) {
    await db.run('UPDATE push_subs SET user_id = ?, p256dh = ?, auth = ? WHERE endpoint = ?',
      [req.user.id, sub.keys?.p256dh || '', sub.keys?.auth || '', sub.endpoint]);
  } else {
    await db.run('INSERT INTO push_subs (id, user_id, endpoint, p256dh, auth, created_at) VALUES (?,?,?,?,?,?)',
      [id('ps_'), req.user.id, sub.endpoint, sub.keys?.p256dh || '', sub.keys?.auth || '', nowIso()]);
  }
  return res.json({ ok: true });
}));

export async function pushToUser(userId, payload) {
  const canWeb = !!(config.push.publicKey && config.push.privateKey);
  const canApp = fcmReady();
  if (!canWeb && !canApp) return 0;

  const subs = await db.all('SELECT * FROM push_subs WHERE user_id = ?', [userId]);
  let sent = 0;
  for (const s of subs) {
    // アプリ（Firebase）ぶん
    if (s.kind === 'fcm') {
      if (!canApp) continue;
      // eslint-disable-next-line no-await-in-loop
      const how = await sendToToken(s.endpoint, payload);
      if (how === 'ok') sent += 1;
      // eslint-disable-next-line no-await-in-loop
      if (how === 'gone') await db.run('DELETE FROM push_subs WHERE id = ?', [s.id]);
      continue;
    }

    // ブラウザ（Web Push）ぶん
    if (!canWeb) continue;
    try {
      // eslint-disable-next-line no-await-in-loop
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, JSON.stringify(payload),
      );
      sent += 1;
    } catch (err) {
      if (err.statusCode === 404 || err.statusCode === 410) {
        // eslint-disable-next-line no-await-in-loop
        await db.run('DELETE FROM push_subs WHERE id = ?', [s.id]);
      }
    }
  }
  return sent;
}

api.post('/push/test', requireAuth, asyncRoute(async (req, res) => {
  const n = await pushToUser(req.user.id, { title: 'cutlog', body: 'いま何してる？ 1カット撮りましょう。', url: '/' });
  res.json({ sent: n });
}));

api.put('/reminders', requireAuth, asyncRoute(async (req, res) => {
  const b = req.body || {};
  const existing = await db.get('SELECT 1 AS ok FROM reminders WHERE user_id = ?', [req.user.id]);
  const values = [b.mode || 'off', b.times || null, Number(b.fromHour ?? 9), Number(b.toHour ?? 22),
    Number(b.perDay ?? 6), Number(b.tzOffset ?? 0), nowIso()];
  if (existing) {
    await db.run(
      `UPDATE reminders SET mode = ?, times = ?, from_hour = ?, to_hour = ?, per_day = ?, tz_offset = ?, updated_at = ?
        WHERE user_id = ?`, [...values, req.user.id],
    );
  } else {
    await db.run(
      `INSERT INTO reminders (mode, times, from_hour, to_hour, per_day, tz_offset, updated_at, user_id)
       VALUES (?,?,?,?,?,?,?,?)`, [...values, req.user.id],
    );
  }
  res.json({ reminder: await db.get('SELECT * FROM reminders WHERE user_id = ?', [req.user.id]) });
}));

// ── 管理 ───────────────────────────────────────────────
api.get('/admin/stats', requireAuth, requireAdmin, asyncRoute(async (req, res) => {
  const users = await db.get('SELECT COUNT(*) AS n FROM users');
  const logs = await db.get('SELECT COUNT(*) AS n FROM logs');
  const cuts = await db.get('SELECT COUNT(*) AS n, COALESCE(SUM(bytes),0) AS b FROM cuts WHERE deleted_at IS NULL');
  const jobs = await db.all('SELECT status, COUNT(*) AS n FROM jobs GROUP BY status');
  res.json({
    users: Number(users.n),
    logs: Number(logs.n),
    cuts: Number(cuts.n),
    bytes: Number(cuts.b),
    jobs,
    db: db.driver,
    storage: storage.driver,
  });
}));

api.get('/admin/users', requireAuth, requireAdmin, asyncRoute(async (req, res) => {
  const rows = await db.all('SELECT id, username, display_name, email, auth_provider, is_admin, disabled, created_at FROM users ORDER BY created_at');
  res.json({ users: rows });
}));

api.patch('/admin/users/:userId', requireAuth, requireAdmin, asyncRoute(async (req, res) => {
  const fields = [];
  const args = [];
  if (req.body?.disabled !== undefined) { fields.push('disabled = ?'); args.push(req.body.disabled ? 1 : 0); }
  if (req.body?.isAdmin !== undefined) { fields.push('is_admin = ?'); args.push(req.body.isAdmin ? 1 : 0); }
  if (!fields.length) return res.status(400).json({ error: '変更する項目がありません' });
  args.push(nowIso(), req.params.userId);
  await db.run(`UPDATE users SET ${fields.join(', ')}, updated_at = ? WHERE id = ?`, args);
  const changed = {};
  if (req.body?.disabled !== undefined) changed.disabled = !!req.body.disabled;
  if (req.body?.isAdmin !== undefined) changed.isAdmin = !!req.body.isAdmin;
  await audit(req, 'admin.user.update', req.params.userId, changed);
  return res.json({ ok: true });
}));
