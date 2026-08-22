// ジョブが失敗したとき、GET /api/jobs/:id が読める理由を返すことの回帰テスト（E12）。
// FFMPEG_PATH を存在しないパスにして書き出し、3回のリトライの末に status=error になり、
// message が空でないことを確かめる。
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnServer, waitForHealthy } from './helpers/server.js';

const PORT = 8897;
const BASE = `http://127.0.0.1:${PORT}`;
let child;
let dataDir;
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

before(async () => {
  dataDir = mkdtempSync(path.join(os.tmpdir(), 'cutlog-jobs-error-test-'));
  child = spawnServer(spawn, process.execPath, ['src/index.js'], {
    ...process.env,
    PORT: String(PORT),
    DATA_DIR: dataDir,
    RENDER_WORKER: 'true',
    FFMPEG_PATH: path.join(os.tmpdir(), 'no-such-ffmpeg-binary.exe'),
  });
  await waitForHealthy(BASE, child);
});

after(async () => {
  child?.kill();
  await new Promise((r) => setTimeout(r, 500));
  try { rmSync(dataDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 }); } catch { /* 気にしない */ }
});

test('ffmpegが無いとき、ジョブは理由つきでerrorになる', { timeout: 30000 }, async () => {
  await api('/api/auth/signup', {
    method: 'POST',
    body: JSON.stringify({ username: 'erruser', password: 'password123', displayName: 'エラー確認' }),
  });
  const log = await api('/api/logs', { method: 'POST', body: JSON.stringify({ name: 'エラーログ' }) });
  const logId = log.body.log.id;

  const fd = new FormData();
  fd.append('file', new Blob([new Uint8Array([255, 216, 255, 217])], { type: 'image/jpeg' }), 'cut.jpg');
  fd.append('meta', JSON.stringify({ kind: 'photo', takenAt: new Date().toISOString(), tzOffset: -540 }));
  const up = await api(`/api/logs/${logId}/cuts`, { method: 'POST', body: fd });
  assert.equal(up.status, 200);

  const render = await api(`/api/logs/${logId}/renders`, {
    method: 'POST',
    body: JSON.stringify({ cutIds: [up.body.cut.id], label: 'エラーテスト' }),
  });
  assert.equal(render.status, 200);
  const jobId = render.body.jobId;

  let job;
  const t0 = Date.now();
  while (Date.now() - t0 < 20000) {
    // eslint-disable-next-line no-await-in-loop
    const { body } = await api(`/api/jobs/${jobId}`);
    job = body.job;
    if (job.status === 'done' || job.status === 'error') break;
    // eslint-disable-next-line no-await-in-loop
    await new Promise((r) => setTimeout(r, 300));
  }
  assert.equal(job.status, 'error');
  assert.ok(job.message && job.message.length > 0, 'エラーの理由が空であってはいけない');
});
