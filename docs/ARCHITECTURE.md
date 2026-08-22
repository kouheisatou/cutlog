# 全体の作り

```
ブラウザ（PWA・素のESモジュール）
   │  fetch / multipart
   ▼
Express（src/routes/api.js）
   ├── 認証        src/auth/       ローカル or OIDC
   ├── DB          src/db/         SQLite または PostgreSQL（同じAPI）
   ├── 保存先      src/storage/    ローカルディスク または S3互換
   └── ジョブ      src/jobs/       DBキュー → ffmpeg（まとめ動画）
```

## 考え方

- **ビルド工程を作らない。** フロントは素のESモジュール、サーバは素のJavaScriptで書く。`npm install` の直後から直せる
- **アダプタで環境差を吸収する。** DBと保存先は同じAPIで包み、呼び出し側は違いを知らない
- **重い処理はキューへ。** ffmpegはジョブにして、Webのプロセスと分けられるようにする
- **設定は環境変数だけにする。** 設定ファイルを増やさない

## データの形

| テーブル | 役割 |
|---|---|
| `users` / `sessions` | 人とログイン。**既定の記録先（`default_log_id`）とまとめ動画の見た目（`render_prefs`）もここに持つ** |
| `logs` / `memberships` | ログ（グループ）と参加者。**`kind` で共有ログ（`shared`）とプライベートログ（`private`）を区別する** |
| `cuts` | 1回の記録。**メタデータはここに全部持つ** |
| `reactions` / `comments` | 反応 |
| `shares` / `share_cuts` | 共有リンクと、**そこに含めるカット** |
| `jobs` | まとめ動画などの重い処理 |
| `push_subs` / `reminders` / `reminder_fires` | 通知 |
| `audit_log` | 誰が何をしたか |

**共有と書き出しは、どちらも「カットの集合を選ぶ」操作である。** だから `share_cuts` のように1件ずつ明示して持たせている。
「この日は全部」という持ち方をしない（後から1カットだけ外せなくなるため）。だから、カットを別のログへ動かしたときは、
その `share_cuts` から外す（動かした時点のログを前提にした共有を、ログが変わったあとも残さない）。

## プライベートログと既定の記録先

利用者は1人につき、`kind='private'` のログを必ず1つ持つ（`src/lib/private-log.js` の `ensurePrivateLog`。
無ければ初回アクセス時に作る）。プライベートログには誰も招待できず、本人も抜けられず、招待コードも使えない
（`isPrivate()` で判定し、招待の作り直し・メンバーの削除・招待コードでの参加を該当のAPIで弾く）。

行き先を指定しないアップロード（`POST /api/cuts`）は「既定の記録先」に入る。既定の記録先は
`users.default_log_id` に持ち、利用者が `PATCH /api/me` の `defaultLogId` で変えられる。指定した先の
メンバーでなくなっていれば、プライベートログへ自動で戻す（`resolveDefaultLog`）。

## カットの付け替え

撮ったあとのカットは、別のログへ動かせる（`POST /api/cuts/:cutId/move` で1件、`POST /api/logs/:logId/cuts/move`
でまとめて）。動かせるのは、自分で撮ったカットと、元のログのオーナー（管理者はどちらも動かせる）。
移す先は自分がメンバーのログに限り、`logs.kind` による制限はない。

## まとめ動画の見た目

SetLogは見た目が固定だが、cutlogはここを全部変えられる。既定値・入力の丸め・ffmpegのフィルタ組み立てを
`src/lib/render-style.js` の1ファイルに閉じ込め、`POST /api/logs/:logId/renders` の `style` と
`PATCH /api/me` の `renderStyle` の両方がここを通る。渡した見た目は `users.render_prefs` へ次回の既定として
保存されるので、渡さなければ前に使った設定で作られる。焼き込む文字のフォントは `RENDER_FONT_FILE` で指定し、
空ならffmpegが持っている既定のフォントを使う。

## ジョブキュー

`jobs` テーブルに積み、ワーカーが1件ずつ取る。

- PostgreSQL: `SELECT ... FOR UPDATE SKIP LOCKED` を使うので、複数台でも取り合わない
- SQLite: トランザクションの中で `status='queued'` を条件に更新し、更新できた側が勝つ

Webとワーカーを分けるときは、Web側を `RENDER_WORKER=false`、ワーカー側を `true` にする。

## 認証

- ローカル: `scrypt`（Node標準）でハッシュする。セッションはDBに置き、Cookieにはトークンだけを入れる
- OIDC: `openid-client` でPKCEを使う。`.env` に issuer・client id・secret を書くと、ログイン画面にボタンが出る
- 最初に登録した人が管理者になる。以降は `ADMIN_USERNAMES` か管理APIで足す

## メディア

1. 端末で撮る
2. multipartで送る
3. `ffprobe` でメタデータを読み、`ffmpeg` でサムネイルを作る
4. 保存先（ローカル or S3）へ置く

配信は `/api/media/:cutId` の1本にまとめてある。**メンバーか、そのカットを含む共有リンクの持ち主だけ**が取れる。
**元ファイルには手を入れない**（書き出しでそのまま出せるようにするため）。
