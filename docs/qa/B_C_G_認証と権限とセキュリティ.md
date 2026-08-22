# B・C・G の確認記録（認証／権限／セキュリティ）

- 実施日: 2026-08-22
- 対象: `docs/RELEASE_QA.md` の B1〜B10・C1〜C10・G1〜G10
- 確認の仕方: コードを読んで判断せず、実際にHTTPのリクエストを送り、返ってきた内容で判定した。
- 検証環境:
  - 検証用サーバ … `PORT=8791 DATA_DIR=./qa-bcg-data`（SQLite・ローカル保存・ffmpeg 8.1・Node 24.14.1）
  - レート制限の確認用 … `PORT=8792`（`RATE_LIMIT_WRITE_PER_MINUTE` を既定のまま）
  - Cookieの `Secure` の確認用 … `PORT=8796 COOKIE_SECURE=true`
  - OIDCの確認用 … `PORT=8799` ＋ 自前で立てた最小のIdP（HTTPS・RS256・PKCE対応）
- 利用者: ①`admin`（最初の1人・管理者） ②`alice`（一般） ③`bob`（一般）
- 日本語の文字列は、Pythonのスクリプトから UTF-8 で送った。

---

## 判定の要約

| 分類 | ✅通った | ❌落ちた（直した） | ⏭対象外 |
|---|---|---|---|
| B（認証とセッション） | 9 | 1（B4） | 0 |
| C（権限） | 10 | 0 | 0 |
| G（セキュリティ） | 8 | 2（G9・G10） | 0 |

C1〜C10の10項目は、`docs/API.md` の全経路を他人のIDで呼び直して、すべて拒否されることを確かめた。
**ただし、確認表の項目には無い場所で、他人のデータが取れる穴を3つ見つけた。**

1. `GET /api/renders/file/:name` … ログインしていれば誰でも他人のまとめ動画を取得できた。
2. `GET /api/media/:cutId?s=<token>` … ゴミ箱へ入れたカットを、共有リンクからまだ取得できた。
3. `GET /api/media/:cutId?s=<token>` … パスワード付きの共有でも、実体の配信はパスワードを確認していなかった。

3つとも直して、同じ攻撃で取れないことを確かめた。
C5とC6は、確認表に書かれた確認そのものは直す前から通っていたので✅としたが、
その周辺で見つけた穴は下の一覧に入れて、節ごとに詳しく書いた。

---

## 見つけた穴の一覧（深刻な順）

| # | 場所 | 内容 | 対応 |
|---|---|---|---|
| 1 | `GET /api/media/:cutId`（G9） | 送ってきた側が申告した Content-Type をそのまま返していた。`.html` や `.svg` を上げるだけで、このサイトと同じオリジンにスクリプトを置けた（保存型のXSS。共有リンクで第三者にも渡せた） | **直した** |
| 2 | `GET /api/renders/file/:name` | ログインしていれば誰でも取得できた。まとめ動画のファイル名は同じログのメンバーには見えるので、抜けたメンバーや別のログの人が他人のまとめ動画を取得できた | **直した** |
| 3 | `GET /api/media/:cutId?s=<token>` | ゴミ箱へ入れたカットを、共有リンクからそのまま取得できた（公開ページの一覧からは消えているので、消したつもりで残っていた） | **直した** |
| 4 | `audit()`・入口の回数制限・ログインの失敗の数え方（G4・F10） | `TRUST_PROXY` を設定していないのに `X-Forwarded-For` を無条件に読んでいた。監査ログのIPを偽れて、ヘッダを毎回変えるだけで回数制限を回り込めた（別の担当からの報告） | **直した** |
| 5 | `POST /api/auth/login`（B4） | 連続失敗の制限が無かった。間違ったパスワードで25回続けても止まらず、そのあと正しいパスワードで入れた | **直した** |
| 6 | `GET /api/media/:cutId?s=<token>` | パスワード付きの共有でも、実体の配信ではパスワードを確認していなかった（カットIDを知っていれば、パスワードを知らないまま取得できた） | **直した** |
| 7 | `PATCH /api/admin/users/:userId`（G10） | 停止・管理者の付け外しが監査ログに1行も残らなかった | **直した** |
| 8 | `POST /api/logs/:logId/shares` | `expiresAt` に日付として読めない文字列（例: `きのう`）を渡すと、そのまま保存され、**期限が永久に来なかった** | **直した** |
| 9 | `src/auth/index.js` のOIDC | 確認の取れていないメールアドレス（`email_verified: false`）でも、同じアドレスの既存の利用者に結び付いた。IdP側でアドレスを名乗れる場合に、管理者の乗っ取りにつながった | **直した** |
| 10 | `src/auth/index.js` のOIDC | 許可ドメインの比較が大文字小文字を区別したので、IdPが `EXAMPLE.CO.JP` を返す環境では正規の利用者が入れなかった（安全側に外れる不具合） | **直した** |
| 11 | `src/auth/index.js` のOIDC | `oidcState` の中身を捨てる処理が無かった。`GET /api/auth/oidc/start` には回数制限が無いので、呼び続けるとメモリが際限なく増えた | **直した** |
| 12 | `POST /api/logs/:logId/cuts`・`POST /api/cuts` | 上限を超えるファイルを送ると `500` と英語の文（`File too large`）が返った（別の担当からの報告） | **直した** |
| 13 | `GET /api/healthz` | `SELECT 1` しか行わないので、DBが読めない状態でも `ok:true` を返した（別の担当からの報告） | **直した** |
| 14 | `web/app.js:108` | 表示名（`m.display_name`）だけ `escapeHtml` を通さずに `innerHTML` へ入れている | **担当外（web/）。下の「他の担当へ回すもの」に書いた** |
| 15 | `src/index.js` | Content-Security-Policy が無い（G5に「CSPを足すか決める」とある） | **担当外（src/index.js）。下に書いた** |
| 16 | `GET` のAPI全般（G4） | 回数制限が書き込み（GET・HEAD以外）にしか無い。`/api/healthz` を500回連続で呼んでも全部200が返った | **担当外（`src/config.js`・`src/index.js` に及ぶ）。下に書いた** |

---

## B. 認証とセッション

### B1 ログイン・ログアウトが動く ✅

```
POST /api/auth/login {"username":"alice","password":"Passw0rd!23"}
-> 200 {"user":{"id":"u__1WOLSORd9u3","username":"alice","displayName":"アリス",...}}
   Set-Cookie: cutlog_session=1ZOXkDCEjeYEnVGPHkk-QUNqdYswOiNG; HttpOnly; SameSite=Lax; Path=/; Max-Age=7776000
GET  /api/me                 -> 200
POST /api/auth/logout        -> 200 {"ok":true}
   Set-Cookie: cutlog_session=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0
GET  /api/me（ログアウト後） -> 401 {"error":"ログインしてください"}
```

ブラウザのCookie入れが空になるだけでなく、**ログアウト前のトークンを手で送り直しても401になる**ことを確かめた。
`sessions` の行がログアウトで消えるので、盗まれたトークンも使えない。

```
GET /api/me (Cookie: cutlog_session=1ZOXkDCE...) -> 401 {"error":"ログインしてください"}
```

### B2 パスワードが平文で保存されていない ✅

```sql
SELECT id, username, substr(password_hash,1,40) FROM users;
-> admin  scrypt$ab308de702618d4aa33e395ad42448fc$...
   alice  scrypt$261e3bb6243d8dd42f12bda78d731fa8$...
   bob    scrypt$c6acb9cd927f551d0650f8fa07146d66$...
```

`scrypt$<16バイトの塩>$<64バイトのハッシュ>` の形で、利用者ごとに塩が違う。
照合は `crypto.timingSafeEqual` を使っている（`src/lib/util.js`）。

### B3 弱いパスワードを弾く ✅

```
POST /api/auth/signup {"username":"weakuser","password":"1234"}
-> 400 {"error":"パスワードは8文字以上にしてください"}
POST /api/auth/signup {"username":"weakuser","password":"1234567"}
-> 400 {"error":"パスワードは8文字以上にしてください"}
POST /api/auth/signup {"username":"ab","password":"Passw0rd!23"}
-> 400 {"error":"ユーザー名は英数字と . _ - で3〜30文字にしてください"}
```

