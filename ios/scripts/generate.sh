#!/bin/bash
# .xcodeproj を作り直す。XcodeGen が要る（brew install xcodegen）。
#
# 生成物の BuildConfig.swift を先に作るのは、
# XcodeGen が sources を並べる時点でファイルが無いと target に入らないため。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ios_dir="$(dirname "$here")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen が見つかりません。'brew install xcodegen' を実行してください。" >&2
  exit 1
fi

"$here/generate-build-config.sh"
cd "$ios_dir"
xcodegen generate
echo "CutlogShell.xcodeproj を生成しました。"
