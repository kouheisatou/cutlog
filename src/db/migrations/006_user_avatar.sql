-- アカウントの顔。保存先に置いた画像の鍵を持つ（無いときは頭文字で出す）。
ALTER TABLE users ADD COLUMN avatar_key TEXT;
