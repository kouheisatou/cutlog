# ネイティブの殻（android / ios）を触るときの環境。
#
#   source scripts/dev-env.sh
#
# ここでしか使わない値をシェルに常駐させたくないので、
# ~/.zshrc などには入れず、必要なときだけ読み込む形にしている。

# ── Android ───────────────────────────────────────────
# Java は Android Studio に同梱されているものを使う（別途入れなくてよい）。
if [ -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

# ── 使えるかどうかの確認 ──────────────────────────────
cutlog_dev_env_check() {
  printf 'java      : %s\n' "$( (java -version 2>&1 | head -1) || echo '見つからない')"
  printf 'adb       : %s\n' "$( (adb version 2>/dev/null | head -1) || echo '見つからない')"
  printf 'emulator  : %s\n' "$( (emulator -version 2>/dev/null | head -1) || echo '見つからない')"
  printf 'avd       : %s\n' "$( (emulator -list-avds 2>/dev/null | tr '\n' ' ') || echo 'なし')"
  printf 'xcodebuild: %s\n' "$( (xcodebuild -version 2>/dev/null | head -1) || echo '見つからない')"
  printf 'simruntime: %s\n' "$( (xcrun simctl list runtimes 2>/dev/null | grep -c 'iOS') || echo 0)件"
}

echo 'cutlog: ネイティブ向けの環境を読み込みました（確認は cutlog_dev_env_check）'
