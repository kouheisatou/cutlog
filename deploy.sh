#!/usr/bin/env bash
#
# cutlog をこのサーバで更新する。gitから最新を取ってきて、作り直して、入れ替える。
#
#   /opt/cutlog/deploy.sh                            最新（origin/main）へ更新
#   /opt/cutlog/deploy.sh v0.2.0                     指定のタグ・ブランチ・コミットへ
#   /opt/cutlog/deploy.sh --rollback                 直前の版へ戻す
#   /opt/cutlog/deploy.sh --status                   いまの状態だけ見る
#
# 途中で失敗したら、そこで止めて元のまま残す（中途半端な状態にしない）。
# 起動後に健康確認が通らなければ、自動で直前の版へ戻す。
#
# .env は git に入っていない。このサーバの /opt/cutlog/.env をそのまま使い続ける。
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/opt/cutlog}"
REMOTE="${REMOTE:-origin}"
BRANCH="${BRANCH:-main}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8787/api/healthz}"
HEALTH_TRIES="${HEALTH_TRIES:-30}"     # 1秒おきに何回まで待つか
STATE_DIR="$APP_DIR/.deploy"
PREV_FILE="$STATE_DIR/previous-commit"
LOG_FILE="$STATE_DIR/deploy.log"

# ── 画面へ出す文 ────────────────────────────────────────
say()  { printf '\033[1m▸ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

trap 'die "途中で失敗しました（$BASH_COMMAND）。中身は入れ替えていません。"' ERR

# ── 使い方だけ見たいとき（どこで実行しても出せる） ──────
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# ── 使う道具がそろっているか ────────────────────────────
need() { command -v "$1" >/dev/null 2>&1 || die "$1 が見つかりません。"; }
need git
need curl
need docker
docker compose version >/dev/null 2>&1 || die "docker compose が使えません。"

[ -d "$APP_DIR/.git" ] || die "$APP_DIR が git の作業場所ではありません。"
cd "$APP_DIR"
mkdir -p "$STATE_DIR"

# ── 自分の身を守る ──────────────────────────────────────
# git を切り替えると、いま動いているこのファイル自身が書き換わったり消えたりする。
# bash は走りながら台本を読むので、そうなると途中でおかしくなる。
# 先に控えを作り、そちらへ移ってから本題に入る。
if [ "${CUTLOG_DEPLOY_DETACHED:-}" != "1" ]; then
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  COPY="$(mktemp "${TMPDIR:-/tmp}/cutlog-deploy.XXXXXX")"
  cp -f "$SELF" "$COPY"
  chmod +x "$COPY"
  # 控えは終わったら消す。exec するので、後始末は控え側で行う。
  CUTLOG_DEPLOY_DETACHED=1 CUTLOG_DEPLOY_COPY="$COPY" exec "$COPY" "$@"
fi
if [ -n "${CUTLOG_DEPLOY_COPY:-}" ]; then
  trap 'rm -f "$CUTLOG_DEPLOY_COPY"' EXIT
fi

compose() { docker compose "$@"; }

# 切り替えた先にこのスクリプトが無い版（deploy.sh を入れる前の古い版）もある。
# その場合は控えを置き直して、次も同じように更新できるようにする。
keep_self() {
  [ -n "${CUTLOG_DEPLOY_COPY:-}" ] || return 0
  [ -e "$APP_DIR/deploy.sh" ] && return 0
  cp -f "$CUTLOG_DEPLOY_COPY" "$APP_DIR/deploy.sh"
  chmod +x "$APP_DIR/deploy.sh"
  warn "この版には deploy.sh が無いので、いまの物を置いておきました"
}

short() { git rev-parse --short "$1" 2>/dev/null || echo '?'; }
subject() { git log -1 --format='%s' "$1" 2>/dev/null || echo '?'; }

# ── いまの状態を出す ────────────────────────────────────
show_status() {
  say "いまの状態"
  printf '  場所      %s\n' "$APP_DIR"
  printf '  コミット  %s  %s\n' "$(short HEAD)" "$(subject HEAD)"
  printf '  もどり先  %s\n' "$([ -f "$PREV_FILE" ] && cat "$PREV_FILE" || echo 'なし')"
  echo
  compose ps
  echo
  printf '  健康確認  '
  curl -fsS --max-time 5 "$HEALTH_URL" 2>/dev/null || printf '応答なし'
  echo
}

# ── 起動を待って、健康確認が通るまで見る ────────────────
wait_healthy() {
  local i
  for ((i = 1; i <= HEALTH_TRIES; i++)); do
    if curl -fsS --max-time 3 "$HEALTH_URL" >/dev/null 2>&1; then
      ok "健康確認が通りました（${i}秒）"
      return 0
    fi
    sleep 1
  done
  return 1
}

# ── 実際に作り直して入れ替える ──────────────────────────
build_and_up() {
  say "イメージを作る"
  compose build
  ok "できました"

  say "入れ替える"
  compose up -d --remove-orphans
  ok "起動しました"

  say "健康確認を待つ"
  wait_healthy
}

# ── 直前の版へ戻す ──────────────────────────────────────
rollback_to() {
  local target="$1"
  warn "直前の版（$(short "$target")）へ戻します"
  git -c advice.detachedHead=false checkout -q --force "$target"
  keep_self
  compose build >/dev/null 2>&1 || compose build
  compose up -d --remove-orphans
  if wait_healthy; then
    ok "戻しました。$(short HEAD)  $(subject HEAD)"
  else
    die "戻した先でも健康確認が通りません。docker compose logs を見てください。"
  fi
}

# ── 引数を読む ──────────────────────────────────────────
TARGET=""
case "${1:-}" in
  --status|-s)
    trap - ERR
    show_status
    exit 0
    ;;
  --rollback|-r)
    [ -f "$PREV_FILE" ] || die "戻り先の記録がありません。"
    PREV="$(cat "$PREV_FILE")"
    say "cutlog を1つ前へ戻す"
    trap - ERR
    rollback_to "$PREV"
    show_status
    exit 0
    ;;
  "") TARGET="" ;;
  -*) die "知らない指定です: $1（--help を見てください）" ;;
  *)  TARGET="$1" ;;