### B4 ログインの連続失敗に制限がある ❌ →（直した）✅

**直す前**: 間違ったパスワードで25回続けても、25回すべて401が返るだけで止まらなかった。

```
25回の状態コード: [401, 401, 401, ... 401]（25回すべて401）
そのあと正しいパスワードで: 200
```

書き込みの回数制限（1IPあたり120回／分）だけが働くので、1つのアカウントへ**1日あたり17万回**試せた。

**原因**: `POST /api/auth/login` に、アカウントごとの失敗回数を数える処理が無かった。

**直した内容**（`src/routes/api.js`）: 失敗をアカウントごと・IPごとに15分の窓で数え、
アカウントは10回、IPは50回で受け付けなくなるようにした。成功したら数え直す。
IPの上限を緩くしたのは、同じ事務所から全員が1つのIPで出ていく形が普通で、
IPを厳しくすると無関係な人まで入れなくなるためである。失敗と停止は監査ログにも残す。

**直したあとに同じ攻撃をやり直した結果**:

```
11回目で止まった: {"error":"ログインの失敗が続いたので、15分ほど待ってからやり直してください"}
25回の内訳: {401: 10, 429: 15}
そのあと正しいパスワードで: 429（当て推量を続けられない）
同じIPから別のアカウント（alice）のログイン: 200（無関係な人を巻き込まない）
監査ログ: auth.login.fail × 10 / auth.login.locked × 16
```

### B5 セッションに期限がある ✅

```sql
SELECT token, created_at, expires_at FROM sessions WHERE token = 'OKtb5V8...';
-> created_at 2026-08-22T13:12:18.283Z / expires_at 2026-11-20T13:12:18.283Z（90日）
```

`expires_at` を過去（`2020-01-01`）に書き換えてから同じCookieで呼んだ結果です。

```
GET /api/me   -> 401 {"error":"ログインしてください"}
GET /api/logs -> 401 {"error":"ログインしてください"}
```

期限切れの行は `src/index.js` の掃除処理が1時間ごとに消す。

### B6 Cookieに `HttpOnly`・`SameSite`・（HTTPSなら）`Secure` が付く ✅

```
（既定・COOKIE_SECURE 未設定）
Set-Cookie: cutlog_session=xuFqJPLEYd43iGOyJk9f2vKrV1h76Pih; HttpOnly; SameSite=Lax; Path=/; Max-Age=7776000
（COOKIE_SECURE=true で起動したサーバ）
Set-Cookie: cutlog_session=XjXNnxDPgvhc7VFC2RCt3l4QAuTGAvYW; HttpOnly; SameSite=Lax; Path=/; Max-Age=7776000; Secure
```

`HttpOnly` と `SameSite=Lax` は常に付き、`Secure` は `COOKIE_SECURE=true` のときだけ付く。
切り替えは `src/config.js` の `auth.cookieSecure` で実装されている。

なお、ログアウトのときに返すCookieには `SameSite` も `Secure` も付いていなかったので、
ログイン時と同じ属性をそろえた（`src/routes/api.js`）。属性が違っても消える動きは変わらないが、
`Secure` を要求する経路で消し損なう余地を残さないためである。

### B7 OIDCが `.env` の設定だけで動く ✅

自前の最小のIdP（HTTPS・RS256・PKCE・nonce対応）を立て、次の設定だけで起動した。

```
OIDC_ISSUER=https://localhost:9912
OIDC_CLIENT_ID=cutlog-test
OIDC_CLIENT_SECRET=shhh
OIDC_ALLOWED_DOMAINS=example.co.jp
```

```
GET /api/config
-> {"oidc":{"enabled":true,"label":"シングルサインオンで入る"}, ...}

GET /api/auth/oidc/start
-> 302 Location: https://localhost:9912/authorize?redirect_uri=http%3A%2F%2Flocalhost%3A8799%2Fapi%2Fauth%2Foidc%2Fcallback
   &scope=openid+email+profile&code_challenge=eCOzRIBx...&code_challenge_method=S256
   &state=d3sDkNP6...&nonce=...&client_id=cutlog-test&response_type=code

GET /api/auth/oidc/callback?code=...&state=...
-> 302 Location: /
   Set-Cookie: cutlog_session=j7Wul4buqKOK7z9EKPPDWHnd2egUEB2e; HttpOnly; SameSite=Lax; Path=/; Max-Age=7776000

GET /api/me
-> 200 {"user":{"id":"u_isORuFgyAtob","username":"taro","displayName":"山田太郎",
        "email":"taro@example.co.jp","isAdmin":true,"provider":"oidc"}, ...}
```

PKCE（S256）・`state`・`nonce` はすべて付いている。設定を書くだけで動いた。

**この確認で分かった注意点**（実装は正しいが、使う人がつまずく）:
`openid-client` v6 は **HTTPSのissuerだけを受け付ける**。`http://` を書くと `/api/auth/oidc/start` が
`400 OIDCが設定されていません` を返し、本当の理由（`only requests to HTTPS are allowed`）はサーバのログにだけ出る。
`docs/AUTH_OIDC.md` に「issuerはHTTPSであること」を書いておくとよい（担当外なので直していない）。

### B8 OIDCで許可ドメインの外の人を拒否できる ✅

`OIDC_ALLOWED_DOMAINS=example.co.jp` を設定して、IdPが返すメールアドレスを変えながら試した。

| IdPが返したアドレス | 結果 |
|---|---|
| `taro@example.co.jp` | 302（ログインできた） |
| `hanako@gmail.com` | 400 `このドメイン（gmail.com）は許可されていません` |
| `x@example.com` | 400 `このドメイン（example.com）は許可されていません` |
| `y@sub.example.co.jp` | 400 `このドメイン（sub.example.co.jp）は許可されていません` |
| `noatsign`（@が無い） | 400 `このドメイン（不明）は許可されていません` |
| `z@EXAMPLE.CO.JP` | **直す前は400（正規の利用者を拒否した）→ 直したあとは302** |

`RELEASE_QA.md` は環境変数の名前を `AUTH_ALLOWED_DOMAINS` と書いているが、
実装が読むのは `OIDC_ALLOWED_DOMAINS` である（`src/config.js`）。表記が一致しないので、J5・J6の担当へ回す。

大文字のドメインを拒否していた件は、比較の前に両方を小文字にして直した（`src/auth/index.js`）。

**この確認の途中で見つけた別の穴**: メールアドレスの確認が取れていないときも、
同じアドレスの既存の利用者に結び付いていた。IdP側で他人のアドレスを名乗れる場合、
`taro@example.co.jp`（管理者）を名乗るだけでその利用者になれた。
`email_verified` が明示的に `false` のときは結び付けないようにした。

```
（直したあと）別人が sub を変え、email_verified=false で taro のアドレスを名乗る
-> 302。ただし入れたのは u_N_d7xiOeJE8C / taro1 / isAdmin=false（別の利用者として作られた）
（回帰確認）email_verified=true なら、これまでどおり同じ利用者 u_isORuFgyAtob に入る
```

### B9 ログインしていない人が、APIから何も取れない ✅

Cookieを付けずに送った結果です。

| 経路 | 結果 |
|---|---|
| `GET /api/logs` | 401 `{"error":"ログインしてください"}` |
| `GET /api/logs/<id>` | 401 |
| `GET /api/logs/<id>/cuts` | 401 |
| `GET /api/cuts/<id>` | 401 |
| `GET /api/media/<id>` | **403・本文0バイト** |
| `GET /api/media/<id>?thumb=1` | **403・本文0バイト** |
| `GET /api/logs/<id>/trash` | 401 |
| `GET /api/logs/<id>/shares` | 401 |
| `GET /api/logs/<id>/renders` | 401 |
| `GET /api/me` | 401 |
| `GET /api/admin/stats`・`/admin/users` | 401 |
| `GET /api/renders/file/<名前>` | 401 |
| `POST /api/logs/<id>/cuts`・`/export`・`/renders`・`/shares`・`/cuts/<id>/comments`・`/logs/join` | すべて401 |

**データは1バイトも返らない。** `/api/media` だけは401や404ではなく403を返すが、
本文が空なので中身は出ていない。`RELEASE_QA.md` の文（「すべて401か404」）と状態コードが違う点は、
記述を実装に合わせるほうが妥当だと判断して、実装は変えていない。

