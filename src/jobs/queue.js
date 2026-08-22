// DBに置くジョブキュー。複数台で動かしても1つのジョブを二重に処理しない。
// PostgreSQL では FOR UPDATE SKIP LOCKED、SQLite ではトランザクションで取り合う。
import os from 'node:os';
import { db, nowIso } from '../db/index.js';
import { config } from '../config.js';
import { id } from '../lib/util.js';

const WORKER_ID = `${os.hostname()}:${process.pid}`;
const handlers = new Map();

// この時間より前から running のままのジョブは、処理していたワーカーが落ちたとみなして拾い直す。
// WORKER_ID（hostname:pid）で絞ると、再起動でpidが変わるたびに一致しなくなり、拾い直しが起きない
// （再起動後は必ず別プロセスになるため、実質いつまでも拾えない）。経過時間で見て、他ワーカーが
// 今まさに処理中のジョブ（locked_at が新しい）は奪わないようにする。
const staleMinutesEnv = process.env.JOB_STALE_MINUTES;
const STALE_RUNNING_MS = (staleMinutesEnv === undefined || staleMinutesEnv === '' ? 15 : Number(staleMinutesEnv)) * 60 * 1000;

export function registerHandler(kind, fn) {
  handlers.set(kind, fn);
}

export async function enqueue(kind, payload, { logId = null, userId = null } = {}) {
  const jid = id('j_');
  await db.run(
    `INSERT INTO jobs (id, kind, payload, status, log_id, created_by, created_at, updated_at)
     VALUES (?,?,?,?,?,?,?,?)`,
    [jid, kind, JSON.stringify(payload), 'queued', logId, userId, nowIso(), nowIso()],
  );
  return jid;
}

export async function getJob(jobId) {
  return db.get('SELECT * FROM jobs WHERE id = ?', [jobId]);
}

async function claimOne() {
  if (db.driver === 'postgres') {
    return db.tx(async (t) => {
      const row = await t.get(
        `SELECT * FROM jobs WHERE status = 'queued' ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED`,
      );
      if (!row) return null;
      await t.run('UPDATE jobs SET status = ?, locked_by = ?, locked_at = ?, updated_at = ? WHERE id = ?',
        ['running', WORKER_ID, nowIso(), nowIso(), row.id]);
      return row;
    });
  }
  return db.tx(async (t) => {
    const row = await t.get(`SELECT * FROM jobs WHERE status = 'queued' ORDER BY created_at LIMIT 1`);
    if (!row) return null;
    const r = await t.run(
      `UPDATE jobs SET status = 'running', locked_by = ?, locked_at = ?, updated_at = ?
        WHERE id = ? AND status = 'queued'`,
      [WORKER_ID, nowIso(), nowIso(), row.id],
    );
    return r.changes ? row : null;
  });
}

async function finish(jobId, status, { message = null, result = null } = {}) {
  await db.run(
    'UPDATE jobs SET status = ?, message = ?, result = ?, updated_at = ?, finished_at = ? WHERE id = ?',
    [status, message, result ? JSON.stringify(result) : null, nowIso(), nowIso(), jobId],
  );
}

let running = 0;
let timer = null;
let recoverTimer = null;

async function tick() {
  if (running >= config.ffmpeg.concurrency) return;
  const job = await claimOne();
  if (!job) return;
  running += 1;
  const handler = handlers.get(job.kind);
  try {
    if (!handler) throw new Error(`未対応のジョブです: ${job.kind}`);
    const result = await handler(JSON.parse(job.payload), job);
    await finish(job.id, 'done', { result });
  } catch (err) {
    const attempts = Number(job.attempts) + 1;
    const retry = attempts < 3;
    await db.run('UPDATE jobs SET attempts = ? WHERE id = ?', [attempts, job.id]);
    if (retry) {
      await db.run('UPDATE jobs SET status = ?, message = ?, updated_at = ? WHERE id = ?',
        ['queued', String(err.message || err).slice(0, 500), nowIso(), job.id]);
    } else {
      await finish(job.id, 'error', { message: String(err.message || err).slice(0, 500) });
    }
  } finally {
    running -= 1;
  }
}

// 落ちたワーカーが running のまま残したジョブを、他ワーカーの処理中のものと区別して拾い直す。
async function recoverStale() {
  const threshold = new Date(Date.now() - STALE_RUNNING_MS).toISOString();
  await db.run(
    `UPDATE jobs SET status = 'queued', locked_by = NULL
      WHERE status = 'running' AND (locked_at IS NULL OR locked_at < ?)`,
    [threshold],
  ).catch(() => {});
}

export function startWorker() {
  if (!config.ffmpeg.worker) {
    console.log('[jobs] このプロセスはワーカーを動かしません（RENDER_WORKER=false）');
    return;
  }
  // 落ちた処理を拾い直す（起動時に一度、その後も一定時間ごとに見に行く）
  recoverStale();
  recoverTimer = setInterval(() => { recoverStale().catch((e) => console.error('[jobs]', e)); }, 5 * 60 * 1000);
  timer = setInterval(() => { tick().catch((e) => console.error('[jobs]', e)); }, 1500);
  console.log(`[jobs] ワーカーを開始しました（同時実行 ${config.ffmpeg.concurrency}）`);
}

export function stopWorker() {
  if (timer) clearInterval(timer);
  if (recoverTimer) clearInterval(recoverTimer);
}
