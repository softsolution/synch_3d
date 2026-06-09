#!/usr/bin/env bash
# Синхронизация ~/gcodes/caps с головного хоста (pull через rsync).
# После копирования — metascan на всех экземплярах Moonraker на этом хосте.
# SYNC_CAPS_SCRIPT_REV — меняется при правках; смотрите в логе после деплоя.
SYNC_CAPS_SCRIPT_REV="2025-06-09-grep-itemize"
set -euo pipefail

CONFIG="${SYNC_CAPS_CONFIG:-$HOME/printer_fbg58_data/config/sync-caps.env}"
if [[ -f "$CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG"
fi

: "${MASTER_IP:?Задайте MASTER_IP в $CONFIG}"
: "${MASTER_USER:=pi}"
: "${MASTER_CAPS_PATH:=gcodes/caps}"
: "${GCODES_ROOT:=$HOME/printer_fbg58_data/gcodes}"
: "${SYNC_SUBDIR:=caps}"
: "${MOONRAKER_HOST:=127.0.0.1}"
: "${MOONRAKER_PORTS:=7125}"
: "${BLOCK_WHILE_PRINTING:=1}"
: "${RSYNC_DELETE:=1}"
: "${RSYNC_CHECKSUM:=0}"
: "${RSYNC_TIMEOUT:=600}"
: "${FORCE_MASTER_MODE:=0}"
: "${LOG_FILE:=$HOME/printer_fbg58data/logs/sync-caps.log}"

LOCAL_CAPS="${GCODES_ROOT%/}/${SYNC_SUBDIR}"
REMOTE="${MASTER_USER}@${MASTER_IP}:${MASTER_CAPS_PATH%/}/"
RSYNC_OPTS=(-a --human-readable --timeout="${RSYNC_TIMEOUT}" --partial)

mkdir -p "$(dirname "$LOG_FILE")" "${LOCAL_CAPS}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

die() {
  log "ERROR: $*"
  exit 1
}

local_ip_matches_master() {
  if [[ "${FORCE_MASTER_MODE}" == "1" ]]; then
    return 0
  fi
  ip -4 addr show 2>/dev/null | awk '{print $2}' | tr -d 'addr:' | grep -qx "${MASTER_IP}" 2>/dev/null
}

moonraker_curl() {
  local port="$1"
  shift
  # JSON-RPC over HTTP: POST /server/jsonrpc (POST на / даёт 405 в Moonraker ≥0.10)
  curl -sfS --max-time 30 "$@" "http://${MOONRAKER_HOST}:${port}/server/jsonrpc"
}

is_printing_on_port() {
  local port="$1"
  local json state
  json="$(moonraker_curl "$port" \
    -d '{"jsonrpc":"2.0","method":"printer.objects.query","params":{"objects":{"print_stats":null}},"id":1}' \
    2>/dev/null)" || return 1
  state="$(printf '%s' "$json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d['result']['status']['print_stats']['state'])
except Exception:
    sys.exit(1)
" 2>/dev/null)" || return 1
  [[ "$state" == "printing" || "$state" == "paused" ]]
}

assert_not_printing() {
  [[ "${BLOCK_WHILE_PRINTING}" != "1" ]] && return 0
  local port
  for port in ${MOONRAKER_PORTS}; do
    if is_printing_on_port "$port"; then
      die "Печать активна (Moonraker :${port}). Синхронизацию отменено."
    fi
  done
}

metascan_file() {
  local port="$1"
  local rel="$2"
  moonraker_curl "$port" \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"server.files.metascan\",\"params\":{\"filename\":\"${rel}\"},\"id\":2}" \
    >/dev/null 2>&1 || log "WARN: metascan не удался :${port} ${rel}"
}

metascan_all_caps() {
  local port rel
  if [[ ! -d "$LOCAL_CAPS" ]]; then
    return 0
  fi
  while IFS= read -r -d '' f; do
    rel="${SYNC_SUBDIR}/${f#"${LOCAL_CAPS}/"}"
    for port in ${MOONRAKER_PORTS}; do
      metascan_file "$port" "$rel"
    done
  done < <(find "$LOCAL_CAPS" -type f \( -iname '*.gcode' -o -iname '*.g' -o -iname '*.nc' \) -print0 2>/dev/null)
}

metascan_changed_only() {
  local port rel
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    for port in ${MOONRAKER_PORTS}; do
      metascan_file "$port" "$rel"
    done
  done <<< "$1"
}

run_rsync() {
  [[ "${RSYNC_DELETE}" == "1" ]] && RSYNC_OPTS+=(--delete)
  [[ "${RSYNC_CHECKSUM}" == "1" ]] && RSYNC_OPTS+=(--checksum)

  local itemize_log
  itemize_log="$(mktemp)"
  # Путь подставляем при установке trap: при RETURN local уже снят, set -u даёт unbound
  trap "rm -f '${itemize_log}'" RETURN

  log "rsync ${REMOTE} -> ${LOCAL_CAPS}/"
  if ! rsync "${RSYNC_OPTS[@]}" --itemize-changes \
    "$REMOTE" "${LOCAL_CAPS}/" 2>&1 | tee -a "$LOG_FILE" | tee "$itemize_log"; then
    die "rsync завершился с ошибкой"
  fi

  # Строки с передачей файла: >f, *f, … (man rsync --itemize-changes).
  # grep, не [[ =~ ]]: bash в Klipper/старых сборках ломается на «>» в regex.
  local changed_rels=""
  while IFS= read -r line; do
    local name="${line##* }"
    [[ -z "$name" || "$name" == "./" ]] && continue
    if [[ -f "${LOCAL_CAPS}/${name}" ]]; then
      changed_rels+="${SYNC_SUBDIR}/${name}"$'\n'
    fi
  done < <(grep -E '^[>*hc.][fdLCS.]' "$itemize_log" 2>/dev/null || true)

  if [[ -n "$changed_rels" ]]; then
    log "metascan для изменённых файлов…"
    metascan_changed_only "$changed_rels"
  else
    log "metascan: изменённых gcode не обнаружено, полный проход по caps/"
    metascan_all_caps
  fi
}

main() {
  log "=== sync-caps start (pid $$, rev ${SYNC_CAPS_SCRIPT_REV}) ==="

  if local_ip_matches_master; then
    log "Этот хост — мастер (${MASTER_IP}). Rsync пропущен, обновляем метаданные Moonraker."
    metascan_all_caps
    log "=== sync-caps done (master mode) ==="
    exit 0
  fi

  assert_not_printing
  mkdir -p "${LOCAL_CAPS}"
  run_rsync
  log "=== sync-caps done ==="
}

main "$@"