認証の要らない `GET /api/config`・`GET /api/healthz`・`GET /api/public/:token/meta` は、
設計どおり誰でも呼べる。返るのはインスタンスの設定と共有の表紙だけで、利用者のデータは入っていない。

### B10 停止した利用者がログインできない ✅

```
PATCH /api/admin/users/u_hkRsOGp4tqQX {"disabled":true}（管理者として）-> 200
SELECT username, disabled FROM users -> bob / 1

POST /api/auth/login {"username":"bob","password":"Passw0rd!23"}
-> 401 {"error":"ユーザー名かパスワードが違います"}
```

**停止する前に取ったCookieも使えなくなる**ことまで確かめた。

```
（有効なセッションを持った状態で）GET /api/me -> 200
PATCH /api/admin/users/<bob> {"disabled":true} -> 200
（同じCookieで）GET /api/me -> 401 {"error":"ログインしてください"}
```

`currentUser` の照会が `u.disabled = 0` を条件に入れているので、既に配ったセッションもその場で使えなくなる。

---

## C. 権限（他人のものが見えないこと）

`docs/API.md` の表を上から順に、**ボブがアリスのID（ログID・カットID・共有ID・コメントID・ジョブID・
まとめ動画のファイル名）を入れて呼ぶ**形で全経路を試した。結果の一覧です。

| メソッド | パス（アリスのIDを入れた） | ボブの結果 | 返ってきた内容 |
|---|---|---|---|
| GET | `/logs/<アリスのログ>` | 403 | `このログのメンバーではありません` |
| PATCH | `/logs/<アリスのログ>` | 403 | 同上 |
| POST | `/logs/<アリスのログ>/invite/rotate` | 403 | 同上 |
| DELETE | `/logs/<アリスのログ>/members/<アリス>` | 403 | 同上 |
| POST | `/logs/join`（アリスの非公開ログの招待コード） | 404 | `その招待コードは見つかりません` |
| GET | `/logs/<アリスのログ>/cuts` | 403 | `このログのメンバーではありません` |
| POST | `/logs/<アリスのログ>/cuts` | 403 | 同上 |
| GET | `/cuts/<アリスのカット>` | 404 | `見つかりません` |
| PATCH | `/cuts/<アリスのカット>` | 404 | 同上 |
| DELETE | `/cuts/<アリスのカット>` | 404 | 同上 |
| POST | `/cuts/<アリスのカット>/restore` | 404 | 同上 |
| POST | `/cuts/<アリスのカット>/move` | 400 | `元のログのメンバーではありません` |
| POST | `/logs/<ボブのログ>/cuts/move`（アリスのカットを入れる） | 200 | `{"moved":[],"skipped":[{...,"reason":"元のログのメンバーではありません"}×2]}`（1件も動かない） |
| GET | `/logs/<アリスのログ>/trash` | 403 | `このログのメンバーではありません` |
| POST | `/cuts/<アリスのカット>/reactions` | 404 | `見つかりません` |
| POST | `/cuts/<アリスのカット>/comments` | 404 | 同上 |
| DELETE | `/comments/<アリスのコメント>` | 403 | `自分のコメントだけ消せます` |
| GET | `/media/<アリスのカット>` | 403 | 本文なし |
| GET | `/media/<アリスのカット>?thumb=1` | 403 | 本文なし |
| GET | `/media/<アリスの非公開カット>` | 403 | 本文なし |
| POST | `/logs/<アリスのログ>/export` | 403 | `このログのメンバーではありません` |
| POST | `/logs/<ボブのログ>/export`（アリスのカットを入れる） | 400 | `書き出せるカットがありません` |
| POST | `/logs/<アリスのログ>/shares` | 403 | `このログのメンバーではありません` |
| GET | `/logs/<アリスのログ>/shares` | 403 | 同上 |
| DELETE | `/shares/<アリスの共有>` | 404 | `見つかりません` |
| POST | `/logs/<アリスのログ>/renders` | 403 | `このログのメンバーではありません` |
| POST | `/logs/<ボブのログ>/renders`（アリスのカットを入れる） | 400 | `このログのカットを選んでください` |
| GET | `/logs/<アリスのログ>/renders` | 403 | `このログのメンバーではありません` |
| GET | `/jobs/<アリスのジョブ>` | 403 | `権限がありません` |
| GET | `/renders/file/<アリスのまとめ動画>` | 403 | `このまとめ動画を見る権限がありません`（**直したあとの値**） |
| PATCH | `/me` `{"defaultLogId":"<アリスのログ>"}` | 400 | `そのログのメンバーではありません` |
| GET | `/admin/stats`・`/admin/users` | 403 | `管理者だけが使えます` |
| PATCH | `/admin/users/<アリス>` | 403 | 同上 |

**拒否されなかったのは `POST /logs/<ボブのログ>/cuts/move` の200だけだが、
`moved` が空で `skipped` に理由が並ぶ仕様どおりの応答であり、カットは1件も動いていない。**
一連の攻撃のあと、アリスのログ名・カット件数・コメント・共有リンクがすべて元のまま残っていることも確かめた。

### C1 参加していないログのカットが取れない ✅

上の表の該当行のとおりである。アリスの共有ログのカットも、非公開（プライベート）ログのカットも取れない。

### C2 他人のカットを消せない・付け替えられない ✅

`DELETE /api/cuts/:id` は404、`POST /api/cuts/:id/move` は400で拒否される。
`moveCuts` が「元のログのメンバーであること」と「自分が撮ったカットであること」の両方を見ている。
ログの名前を書き換える攻撃も403で止まり、確認後もアリスのログ名は `アリスの日記` のままだった。

### C3 プライベートのログに他人が入れない ✅

DBから招待コードを取り出し（漏れた想定）、そのコードで参加を試した。

```
アリスの非公開ログの招待コード: RDNTXNGN
POST /api/logs/join {"code":"RDNTXNGN"} -> 404 {"error":"その招待コードは見つかりません"}
（対照）共有ログのコード TC5YKTVU なら -> 200（参加できる。設計どおり）
```

`isPrivate(log)` で弾いている。招待コードが漏れても非公開ログには入れない。

### C4 共有リンクは、含めたカットだけを見せる ✅

アリスの共有リンクには `c_AEr3mSamIzug`（cut1）だけを含め、`c_CZ53_hdnKZa3`（cut2）は含めなかった。

```
POST /api/public/G58sF9c-oBdPGdFR {}
-> 200 cuts に入っているのは c_AEr3mSamIzug の1件だけ

GET /api/media/c_AEr3mSamIzug?s=G58sF9c-oBdPGdFR  -> 200（含めたカット）
GET /api/media/c_CZ53_hdnKZa3?s=G58sF9c-oBdPGdFR  -> 403（含めていないカット）
GET /api/media/c_Vur7Tsxt87Vg?s=G58sF9c-oBdPGdFR  -> 403（別のログのカット）
GET /api/media/c_x9otcGDVBrbo?s=G58sF9c-oBdPGdFR  -> 403（非公開ログのカット）
GET /api/media/c_AEr3mSamIzug?s=zzzzzzzzzzzzzzzz   -> 403（でたらめなトークン）
```

共有を作るときに他のログのカットIDを混ぜる攻撃も試したが、公開ページに出たのは自分のログのカットだけだった。

```
POST /api/logs/<アリスのログ>/shares {"cutIds":["<アリス>","<ボブ>","<ボブの非公開>"]}
-> 公開ページに出たカットID: ['c_AEr3mSamIzug']（ボブのIDは混ざらない）
```

### C5 止めた共有リンク・期限切れの共有リンクが開かない ✅（期限の検査を直した）

```
（止める前）POST /api/public/AQquSyrI3ZV0SxjV {} -> 200
DELETE /api/shares/sh_nEc8jMF6HnNp -> 200 {"ok":true}
（止めた後）POST /api/public/AQquSyrI3ZV0SxjV {}      -> 404 {"error":"この共有リンクは使えません"}
（止めた後）GET  /api/public/AQquSyrI3ZV0SxjV/meta    -> 404
（止めた後）GET  /api/media/<cut>?s=AQquSyrI3ZV0SxjV  -> 403

（expiresAt を 2020-01-01 にした共有）
POST /api/public/DRBEoZaWGZ4fAz3p {}                 -> 404
GET  /api/media/<cut>?s=DRBEoZaWGZ4fAz3p             -> 403
```

