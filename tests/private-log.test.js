// プライベートログ・既定の記録先・カットの付け替え の結合テスト。
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnServer, waitForHealthy } from './helpers/server.js';

const PORT = 8901;
const BASE = `http://127.0.0.1:${PORT}`;
let child;
let dataDir;

// 利用者ごとにクッキーを持つクライアントを作る（api.test.js と違い、複数人が同時に必要なため）。
function makeClient() {
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
  api.clearCookie = () => { cookie = ''; };
  return api;
}

function fileForm(bytes = [255, 216, 255, 217], name = 'cut.jpg') {
  const fd = new FormData();
  fd.append('file', new Blob([new Uint8Array(bytes)], { type: 'image/jpeg' }), name);
  fd.append('meta', JSON.stringify({ kind: 'photo', takenAt: new Date().toISOString(), tzOffset: -540 }));
  return fd;
}

before(async () => {
  dataDir = mkdtempSync(path.join(os.tmpdir(), 'cutlog-test-priv-'));
  child = spawnServer(spawn, process.execPath, ['src/index.js'], {
    ...process.env, PORT: String(PORT), DATA_DIR: dataDir, RENDER_WORKER: 'false',
  });
  await waitForHealthy(BASE, child);
});

after(async () => {
  child?.kill();
  await new Promise((r) => setTimeout(r, 500));
  try { rmSync(dataDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 }); } catch { /* 気にしない */ }
});

const alice = makeClient();
const bob = makeClient();

let alicePrivate;
let aliceShared; // アリスがオーナーの共有ログ（ボブも参加）

test('登録すると、プライベートという名前のログが自動でできる', async () => {
  const signup = await alice('/api/auth/signup', {
    method: 'POST',
    body: JSON.stringify({ username: 'alice', password: 'password123', displayName: 'アリス' }),
  });
  assert.equal(signup.status, 200);

  const { status, body } = await alice('/api/logs');
  assert.equal(status, 200);
  assert.equal(body.logs.length, 1);
  alicePrivate = body.logs[0];
  assert.equal(alicePrivate.kind, 'private');
  assert.equal(alicePrivate.name, 'プライベート');
});

test('GET /api/logs の先頭にプライベートが来る', async () => {
  const created = await alice('/api/logs', { method: 'POST', body: JSON.stringify({ name: '共有ログ' }) });
  assert.equal(created.status, 200);
  aliceShared = created.body.log;

  const { body } = await alice('/api/logs');
  assert.equal(body.logs.length, 2);
  assert.equal(body.logs[0].kind, 'private');
  assert.equal(body.logs[0].id, alicePrivate.id);
});

test('プライベートの招待コードで参加しようとすると404になる', async () => {
  const { status, body } = await alice('/api/logs/join', {
    method: 'POST',
    body: JSON.stringify({ code: alicePrivate.invite_code }),
  });
  assert.equal(status, 404);
  assert.ok(body.error);
});

test('プライベートは招待コードを回せない（400）', async () => {
  const { status } = await alice(`/api/logs/${alicePrivate.id}/invite/rotate`, { method: 'POST' });
  assert.equal(status, 400);
});

test('プライベートからは抜けられない（400）', async () => {
  const { status } = await alice(`/api/logs/${alicePrivate.id}/members/${alicePrivate.owner_id}`, { method: 'DELETE' });
  assert.equal(status, 400);
});

test('GET /api/me は privateLogId・defaultLogId・renderStyle を返し、初期状態では両IDが一致する', async () => {
  const { status, body } = await alice('/api/me');
  assert.equal(status, 200);
  assert.equal(body.privateLogId, alicePrivate.id);
  assert.equal(body.defaultLogId, alicePrivate.id);
  assert.ok(body.renderStyle);
  assert.equal(body.renderStyle.size, 'landscape');
});

test('PATCH /api/me で defaultLogId を参加済みの別ログへ変えられる', async () => {
  const { status, body } = await alice('/api/me', {
    method: 'PATCH',
    body: JSON.stringify({ defaultLogId: aliceShared.id }),
  });
  assert.equal(status, 200);
  assert.equal(body.defaultLogId, aliceShared.id);

  const me = await alice('/api/me');
  assert.equal(me.body.defaultLogId, aliceShared.id);
});

