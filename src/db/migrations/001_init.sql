-- cutlog 初期スキーマ。SQLite と PostgreSQL の両方で流れるように、共通の型だけで書く。
-- 日時は ISO8601 の TEXT で持つ（両方で同じ比較ができるため）。

CREATE TABLE IF NOT EXISTS users (
  id            TEXT PRIMARY KEY,
  username      TEXT NOT NULL UNIQUE,
  display_name  TEXT NOT NULL,
  email         TEXT,
  password_hash TEXT,
  auth_provider TEXT NOT NULL DEFAULT 'local',
  external_id   TEXT,
  is_admin      INTEGER NOT NULL DEFAULT 0,
  disabled      INTEGER NOT NULL DEFAULT 0,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_external ON users(auth_provider, external_id);

CREATE TABLE IF NOT EXISTS sessions (
  token      TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_agent TEXT,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);

CREATE TABLE IF NOT EXISTS logs (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  owner_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  invite_code TEXT NOT NULL UNIQUE,
  cut_seconds INTEGER NOT NULL DEFAULT 3,
  archived    INTEGER NOT NULL DEFAULT 0,
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS memberships (
  log_id    TEXT NOT NULL REFERENCES logs(id) ON DELETE CASCADE,
  user_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role      TEXT NOT NULL DEFAULT 'member',
  joined_at TEXT NOT NULL,
  PRIMARY KEY (log_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_memberships_user ON memberships(user_id);

CREATE TABLE IF NOT EXISTS cuts (
  id          TEXT PRIMARY KEY,
  log_id      TEXT NOT NULL REFERENCES logs(id) ON DELETE CASCADE,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind        TEXT NOT NULL,
  storage_key TEXT NOT NULL,
  thumb_key   TEXT,
  mime        TEXT NOT NULL,
  bytes       INTEGER NOT NULL,
  duration_ms INTEGER,
  width       INTEGER,
  height      INTEGER,
  facing      TEXT,
  source      TEXT NOT NULL DEFAULT 'camera',
  taken_at    TEXT NOT NULL,
  tz_offset   INTEGER NOT NULL DEFAULT 0,
  local_date  TEXT NOT NULL,
  note        TEXT,
  tags        TEXT,
  checksum    TEXT,
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL,
  deleted_at  TEXT
);
CREATE INDEX IF NOT EXISTS idx_cuts_log_date ON cuts(log_id, local_date);
CREATE INDEX IF NOT EXISTS idx_cuts_log_taken ON cuts(log_id, taken_at);

CREATE TABLE IF NOT EXISTS reactions (
  id         TEXT PRIMARY KEY,
  cut_id     TEXT NOT NULL REFERENCES cuts(id) ON DELETE CASCADE,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  emoji      TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE (cut_id, user_id, emoji)
);

CREATE TABLE IF NOT EXISTS comments (
  id         TEXT PRIMARY KEY,
  cut_id     TEXT NOT NULL REFERENCES cuts(id) ON DELETE CASCADE,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body       TEXT NOT NULL,
  created_at TEXT NOT NULL,
  deleted_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_comments_cut ON comments(cut_id);

CREATE TABLE IF NOT EXISTS shares (
  id             TEXT PRIMARY KEY,
  log_id         TEXT NOT NULL REFERENCES logs(id) ON DELETE CASCADE,
  token          TEXT NOT NULL UNIQUE,
  title          TEXT NOT NULL,
  password_hash  TEXT,
  expires_at     TEXT,
  allow_download INTEGER NOT NULL DEFAULT 1,
  view_count     INTEGER NOT NULL DEFAULT 0,
  created_by     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at     TEXT NOT NULL,
  revoked_at     TEXT
);

CREATE TABLE IF NOT EXISTS share_cuts (
  share_id TEXT NOT NULL REFERENCES shares(id) ON DELETE CASCADE,
  cut_id   TEXT NOT NULL REFERENCES cuts(id) ON DELETE CASCADE,
  PRIMARY KEY (share_id, cut_id)
);

CREATE TABLE IF NOT EXISTS push_subs (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  endpoint   TEXT NOT NULL UNIQUE,
  p256dh     TEXT NOT NULL,
  auth       TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS reminders (
  user_id    TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  mode       TEXT NOT NULL DEFAULT 'off',
  times      TEXT,
  from_hour  INTEGER NOT NULL DEFAULT 9,
  to_hour    INTEGER NOT NULL DEFAULT 22,
  per_day    INTEGER NOT NULL DEFAULT 6,
  tz_offset  INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS reminder_fires (
  user_id TEXT NOT NULL,
  slot    TEXT NOT NULL,
  PRIMARY KEY (user_id, slot)
);

-- まとめ動画などの重い処理は、DBのキューに積んでワーカーが拾う（複数台でも動く）
CREATE TABLE IF NOT EXISTS jobs (
  id           TEXT PRIMARY KEY,
  kind         TEXT NOT NULL,
  payload      TEXT NOT NULL,
  status       TEXT NOT NULL DEFAULT 'queued',
  attempts     INTEGER NOT NULL DEFAULT 0,
  locked_by    TEXT,
  locked_at    TEXT,
  message      TEXT,
  result       TEXT,
  log_id       TEXT,
  created_by   TEXT,
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL,
  finished_at  TEXT
);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status, created_at);
CREATE INDEX IF NOT EXISTS idx_jobs_log ON jobs(log_id, created_at);

CREATE TABLE IF NOT EXISTS audit_log (
  id         TEXT PRIMARY KEY,
  user_id    TEXT,
  action     TEXT NOT NULL,
  target     TEXT,
  detail     TEXT,
  ip         TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at);
