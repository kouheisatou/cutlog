#!/usr/bin/env bash
# 見比べを一周する。
#   ./tool/parity/run.sh            全画面
#   ./tool/parity/run.sh logs,all   その画面だけ
# ★ 本物を撮る → Flutter を建てて撮る → 重ねて測る、までを1つにしてある。
#   途中だけ手で走らせると、古い絵と新しい絵を比べてしまう。
set -euo pipefail
cd "$(dirname "$0")/../.."

ONLY="${1:-}"
ARG=""
[ -n "$ONLY" ] && ARG="--only=$ONLY"

echo "── サーバの様子 ──────────────────────────────"
curl -sf -o /dev/null http://localhost:8787/ || { echo "本物のサーバ(8787)が止まっています。npm start してください。"; exit 1; }
if ! curl -sf -o /dev/null http://localhost:8788/; then
  echo "見比べ用の配り口(8788)を起こします"
  (node tool/parity/serve.mjs > /tmp/parity-serve.log 2>&1 &)
  sleep 2
fi

echo "── 中身を用意 ────────────────────────────────"
# 撮影の画面で流し込む真っ黒の映像。既定の作り物は動く模様で、撮るたびに絵が変わる。
if [ ! -f tool/parity/fixtures/black.y4m ]; then
  mkdir -p tool/parity/fixtures
  ffmpeg -hide_banner -loglevel error -y -f lavfi -i color=c=black:s=640x360:d=2 \
    -pix_fmt yuv420p tool/parity/fixtures/black.y4m
fi
node tool/parity/seed.mjs

echo "── 組み立て（Flutter → web）──────────────────"
flutter build web --release 2>&1 | tail -2

echo "── 本物を撮る ────────────────────────────────"
node tool/parity/shoot.mjs --target=web $ARG

echo "── Flutter を撮る ────────────────────────────"
node tool/parity/shoot.mjs --target=flutter $ARG

echo "── 座標を吸い出す ────────────────────────────"
node tool/parity/probe.mjs $ARG > /dev/null

echo "── 重ねて測る ────────────────────────────────"
python3 tool/parity/diff.py shots