test('PATCH /api/me で参加していないログを渡すと400になる', async () => {
  const { status } = await alice('/api/me', {
    method: 'PATCH',
    body: JSON.stringify({ defaultLogId: 'l_doesnotexist' }),
  });
  assert.equal(status, 400);
});

test('PATCH /api/me に null を渡すとプライベートへ戻る', async () => {
  const { status, body } = await alice('/api/me', {
    method: 'PATCH',
    body: JSON.stringify({ defaultLogId: null }),
  });
  assert.equal(status, 200);
  assert.equal(body.defaultLogId, alicePrivate.id);
});

test('logIdを指定しないアップロードは、既定の記録先（プライベート）へ入る', async () => {
  const up = await alice('/api/cuts', { method: 'POST', body: fileForm() });
  assert.equal(up.status, 200);
  assert.equal(up.body.cut.logId, alicePrivate.id);
});

test('既定の記録先を共有ログへ変えると、logIdなしアップロードもそこへ入る', async () => {
  await alice('/api/me', { method: 'PATCH', body: JSON.stringify({ defaultLogId: aliceShared.id }) });
  const up = await alice('/api/cuts', { method: 'POST', body: fileForm() });
  assert.equal(up.status, 200);
  assert.equal(up.body.cut.logId, aliceShared.id);
  // 後片付け：以後のテストのため既定をプライベートへ戻す
  await alice('/api/me', { method: 'PATCH', body: JSON.stringify({ defaultLogId: null }) });
});

test('PATCH /api/me に renderStyle を渡すと保存され、GET /api/me で丸められた形が返る', async () => {
  const patch = await alice('/api/me', {
    method: 'PATCH',
    body: JSON.stringify({ renderStyle: { fps: 999, time: { fontSize: 999 } } }),
  });
  assert.equal(patch.status, 200);
  assert.equal(patch.body.renderStyle.fps, 60);
  assert.equal(patch.body.renderStyle.time.fontSize, 160);

  const me = await alice('/api/me');
  assert.equal(me.body.renderStyle.fps, 60);
  assert.equal(me.body.renderStyle.time.fontSize, 160);
});

// ── カットの付け替え ────────────────────────────────────
let logA; // アリスがオーナー。ボブも参加
let logB; // アリスがオーナー。ボブは参加していない
let logC; // アリスがオーナー。ボブも参加（logAとは別にボブが参加している2つ目のログ）
let cutByAlice;
let cutByBob;

test('準備：ボブが登録し、アリスの共有ログへ参加する', async () => {
  const signup = await bob('/api/auth/signup', {
    method: 'POST',
    body: JSON.stringify({ username: 'bob', password: 'password123', displayName: 'ボブ' }),
  });
  assert.equal(signup.status, 200);
  assert.equal(signup.body.user.isAdmin, false);

  const createA = await alice('/api/logs', { method: 'POST', body: JSON.stringify({ name: 'ログA' }) });
  logA = createA.body.log;
  const createB = await alice('/api/logs', { method: 'POST', body: JSON.stringify({ name: 'ログB' }) });
  logB = createB.body.log;
  const createC = await alice('/api/logs', { method: 'POST', body: JSON.stringify({ name: 'ログC' }) });
  logC = createC.body.log;

  const joinA = await bob('/api/logs/join', { method: 'POST', body: JSON.stringify({ code: logA.invite_code }) });
  assert.equal(joinA.status, 200);
  const joinC = await bob('/api/logs/join', { method: 'POST', body: JSON.stringify({ code: logC.invite_code }) });
  assert.equal(joinC.status, 200);
  // logB にはボブを参加させない（403のテストで使う）
});

test('準備：アリスとボブがそれぞれログAへカットを上げる', async () => {
  const upA = await alice(`/api/logs/${logA.id}/cuts`, { method: 'POST', body: fileForm() });
  assert.equal(upA.status, 200);
  cutByAlice = upA.body.cut;

  const upB = await bob(`/api/logs/${logA.id}/cuts`, { method: 'POST', body: fileForm() });
  assert.equal(upB.status, 200);
  cutByBob = upB.body.cut;
});

test('移す先のメンバーでなければ403になる', async () => {
  const move = await bob(`/api/cuts/${cutByBob.id}/move`, {
    method: 'POST',
    body: JSON.stringify({ logId: logB.id }), // ボブはlogBのメンバーではない
  });
  assert.equal(move.status, 403);
});