esac

say "cutlog を更新する"
printf '  いま      %s  %s\n' "$(short HEAD)" "$(subject HEAD)"

# ── 手で直した跡が残っていないか ────────────────────────
# .env は git の管理外なので、ここには出てこない。
if ! git diff --quiet || ! git diff --cached --quiet; then
  git status --short
  die "作業場所に手で直した跡があります。取り込むか、git checkout -- . で消してから実行してください。"
fi

# ── 取ってくる ──────────────────────────────────────────
say "gitから取ってくる"
git fetch --prune --tags "$REMOTE"
if [ -n "$TARGET" ]; then
  git rev-parse --verify -q "${TARGET}^{commit}" >/dev/null \
    || git rev-parse --verify -q "${REMOTE}/${TARGET}^{commit}" >/dev/null \
    || die "$TARGET が見つかりません。"
  NEW="$(git rev-parse --verify -q "${TARGET}^{commit}" || git rev-parse "${REMOTE}/${TARGET}^{commit}")"
else
  NEW="$(git rev-parse "${REMOTE}/${BRANCH}")"
fi
CUR="$(git rev-parse HEAD)"

if [ "$CUR" = "$NEW" ]; then
  ok "すでに最新です（$(short HEAD)）。作り直しはしません。"
  trap - ERR
  show_status
  exit 0
fi

printf '  これから  %s  %s\n' "$(short "$NEW")" "$(subject "$NEW")"
echo "  変わるところ:"
git log --oneline --no-decorate "$CUR..$NEW" 2>/dev/null | sed 's/^/    /' | head -20 || true

# 戻り先をここで控える（入れ替える前の状態）
echo "$CUR" > "$PREV_FILE"

say "作業場所を新しい版にする"
git -c advice.detachedHead=false checkout -q --force "$NEW"
keep_self
ok "$(short HEAD)  $(subject HEAD)"

# ここから先で失敗したら、自分で元へ戻す
trap 'warn "更新に失敗しました"; rollback_to "$CUR"; exit 1' ERR

build_and_up

trap - ERR
{
  printf '%s  %s -> %s  %s\n' "$(date -Iseconds)" "$(short "$CUR")" "$(short "$NEW")" "$(subject "$NEW")"
} >> "$LOG_FILE"

say "終わりました"
show_status
