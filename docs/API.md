# HTTP API

すべて `/api` の下にあります。認証はセッションのCookie（`cutlog_session`）です。

## 認証

| メソッド | パス | 説明 |
|---|---|---|
| POST | `/auth/signup` | 登録する（`AUTH_OPEN_SIGNUP` に従う。最初の1人は必ず作れる） |
| POST | `/auth/login` | ログインする |
| POST | `/auth/logout` | ログアウトする |
| GET | `/auth/oidc/start` | SSOの入口（IdPへリダイレクトする） |
| GET | `/auth/oidc/callback` | SSOの戻り先（IdPからのリダイレクトを受け、ログインしてトップへ戻す） |
| GET | `/me` | 自分の情報・通知の設定・プライベートログのID（`privateLogId`）・既定の記録先（`defaultLogId`）・まとめ動画の見た目（`renderStyle`）を返す |
| PATCH | `/me` | 表示名を変える（`defaultLogId` で既定の記録先を、`renderStyle` でまとめ動画の見た目の既定を変えられる） |

## ログ（グループ）

| メソッド | パス | 説明 |
|---|---|---|
| GET | `/logs` | 参加しているログの一覧 |
| POST | `/logs` | 作る |
| POST | `/logs/join` | 招待コードで参加する |
| GET | `/logs/:logId` | 詳細・メンバー・日付ごとの件数 |
| PATCH | `/logs/:logId` | 名前と秒数を変える（オーナーだけ） |
| POST | `/logs/:logId/invite/rotate` | 招待コードを作り直す |
| DELETE | `/logs/:logId/members/:userId` | 外す（自分なら誰でも、他人はオーナーだけ） |

## カット

| メソッド | パス | 説明 |
|---|---|---|
| GET | `/logs/:logId/cuts` | 一覧（`date` `from` `to` `author` `tag` `q` で絞れる） |
| POST | `/logs/:logId/cuts` | 追加する（multipartで `file` と `meta`） |
| POST | `/cuts` | 行き先を指定せずに追加する（multipartで `file` と `meta`。**既定の記録先**へ入る） |
| GET | `/cuts/:cutId` | 詳細・リアクション・コメント |
| PATCH | `/cuts/:cutId` | メモとタグ |
| DELETE | `/cuts/:cutId` | ゴミ箱へ入れる |
| POST | `/cuts/:cutId/restore` | 戻す |
| POST | `/cuts/:cutId/move` | 1件だけ、別のログへ動かす（`logId`。**動かしたカットは元の共有リンクから外れる**） |
| POST | `/logs/:logId/cuts/move` | まとめて、このログへ動かす（`cutIds`。動かせないカットは `skipped` に理由付きで返る） |
| GET | `/logs/:logId/trash` | ゴミ箱の一覧 |
| POST | `/cuts/:cutId/reactions` | 絵文字（同じものを送ると取り消す） |
| POST | `/cuts/:cutId/comments` | コメントする |
| DELETE | `/comments/:commentId` | コメントを消す |
| GET | `/media/:cutId` | 実体（`?thumb=1` `?download=1` `?s=<共有トークン>`） |

`meta` の例です。

```json
{
  "kind": "video",
  "durationMs": 3000,
  "takenAt": "2026-08-22T10:00:00.000Z",
  "tzOffset": -540,
  "facing": "environment",
  "source": "camera",
  "note": "昼ごはん",
  "tags": ["食事"]
}
```

`tzOffset` はJavaScriptの `getTimezoneOffset()` と同じ向きです（日本なら `-540`）。
サーバはこれを使って `localDate` を決めるので、**海外で撮っても現地の日付でまとまります。**

カットを動かせるのは、自分で撮ったカットと、動かす前のログのオーナーです（管理者はどちらも動かせます）。
移す先は自分がメンバーのログに限ります。プライベートログは招待コードが使えないので、`logId` で直接指定してください。

## 書き出し・共有・まとめ動画