**ここで穴が1つ出た。** `expiresAt` に日付として読めない文字列を渡すと、そのまま保存されて期限が来なかった。

```
（直す前）
POST /api/logs/<log>/shares {"cutIds":[...],"expiresAt":"きのう"} -> 200
SELECT title, expires_at FROM shares -> 期限が壊れている / きのう
POST /api/public/<token> {} -> 200（永久に開く）
```

`new Date('きのう').getTime()` は `NaN` になり、`NaN < Date.now()` が偽になるので、
期限の判定を素通りしていた。作った人は期限を付けたつもりでいるので危険である。

**直した内容**: 共有を作るときに日付として読める値だけを受け、読めない値は400で返す。
併せて `validShare` でも、保存済みの値が読めないときは期限切れとして扱うようにした。

```
（直したあと）
POST /api/logs/<log>/shares {"cutIds":[...],"expiresAt":"きのう"}
-> 400 {"error":"期限は日付として読める形で渡してください（例: 2026-09-01T00:00:00.000Z）"}
POST /api/logs/<log>/shares {"cutIds":[...],"expiresAt":"2027-01-01T00:00:00.000Z"}
-> 200（DBには 2027-01-01T00:00:00.000Z が入る。共有は開く）
```

### C6 パスワード付きの共有が、パスワードなしで開かない ✅（実体の配信も直した）

```
GET  /api/public/<token>/meta -> 200 {"title":"鍵つき","needPassword":true,"allowDownload":true}
POST /api/public/<token> {}                        -> 401 {"error":"パスワードが違います","needPassword":true}
POST /api/public/<token> {"password":"chigau"}     -> 401
POST /api/public/<token> {"password":""}           -> 401
POST /api/public/<token> {"password":"himitsu123"} -> 200
```

公開ページはパスワードで守られていた。**ただし実体の配信は守られていなかった。**

```
（直す前）GET /api/media/c_AEr3mSamIzug?s=<鍵つきtoken> -> 200（パスワードを1度も入れていない）
```

カットIDを知らないと届かないので実際に使うのは難しいが、パスワードの意味が無くなる。

**直した内容**: 公開ページでパスワードが合った時点で、`password_hash` から作った値を
`cutlog_share_<共有ID>` のCookie（HttpOnly・SameSite=Lax）へ入れ、
`GET /api/media/:cutId?s=` でも同じ値を求めるようにした。この値はパスワードを知らない人には作れない。

```
（直したあと）
パスワードを入れないまま GET /api/media/<cut>?s=<鍵つきtoken>  -> 403
POST /api/public/<token> {"password":"himitsu123"}             -> 200
   Set-Cookie: cutlog_share_sh_3JbIkByfOz-v=hcU70bI_1yAj9mDIdTzC...; HttpOnly; SameSite=Lax; Path=/; Max-Age=86400
そのあと GET /api/media/<cut>?s=<鍵つきtoken>                  -> 200（9102バイト。共有ページは今も見られる）
違うパスワードを入れた人の GET /api/media/<cut>?s=             -> 403
（回帰確認）パスワードなしの共有の GET /api/media/<cut>?s=      -> 200（これまでどおり）
```

### C7 まとめ動画に、他のログのカットを混ぜられない ✅（回帰していない）

今日直した箇所の回帰確認である。

```
POST /api/logs/<アリスのログ>/renders {"cutIds":["<ボブのカット>"]}
-> 400 {"error":"このログのカットを選んでください"}
POST /api/logs/<アリスのログ>/renders {"cutIds":["<ボブの非公開カット>"]}
-> 400 {"error":"このログのカットを選んでください"}
POST /api/logs/<アリスのログ>/renders {"cutIds":["<アリス>","<ボブ>","<ボブの非公開>"]}
-> 200 jobId=j_IUrfHzgiYwgn
   ジョブのpayload: {"cutIds":["c_AEr3mSamIzug"], ...}（他人のIDはキューに積まれる前に外れている）
   ジョブ結果: done / cutCount=1
POST /api/logs/<ボブのログ>/renders（アリスが呼ぶ）
-> 403 {"error":"このログのメンバーではありません"}
```

**他人のIDは、ジョブとして保存される前の段階で外れている。** 出来上がった動画も1カットだけである。

### C8 書き出し（ZIP）に、他のログのカットを混ぜられない ✅

```
POST /api/logs/<アリスのログ>/export {"cutIds":["<ボブ>","<ボブの非公開>"]}
-> 400 {"error":"書き出せるカットがありません"}

POST /api/logs/<アリスのログ>/export {"cutIds":["<アリス>","<ボブ>","<ボブの非公開>"]}
-> 200（15533バイト）
   ZIPの中身: media/2026-08-22/c_AEr3mSamIzug.mp4, thumbs/c_AEr3mSamIzug_thumb.jpg,
              cuts.json, cuts.csv, README.md
   cuts.json に入ったカットID: ['c_AEr3mSamIzug']（ボブのIDは混ざらない）

POST /api/logs/<ボブのログ>/export（アリスが呼ぶ）
-> 403 {"error":"このログのメンバーではありません"}
```

ZIPを実際に開き、`cuts.json` の中身とファイル名の両方を見て確かめた。

### C9 管理者APIが一般の利用者から叩けない ✅

```
GET   /api/admin/stats（ボブ）                      -> 403 {"error":"管理者だけが使えます"}
GET   /api/admin/users（ボブ）                      -> 403
PATCH /api/admin/users/<ボブ自身> {"isAdmin":true}  -> 403
PATCH /api/admin/users/<管理者> {"disabled":true}   -> 403
SELECT username,is_admin,disabled FROM users -> bob / 0 / 0（変わっていない）
                                              admin / 1 / 0（停止されていない）
```

自分を管理者に上げる攻撃も、管理者を停止して締め出す攻撃も通らなかった。

### C10 まとめ動画のファイルが、URLを知っただけの他人に取得されない ✅（穴があったので直した）

```
（ログアウト状態）GET /api/renders/file/rd_pl8naUeN6gYl.mp4
-> 401 {"error":"ログインしてください"}
```

`RELEASE_QA.md` の確認どおりログアウトでは取得できないが、**ログインしていれば誰でも取得できた。**

```
（直す前）
作った本人アリス          -> 200 / 21633バイト
無関係なボブ（ログイン済）-> 200 / 21633バイト / Content-Type: video/mp4
                            先頭16バイト: b'\x00\x00\x00 ftypisom\x00\x00\x02\x00'（中身が取れている）
```

**原因**: `GET /api/renders/file/:name` が `requireAuth` だけで、ファイルとログの結び付きを見ていなかった。
ファイル名は `GET /api/logs/:logId/renders` で同じログのメンバー全員に見えるので、
ログから抜けた人や、名前が別の場所へ写された場合に、他のログのまとめ動画が取得できた。

**直した内容**: そのファイルを作ったジョブ（`jobs.result` の `filename`）を引き、
そのジョブのログのメンバーか管理者でなければ403を返すようにした。

**直したあとに同じ攻撃をやり直した結果**:

```
作った本人アリス           -> 200 / 21633バイト
無関係なボブ（ログイン済） -> 403 {"error":"このまとめ動画を見る権限がありません"}
管理者                     -> 200 / 21633バイト（管理者は見られる）
ログアウト                 -> 401 {"error":"ログインしてください"}
存在しない名前             -> 404
```

パスを抜け出す攻撃も、直す前から後まで通らない。

```
GET /api/renders/file/../cutlog.db                   -> 404
GET /api/renders/file/..%2Fcutlog.db                 -> 404
GET /api/renders/file/....//cutlog.db                -> 404
GET /api/renders/file/..%5Ccutlog.db                 -> 404
GET /api/renders/file/%2e%2e%2f%2e%2e%2fpackage.json -> 404
GET /api/renders/file/..\cutlog.db                   -> 404
```

### C（表に無い追加の確認）ゴミ箱へ入れたカットが、共有リンクから取得できた ❌ →（直した）✅

共有リンクに含めたカットをゴミ箱へ入れたあとの動きを試した。

