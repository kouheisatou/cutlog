-- 「プライベート」ログを区別するための列。
--   shared  … 招待してみんなで使うログ（これまでのログはすべてこれ）
--   private … 本人だけのログ。誰も招待できず、行き先を選ばなかったカットはここへ入る
ALTER TABLE logs ADD COLUMN kind TEXT NOT NULL DEFAULT 'shared';
CREATE INDEX IF NOT EXISTS idx_logs_owner_kind ON logs(owner_id, kind);

-- 既定の記録先。空ならプライベートへ入る。利用者が自分で変えられる。
ALTER TABLE users ADD COLUMN default_log_id TEXT;
-- まとめ動画の見た目の設定（JSON）。前に使った設定を次も使う。
ALTER TABLE users ADD COLUMN render_prefs TEXT;
