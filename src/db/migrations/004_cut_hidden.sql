-- カットごとの「非表示」。
-- 選ぶ／選ばないではなく、そのログの中でこのカットを出すかどうかの状態として持つ。
-- 非表示にしたものは、日の連続再生から外れる（消えるわけではない）。
ALTER TABLE cuts ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0;
