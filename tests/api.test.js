// APIの結合テスト。SQLite でも PostgreSQL でも同じものが通る。
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnServer, waitForHealthy } from './helpers/server.js';

const PORT = 8899;
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
  dataDir = mkdtempSync(path.join(os.tmpdir(), 'cutlog-test-'));
  child = spawnServer(spawn, process.execPath, ['src/index.js'], {
    ...process.env, PORT: String(PORT), DATA_DIR: dataDir, RENDER_WORKER: 'false',
  });
  await waitForHealthy(BASE, child);
});

after(async () => {
  child?.kill();
  // Windows ではファイルが解放されるまで少し待つ。消せなくてもテストは落とさない。
  await new Promise((r) => setTimeout(r, 500));
  try { rmSync(dataDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 }); } catch { /* 気にしない */ }
});

test('ヘルスチェックが返る', async () => {
  const { status, body } = await api('/api/healthz');
  assert.equal(status, 200);
  assert.equal(body.ok, true);
});

test('登録すると、最初の人が管理者になる', async () => {
  const { status, body } = await api('/api/auth/signup', {
    method: 'POST',
    body: JSON.stringify({ username: 'tester', password: 'password123', displayName: 'テスト' }),
  });
  assert.equal(status, 200);
  assert.equal(body.user.isAdmin, true);
});

test('ログを作り、カットを上げて、一覧に出る', async () => {
  const log = await api('/api/logs', { method: 'POST', body: JSON.stringify({ name: 'テストログ' }) });
  assert.equal(log.status, 200);
  const logId = log.body.log.id;

  const fd = new FormData();
  fd.append('file', new Blob([new Uint8Array([255, 216, 255, 217])], { type: 'image/jpeg' }), 'cut.jpg');
  fd.append('meta', JSON.stringify({ kind: 'photo', takenAt: new Date().toISOString(), tzOffset: -540 }));
  const up = await api(`/api/logs/${logId}/cuts`, { method: 'POST', body: fd });
  assert.equal(up.status, 200);
  assert.equal(up.body.cut.kind, 'photo');

  const list = await api(`/api/logs/${logId}/cuts`);
  assert.equal(list.body.cuts.length, 1);
  assert.ok(list.body.cuts[0].localDate);
});

test('共有リンクは、選んだカットだけを見せる', async () => {
  const { body: { logs } } = await api('/api/logs');
  // プライベートログが自動でできて先頭に来るので、カットを上げた「テストログ」を選ぶ
  const logId = logs.find((l) => l.kind !== 'private').id;
  const { body: { cuts } } = await api(`/api/logs/${logId}/cuts`);
  const share = await api(`/api/logs/${logId}/shares`, {
    method: 'POST',
    body: JSON.stringify({ cutIds: [cuts[0].id], title: 'テスト共有' }),
  });
  assert.equal(share.status, 200);
  const token = share.body.share.token;

  const saved = cookie;
  cookie = ''; // ログインしていない人として見る
  const pub = await api(`/api/public/${token}`, { method: 'POST', body: JSON.stringify({}) });
  assert.equal(pub.status, 200);
  assert.equal(pub.body.cuts.length, 1);
  cookie = saved;
});

test('書き出しはZIPを返す', async () => {
  const { body: { logs } } = await api('/api/logs');
  const logId = logs.find((l) => l.kind !== 'private').id;
  const { body: { cuts } } = await api(`/api/logs/${logId}/cuts`);
  const res = await fetch(`${BASE}/api/logs/${logId}/export`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', cookie },
    body: JSON.stringify({ cutIds: cuts.map((c) => c.id) }),
  });
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('content-type'), 'application/zip');
  const buf = Buffer.from(await res.arrayBuffer());
  assert.equal(buf.subarray(0, 2).toString(), 'PK');
});

test('ログインしていない人は、ログの一覧を取れない', async () => {
  const saved = cookie;
  cookie = '';
  const { status } = await api('/api/logs');
  assert.equal(status, 401);
  cookie = saved;
});