```
（直す前）
共有を作る -> 削除前 GET /api/media/<cut>?s=<token> -> 200
DELETE /api/cuts/<cut> -> 200
POST /api/public/<token> {} の一覧 -> []（公開ページからは消えている）
GET /api/media/<cut>?s=<token>     -> 200 / 9057バイト（★まだ取得できる）
```

公開ページの一覧は `deleted_at IS NULL` で絞っているのに、実体の配信は絞っていなかった。
消したつもりのカットが、リンクを持っている人には残っていた。

**直した内容**: 共有トークンで来た要求では、`deleted_at` が入っているカットを配らないようにした。

```
（直したあと）
削除前 -> 200
DELETE /api/cuts/<cut> -> 200
削除後 GET /api/media/<cut>?s=<token> -> 403
公開ページの一覧 -> []
戻したあと（restore）  -> 200（ゴミ箱から戻せば また見られる）
```

### C（表に無い追加の確認）`GET /api/jobs/:jobId` ✅

```
アリス（本人）  -> 200 {"job":{"id":"j_XZaK1PiisYau","status":"queued",...}}
ボブ（無関係）  -> 403 {"error":"権限がありません"}
ログアウト      -> 401 {"error":"ログインしてください"}
```

---

## G. セキュリティ

### G1 XSSが無い ✅（ただし `web/app.js` に1か所の直しを回す）

**メモ・ログ名・コメント・共有のタイトル・タグ・表示名のすべてに**、次の2つを入れた。

```
<img src=x onerror=alert(1)>
"><script>alert(1)</script>
```

（`alert` が実際に出る操作はしていない。HTMLのソースを取得して、その中身で判定した。）

```
POST /api/logs           {"name":"ログ名<img src=x onerror=alert(1)>\"><script>alert(1)</script>"}     -> 200
POST /api/logs/<x>/cuts  meta.note に同じ文字列 / meta.tags に <img src=x onerror=alert(1)>            -> 200
POST /api/cuts/<x>/comments {"body":"コメント<img ...>"}                                                -> 200
PATCH /api/me            {"displayName":"表示名<img ...>"}                                              -> 200
POST /api/logs/<x>/shares {"title":"共有<img ...>"}                                                     -> 200
```

**① APIの応答**: すべて `Content-Type: application/json; charset=utf-8` で返る。
本文には `<img src=x onerror=alert(1)>` の文字がそのまま入っているが、JSONの値なのでHTMLとして解釈されない。
`GET /logs/<x>`・`/logs/<x>/cuts`・`/cuts/<x>`・`/logs/<x>/shares`・`/me`・`POST /public/<token>`・
`GET /public/<token>/meta` の7経路すべてで同じだった。JSONの扱いとしては正しい。

**② サーバが返すHTML**: 利用者の文字は1文字も混ざらないので、サーバ側で組み立てるXSSは無い。

```
GET /                     -> 200 text/html 17490バイト  攻撃文字列は入っていない
GET /s/14H_emkAXs_xmO_v   -> 200 text/html 996バイト    攻撃文字列は入っていない（共有の公開ページ）
GET /index.html           -> 200 同上
GET /share.html           -> 200 同上
```

`web/index.html` と `web/share.html` は静的で、値はブラウザ側のJSが後から入れる作りである。

**③ 画面を組むJSの点検**: `web/app.js` と `web/share.js` の `innerHTML` に渡す文字列の
`${...}` をすべて拾い、利用者が決められる値が `escapeHtml`／`esc` を通っているかを1つずつ確かめた。

- メモ・ログ名・コメント・共有のタイトル・移動先の名前は、すべて `escapeHtml` を通っている。
- `web/share.js` の公開ページも、メモは `esc` を通り、タイトルは `textContent` で入れている。
- **`web/app.js:108` の表示名だけがエスケープを通っていない。**

```js
sel.innerHTML = '<option value="">全員</option>'
  + members.map((m) => `<option value="${m.id}">${m.display_name}</option>`).join('');
```

`<option>` の中はブラウザが文字として扱うため、この位置に置かれた `<img>` や `<script>` は動かない。
実際に script が走るところまでは至らないが、他の全部が `escapeHtml` を通っている中でここだけ通っていないので、
`web/` の担当へ直しを回す（`${escapeHtml(m.display_name)}` にする）。

**④ 派生の確認**: `web/app.js` の詳細表は `${cut.mime}` もエスケープせずに入れている。
`cut.mime` はアップロードする側が申告する値なので、ここへHTMLを入れられるかを試した。

```
multipartのパートに Content-Type: video/mp4"><img src=x onerror=alert(1)> を付けて送る
-> 200。保存された mime は "text/plain"（multerが不正な型を捨てている）
Content-Type: video/mp4; x="<img src=x onerror=alert(1)>"
-> 200。保存された mime は "video/mp4"（引数が落ちる）
Content-Type: video/mp4;a=<b>
-> 200。保存された mime は "text/plain"
```

`<` を含む値は保存されないので、この経路からのXSSは成り立たない。
加えて、G9の直しで保存する型を許可した一覧に丸めるようにしたので、`cut.mime` は
`image/jpeg`・`video/mp4` のような決まった語だけになった。

### G2 ffmpegへ渡す文字から抜け出せない ✅（回帰していない）

今日直した箇所の回帰確認である。メモと表紙の文言に次を入れ、実際にまとめ動画を書き出した。

| 入れた文字列 |
|---|
| `a', nosuchfilterxyz` |
| `%{pts}` |
| `a':drawtext=text='のっとり` |
| `x'; drawbox=0:0:100:100:red@1:t=fill; '` |
| `%{eif:n:d}%{localtime}` |
| `日本語のメモ ' : \ % [ ] , ; =` |

表紙の文言には `表紙 a', nosuchfilterxyz %{pts}` を入れた。

```
POST /api/logs/<log>/renders {"cutIds":[6件],"style":{...note.show:true, title.show:true...}}
-> 200 jobId=j_75FiW8t_mMRt
ジョブ結果: done
   {"filename":"rd_rzNFA2T8SQ58.mp4","cutCount":6,"bytes":107501,"width":720,"height":1280}
ffprobe: 720x1280 / 61/4 fps / 81フレーム / 6.907667秒
```

**フィルタは壊れず、6カットすべてが完走した。** 出来た動画からフレームを取り出して目で見た結果です。

- `a', nosuchfilterxyz` が **文字としてそのまま描かれている**（フィルタとして解釈されていない）。
- `%{pts}` が `%{pts}` の文字のまま描かれている（`expansion=none` を付けているので展開されない）。
- `a':drawtext=text='のっとり` も1行の文字として描かれ、余分な文字は増えていない。
- `x'; drawbox=...` を入れても**赤い四角は現れない**（drawboxが差し込まれていない）。
- `日本語のメモ ' : \ % [ ] , ; =` が豆腐にならずに描かれている。

文字はいったんファイルへ書いて `textfile=` で渡す作りなので、フィルタの書式へ埋め込まれていない
（`src/lib/render-style.js` の `drawTextFile`）。`npm test` の該当テスト（`textfile=` で渡すこと・
`expansion=none` を必ず付けること）も通っている。

### G3 パス・コマンドの注入が無い ✅

ファイル名に次を入れて9件を送った。

```
'../../../../evil.mp4'  '..\..\evil.mp4'  'a;whoami.mp4'  'a$(whoami).mp4'  'a`whoami`.mp4'
'a|whoami.mp4'  'a\'";.mp4'  '日本語 ファイル.mp4'  'a\nb.mp4'
```

9件すべて200で保存され、**保存名はすべてサーバが決めた `c_<ランダム>.mp4` になった。**

```
'../../../../evil.mp4' -> storage_key: c_ACl95O7rjkjv.mp4 / thumb_key: c_ACl95O7rjkjv_thumb.jpg
'a;whoami.mp4'         -> storage_key: c_KI7q_C3AdsON.mp4 / thumb_key: c_KI7q_C3AdsON_thumb.jpg
（以下同様）
```

`data/media` の中身を一覧で確かめたところ、`c_*` の形のファイルだけが並び、
`DATA_DIR` の外（`/c/dev/cutlog/evil.mp4` など）には1つも出ていなかった。
送ってきた側のファイル名は保存にも `ffmpeg` の引数にも使われない（`createCut` が `${cid}.${ext}` を作る）。
`LocalStorage.full()` も `path.basename(key)` を通す。`ffmpeg` は `execFile` で配列の引数として呼ぶので、
シェルを経由しない。

