// まとめ動画の完走テスト（結合）。写真だけの書き出しが壊れていた回帰を防ぐ。
// ffmpegでの実レンダリングをワーカーに実際に走らせ、ジョブが done になり、
// 寸法(width/height)が指定どおりになることまで確かめる。
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnServer, waitForHealthy } from './helpers/server.js';

const PORT = 8898;
const BASE = `http://127.0.0.1:${PORT}`;
let child;
let dataDir;
let assetDir;
let cookie = '';

async function api(p, opts = {}) {
  const res = await fetch(BASE + p, {
    ...opts,
    headers: {
      ...(opts.body instanceof FormData ? {} : { 'Content-Type': 'application/json' }),
      ...(cookie ? { cookie } : {}),
      ...(opts.headers || {}),
    },
  });
  const setCookie = res.headers.get('set-cookie');
  if (setCookie) cookie = setCookie.split(';')[0];
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : {} };
}

async function waitJob(jobId, timeoutMs = 30000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    // eslint-disable-next-line no-await-in-loop
    const { body } = await api(`/api/jobs/${jobId}`);
    if (body.job.status === 'done' || body.job.status === 'error') return body.job;
    // eslint-disable-next-line no-await-in-loop
    await new Promise((r) => setTimeout(r, 300));
  }
  throw new Error('ジョブが時間内に終わりませんでした');
}

async function uploadPhoto(logId, file, note) {
  const buf = await import('node:fs/promises').then((m) => m.readFile(file));
  const fd = new FormData();
  fd.append('file', new Blob([buf], { type: 'image/jpeg' }), 'photo.jpg');
  fd.append('meta', JSON.stringify({
    kind: 'photo', source: 'upload', note, takenAt: new Date().toISOString(), tzOffset: -540,
  }));
  const { status, body } = await api(`/api/logs/${logId}/cuts`, { method: 'POST', body: fd });
  assert.equal(status, 200, JSON.stringify(body));
  return body.cut.id;
}

before(async () => {
  dataDir = mkdtempSync(path.join(os.tmpdir(), 'cutlog-render-test-'));
  assetDir = mkdtempSync(path.join(os.tmpdir(), 'cutlog-render-asset-'));
  const p1 = path.join(assetDir, 'p1.jpg');
  const p2 = path.join(assetDir, 'p2.jpg');
  spawnSync('ffmpeg', ['-y', '-f', 'lavfi', '-i', 'color=c=blue:size=320x240', '-update', '1', '-frames:v', '1', p1]);
  spawnSync('ffmpeg', ['-y', '-f', 'lavfi', '-i', 'color=c=red:size=320x240', '-update', '1', '-frames:v', '1', p2]);

  child = spawnServer(spawn, process.execPath, ['src/index.js'], {
    ...process.env, PORT: String(PORT), DATA_DIR: dataDir, RENDER_WORKER: 'true',
  });
  await waitForHealthy(BASE, child);
});

after(async () => {
  child?.kill();
  await new Promise((r) => setTimeout(r, 500));
  try { rmSync(dataDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 }); } catch { /* 気にしない */ }
  try { rmSync(assetDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 }); } catch { /* 気にしない */ }
});

test('写真だけのまとめ動画が完走し、指定した寸法になる（回帰防止）', { timeout: 60000 }, async () => {
  await api('/api/auth/signup', {
    method: 'POST',
    body: JSON.stringify({ username: 'photouser', password: 'password123', displayName: '写真テスト' }),
  });
  const log = await api('/api/logs', { method: 'POST', body: JSON.stringify({ name: '写真だけログ' }) });
  const logId = log.body.log.id;

  const c1 = await uploadPhoto(logId, path.join(assetDir, 'p1.jpg'), '写真1');
  const c2 = await uploadPhoto(logId, path.join(assetDir, 'p2.jpg'), '写真2');

  const render = await api(`/api/logs/${logId}/renders`, {
    method: 'POST',
    body: JSON.stringify({
      cutIds: [c1, c2],
      style: { size: 'square', fit: 'cover', photoMs: 500 },
      label: '写真だけテスト',
    }),
  });
  assert.equal(render.status, 200, JSON.stringify(render.body));

  const job = await waitJob(render.body.jobId);
  assert.equal(job.status, 'done', job.message || '');
  assert.equal(job.result.width, 1080);
  assert.equal(job.result.height, 1080);
  assert.equal(job.result.cutCount, 2);
});
