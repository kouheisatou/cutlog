-- 撮った場所。分かるときだけ入れる（端末が許さないこともあるので、無くても構わない）。
-- 緯度・経度は度で持ち、accuracy は「だいたい何メートルの誤差か」を表す。
ALTER TABLE cuts ADD COLUMN lat REAL;
ALTER TABLE cuts ADD COLUMN lon REAL;
ALTER TABLE cuts ADD COLUMN place_accuracy REAL;