| メソッド | パス | 説明 |
|---|---|---|
| POST | `/logs/:logId/export` | **選んだカットだけ**をZIPで返す（`cutIds`・`includeMetadata`） |
| POST | `/logs/:logId/shares` | 共有リンクを作る（`cutIds`・`title`・`password`・`expiresAt`・`allowDownload`） |
| GET | `/logs/:logId/shares` | 共有リンクの一覧 |
| DELETE | `/shares/:shareId` | 止める |
| GET | `/public/:token/meta` | 共有の表紙（パスワードが要るかどうか） |
| POST | `/public/:token` | 共有の中身（`password`） |
| POST | `/logs/:logId/renders` | まとめ動画のジョブを積む（`cutIds`・`style`・`label`） |
| GET | `/logs/:logId/renders` | まとめ動画の一覧 |
| GET | `/renders/file/:name` | まとめ動画ファイルの実体（ログインしていれば誰でも取れる。ファイル名を直接指定） |
| GET | `/jobs/:jobId` | ジョブの状態（`queued` / `running` / `done` / `error`） |

`style` を渡すと、まとめ動画の見た目（大きさ・収め方・背景色・fps・1カットの長さ・写真の長さ・並び順・
時刻の焼き込み・メモの焼き込み・表紙）を1回だけ変えられます。渡した `style` は次回の既定として保存されるので、
渡さなければ前に使った設定を使います（一度も渡していなければ、下の既定値を使います）。

```json
{
  "size": "portrait",
  "width": 720,
  "height": 1280,
  "fit": "contain",
  "background": "#000000",
  "fps": 30,
  "perCutMs": 0,
  "photoMs": 2000,
  "order": "time",
  "time": {
    "show": true,
    "format": "HH:mm",
    "position": "br",
    "fontSize": 36,
    "color": "#FFFFFF",
    "box": true,
    "boxColor": "#000000",
    "boxOpacity": 0.4
  },
  "note": {
    "show": false,
    "position": "bc",
    "fontSize": 28,
    "color": "#FFFFFF",
    "box": true,
    "boxColor": "#000000",
    "boxOpacity": 0.4
  },
  "title": {
    "show": false,
    "text": "",
    "seconds": 2,
    "fontSize": 64,
    "color": "#FFFFFF",
    "background": "#000000"
  }
}
```

- `size` は `portrait`（縦・720x1280）/ `square`（正方形・1080x1080）/ `landscape`（横・1280x720）/ `custom`（`width`・`height` を自分で決める）
- `fit` は `contain`（余白を足して全部入れる）/ `cover`（画面いっぱいに切り抜く）
- `order` は `time`（撮った順）/ `reverse`（新しい順）
- `time` と `note` は焼き込む文字の位置（`tl` `tc` `tr` `bl` `bc` `br`）・文字の大きさ・色・下地の有無と色と不透明度を持つ
- `title` は先頭に足す表紙の板（`show` が `true` かつ `text` があるときだけ出る）
- 渡した値は安全な範囲に丸められます（例: `fps` は10〜60、`fontSize` は12〜200）

ZIPの中身です。

```
media/2026-08-22/c_xxxx.mp4    元ファイル（変換しない）
thumbs/c_xxxx_thumb.jpg        サムネイル
cuts.json                      全メタデータ
cuts.csv                       表計算で開く用
README.md                      中身の説明
```

## 通知・管理

| メソッド | パス | 説明 |
|---|---|---|
| POST | `/push/subscribe` | 購読を登録する |
| POST | `/push/test` | テストを送る |
| PUT | `/reminders` | 撮影を促す設定（`mode`・`times`・`fromHour`・`toHour`・`perDay`・`tzOffset`） |
| GET | `/healthz` | 死活。`{"ok":true,"db":"sqlite","storage":"local"}` |
| GET | `/config` | インスタンスの設定（ログイン方法など。認証は要らない） |
| GET | `/admin/stats` | 件数と容量（管理者） |
| GET | `/admin/users` | 利用者の一覧（管理者） |
| PATCH | `/admin/users/:userId` | 停止・管理者の付け外し（管理者） |
