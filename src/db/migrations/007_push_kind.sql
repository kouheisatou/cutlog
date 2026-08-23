-- 通知の届け先に「種類」を持たせる。
-- ★ これまではブラウザの購読（Web Push）だけだったが、iOS / Android のアプリは
--   Firebase 経由で届ける。同じ表に混ぜて置き、送るときに分ける。
--   既にある行は Web Push なので、既定値をそちらにしておく。
ALTER TABLE push_subs ADD COLUMN kind TEXT NOT NULL DEFAULT 'webpush';
