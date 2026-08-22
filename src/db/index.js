// DBアダプタ。SQLite（既定・設定なしで動く）と PostgreSQL（大きめの環境）の両方を同じAPIで扱う。
//
// SQLは `?` のプレースホルダで書く。PostgreSQL では $1, $2 ... へ自動で置き換える。
// 方言に寄る書き方（RETURNING・UPSERTの構文差など）はここに閉じ込め、呼び出し側では使わない。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from '../config.js';

const here = path.dirname(fileURLToPath(import.meta.url));

function toPgSql(sql) {
  let i = 0;
  return sql.replace(/\?/g, () => `$${++i}`);
}

class SqliteDb {
  constructor(file) {
    // Node 22+ に同梱。ネイティブ拡張を足さないので、誰でも `npm i` だけで動く。
    const { DatabaseSync } = require('node:sqlite');
    fs.mkdirSync(path.dirname(file), { recursive: true });
    this.raw = new DatabaseSync(file);
    this.raw.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');
    this.driver = 'sqlite';
  }

  async all(sql, params = []) { return this.raw.prepare(sql).all(...params); }

  async get(sql, params = []) { return this.raw.prepare(sql).get(...params) ?? null; }

  async run(sql, params = []) { return this.raw.prepare(sql).run(...params); }

  async exec(sql) { return this.raw.exec(sql); }

  async tx(fn) {
    this.raw.exec('BEGIN');
    try {
      const out = await fn(this);
      this.raw.exec('COMMIT');
      return out;
    } catch (err) {
      this.raw.exec('ROLLBACK');
      throw err;
    }
  }

  async close() { this.raw.close(); }
}

class PostgresDb {
  constructor(pool) {
    this.pool = pool;
    this.driver = 'postgres';
  }

  async all(sql, params = []) { return (await this.pool.query(toPgSql(sql), params)).rows; }

  async get(sql, params = []) { return (await this.pool.query(toPgSql(sql), params)).rows[0] ?? null; }

  async run(sql, params = []) {
    const r = await this.pool.query(toPgSql(sql), params);
    return { changes: r.rowCount };
  }

  async exec(sql) { return this.pool.query(sql); }

  async tx(fn) {
    const client = await this.pool.connect();
    const scoped = {
      driver: 'postgres',
      all: async (s, p = []) => (await client.query(toPgSql(s), p)).rows,
      get: async (s, p = []) => (await client.query(toPgSql(s), p)).rows[0] ?? null,
      run: async (s, p = []) => ({ changes: (await client.query(toPgSql(s), p)).rowCount }),
      exec: async (s) => client.query(s),
    };
    try {
      await client.query('BEGIN');
      const out = await fn(scoped);
      await client.query('COMMIT');
      return out;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async close() { await this.pool.end(); }
}

// node:sqlite は CommonJS の require が要るので用意する
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

export let db = null;

export async function initDb() {
  if (config.db.driver === 'postgres') {
    const { default: pg } = await import('pg');
    const pool = new pg.Pool({ connectionString: config.db.url, max: Number(process.env.PG_POOL_MAX || 10) });
    await pool.query('SELECT 1');
    db = new PostgresDb(pool);
  } else {
    const file = config.db.sqliteFile || path.join(config.dataDir, 'cutlog.db');
    db = new SqliteDb(file);
  }
  await migrate();
  return db;
}

// ── マイグレーション（SQLファイルを順に流す） ─────────────────────
async function migrate() {
  await db.exec(`CREATE TABLE IF NOT EXISTS schema_migrations (
    name TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL
  )`);
  const dir = path.join(here, 'migrations');
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
  for (const f of files) {
    const done = await db.get('SELECT 1 AS ok FROM schema_migrations WHERE name = ?', [f]);
    if (done) continue;
    const sql = fs.readFileSync(path.join(dir, f), 'utf8');
    const body = pickDialect(sql, db.driver);
    await db.exec(body);
    await db.run('INSERT INTO schema_migrations (name, applied_at) VALUES (?, ?)', [f, new Date().toISOString()]);
    console.log(`[db] applied ${f}`);
  }
}

// マイグレーションSQLの中で方言を分ける。
//   -- @sqlite ... -- @end   /   -- @postgres ... -- @end
function pickDialect(sql, driver) {
  const other = driver === 'sqlite' ? 'postgres' : 'sqlite';
  return sql
    .replace(new RegExp(`--\\s*@${other}[\\s\\S]*?--\\s*@end`, 'g'), '')
    .replace(new RegExp(`--\\s*@${driver}\\s*`, 'g'), '')
    .replace(/--\s*@end\s*/g, '');
}

export function nowIso() { return new Date().toISOString(); }
