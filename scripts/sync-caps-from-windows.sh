#!/usr/bin/env bash
# Push caps с Windows-ПК на головной хост (gcodes/caps) + metascan на мастере.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG="${SYNC_CAPS_FROM_WINDOWS_CONFIG:-${REPO_ROOT}/config/sync-caps-from-windows.env}"

if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: не найден конфиг: $CONFIG" >&2
  echo "Скопируйте config/sync-caps-from-windows.env.example → config/sync-caps-from-windows.env" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG"

: "${MASTER_IP:?Задайте MASTER_IP в $CONFIG}"
: "${MASTER_USER:?Задайте MASTER_USER в $CONFIG}"
: "${MASTER_CAPS_PATH:=gcodes/caps}"
: "${LOCAL_CAPS_PATH:?Задайте LOCAL_CAPS_PATH в $CONFIG}"
: "${RSYNC_DELETE:=1}"
: "${RSYNC_CHECKSUM:=0}"
: "${RSYNC_TIMEOUT:=600}"
: "${REMOTE_METASCAN:=1}"
: "${MASTER_SYNC_SCRIPT:=/home/${MASTER_USER}/bin/sync-caps.sh}"
: "${MASTER_SYNC_CONFIG:=/home/${MASTER_USER}/printer_data/config/sync-caps.env}"
: "${FORCE_MASTER_METASCAN:=1}"
: "${LOG_FILE:=${REPO_ROOT}/logs/sync-caps-from-windows.log}"
# auto = rsync если есть, иначе scp (OpenSSH в Git Bash / Windows)
: "${SYNC_BACKEND:=auto}"

REMOTE="${MASTER_USER}@${MASTER_IP}:${MASTER_CAPS_PATH%/}/"
RSYNC_OPTS=(-a --human-readable --timeout="${RSYNC_TIMEOUT}" --partial)
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=30)
SSH_CMD=(ssh "${SSH_OPTS[@]}")
SCP_CMD=(scp "${SSH_OPTS[@]}")

mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

die() {
  log "ERROR: $*"
  exit 1
}

normalize_local_path() {
  local p="$1"
  if command -v cygpath &>/dev/null; then
    cygpath -u "$p"
  else
    printf '%s' "$p"
  fi
}

setup_ssh() {
  if [[ -n "${SSH_IDENTITY_FILE:-}" ]]; then
    [[ -f "$SSH_IDENTITY_FILE" ]] || die "SSH-ключ не найден: $SSH_IDENTITY_FILE"
    SSH_CMD+=(-i "$SSH_IDENTITY_FILE")
    SCP_CMD+=(-i "$SSH_IDENTITY_FILE")
  fi
  RSYNC_RSH="${SSH_CMD[*]}"
  export RSYNC_RSH
}

find_rsync() {
  local candidate
  if [[ -n "${RSYNC_BIN:-}" && -x "$RSYNC_BIN" ]]; then
    printf '%s' "$RSYNC_BIN"
    return 0
  fi
  if command -v rsync &>/dev/null; then
    command -v rsync
    return 0
  fi
  for candidate in \
    "/c/Program Files/cwRsync/bin/rsync.exe" \
    "/c/Program Files (x86)/cwRsync/bin/rsync.exe" \
    "/c/tools/rsync/rsync.exe"; do
    if [[ -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

resolve_sync_backend() {
  local rsync_bin=""
  case "${SYNC_BACKEND}" in
    scp) printf '%s' "scp"; return 0 ;;
    rsync)
      rsync_bin="$(find_rsync)" || die "SYNC_BACKEND=rsync, но rsync не найден (см. docs/WINDOWS.md)"
      printf '%s' "rsync"
      return 0
      ;;
    auto)
      if rsync_bin="$(find_rsync)"; then
        printf '%s' "rsync"
      else
        printf '%s' "scp"
      fi
      return 0
      ;;
    *)
      die "Неизвестный SYNC_BACKEND=${SYNC_BACKEND} (допустимо: auto, rsync, scp)"
      ;;
  esac
}

run_rsync_push() {
  local local_caps rsync_bin
  local_caps="$(normalize_local_path "$LOCAL_CAPS_PATH")"
  rsync_bin="$(find_rsync)" || die "rsync не найден"

  [[ "${RSYNC_DELETE}" == "1" ]] && RSYNC_OPTS+=(--delete)
  [[ "${RSYNC_CHECKSUM}" == "1" ]] && RSYNC_OPTS+=(--checksum)

  log "rsync ${local_caps}/ -> ${REMOTE}"
  if ! "$rsync_bin" "${RSYNC_OPTS[@]}" "${local_caps}/" "$REMOTE" 2>&1 | tee -a "$LOG_FILE"; then
    die "rsync завершился с ошибкой"
  fi
}

run_scp_push() {
  local local_caps
  local_caps="$(normalize_local_path "$LOCAL_CAPS_PATH")"

  if [[ "${RSYNC_DELETE}" == "1" ]]; then
    log "WARN: scp не удаляет лишние файлы на мастере (RSYNC_DELETE игнорируется). Для зеркала установите rsync."
  fi
  if [[ "${RSYNC_CHECKSUM}" == "1" ]]; then
    log "WARN: RSYNC_CHECKSUM не поддерживается в режиме scp"
  fi

  log "scp ${local_caps}/ -> ${REMOTE} (rsync не найден, используется OpenSSH scp)"
  if ! "${SSH_CMD[@]}" "${MASTER_USER}@${MASTER_IP}" "mkdir -p ${MASTER_CAPS_PATH}" 2>&1 | tee -a "$LOG_FILE"; then
    die "не удалось создать каталог на мастере: ${MASTER_CAPS_PATH}"
  fi
  if ! "${SCP_CMD[@]}" -r "${local_caps}/." "${REMOTE}" 2>&1 | tee -a "$LOG_FILE"; then
    die "scp завершился с ошибкой"
  fi
}

run_push() {
  local local_caps backend
  local_caps="$(normalize_local_path "$LOCAL_CAPS_PATH")"
  [[ -d "$local_caps" ]] || die "Локальная папка caps не найдена: $LOCAL_CAPS_PATH"

  backend="$(resolve_sync_backend)"
  case "$backend" in
    rsync) run_rsync_push ;;
    scp) run_scp_push ;;
    *) die "Внутренняя ошибка: неизвестный backend ${backend}" ;;
  esac
}

run_remote_metascan() {
  [[ "${REMOTE_METASCAN}" == "1" ]] || return 0

  local remote_cmd="SYNC_CAPS_CONFIG=${MASTER_SYNC_CONFIG}"
  if [[ "${FORCE_MASTER_METASCAN}" == "1" ]]; then
    remote_cmd+=" FORCE_MASTER_MODE=1"
  fi
  remote_cmd+=" ${MASTER_SYNC_SCRIPT}"

  log "metascan на мастере (${MASTER_IP})…"
  if ! "${SSH_CMD[@]}" "${MASTER_USER}@${MASTER_IP}" "$remote_cmd" 2>&1 | tee -a "$LOG_FILE"; then
    die "metascan на мастере не удался (проверьте ${MASTER_SYNC_SCRIPT} и SSH)"
  fi
}

main() {
  log "=== sync-caps-from-windows start (pid $$) ==="
  setup_ssh
  run_push
  run_remote_metascan
  log "=== sync-caps-from-windows done ==="
}

main "$@"
