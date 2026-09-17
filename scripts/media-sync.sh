#!/usr/bin/env bash
#
# Seafile のライブラリを Jellyfin のメディアディレクトリに一方向コピーする。
# media-sync.service から実行される。
#
# なぜ同期 (コピー) なのか:
#   Seafile はライブラリの中身をブロック単位の content-addressed ストアに持っていて、
#   ディスク上に実ファイルとして存在しない。Jellyfin に見せるには実ファイルの
#   見た目を作る必要があり、やり方は FUSE マウント (seaf-fuse / rclone mount) か
#   コピーの二択になる。
#   このホストは毎晩 02:00 に restic-backup.service が全コンテナを stop/start する。
#   seafile コンテナに依存する FUSE マウントは、そのたびに壊れて再マウントが要る。
#   コピーならその問題が起きないので、ディスクを二重に食う代わりにこちらを選んだ。
#
# rclone はホストに入れず、公式イメージを都度 docker run で使い捨てる。
# --network host にしているのは、Seafile の API がダウンロード URL を SERVICE_URL
# (= .env の SEAFILE_SERVER_HOSTNAME、Tailscale 名) で組み立てて返すため。
# コンテナ内の独自ネットワークからだとその名前を引けず、リンクを辿れない。
#
set -euo pipefail

CONFIG_FILE="${MEDIA_SYNC_CONFIG:-/selfhost/scripts/media-sync.env}"
[[ -r "$CONFIG_FILE" ]] || { printf '[media-sync] ERROR: 設定ファイルを読めない: %s\n' "$CONFIG_FILE" >&2; exit 1; }
# shellcheck source=/dev/null
source "$CONFIG_FILE"

DOCKER_BIN="${DOCKER_BIN:-/usr/bin/docker}"
RCLONE_IMAGE="${RCLONE_IMAGE:-rclone/rclone:1.68}"
SEAFILE_CONTAINER="${SEAFILE_CONTAINER:-seafile}"
# 同期先。外付けディスクに逃がすときはここだけ差し替える (systemd から見えるパスにすること)。
DEST="${DEST:-/selfhost/compose/jellyfin/media/seafile}"
# 同期先を書く uid:gid。Jellyfin が user: "1000:1000" で動くのに合わせる。
RUN_AS="${RUN_AS:-1000:1000}"
# 1 回の同期で消してよいファイル数の上限。設定ミスやライブラリの取り違えで
# 同期先を丸ごと消してしまうのを防ぐ安全弁。正当な大量削除ならここで一度失敗する。
MAX_DELETE="${MAX_DELETE:-25}"

log() { printf '[media-sync] %s\n' "$*"; }
die() { printf '[media-sync] ERROR: %s\n' "$*" >&2; exit 1; }

for v in SEAFILE_URL SEAFILE_USER SEAFILE_PASS SEAFILE_LIBRARY; do
  [[ -n "${!v:-}" ]] || die "$CONFIG_FILE に $v が設定されていない"
done
[[ -x "$DOCKER_BIN" ]] || die "docker が見つからない: $DOCKER_BIN"

# 02:00 のバックアップ中は seafile が止まっている。そこに当たったら黙って見送る。
# 次回のタイマーで拾えるので、エラーにして journal を汚す意味がない。
running="$("$DOCKER_BIN" inspect -f '{{.State.Running}}' "$SEAFILE_CONTAINER" 2>/dev/null || echo false)"
if [[ "$running" != true ]]; then
  log "seafile が停止中。今回は見送る (バックアップ中の可能性)"
  exit 0
fi

[[ -d "$DEST" ]] || die "同期先がない: $DEST (先に mkdir すること)"

log "同期中: ${SEAFILE_LIBRARY} -> ${DEST}"

# rclone の remote は設定ファイルではなく環境変数で組み立てる (RCLONE_CONFIG_<名前>_<項目>)。
# パスワードを平文で置いたファイルを増やさずに済む。--config /dev/null で
# 設定ファイルを一切読ませない。
#
# --exclude /.gitkeep は必須。sync は「同期元にないものを消す」ので、これがないと
# 同期先ディレクトリを git に残すための .gitkeep が毎回消される。
#
# shellcheck disable=SC2086  # RCLONE_EXTRA_ARGS は複数の引数に分割させたい
"$DOCKER_BIN" run --rm \
  --network host \
  --user "$RUN_AS" \
  -e RCLONE_CONFIG_SEAFILE_TYPE=seafile \
  -e RCLONE_CONFIG_SEAFILE_URL="$SEAFILE_URL" \
  -e RCLONE_CONFIG_SEAFILE_USER="$SEAFILE_USER" \
  -e RCLONE_CONFIG_SEAFILE_PASS="$SEAFILE_PASS" \
  -e RCLONE_CONFIG_SEAFILE_LIBRARY="$SEAFILE_LIBRARY" \
  -e RCLONE_CONFIG_SEAFILE_LIBRARY_KEY="${SEAFILE_LIBRARY_KEY:-}" \
  -e RCLONE_CONFIG_SEAFILE_2FA="${SEAFILE_2FA:-false}" \
  -v "$DEST:/dest" \
  "$RCLONE_IMAGE" \
  sync "SEAFILE:" /dest \
  --config /dev/null \
  --max-delete "$MAX_DELETE" \
  --exclude /.gitkeep \
  --stats-one-line \
  --stats 1m \
  ${RCLONE_EXTRA_ARGS:-}

log "完了"
