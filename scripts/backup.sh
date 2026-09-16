#!/usr/bin/env bash
#
# restic によるバックアップ。restic-backup.service から実行される。
# 設定は環境変数、または設定ファイル（既定: /selfhost/scripts/backup.env）で上書きできる。
#
set -euo pipefail

# --- 設定ファイルの読み込み ------------------------------------------------
# 秘密情報やホスト固有の設定はリポジトリに入れず、この設定ファイルに書く。
# 存在しなければ既定値のまま動く。
CONFIG_FILE="${RESTIC_BACKUP_CONFIG:-/selfhost/scripts/backup.env}"
if [[ -r "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

# --- 既定値 ----------------------------------------------------------------
RESTIC_BIN="${RESTIC_BIN:-/usr/bin/restic}"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/selfhost/backup/resticrepo}"
RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-/var/lib/restic/repository-password}"
BACKUP_TAG="${BACKUP_TAG:-systemd}"
# 存在すれば restic に --exclude-file として渡す
BACKUP_EXCLUDE_FILE="${BACKUP_EXCLUDE_FILE:-/selfhost/scripts/backup.exclude}"

export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE

# バックアップ対象。配列でも空白区切りの文字列でも指定できる
# （systemd の Environment= からは文字列でしか渡せないため）。
if [[ -z "${BACKUP_PATHS+x}" ]]; then
  BACKUP_PATHS=(/selfhost/data)
elif [[ "$(declare -p BACKUP_PATHS)" != "declare -a"* ]]; then
  read -r -a BACKUP_PATHS <<<"$BACKUP_PATHS"
fi

# restic backup に追加で渡すオプション。同じく配列／文字列のどちらでもよい。
if [[ -z "${BACKUP_OPTS+x}" ]]; then
  BACKUP_OPTS=(--exclude-caches)
elif [[ "$(declare -p BACKUP_OPTS)" != "declare -a"* ]]; then
  read -r -a BACKUP_OPTS <<<"$BACKUP_OPTS"
fi

# --- 事前チェック ----------------------------------------------------------
log() { printf '%s %s\n' "[backup.sh]" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

[[ -x "$RESTIC_BIN" ]] || die "restic が見つからない: $RESTIC_BIN"
[[ -r "$RESTIC_PASSWORD_FILE" ]] || die "パスワードファイルを読めない: $RESTIC_PASSWORD_FILE"
[[ ${#BACKUP_PATHS[@]} -gt 0 ]] || die "BACKUP_PATHS が空"

for path in "${BACKUP_PATHS[@]}"; do
  [[ -e "$path" ]] || die "バックアップ対象が存在しない: $path"
done

# リポジトリが未初期化のまま走ると分かりにくいエラーになるので先に確かめる。
if ! "$RESTIC_BIN" cat config >/dev/null 2>&1; then
  die "restic リポジトリを開けない: $RESTIC_REPOSITORY (未初期化なら restic init)"
fi

if [[ -r "$BACKUP_EXCLUDE_FILE" ]]; then
  BACKUP_OPTS+=(--exclude-file "$BACKUP_EXCLUDE_FILE")
fi

# --- 実行 ------------------------------------------------------------------
log "repo=$RESTIC_REPOSITORY tag=$BACKUP_TAG paths=${BACKUP_PATHS[*]}"

"$RESTIC_BIN" backup \
  "${BACKUP_PATHS[@]}" \
  --tag "$BACKUP_TAG" \
  "${BACKUP_OPTS[@]}"

log "バックアップ完了"
