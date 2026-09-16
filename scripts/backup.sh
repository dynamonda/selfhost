#!/usr/bin/env bash
#
# selfhost のバックアップ。restic-backup.service から root で実行される。
#
# compose/<サービス>/backup.conf を置いたサービスが対象になる。
# このスクリプトにサービス名は書かない。追加するときは backup.conf を作るだけ。
#
set -euo pipefail
shopt -s nullglob

# --- 設定ファイルの読み込み ------------------------------------------------
# 秘密情報やホスト固有の設定はリポジトリに入れず、この設定ファイルに書く。
CONFIG_FILE="${RESTIC_BACKUP_CONFIG:-/selfhost/scripts/backup.env}"
if [[ -r "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

# --- 既定値 ----------------------------------------------------------------
SELFHOST_ROOT="${SELFHOST_ROOT:-/selfhost}"
COMPOSE_ROOT="${COMPOSE_ROOT:-$SELFHOST_ROOT/compose}"
RESTIC_BIN="${RESTIC_BIN:-/usr/bin/restic}"
DOCKER_BIN="${DOCKER_BIN:-/usr/bin/docker}"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-$SELFHOST_ROOT/backup/resticrepo}"
RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-/var/lib/restic/repository-password}"

export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE

# compose 配下以外にバックアップしたいパス（タグ: selfhost）。
# 配列でも空白区切りの文字列でも指定できる。
if [[ -z "${EXTRA_PATHS+x}" ]]; then
  EXTRA_PATHS=("$SELFHOST_ROOT/data")
elif [[ "$(declare -p EXTRA_PATHS)" != "declare -a"* ]]; then
  read -r -a EXTRA_PATHS <<<"$EXTRA_PATHS"
fi

log()     { printf '[backup] %s\n' "$*"; }
log_svc() { printf '[backup:%s] %s\n' "$1" "${*:2}"; }
die()     { printf '[backup] ERROR: %s\n' "$*" >&2; exit 1; }

# --- restic 実行 -----------------------------------------------------------
# 引数: <タグ> <パス...> -- <除外パターン...>
# restic の終了コード 3（読めなかったファイルがある）を成功扱いしないのが要点。
# ここを握りつぶすと「成功したのに中身が欠けている」バックアップができる。
run_restic() {
  local tag="$1"; shift
  local paths=() excludes=() arg
  local seen_sep=0
  for arg in "$@"; do
    if [[ "$arg" == "--" ]]; then seen_sep=1; continue; fi
    if (( seen_sep )); then excludes+=(--exclude "$arg"); else paths+=("$arg"); fi
  done

  local rc=0
  "$RESTIC_BIN" backup \
    "${paths[@]}" \
    --tag "$tag" \
    --exclude-caches \
    ${excludes[@]+"${excludes[@]}"} || rc=$?

  case "$rc" in
    0) return 0 ;;
    3) log_svc "$tag" "ERROR: 読めなかったファイルがある (restic exit 3)。バックアップは不完全" >&2
       return 1 ;;
    *) log_svc "$tag" "ERROR: restic が失敗した (exit $rc)" >&2
       return 1 ;;
  esac
}

