#!/bin/bash
# リポジトリのルートにある native.env を読み、
# CutlogShell/Generated/BuildConfig.swift を作り直す。
#
# なぜビルド時に埋め込むか:
#   自己ホストの殻なので接続先は環境ごとに違うが、
#   利用者に毎回入力させたくない。値はビルドの入力として固定する。
#
# ビルドのたびに Xcode の Run Script フェーズから呼ばれる。
# XcodeGen で .xcodeproj を作る前にも呼ぶ（生成物が無いと sources に並ばないため）。
set -euo pipefail

# このスクリプトの位置から ios/ とリポジトリのルートを割り出す。
# Xcode から呼ばれるときは SRCROOT があるが、手で叩くときのために両対応にする。
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ios_dir="${SRCROOT:-$(dirname "$here")}"
repo_root="$(cd "$ios_dir/.." && pwd)"

env_file="$repo_root/native.env"
if [ ! -f "$env_file" ]; then
  # 手元に native.env が無いときは雛形で代用する。
  # 雛形にも既定の住所が書いてあるので、とりあえずビルドは通る。
  env_file="$repo_root/native.env.example"
fi

if [ ! -f "$env_file" ]; then
  echo "error: native.env も native.env.example も見つかりません（探した場所: ${repo_root}）。" >&2
  echo "error: リポジトリのルートで 'cp native.env.example native.env' してから、接続先を書いてください。" >&2
  exit 1
fi

# KEY=VALUE だけを拾う。値に # が入ることはないので行末コメントは考えない。
read_key() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$env_file" \
    | tail -n 1 \
    | sed -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//'
}

base_url="$(read_key CUTLOG_BASE_URL)"
app_name="$(read_key CUTLOG_APP_NAME)"
[ -n "$app_name" ] || app_name="cutlog"

# 空のまま埋め込むと「起動したけど真っ白」という分かりにくい失敗になる。
# ここで止めた方が原因がすぐ分かる。
if [ -z "$base_url" ]; then
  echo "error: $env_file に CUTLOG_BASE_URL がありません（または空です）。" >&2
  echo "error: 例) CUTLOG_BASE_URL=https://cutlog.example.com" >&2
  exit 1
fi
case "$base_url" in
  http://*|https://*) ;;
  *)
    echo "error: CUTLOG_BASE_URL は http:// か https:// で始めてください（今の値: ${base_url}）。" >&2
    exit 1
    ;;
esac
# 末尾のスラッシュは URL の組み立てで二重になるので落としておく
base_url="${base_url%/}"

out_dir="$ios_dir/CutlogShell/Generated"
out="$out_dir/BuildConfig.swift"
mkdir -p "$out_dir"

tmp="$(mktemp)"
cat > "$tmp" <<EOF
// このファイルは native.env から自動生成される。直接編集しても次のビルドで消える。
// 生成元: ios/scripts/generate-build-config.sh
import Foundation

/// ビルド時に埋め込まれた設定。
enum BuildConfig {
    /// つなぐ先の cutlog サーバ。native.env の CUTLOG_BASE_URL。
    static let baseURLString = "$base_url"

    /// 画面に出すアプリ名。native.env の CUTLOG_APP_NAME。
    static let appName = "$app_name"

    /// 組み立て済みの URL。生成時に形を検証しているので、ここで落ちることはない。
    static let baseURL: URL = {
        guard let url = URL(string: baseURLString) else {
            fatalError("BuildConfig.baseURLString が URL になりません: \\(baseURLString)")
        }
        return url
    }()
}
EOF

# 中身が同じなら触らない。毎回書き換えると Swift の再コンパイルが走ってしまう。
if [ -f "$out" ] && cmp -s "$tmp" "$out"; then
  rm -f "$tmp"
  echo "BuildConfig.swift は最新です（${base_url}）"
else
  mv "$tmp" "$out"
  echo "BuildConfig.swift を生成しました（${base_url}）"
fi