### G4 レート制限がある ⚠️（書き込みには有る。読み取りには無い）

既定の設定（`RATE_LIMIT_WRITE_PER_MINUTE` 未設定＝120回／分）のサーバへ送った結果です。

```
① POST /api/logs を200回続けて送る
   119回目で 429 {"error":"リクエストが多すぎます。少し待ってください"}
   内訳: {200: 118, 429: 82}
② GET /api/logs を300回続けて送る
   内訳: {200: 300}（0.9秒。1回も止まらない）
③ POST /api/auth/login を200回失敗させる
   内訳: {429: 200}（①で既に上限に達していたため最初から429）
④ GET /api/healthz を500回送る
   内訳: {200: 500}（認証の要らない読み取りも止まらない）
```

**書き込みには回数制限が有り、読み取りには無い。** 判定は「有る」とするが、
`GET /api/media/:id` のような重い読み取りが無制限なので、公開して使うなら読み取り側にも上限が要る。
実装は `src/routes/api.js` の入口にあるが、上限の値は `src/config.js` が持ち、
GETを対象に含めるかは設計の判断になるため、担当外として下に回した。

なお、この確認のあとで、**`X-Forwarded-For` を偽ればこの回数制限を回り込めた**ことが分かった
（別の担当からの報告）。数える鍵を接続元のアドレスに直し、回り込めないことを実測した。
詳しくは下の「他の担当から回ってきた不具合」の**い**に書いた。

### G5 セキュリティヘッダが付く ✅（CSPの判断は担当外へ回す）

```
GET /api/config
  X-Content-Type-Options: nosniff
  Referrer-Policy: same-origin
  Permissions-Policy: camera=(self), microphone=(self), geolocation=()
GET /（画面のHTML）
  同じ3つが付く
GET /s/<token>（共有の公開ページ）
  同じ3つが付く
```

`RELEASE_QA.md` が挙げる3つはすべて付いている。**Content-Security-Policy は付いていない。**
サイト全体のCSPは `src/index.js` で足すことになるので担当外だが、
G9の直しに合わせて `GET /api/media/:cutId` の応答だけには
`Content-Security-Policy: default-src 'none'; sandbox` を付けた。
アップロードされたファイルが万一HTMLとして解釈されても、そこからスクリプトが動かないようにするためである。

### G6 秘密情報がログに出ない ✅

```
grep -c "Passw0rd\|himitsu123" qa-bcg-data/server.log qa-bcg-data2/server.log
-> どちらも 0
grep -i "password\|cookie\|scrypt\|session\|Set-Cookie" qa-bcg-data/server.log
-> 1件もヒットしない
```

標準出力に出るのは、起動の行（`[db] applied ...`／`[jobs] ワーカーを開始しました`／待ち受けの行）と、
エラーのときの例外だけである。パスワード・セッショントークン・Cookieは出ていない。

なお、不正なmultipartを送ったときに `Error: Malformed part header` の呼び出し履歴が出て、
`node_modules` の中のファイルの位置が見える。サーバのログにしか出ないので問題は無いと判断した。

### G7 共有トークンが推測できない ✅

```js
// src/routes/api.js
const token = crypto.randomBytes(12).toString('base64url');   // 共有リンク：96ビット・16文字
// src/auth/index.js
const token = crypto.randomBytes(24).toString('base64url');   // セッション：192ビット・32文字
// src/lib/util.js
return prefix + crypto.randomBytes(9).toString('base64url');  // ID：72ビット・12文字
```

実際に発行された値です。

```
共有リンク: G58sF9c-oBdPGdFR / AQquSyrI3ZV0SxjV / Uhbr2vwEUgcOjdFp（16文字）
セッション: 1ZOXkDCEjeYEnVGPHkk-QUNqdYswOiNG（32文字）
```

すべて `crypto.randomBytes` で作っており、連番や時刻から作った部分は無い。
共有リンクは96ビットあるので当て推量では届かない。
（招待コードは紛らわしい文字を外した32種から8文字＝約40ビットで、これは書き込みの回数制限に守られている。）

### G8 依存に既知の脆弱性が無い ✅

```
npm audit
-> found 0 vulnerabilities
```

### G9 アップロードされたファイルが、そのまま実行されない ❌ →（直した）✅

**直す前の結果です。** `.html`・`.svg`・`.js`・`.xhtml` を上げて `GET /api/media/:id` の応答を見た。

| 上げたもの | 申告したContent-Type | 保存されたmime | 配信のContent-Type | 判定 |
|---|---|---|---|---|
| `evil.html` | `text/html` | `text/html` | **`text/html`** | ★危険 |
| `evil.svg` | `image/svg+xml` | `image/svg+xml` | **`image/svg+xml`** | ★危険 |
| `evil2.html`（kind=video） | `text/html` | `text/html` | **`text/html`** | ★危険 |
| `evil.xhtml` | `application/xhtml+xml` | `application/xhtml+xml` | **`application/xhtml+xml`** | ★危険 |
| `evil.js` | `text/javascript` | `text/javascript` | **`text/javascript`** | ★危険 |

```
GET /api/media/c_hAokTCJBrGMv
  Content-Type: text/html
  Content-Disposition: なし
  X-Content-Type-Options: nosniff
  Content-Security-Policy: なし
  本文の先頭: b'<html><body><script>document.title="XSS"</script><h1>uploade'
```

**`X-Content-Type-Options: nosniff` は助けにならない。** Content-Type を `text/html` と明示しているので、
ブラウザは推測せずにHTMLとして表示する。つまり、カットを1件上げられる人は誰でも、
**このサイトと同じオリジンにスクリプトを置ける**（保存型のXSS）。共有リンクを使えば、
`/api/media/<id>?s=<token>` の形でログインしていない第三者にも渡せる。
同じオリジンで動くスクリプトは、Cookieが `HttpOnly` でもAPIをその人として呼べるので、影響は大きい。

**原因**: `res.setHeader('Content-Type', cut.mime)` が、送ってきた側の申告をそのまま返していた。
保存する `mime` 列も申告のままだった（保存名の拡張子は `.jpg`／`.mp4` に直しているのに、型だけ直していなかった）。

**直した内容**（`src/routes/api.js`）:

1. 配ってよい型の一覧（`SAFE_MEDIA_TYPES`）を作り、そこに載っている型だけを Content-Type にする。
2. 一覧に無い型は、保存名の拡張子から決め直す（`EXT_MEDIA_TYPES`）。それでも決まらなければ
   `application/octet-stream` にして `Content-Disposition: attachment` を付ける。
3. 保存するときにも同じ処理を通すので、`cuts.mime` に妙な型が残らない。
4. `Content-Security-Policy: default-src 'none'; sandbox` と `X-Content-Type-Options: nosniff` を付ける。

**直したあとに同じ攻撃をやり直した結果**:

| 申告したContent-Type | 保存されたmime | 配信のContent-Type | 判定 |
|---|---|---|---|
| `text/html` | `image/jpeg` | `image/jpeg` | 直った |
| `image/svg+xml` | `image/jpeg` | `image/jpeg` | 直った |
| `text/html`（kind=video） | `video/webm` | `video/webm` | 直った |
| `application/xhtml+xml` | `image/jpeg` | `image/jpeg` | 直った |
| `text/javascript` | `image/jpeg` | `image/jpeg` | 直った |
| `image/jpeg`（正しい写真） | `image/jpeg` | `image/jpeg` | 表示できる（9057バイト・inlineのまま） |
| `video/mp4`（正しい動画） | `video/mp4` | `video/mp4` | 表示できる（9102バイト・inlineのまま） |

```
GET /api/media/<id>
  Content-Type: image/jpeg
  X-Content-Type-Options: nosniff
  Content-Security-Policy: default-src 'none'; sandbox
  Content-Disposition: なし（画面に表示するため。危ない型のときだけ attachment を付ける）
サムネイル（?thumb=1）: image/jpeg
?download=1 のとき: Content-Type: video/mp4 / Content-Disposition: attachment; filename="c_AEr3mSamIzug.mp4"
```

