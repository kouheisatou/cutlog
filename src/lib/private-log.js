// 「プライベート」ログは、利用者1人につき必ず1つある。
// 誰も招待できず、行き先を選ばずに撮ったカットはここへ入る。
import { db, nowIso } from '../db/index.js';
import { id, inviteCode } from './util.js';

export const PRIVATE_LOG_NAME = 'プライベート';

// 無ければ作って返す。既にあればそれを返す（何度呼んでもよい）。
export async function ensurePrivateLog(userId) {
  const found = await db.get(
    "SELECT * FROM logs WHERE owner_id = ? AND kind = 'private' ORDER BY created_at LIMIT 1", [userId],
  );
  if (found) return found;
  const lid = id('l_');
  const now = nowIso();
  try {
    await db.run(
      `INSERT INTO logs (id, name, owner_id, invite_code, cut_seconds, kind, created_at, updated_at)
       VALUES (?,?,?,?,?,?,?,?)`,
      [lid, PRIVATE_LOG_NAME, userId, inviteCode(), 3, 'private', now, now],
    );
  } catch (err) {
    // 同時に呼ばれて先に作られたときは、そちらを使う（一意索引が止めてくれる）
    const other = await db.get(
      "SELECT * FROM logs WHERE owner_id = ? AND kind = 'private' ORDER BY created_at LIMIT 1", [userId],
    );
    if (other) return other;
    throw err;
  }
  await db.run('INSERT INTO memberships (log_id, user_id, role, joined_at) VALUES (?,?,?,?)',
    [lid, userId, 'owner', now]);
  return db.get('SELECT * FROM logs WHERE id = ?', [lid]);
}

export function isPrivate(log) {
  return !!log && log.kind === 'private';
}
