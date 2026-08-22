# シングルサインオン（OIDC）

`.env` に3行書くだけで、ログイン画面にボタンが出ます。

```
OIDC_ISSUER=...
OIDC_CLIENT_ID=...
OIDC_CLIENT_SECRET=...
```

**リダイレクトURIは必ずこの形です。**

```
<BASE_URL>/api/auth/oidc/callback
```

## Google

1. Google Cloudコンソールで「APIとサービス」から「認証情報」を開く
2. 「認証情報を作成」から「OAuth クライアント ID」を選び、種類は「ウェブ アプリケーション」にする
3. 「承認済みのリダイレクト URI」に `https://cutlog.example.com/api/auth/oidc/callback` を足す
4. 発行されたIDとシークレットを `.env` に書く

```
OIDC_ISSUER=https://accounts.google.com
OIDC_CLIENT_ID=xxxx.apps.googleusercontent.com
OIDC_CLIENT_SECRET=xxxx
OIDC_BUTTON_LABEL=Googleで入る
OIDC_ALLOWED_DOMAINS=example.co.jp
```

`OIDC_ALLOWED_DOMAINS` を書くと、そのドメインのメールを持つ人だけが入れます。

## Microsoft Entra ID

```
OIDC_ISSUER=https://login.microsoftonline.com/<テナントID>/v2.0
OIDC_CLIENT_ID=<アプリケーションID>
OIDC_CLIENT_SECRET=<クライアントシークレット>
OIDC_BUTTON_LABEL=Microsoftで入る
```

## Keycloak

```
OIDC_ISSUER=https://keycloak.example.com/realms/<realm名>
OIDC_CLIENT_ID=cutlog
OIDC_CLIENT_SECRET=<シークレット>
```

## Auth0・Okta・GitLab など

OpenID Connectに対応していれば、同じ3行で動きます。`OIDC_ISSUER` には、
ディスカバリ文書（`.well-known/openid-configuration`）を持つURLの、その手前までを書いてください。

## つまずいたとき

| 症状 | 原因 |
|---|---|
| `redirect_uri_mismatch` が出る | `BASE_URL` と、IdPに登録したURIが食い違っている |
| ログインした後に戻ってこない | リバースプロキシの後ろなのに `TRUST_PROXY=true` を入れていない |
| 毎回ログアウトされる | HTTPSなのに `COOKIE_SECURE=false` になっている（またはその逆） |
| ボタンが出ない | `OIDC_ISSUER` か `OIDC_CLIENT_ID` が空。起動時のログにエラーが出ていないか見る |
