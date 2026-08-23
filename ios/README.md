# cutlog iOS 殻（CutlogShell）

cutlog の Web アプリを WKWebView で表示し、**撮影だけをネイティブ（AVFoundation）で行う**殻です。

ブラウザの `getUserMedia` では、iPhone の手ぶれ補正（シネマティック手ぶれ補正）や
画づくりの処理がまったく通りません。カットは手持ちで撮るものなので、そこが効くかどうかで
出来上がりが大きく変わります。**この殻の存在理由は手ぶれ補正を効かせること**です。

- Bundle Identifier: `dev.cutlog.shell`
- Deployment Target: iOS 17.0
- UIKit（Storyboard なし・コードのみ）

---

## 1. 接続先の設定（native.env）

接続先はアプリ内で入力させず、**ビルド時に埋め込みます**。
リポジトリのルートにある `native.env` を読みます。

```bash
# リポジトリのルートで
cp native.env.example native.env
```

```
CUTLOG_BASE_URL=https://appserver.tail7ca50.ts.net:8787
CUTLOG_APP_NAME=cutlog
```

- `native.env` が無ければ `native.env.example` に落ちます。
- **どちらも無い / `CUTLOG_BASE_URL` が空 / `http(s)://` で始まらない** 場合は、
  理由を書いてビルドを失敗させます（黙って空文字を埋め込むことはしません）。

### 仕組み（採用したのは a 案）

`ios/scripts/generate-build-config.sh` を Xcode の Run Script フェーズ（Compile Sources の前）で毎回走らせ、
`ios/CutlogShell/Generated/BuildConfig.swift` を作り直します。アプリからは `BuildConfig.baseURL` で読みます。

生成物なので `ios/.gitignore` で除外しています。ビルドのたびに作られるため、
リポジトリを clone した直後でも `xcodebuild` を叩けばそのまま通ります。

> リポジトリのルートの外を読む必要があるため、この target では
> `ENABLE_USER_SCRIPT_SANDBOXING = NO` にしています。

**接続先を変えるには** `native.env` を書き換えて、ビルドし直してください。
アプリ側に切り替え画面はありません（自己ホストの住所は環境ごとに固定という前提です）。

`CUTLOG_APP_NAME` は画面内の表示にだけ使います。
ホーム画面に出る名前を変えるには `CutlogShell/Info.plist` の `CFBundleDisplayName` も直してください。

---

## 2. ビルド

### 2-1. そのままビルドする（XcodeGen は不要）

`CutlogShell.xcodeproj` はリポジトリに入れてあるので、`xcodebuild` だけでビルドできます。

```bash
cd ios
xcodebuild -project CutlogShell.xcodeproj -target CutlogShell \
  -sdk iphonesimulator -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

成果物は `ios/build/Debug-iphonesimulator/cutlog.app` に出ます。

**`-scheme` を使う書き方**もできますが、こちらは
シミュレータのランタイムが入っていないと「destination が見つからない」で失敗します。

```bash
cd ios
xcodebuild -scheme CutlogShell -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

> `CODE_SIGNING_ALLOWED=NO` は、署名の設定が無い環境でも通すために付けています。
> シミュレータ向けなら署名は要りません。

### 2-2. プロジェクトを作り直す（XcodeGen）

`.xcodeproj` は `project.yml` から生成しています。ファイルを足したときは作り直してください。

```bash
brew install xcodegen
cd ios
./scripts/generate.sh     # BuildConfig.swift を作ってから xcodegen generate
```

---

## 3. シミュレータで動かす

```bash
# 使えるランタイムを確かめる（空なら Xcode > Settings > Components から入れる）
xcrun simctl list runtimes

# 端末を用意して起動
xcrun simctl create cutlog-test com.apple.CoreSimulator.SimDeviceType.iPhone-16
xcrun simctl boot cutlog-test
open -a Simulator

# 入れて動かす
xcrun simctl install cutlog-test ios/build/Debug-iphonesimulator/cutlog.app
xcrun simctl launch cutlog-test dev.cutlog.shell

# 画面を撮る
xcrun simctl io cutlog-test screenshot /tmp/ios-shot.png
```

