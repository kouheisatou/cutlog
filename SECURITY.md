# セキュリティ

## 報告

脆弱性を見つけたときは、**公開のIssueにせず**、GitHubの
[Security Advisories](https://github.com/kouheisatou/cutlog/security/advisories/new) から
非公開でご連絡ください。

## セルフホストする方へ

- **HTTPSで公開してください。** カメラとWeb Pushは、HTTPSかlocalhostでしか動きません
- `COOKIE_SECURE=true` と `TRUST_PROXY=true` を、リバースプロキシの後ろでは設定してください
- 公開サーバでは `AUTH_OPEN_SIGNUP=false` にし、OIDC か招待だけで人を入れてください
- 共有リンクは**URLを知っていれば見られます。**必要ならパスワードと有効期限を設定してください
- バックアップ（DBとメディア）を取ってください