# --- サービス1件のバックアップ ---------------------------------------------
# 関数本体を () にしてサブシェルで動かす。backup.conf で定義された変数や関数が
# 次のサービスに漏れず、EXIT トラップもこの関数の終わりで確実に発火する。
# サブシェル内なので exit してもスクリプト全体は止まらない。
backup_service() (
  local svc_dir="$1" name="$2"
  cd "$svc_dir"

  # backup.conf で上書きされる既定値
  local BACKUP_ENABLED=1
  local QUIESCE=stop
  local BACKUP_PATHS=(./data)
  local BACKUP_EXCLUDE=()
  pre_backup()  { :; }
  post_backup() { :; }

  # shellcheck source=/dev/null
  source ./backup.conf

  if [[ "$BACKUP_ENABLED" != 1 ]]; then
    log_svc "$name" "スキップ (BACKUP_ENABLED=0)"
    exit 0
  fi

  case "$QUIESCE" in
    none)
      pre_backup()  { :; }
      post_backup() { :; }
      ;;
    stop)
      # 元から停止していたサービスを勝手に起動しないよう、状態を見てから止める
      pre_backup() {
        if [[ -z "$("$DOCKER_BIN" compose ps --status=running --quiet)" ]]; then
          log_svc "$name" "既に停止している。停止・再開をスキップ"
          _skip_start=1
          return 0
        fi
        log_svc "$name" "停止中..."
        "$DOCKER_BIN" compose stop
      }
      post_backup() {
        [[ -n "${_skip_start:-}" ]] && return 0
        log_svc "$name" "再開中..."
        "$DOCKER_BIN" compose start
      }
      ;;
    custom)
      # backup.conf が pre_backup / post_backup を定義している前提
      ;;
    *)
      log_svc "$name" "ERROR: QUIESCE の値が不正: $QUIESCE" >&2
      exit 1
      ;;
  esac

  # 復帰は必ずトラップで行う。バックアップが失敗しても、途中で kill されても、
  # サービスを止めっぱなしにしない。pre_backup より前に仕掛けるのは、停止が
  # 中途半端に失敗した場合も再開を通すため。
  # EXIT だけでなく INT/TERM/HUP も捕まえるのは、systemd の TimeoutSec 超過や
  # systemctl stop で殺されたときにも確実に再開させるため。
  _cleanup() {
    local rc=$?
    trap - EXIT INT TERM HUP
    if ! post_backup; then
      log_svc "$name" "ERROR: 復帰処理に失敗した。手動で確認すること" >&2
      rc=1
    fi
    exit "$rc"
  }
  trap _cleanup EXIT INT TERM HUP

  if ! pre_backup; then
    log_svc "$name" "ERROR: 停止処理に失敗した。バックアップを中止" >&2
    exit 1
  fi

  log_svc "$name" "バックアップ中: ${BACKUP_PATHS[*]}"
  run_restic "$name" "${BACKUP_PATHS[@]}" -- ${BACKUP_EXCLUDE[@]+"${BACKUP_EXCLUDE[@]}"} || exit 1

  exit 0
)

# --- 事前チェック ----------------------------------------------------------
[[ -x "$RESTIC_BIN" ]] || die "restic が見つからない: $RESTIC_BIN"
[[ -r "$RESTIC_PASSWORD_FILE" ]] || die "パスワードファイルを読めない: $RESTIC_PASSWORD_FILE"
"$RESTIC_BIN" cat config >/dev/null 2>&1 \
  || die "restic リポジトリを開けない: $RESTIC_REPOSITORY (未初期化なら restic init)"

# --- 実行 ------------------------------------------------------------------
declare -a ok=() failed=()

for conf in "$COMPOSE_ROOT"/*/backup.conf; do
  svc_dir="$(dirname "$conf")"
  name="$(basename "$svc_dir")"
  if [[ ! -x "$DOCKER_BIN" ]]; then
    die "docker が見つからない: $DOCKER_BIN"
  fi
  if backup_service "$svc_dir" "$name"; then
    ok+=("$name")
  else
    failed+=("$name")
  fi
done

if (( ${#EXTRA_PATHS[@]} > 0 )); then
  existing=()
  for path in "${EXTRA_PATHS[@]}"; do
    if [[ -e "$path" ]]; then existing+=("$path"); else log "WARN: 対象が存在しない: $path"; fi
  done
  if (( ${#existing[@]} > 0 )); then
    log "バックアップ中 (selfhost): ${existing[*]}"
    if run_restic selfhost "${existing[@]}"; then ok+=(selfhost); else failed+=(selfhost); fi
  fi
fi

log "完了: 成功 ${#ok[@]} 件 [${ok[*]-}] / 失敗 ${#failed[@]} 件 [${failed[*]-}]"
(( ${#failed[@]} == 0 )) || exit 1
