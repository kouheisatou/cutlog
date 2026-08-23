// 見比べ用の中身を、ローカルのサーバへ入れておく。
// ★ 空の画面どうしを見比べても意味がない。行・サムネ・カレンダーの点・地図のピンまで
//   出そろった状態にして、はじめて「同じか」を測れる。
// ★ ここで作るアカウントは localhost の開発サーバ専用の捨てアカウント。
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const BASE = process.env.CUTLOG_BASE || 'http://localhost:8787';
export const ACCOUNT = { username: 'parity_shot', password: 'parity-shot-0000', displayName: '見比べ' };

// 撮った日をばらけさせる。カレンダーに点が並び、日付ごとの見出しも出る。
const DAYS = [0, 0, 0, 1, 1, 3, 6, 6, 12, 20, 33];

// 地図にピンを出すための座標（東京のあたりに散らす）
const SPOTS = [
  [35.6812, 139.7671], [35.6586, 139.7454], [35.7100, 139.8107],
  [35.6605, 139.7292], [35.6284, 139.7367],
];

const NOTES = [
  'あさの支度', '通りの角で', 'ひるの休み', '駅までの道', '帰りの電車',
  '夕方の空', 'ねこがいた', '', 'あたらしい店', '雨のにおい', 'よるの窓',
];

async function call(path, { method = 'GET', body, cookie, raw } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      ...(raw ? {} : { 'content-type': 'application/json' }),
      ...(cookie ? { cookie } : {}),
    },
    body: raw ? body : (body ? JSON.stringify(body) : undefined),
  });
  const setCookie = res.headers.get('set-cookie');
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* 本文が JSON でないこともある */ }
  return { ok: res.ok, status: res.status, json, text, setCookie };
}

function cookieOf(setCookie) {
  return String(setCookie || '').split(';')[0];
}

/** 2秒の色の動画を1本つくる。中身より「絵が違う」ことが大事。 */
function makeClip(dir, i) {
  const out = join(dir, `clip${i}.mp4`);
  const hue = (i * 37) % 360;
  execFileSync('ffmpeg', [
    '-hide_banner', '-loglevel', 'error', '-y',
    '-f', 'lavfi', '-i', `color=c=0x${hsvHex(hue)}:s=640x360:d=2,format=yuv420p`,
    '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=mono',
    '-shortest', '-c:v', 'libx264', '-preset', 'ultrafast', '-c:a', 'aac',
    out,
  ]);
  return out;
}

function hsvHex(h) {
  // 彩度・明度は固定。色みだけを回して、サムネの並びに変化を出す。
  const f = (n) => {
    const k = (n + h / 60) % 6;
    const v = 0.85 - 0.55 * Math.max(0, Math.min(k, 4 - k, 1));
    return Math.round(v * 255).toString(16).padStart(2, '0');
  };
  return `${f(5)}${f(3)}${f(1)}`;
}

async function ensureAccount() {
  const up = await call('/api/auth/signup', { method: 'POST', body: ACCOUNT });
  if (up.ok) return cookieOf(up.setCookie);
  const inn = await call('/api/auth/login', { method: 'POST', body: ACCOUNT });
  if (inn.ok) return cookieOf(inn.setCookie);
  throw new Error(`ログインできません: ${inn.status} ${inn.text}`);
}

async function main() {
  const cookie = await ensureAccount();

  const have = await call('/api/logs', { cookie });
  const existing = have.json?.logs || [];
  const total = existing.reduce((n, l) => n + Number(l.cut_count || 0), 0);
  if (total >= DAYS.length) {
    console.log(`すでに ${existing.length} ログ / ${total} カットあります。追加はしません。`);
    return;
  }

  const names = ['まいにち', '散歩の記録', '仕事のメモ'];
  const logs = [];
  for (const name of names) {
    const found = existing.find((l) => l.name === name);
    if (found) { logs.push(found); continue; }
    const made = await call('/api/logs', { method: 'POST', body: { name }, cookie });
    if (!made.ok) throw new Error(`ログを作れません: ${made.text}`);
    logs.push(made.json.log);
  }

  const dir = mkdtempSync(join(tmpdir(), 'cutlog-seed-'));
  try {
    for (let i = 0; i < DAYS.length; i++) {
      const log = logs[i % logs.length];
      const file = makeClip(dir, i);
      const taken = new Date(Date.now() - DAYS[i] * 864e5 - (i % 7) * 37 * 60000);
      const spot = SPOTS[i % SPOTS.length];

      const form = new FormData();
      form.set('file', new Blob([readFileSync(file)], { type: 'video/mp4' }), `clip${i}.mp4`);
      form.set('meta', JSON.stringify({
        kind: 'video',
        durationMs: 2000,
        takenAt: taken.toISOString(),
        tzOffset: -540,                      // 日本（UTC+9）
        note: NOTES[i % NOTES.length],
        source: 'camera',
        lat: spot[0] + (i % 5) * 0.004,
        lon: spot[1] + (i % 3) * 0.004,
        accuracy: 12,
      }));

      const res = await fetch(`${BASE}/api/logs/${log.id}/cuts`, { method: 'POST', headers: { cookie }, body: form });
      if (!res.ok) throw new Error(`カットを入れられません: ${res.status} ${await res.text()}`);
      process.stdout.write('.');
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }

  console.log(`\n${logs.length} ログ / ${DAYS.length} カットを入れました。`);
}

// ★ この形は shoot.mjs からも読む（ACCOUNT を借りるため）。
//   直に叩かれたときだけ種を播く。読まれただけで走ると、撮るたびに動画を作り直してしまう。
if (process.argv[1] && process.argv[1].endsWith('seed.mjs')) {
  main().catch((e) => { console.error(e.message); process.exit(1); });
}