正しい写真と動画は今までどおり画面に表示でき、ダウンロードも動く。`npm test` は41件すべて通る。

### G10 管理画面の操作が監査ログに残る ❌ →（直した）✅

**直す前**: 停止・復帰・管理者の付け外しを合わせて6回行ったあとで `audit_log` を見たが、
**1行も増えていなかった。** 残っていたのは `log.create`・`cut.create`・`share.create` だけだった。

```sql
SELECT action, target, detail, created_at FROM audit_log ORDER BY created_at DESC LIMIT 15;
-> share.create / cut.create ×6 / log.create ×2 のみ（admin の行が無い）
```

**原因**: `PATCH /api/admin/users/:userId` が `audit()` を呼んでいなかった。

**直した内容**: 変更した項目を添えて `admin.user.update` を記録するようにした。

**直したあとに同じ操作をやり直した結果**:

```sql
SELECT action, target, detail, user_id FROM audit_log WHERE action LIKE 'admin%' ORDER BY created_at DESC;
-> admin.user.update / u_hkRsOGp4tqQX / {"isAdmin":false}  / u_tOqt_LQBpLhO
   admin.user.update / u_hkRsOGp4tqQX / {"isAdmin":true}   / u_tOqt_LQBpLhO
   admin.user.update / u_hkRsOGp4tqQX / {"disabled":false} / u_tOqt_LQBpLhO
   admin.user.update / u_hkRsOGp4tqQX / {"disabled":true}  / u_tOqt_LQBpLhO
```

誰が（`user_id`）・誰に（`target`）・何をしたか（`detail`）・いつか（`created_at`）・
どこから（`ip`）が残る。併せて、ログインの失敗（`auth.login.fail`）と
連続失敗による停止（`auth.login.locked`）も残すようにした。

---

## 直したものの一覧

すべて担当範囲（`src/routes/api.js`・`src/auth/index.js`）の中で直した。
`npm test`（41件）はすべて通っている。

### `src/routes/api.js`

| 直したこと | 対応する項目 |
|---|---|
| 配信する Content-Type を許可した型に限り、保存する `mime` も同じ処理を通す。`Content-Security-Policy: default-src 'none'; sandbox` を付ける | G9 |
| `GET /renders/file/:name` で、そのファイルを作ったジョブのログのメンバー（か管理者）だけに配る | C10の周辺 |
| 共有トークンで来た要求では、ゴミ箱のカット（`deleted_at`）を配らない | C4・C5の周辺 |
| パスワード付きの共有は、実体の配信でもパスワードを通したことを求める（`cutlog_share_<共有ID>` のCookie） | C6 |
| 共有を作るときに `expiresAt` を検査し、日付として読めない値は400で返す。保存済みの値が読めないときは期限切れとして扱う | C5 |
| ログインの連続失敗を、アカウントごと10回・IPごと50回・15分の窓で止める | B4 |
| `PATCH /admin/users/:userId` を監査ログに残す。ログインの失敗と停止も残す | G10 |
| ログアウトで返すCookieに `SameSite=Lax` と（設定に応じて）`Secure` を付ける | B6 |
| `clientIp(req)` を作り、`TRUST_PROXY` が偽のときは `X-Forwarded-For` を読まない。監査ログ・回数制限・ログインの失敗の数え方の3か所を同じ値にそろえる | G4・F10（別の担当からの報告） |
| multerのエラーを受け取り、上限超えは `413`、他は `400` と日本語の文にする。一時ファイルも消す | D6・E12（別の担当からの報告） |
| `GET /healthz` が `schema_migrations` へ問い合わせ、読めなければ `503` と `ok:false` を返す | F1（別の担当からの報告） |
| `POST /cuts/:cutId/restore` を監査ログに残す | F10（別の担当からの報告） |

### `src/auth/index.js`

| 直したこと | 対応する項目 |
|---|---|
| 許可ドメインの比較を、大文字小文字を区別しない形にする | B8 |
| メールアドレスだけで既存の利用者に結び付けるのは、`email_verified` が `false` でないときに限る | B7・B8の周辺 |
| `oidcState` の古い記録を捨てる（10分で期限切れ・5000件で打ち切り）。`state` の期限も見る | B7の周辺 |

---

## 他の担当へ回すもの

担当範囲の外に原因があるため直していない。再現の手順と直し方の案を書く。

### 1. `web/app.js:108` の表示名がエスケープを通っていない（G1）

**再現**: `PATCH /api/me {"displayName":"表示名<img src=x onerror=alert(1)>\"><script>alert(1)</script>"}` を
送ってから、その人がメンバーになっている共有ログを画面で開き、投稿者の絞り込み（`#authorFilter`）の
HTMLを見る。値がそのまま `<option>` の中に入る。

**直し方の案**: 他の場所と同じように `escapeHtml` を通す。

```js
// 現状
+ members.map((m) => `<option value="${m.id}">${m.display_name}</option>`).join('');
// 案
+ members.map((m) => `<option value="${escapeHtml(m.id)}">${escapeHtml(m.display_name)}</option>`).join('');
```

`<option>` の中はブラウザが文字として扱うのでスクリプトは動かないが、
`web/app.js` の他の全部が `escapeHtml` を通っている中でここだけ通っていない。

同じファイルの詳細表にある `${cut.mime}` も、エスケープを通していない。
こちらはG9の直しで `image/jpeg` のような決まった語しか入らなくなったので、実際の危険は無い。

### 2. Content-Security-Policy が無い（G5・`src/index.js`）

**再現**: `curl -D - http://localhost:8791/` の応答ヘッダに `Content-Security-Policy` が無い。

**直し方の案**: `src/index.js` のヘッダを付ける処理へ1行足す。
画面のJSはすべて自分のオリジンから読み込むので、次の内容で動くはずである。

```js
res.setHeader('Content-Security-Policy',
  "default-src 'self'; img-src 'self' blob: data:; media-src 'self' blob:; "
  + "style-src 'self' 'unsafe-inline'; script-src 'self'; object-src 'none'; frame-ancestors 'none'");
```

`web/index.html` にインラインの `<script>` や `<style>` が残っていると `script-src 'self'` で動かなくなるので、
足したあとに画面を一巡して確かめる必要がある。

### 3. 読み取り（GET）に回数制限が無い（G4・`src/routes/api.js` と `src/config.js` にまたがる）

**再現**: `GET /api/healthz` を500回続けて送ると500回とも200が返る。`GET /api/logs` も300回で止まらない。

**直し方の案**: 入口の回数制限はメソッドで判定しており（`src/routes/api.js`）、
上限の値は `src/config.js` の `limits.writePerMinute` が持っている。
読み取り側の上限（例: `RATE_LIMIT_READ_PER_MINUTE`、既定600）を `src/config.js` に足し、
GETにも別枠で数えるのが素直である。設定項目が増えるので、`.env.example` と
`docs/CONFIGURATION.md` の担当と合わせて決めるのがよい。

### 4. `RELEASE_QA.md` と実装が一致しない箇所（J5・J6の担当へ）

- B8の確認の仕方に `AUTH_ALLOWED_DOMAINS` と書かれているが、実装が読むのは `OIDC_ALLOWED_DOMAINS` である。
- B9の確認の仕方に「すべて401か404」と書かれているが、`GET /api/media/:id` は403を返す（本文は空である）。
  データは出ていないので、記述を実装に合わせるのが妥当だと判断した。
- C10の確認の仕方が「ログアウトして叩く」だけなので、**ログイン済みの他人**を試す観点が抜けていた。
  そこに穴があったので、確認の仕方に「別の利用者でログインして送る」を足すとよい。

### 5. `docs/AUTH_OIDC.md` に「issuerはHTTPSであること」を書く（B7・docsの担当へ）

`openid-client` v6 はHTTPSのissuerだけを受け付ける。`http://` を書くと
`/api/auth/oidc/start` が `400 OIDCが設定されていません` を返し、
本当の理由（`only requests to HTTPS are allowed`）はサーバのログにしか出ない。
設定を間違えた人が原因にたどり着けないので、注意書きが要る。

### 6. 検証中に別の担当のサーバへ利用者を1件作ってしまった

