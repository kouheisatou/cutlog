# cutlog — Android のネイティブ殻

cutlog の Web をそのまま WebView で映し、**撮影だけをネイティブ（CameraX）で行う**ための殻。

ブラウザの `getUserMedia` では端末の手ぶれ補正や画づくりが通らない。
そこで撮影と、その場でのアップロードだけをネイティブ側に持たせ、
それ以外（一覧・再生・編集・ログイン）はすべて Web 側のままにしてある。

- applicationId: `dev.cutlog.shell`
- minSdk 26 / compileSdk 35 / targetSdk 35
- Kotlin + Gradle Kotlin DSL（AGP 9 / Gradle 9。AGP 9 から Kotlin サポートが AGP に内蔵されたので `org.jetbrains.kotlin.android` は入れていない）

## つなぐ先を決める

**接続先はビルドのときに埋め込む。アプリの中では入力させない。**

リポジトリのルートの `native.env` を読み、`CUTLOG_BASE_URL` を `BuildConfig.BASE_URL` に入れる。

```sh
# リポジトリのルートで
cp native.env.example native.env
$EDITOR native.env     # CUTLOG_BASE_URL を自分のサーバに書き換える
```

```
CUTLOG_BASE_URL=https://appserver.tail7ca50.ts.net:8787
CUTLOG_APP_NAME=cutlog
```

- `native.env` が無ければ `native.env.example` を読む
- どちらも無ければ、分かる形でビルドを止める（空の URL を埋め込んだ APK は作らない）
- `CUTLOG_APP_NAME` はランチャーに出る名前になる（省略時は `cutlog`）
- **URL を変えたら入れ直しが要る**（アプリの中に設定画面は無い）

### 動作確認だけ別の行き先にしたいとき

`native.env` を書き換えずに、その回のビルドだけ上書きできる。
エミュレータから手元のサーバ（`http://10.0.2.2:PORT`）を見るときに使う。

```sh
./gradlew assembleDebug -PcutlogBaseUrl=http://10.0.2.2:8899
```

## ビルド

```sh
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

cd android
./gradlew assembleDebug
# → app/build/outputs/apk/debug/app-debug.apk
```

`local.properties`（`sdk.dir`）は git に入れない。無ければ次で作る。

```sh
printf 'sdk.dir=%s\n' "$ANDROID_HOME" > local.properties
```

## エミュレータで動かす

```sh
emulator -avd cutlog_pixel -no-snapshot -no-audio &
adb wait-for-device
# 起動しきるまで待つ
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 2; done

adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n dev.cutlog.shell/.MainActivity
adb exec-out screencap -p > /tmp/android-shot.png
```

エミュレータの向きは撮影画面に入ると横になる（`CaptureActivity` は landscape 固定）。
`cutlog_pixel` の背面カメラは `emulated` なので、色の帯のテストパターンが映る。

権限のダイアログは順に出る。画面を叩かずに済ませるなら:

```sh
adb shell pm grant dev.cutlog.shell android.permission.CAMERA
adb shell pm grant dev.cutlog.shell android.permission.RECORD_AUDIO
adb shell pm grant dev.cutlog.shell android.permission.ACCESS_FINE_LOCATION
```

エミュレータから見たホストは `10.0.2.2`。tailscale 上のサーバ（`*.ts.net`）へは
エミュレータからは届かないので、手元で確かめるときは `-PcutlogBaseUrl` を使う。

## JS ブリッジの約束

Web 側（`web/app.js` の `nativeShell`）とこの殻の取り決め。

### web → native

```js
window.CutlogNative.capture(JSON.stringify({
  type: 'capture',
  baseUrl: location.origin,   // 例 https://cutlog.example.com
  logId:  'l_xxxxx',          // 撮ったカットの行き先
  seconds: 5,                 // 何秒撮るか
  tzOffset: new Date().getTimezoneOffset(),
}));
```

引数は **JSON 文字列 1 本**。`addJavascriptInterface` はオブジェクトを渡せないため。

### native → web

撮影とアップロードが終わったら、殻が次を呼ぶ。

```js
window.cutlogNative.onResult({ ok: true });
window.cutlogNative.onResult({ ok: false, error: 'カメラを使えませんでした' });
```

`window.cutlogNative.onResult` が無いときは何もしない（古い Web でも落ちないように）。

### 動画はブリッジを通さない

撮ったものは殻からサーバへ直接上げる。JS 橋に動画のバイト列を通すと
文字列化で数倍に膨れて実用にならないため。Web には成否だけが返る。

```
POST {baseUrl}/api/logs/{logId}/cuts
Content-Type: multipart/form-data
Cookie: <WebView が持っているものをそのまま>

file: 動画（video/mp4）
meta: JSON 文字列
```

`meta` の形:

```json
{
  "kind": "video",
  "durationMs": 2910,
  "takenAt": "2026-08-23T02:25:45.830355Z",
  "tzOffset": -540,
  "facing": "environment",
  "source": "camera",
  "lat": 37.421998,
  "lon": -122.084,
  "accuracy": 5
}
```

`lat` / `lon` / `accuracy` は位置が取れたときだけ入る。断られても撮影は止めない。

### 認証

殻はログインの仕組みを持たない。Web 側の認証が唯一の正とし、
アップロードのときは `CookieManager.getInstance().getCookie(baseUrl)` の中身を
そのまま `Cookie` ヘッダに載せる。

## 中身

```
android/
  settings.gradle.kts          リポジトリを google/mavenCentral に固定
  build.gradle.kts             プラグインの宣言だけ
  gradle/libs.versions.toml    依存のバージョン（compileSdk 35 に合う世代で止めてある）
  app/
    build.gradle.kts           native.env の読み込みと BuildConfig.BASE_URL
    src/main/AndroidManifest.xml
    src/main/java/dev/cutlog/shell/
      MainActivity.kt          WebView 一枚 ＋ JS 橋（CutlogNative）
      CaptureActivity.kt       CameraX での撮影（横向き固定・秒数で自動停止）
      CaptureRequest.kt        web から降りてくる注文の読み取り
      Uploader.kt              OkHttp での multipart 送信（Cookie 流用）
    src/main/res/
      layout/activity_main.xml     WebView ＋ つながらないときの覆い
      layout/activity_capture.xml  プレビュー ＋ 録画 / やめる
```

## 撮影まわりの決め事

- **横向き固定**。カットは横で見る前提なので、端末の向きに任せない
- **画質**は FHD → HD → SD の順に狙い、出せない相手には落ちる。
  一段しか譲らないと、対応画質の少ない端末で撮影自体ができなくなる
- **手ぶれ補正**は端末が対応していれば入れる。
  CameraX 1.4 の `CameraInfo` にはまだ問い合わせ口が無いので、
  Camera2 の `CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES` を直接見ている。
  録画側（EIS）とプレビュー側（Android 13 以降）は別枠なので、別々に見る
- **秒数が来たら自分で止める**。Web 側の「◯秒のカット」に合わせるため
- **位置**は Play サービスに頼らず素の `LocationManager` で取る。
  セルフホスト前提のアプリに Google の依存を増やしたくないため

## まだ確かめていないこと

- 手ぶれ補正が実際にどれだけ効くかは実機でないと分からない
  （エミュレータは「対応している」と答えるが、映像は合成のテストパターン）
- 実機の背面カメラでの FHD 実出力、長い録画、電池・発熱
- release ビルドの署名と配布