シミュレータにはカメラが無いので、**撮影はシミュレータでは確認できません**。
表示・ログイン・ブリッジの呼び出しまでが確認の範囲です。

---

## 4. 実機ビルド（署名）

実機では署名が要ります。Apple Developer のアカウント（無料枠でも可）を用意して、
チーム ID を渡してください。

```bash
cd ios
xcodebuild -project CutlogShell.xcodeproj -target CutlogShell \
  -sdk iphoneos -configuration Debug \
  DEVELOPMENT_TEAM=XXXXXXXXXX \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates build
```

- `DEVELOPMENT_TEAM` は Xcode の Settings > Accounts か、
  `security find-identity -v -p codesigning` で確認できます。
- Bundle ID `dev.cutlog.shell` はそのままだと他人と衝突しません。
  無料アカウントでプロファイルが作れない場合だけ、自分のものに変えてください。
- 初回は端末側で「設定 > 一般 > VPN とデバイス管理」から開発者を信頼する操作が要ります。

`native.env` の接続先が **端末から見えるアドレス**であることを確かめてください
（Tailscale 越しなら端末にも Tailscale を入れる、など）。

---

## 5. Web との受け渡し（ブリッジ契約）

Web 側（`web/app.js`）は実装済みで、殻はそれに合わせています。

### Web → native

```js
window.webkit.messageHandlers.cutlog.postMessage({
  type: "capture",
  baseUrl,   // location.origin
  logId,     // 記録先のログ ID
  seconds,   // 何秒撮るか
  tzOffset,  // new Date().getTimezoneOffset()（日本なら -540）
});
```

`WKUserContentController.add(_:name:"cutlog")` で受けます。
Web 側は `window.webkit?.messageHandlers?.cutlog` の有無で殻の中かどうかを判定するので、
**ハンドラ名 `cutlog` は変えないでください。**

### native → Web

```js
window.cutlogNative.onResult({ ok: true });
window.cutlogNative.onResult({ ok: false, error: "…" });
```

`evaluateJavaScript` で呼びます。利用者が自分で撮影をやめたときは
`{ ok: false }`（`error` なし）を返します。Web 側はこのとき何も出しません。

### アップロード

動画は JS を経由させず、ネイティブから直接送ります
（base64 で橋渡しするとメモリが跳ねるため）。

```
POST {baseUrl}/api/logs/{logId}/cuts
Content-Type: multipart/form-data
  file : 動画（video/mp4）
  meta : JSON 文字列
```

`meta` の形:

```json
{
  "kind": "video",
  "durationMs": 3012,
  "takenAt": "2026-08-23T02:00:00.000Z",
  "tzOffset": -540,
  "facing": "environment",
  "source": "camera",
  "lat": 35.68, "lon": 139.76, "accuracy": 12.5
}
```

`lat` / `lon` / `accuracy` は位置情報が取れたときだけ入れます。

**認証は WKWebView のセッション Cookie（`cutlog_session`）を借ります。**
`WKWebsiteDataStore.default().httpCookieStore.getAllCookies` で取り出し、
domain / path / secure / 有効期限を照合したうえで `Cookie` ヘッダを自分で組み立てます。
`URLRequest.httpShouldHandleCookies = false` にしているのは、
URLSession の自動管理だと WKWebView とは別の保管庫を見てしまい、セッションが渡らないためです。

---

## 6. 手ぶれ補正について

`CutlogShell/CameraSession.swift` が担当です。効く順に 3 つ気を使っています。

1. **カメラの選び方** — `.builtInTripleCamera` → `.builtInDualWideCamera` → `.builtInWideAngleCamera`。
   複合カメラは超広角側の余白を使えるので、シネマティック手ぶれ補正が効きやすく画質も良い。
2. **フォーマット** — `sessionPreset = .hd1920x1080`。
   4K は手ぶれ補正の付かない形式が選ばれることがあるため、1080p を基本にする。
