// Firebase Cloud Messaging へ通知を渡す。
// ★ 外の部品は足していない。要るのは「鍵で署名した券を作って、引き換えに通行証をもらう」だけで、
//   Node に入っている暗号の道具で足りる。依存を増やすと、自分で建てる人の手間が増える。
// ★ 通行証は1時間ほど使い回せる。毎回取り直すと、送るたびに余計な往復が1回増える。
import crypto from 'node:crypto';
import fs from 'node:fs';

import { config } from '../config.js';

let cached = null;         // { token, until }

/** 設えを読む。置いていなければ null（通知は Web Push だけになる）。 */
function account() {
  const inline = config.push.fcmServiceAccountJson;
  if (inline) {
    try { return JSON.parse(inline); } catch { return null; }
  }
  const file = config.push.fcmServiceAccountFile;
  if (!file) return null;
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
}

export function fcmReady() {
  return !!account();
}

function base64url(input) {
  return Buffer.from(input).toString('base64url');
}

/** 鍵で署名した券を作り、Google に通行証と引き換える。 */
async function accessToken() {
  if (cached && cached.until > Date.now() + 60_000) return cached.token;

  const acc = account();
  if (!acc?.client_email || !acc?.private_key) return null;

  const now = Math.floor(Date.now() / 1000);
  const head = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const body = base64url(JSON.stringify({
    iss: acc.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const sign = crypto.createSign('RSA-SHA256');
  sign.update(`${head}.${body}`);
  const jwt = `${head}.${body}.${sign.sign(acc.private_key, 'base64url')}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!res.ok) return null;
  const j = await res.json();
  cached = { token: j.access_token, until: Date.now() + (j.expires_in || 3600) * 1000 };
  return cached.token;
}

/**
 * 1つの端末へ届ける。
 * 返り値: 'ok' | 'gone'（相手が消えている＝この届け先は捨ててよい）| 'ng'
 */
export async function sendToToken(token, payload) {
  const acc = account();
  const at = await accessToken();
  if (!acc || !at) return 'ng';

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${acc.project_id}/messages:send`,
    {
      method: 'POST',
      headers: { authorization: `Bearer ${at}`, 'content-type': 'application/json' },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: payload.title || 'cutlog', body: payload.body || '' },
          // 押したときにどこへ行くかは、アプリ側がこの値で決める
          data: { url: String(payload.url || '/') },
          apns: {
            payload: { aps: { sound: 'default' } },
          },
          android: {
            priority: 'high',
            notification: { channelId: 'cutlog' },
          },
        },
      }),
    },
  );

  if (res.ok) return 'ok';
  // 相手が消えている（アプリを消した・鍵が入れ替わった）ときは、届け先を捨てる
  if (res.status === 404 || res.status === 400) {
    const text = await res.text();
    if (text.includes('UNREGISTERED') || text.includes('INVALID_ARGUMENT')) return 'gone';
  }
  return 'ng';
}