test('自分のカットを別のログへ動かせる（元のログからは消え、新しいログに出る）', async () => {
  const move = await bob(`/api/cuts/${cutByBob.id}/move`, {
    method: 'POST',
    body: JSON.stringify({ logId: logC.id }), // ボブはlogCのメンバーでもある
  });
  assert.equal(move.status, 200);
  assert.equal(move.body.cut.logId, logC.id);

  const inNew = await bob(`/api/logs/${logC.id}/cuts`);
  assert.ok(inNew.body.cuts.some((c) => c.id === cutByBob.id));

  const inOld = await bob(`/api/logs/${logA.id}/cuts`);
  assert.ok(!inOld.body.cuts.some((c) => c.id === cutByBob.id));
});

test('他人のカットは動かせない（動かす側がメンバーに過ぎない場合）', async () => {
  // ボブはlogAのメンバー（role=member）。アリスが上げたカット（cutByAlice）を
  // ボブが参加している別ログ（logC）へ動かそうとすると、権限がなく失敗する。
  const move = await bob(`/api/cuts/${cutByAlice.id}/move`, {
    method: 'POST',
    body: JSON.stringify({ logId: logC.id }),
  });
  assert.equal(move.status, 400);
  assert.ok(move.body.error);
});

test('オーナーでも、他の人が撮ったカットは動かせない', async () => {
  // アリスはlogAのオーナーだが、ボブが撮ったカットを自分のログへ持ち出すことはできない。
  // （持ち出せると、撮った本人が二度と見られなくなる）
  const upBob2 = await bob(`/api/logs/${logA.id}/cuts`, { method: 'POST', body: fileForm() });
  const cutByBob2 = upBob2.body.cut;

  const move = await alice(`/api/cuts/${cutByBob2.id}/move`, {
    method: 'POST',
    body: JSON.stringify({ logId: logB.id }),
  });
  assert.equal(move.status, 400);

  // logAに残ったままである
  const inOld = await alice(`/api/logs/${logA.id}/cuts`);
  assert.ok(inOld.body.cuts.some((c) => c.id === cutByBob2.id));

  // まとめて動かす方でも、skippedへ入って動かない
  const bulk = await alice(`/api/logs/${logB.id}/cuts/move`, {
    method: 'POST',
    body: JSON.stringify({ cutIds: [cutByBob2.id] }),
  });
  assert.equal(bulk.status, 200);
  assert.deepEqual(bulk.body.moved, []);
  assert.equal(bulk.body.skipped.length, 1);
});

test('動かしたカットは、元の共有リンクから外れる', async () => {
  // logAへ新しいカットを上げ、共有を作ってからlogBへ動かす。
  const up = await alice(`/api/logs/${logA.id}/cuts`, { method: 'POST', body: fileForm() });
  const cut = up.body.cut;
  const share = await alice(`/api/logs/${logA.id}/shares`, {
    method: 'POST',
    body: JSON.stringify({ cutIds: [cut.id], title: '共有テスト' }),
  });
  assert.equal(share.status, 200);
  const token = share.body.share.token;

  const beforeMove = await alice('/api/public/' + token, { method: 'POST', body: JSON.stringify({}) });
  assert.equal(beforeMove.body.cuts.length, 1);

  const move = await alice(`/api/cuts/${cut.id}/move`, { method: 'POST', body: JSON.stringify({ logId: logB.id }) });
  assert.equal(move.status, 200);

  const afterMove = await alice('/api/public/' + token, { method: 'POST', body: JSON.stringify({}) });
  assert.equal(afterMove.body.cuts.length, 0);
});

test('まとめて動かすAPIは {moved, skipped} を返す', async () => {
  const up1 = await alice(`/api/logs/${logA.id}/cuts`, { method: 'POST', body: fileForm() });
  const good = up1.body.cut.id;
  const bad = 'c_doesnotexist';

  const { status, body } = await alice(`/api/logs/${logB.id}/cuts/move`, {
    method: 'POST',
    body: JSON.stringify({ cutIds: [good, bad] }),
  });
  assert.equal(status, 200);
  assert.deepEqual(body.moved, [good]);
  assert.equal(body.skipped.length, 1);
  assert.equal(body.skipped[0].cutId, bad);
});