3. **接続への設定** — `connection.preferredVideoStabilizationMode` に、強い順で使えるものを入れる。
   `.cinematicExtendedEnhanced`（iOS 18+）→ `.cinematicExtended` → `.cinematic` → `.standard`。

> 対応の可否を持っているのは `AVCaptureConnection` ではなく **`AVCaptureDeviceFormat`** です
> （`connection` 側には総合可否の `isVideoStabilizationSupported` しかありません）。
> そのため `device.activeFormat.isVideoStabilizationModeSupported(_:)` で判定しています。
> また、`sessionPreset` が `activeFormat` に反映されるのは `commitConfiguration` の時点なので、
> 補正を決めるのは必ず commit の**あと**です。

1080p でも補正が付かない形式が選ばれた場合は、
`device.formats` から「1920x1080・30fps・cinematic 系に対応」のものを探して `activeFormat` を入れ替えます
（このとき `sessionPreset` は `.inputPriority` に落ちますが、
補正の無い 1080p より補正の効く 1080p の方がこの殻の目的に適います）。

実際に効いている補正は撮影画面の左上に日本語で出るので、実機で目視できます。

そのほか:
- 横向き固定（`supportedInterfaceOrientations = .landscape`）。
  向きは iOS 17 の `connection.videoRotationAngle` で入れます（`landscapeRight` が 0 度）。
- `AVCaptureMovieFileOutput` の出力先の拡張子を `.mp4` にしています。
  既定の QuickTime `.mov` のままだと、サーバ側の保存時の拡張子判定と食い違うためです。
- `seconds` 経過でこちらから `stopRecording()` します。
  保険として `maxRecordedDuration` を +1 秒で入れてあります。

---

## 7. ファイル構成

```
ios/
├── project.yml                 XcodeGen の定義
├── CutlogShell.xcodeproj/      生成物（xcodebuild 単体で使えるよう追跡している）
├── scripts/
│   ├── generate-build-config.sh  native.env → Generated/BuildConfig.swift
│   └── generate.sh               上を実行してから xcodegen generate
└── CutlogShell/
    ├── AppDelegate.swift        窓の組み立て。向きの可否を最前面の画面へ委ねる
    ├── RootViewController.swift 土台。起動したら WebView を出すだけ
    ├── WebViewController.swift  WKWebView 1 枚 ＋ JS ブリッジ
    ├── CaptureRequest.swift     Web から来る撮影の注文
    ├── CaptureViewController.swift 撮影画面（プレビュー・シャッター・カウントダウン）
    ├── CameraSession.swift      AVFoundation。★手ぶれ補正はここ
    ├── CutUploader.swift        multipart 送信 ＋ WKWebView の Cookie 流用
    ├── LocationProvider.swift   位置情報（取れたときだけ meta に足す）
    ├── Info.plist               権限の説明（日本語）・向き・ATS
    ├── Assets.xcassets/         アプリアイコン（今は空。下の「未対応」参照）
    └── Generated/BuildConfig.swift  ビルド時に生成（git 管理外）
```

---

## 8. 分かっている制約・未対応

- **アプリアイコンが入っていません。** アイコンを入れると `actool` が走り、
  それにはシミュレータのランタイムが必要になります。
  ランタイムを入れたうえで `AppIcon.appiconset` に 1024x1024 の PNG を置き、
  `Contents.json` に `"filename"` を足してください。
- 撮影・手ぶれ補正・位置情報は**実機でしか確認できません**（シミュレータにカメラがないため）。
- WebView 内での再読み込みは **2 本指の長押し（1 秒）**で出せます。常設のボタンは置いていません。
- 自己署名証明書のサーバには繋がりません。ATS は
  `NSAllowsArbitraryLoads = false` / `NSAllowsLocalNetworking = true` にしてあります。
- サーバ側が想定より大きいファイルを弾く場合の再試行はしていません（1 回で失敗したらそのまま Web に返します）。