ポート8793で動いていたサーバを自分のものと誤って、`POST /api/auth/signup` で
`secuser` というユーザー名の利用者を1件作った（パスワードは `Passw0rd!23`）。
`A7`（2人目以降は管理者にならない）や `A8`（登録を止められる）の確認をしている担当は、
利用者の件数が1件多くなっている可能性があるので、必要ならそのデータディレクトリを作り直してほしい。
自分の検証は8791・8792・8796・8799で行った。

---

## 他の担当から回ってきた不具合（`src/routes/api.js` の分）

機能・規模のQAの担当と、データ・運用のQAの担当から上がった不具合を、こちらで直して確かめた。

### あ. アップロードの上限を超えたときに `500` と英語で返っていた

**再現**: `MAX_UPLOAD_MB=5` で起動し、5MBを超える動画を送る。

```
（直す前）POST /api/logs/<log>/cuts（11.2MBの動画）
-> 500 {"error":"File too large"}
```

**原因**: `upload.single('file')`（multer）が投げる `LIMIT_FILE_SIZE` を誰も受け取らず、
`src/index.js` の最後のエラー処理へ流れて500になっていた。

**直した内容**: multerを包む `uploadFile()` を作り、multerのエラーの種類ごとに
状態コードと日本語の文を決めるようにした。文にはサーバの中の様子（パス・呼び出し履歴）を入れない。
途中まで書けた一時ファイルも消す。

**直したあと**（`MAX_UPLOAD_MB=5` のサーバで実測）:

| 送ったもの | 結果 | 返ってきた内容 |
|---|---|---|
| 11.2MBの動画（`POST /logs/<log>/cuts`） | **413** | `ファイルが大きすぎます。1件あたり5MBまで上げられます。短く撮り直すか、画質を下げてから送ってください。` |
| 11.2MBの動画（`POST /cuts`） | **413** | 同じ文 |
| 項目名を `movie` にする | 400 | `ファイルの項目名が違います。file という名前で1件だけ送ってください。` |
| ファイルを2件送る | 400 | 同上 |
| `meta` を1MBにする | 413 | `meta が長すぎます。短くしてから送ってください。` |
| Content-Type に改行を入れる | 400 | `送られたデータを読めませんでした。multipart/form-data で file と meta を送ってください。` |
| 本文が途中で切れている | 400 | 同上 |
| multipart になっていない | 400 | 同上 |
| 上限の中の正しい動画 | 200 | カットが作られる（回帰なし） |

上限の数値（`5`）は `config.media.maxUploadMb` から入れているので、設定を変えれば文も変わる。

**あわせて確かめたこと（G3・G6に当たる）**: ファイル名に妙な文字を入れたときも、
500や英語の文は返らず、サーバの中の様子も出ない。

| ファイル名 | 結果 |
|---|---|
| `../../../../evil.mp4` | 200（保存名はサーバが決めた `c_*.mp4`） |
| `a;whoami.mp4`・`a$(whoami).mp4`・`a"quote.mp4` | 200（同上） |
| `日本語 ファイル.mp4` | 200（同上） |
| `a` を300回並べた名前 + `.mp4` | 200（同上） |
| `null.mp4`（NUL文字入り） | 400 `送られたデータを読めませんでした。…` |

いずれの応答にも `C:\`・`node_modules`・`at Object`・例外の名前は入っていない。

### い. `X-Forwarded-For` を無条件に信用していた（★セキュリティ）

**再現**: `TRUST_PROXY` を設定せずに起動し、`X-Forwarded-For: 1.2.3.4` を付けてAPIへ送り、
`audit_log` の `ip` 列を見る。

**直す前**: 偽装した値がそのまま記録され、回数制限も同じ値で数えていたので、
**ヘッダを毎回変えるだけで回数制限を回り込めた。**

**原因**: `audit()`・入口の回数制限・ログインの失敗の数え方の3か所が、
`req.headers['x-forwarded-for'] || req.socket.remoteAddress` を直に読んでいた。

**直した内容**: `clientIp(req)` を1つ作り、3か所すべてがそれを使うようにした。
`config.trustProxy` が偽のときは `req.socket.remoteAddress` だけを使い、
真のときは `X-Forwarded-For` の**左端**を使う。

**直したあとに同じ攻撃をやり直した結果**（`TRUST_PROXY` 未設定のサーバ）:

```
POST /api/logs（ヘッダなし）                             -> audit_log.ip = '::1'
POST /api/logs（X-Forwarded-For: 1.2.3.4）               -> audit_log.ip = '::1'
POST /api/logs（X-Forwarded-For: 9.9.9.9, 8.8.8.8）      -> audit_log.ip = '::1'
記録されたIPの種類: {'::1'}（偽装は通らない）

毎回ちがうIPを名乗って POST /api/logs を150回送る（上限120回／分）
-> {200: 116, 429: 34}（回り込めない）
```

**`TRUST_PROXY=true` のときの動き**（逆向きのプロキシの後ろに置いた場合）:

```
POST /api/logs（X-Forwarded-For: 203.0.113.7, 198.51.100.1）-> audit_log.ip = '203.0.113.7'（左端）
POST /api/logs（ヘッダなし）                                 -> audit_log.ip = '::1'
毎回ちがう利用者のIPで20回 -> {200: 20}（利用者ごとに数えるので、これが正しい動き）
```

### う. `/api/healthz` がDBの異常を見つけられなかった

**直す前**: `SELECT 1 AS ok` はテーブルへ触らないので、DBが読めない状態でも `{"ok":true}` を返した。

**直した内容**: 実際にある `schema_migrations` へ問い合わせ、
読めなければ `503` と `ok: false` を返すようにした。応答の形（`ok`・`db`・`storage`・`time`）は保ち、
適用済みのマイグレーションの件数（`migrations`）を足した。

**ストレージ（保存先）を確かめるかどうかの判断**: **確かめないことにした。**
死活は監視の間隔で繰り返し呼ばれるので、速く返ることが大事である。
保存先がS3互換のときは外への通信が入って遅くなり、外の障害でWebまで異常と見なされる。
保存先が書けるかどうかはアップロードと書き出しの経路で分かるので、そちらで見るのが妥当だと考えた。

**直したあとに実際にDBを壊して確かめた結果**:

```
（壊す前）GET /api/healthz
-> 200 {"ok":true,"db":"sqlite","storage":"local","migrations":3,"time":"..."}

（別のプロセスから DROP TABLE schema_migrations を実行し、DBが読めない状態を作る）
GET /api/healthz
-> 503 {"ok":false,"db":"sqlite","storage":"local",
        "error":"データベースを読めません。保存先のファイルと接続の設定を確かめてください","time":"..."}
サーバのログ: [healthz] データベースを読めません: no such table: schema_migrations

（テーブルを作り直す）
GET /api/healthz -> 200 {"ok":true,...}
```

**この確認で分かった限界を書き残す**: SQLiteの場合、**動いているサーバの目の前でDBのファイルを
0バイトにしても、そのサーバは開いたままのファイルの手がかりから読み続けるので、
どんな問い合わせをしても成功する。** 実測でも、ファイルを0バイトにした直後の `/api/healthz` は
200を返した。これは確認の中身ではなくSQLiteのファイルの扱い方によるもので、
プロセスがファイルを開き直した時点で503に変わる。
0バイトのファイルを置いたまま起動し直した場合は、`initDb()` がテーブルを作り直すので200に戻る
（そのときデータは失われているが、DBは読める状態である）。
`/api/healthz` は「いまDBが読めるか」を返すものであり、「データが失われていないか」は返さない。

### え. `restore`（ゴミ箱から戻す操作）が監査ログに残っていなかった

`POST /api/cuts/:cutId/restore` に `audit(req, 'cut.restore', c.id, { logId })` を1行足した。
他の操作（`cut.create`・`cut.delete`・`cut.move`）と同じ形である。

```sql
SELECT action, target, detail FROM audit_log WHERE action = 'cut.restore';
-> cut.restore / c_CZ53_hdnKZa3 / {"logId":"l_l0dOUtGgUISw"}
```

---

## 判定の記録

| 実施日 | 実施者 | 通った | 落ちた | 対象外 |
|---|---|---|---|---|
| 2026-08-22 | B・C・G の担当 | 27 | 3（B4・G9・G10。すべて直して再確認した） | 0 |
