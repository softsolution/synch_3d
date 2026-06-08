#!/usr/bin/env bash
# Установка sync-caps на один хост Armbian.
# Запускать под пользователем Klipper (pi, klipper, …).
#
# Пути к printer_data на хостах различаются — задайте при установке, например:
#   SYNC_INSTALL_USER=klipper \
#   SYNC_CONFIG_DIR=/home/klipper/fbg51_data/config \
#   SYNC_CONFIG_DIRS="/home/klipper/fbg51_data/config /home/klipper/fbg52_data/config" \
#   ./install-on-host.sh
set -euo pipefail

INSTALL_USER="${SYNC_INSTALL_USER:-pi}"
BIN_DIR="${SYNC_BIN_DIR:-${HOME}/bin}"
CONFIG_DIR="${SYNC_CONFIG_DIR:-${HOME}/printer_data/config}"
DATA_ROOT="$(dirname "$CONFIG_DIR")"
LOG_DIR="${DATA_ROOT}/logs"

if [[ -n "${SYNC_CONFIG_DIRS:-}" ]]; then
  read -ra ALL_CONFIG_DIRS <<< "$SYNC_CONFIG_DIRS"
  if [[ -z "${SYNC_CONFIG_DIR:-}" ]]; then
    CONFIG_DIR="${ALL_CONFIG_DIRS[0]}"
    DATA_ROOT="$(dirname "$CONFIG_DIR")"
    LOG_DIR="${DATA_ROOT}/logs"
  fi
else
  ALL_CONFIG_DIRS=("$CONFIG_DIR")
fi

SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sync-caps.sh"
ENV_EXAMPLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/sync-caps.env.example"
SNIPPET_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/printer.sync-caps.snippet.cfg"
SHELL_CMD="SYNC_CAPS_CONFIG=${CONFIG_DIR}/sync-caps.env ${BIN_DIR}/sync-caps.sh"

if [[ "$(id -un)" != "$INSTALL_USER" ]]; then
  echo "Запустите от пользователя ${INSTALL_USER}: sudo -E -u ${INSTALL_USER} $0"
  exit 1
fi

mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$LOG_DIR"

install -m 755 "$SCRIPT_SRC" "${BIN_DIR}/sync-caps.sh"

if [[ ! -f "${CONFIG_DIR}/sync-caps.env" ]]; then
  sed -e "s|/home/pi/printer_data|${DATA_ROOT}|g" \
      -e "s|MASTER_USER=pi|MASTER_USER=${INSTALL_USER}|g" \
      "$ENV_EXAMPLE" > "${CONFIG_DIR}/sync-caps.env"
  chmod 600 "${CONFIG_DIR}/sync-caps.env"
  echo "Создан ${CONFIG_DIR}/sync-caps.env — отредактируйте MASTER_IP и пути."
else
  echo "Конфиг уже есть: ${CONFIG_DIR}/sync-caps.env (не перезаписан)"
fi

for cfg_dir in "${ALL_CONFIG_DIRS[@]}"; do
  mkdir -p "$cfg_dir"
  if [[ ! -f "${cfg_dir}/sync-caps.cfg" ]]; then
    sed "s|command: /home/pi/bin/sync-caps.sh|command: ${SHELL_CMD}|" \
      "$SNIPPET_SRC" > "${cfg_dir}/sync-caps.cfg"
    chmod 644 "${cfg_dir}/sync-caps.cfg"
    echo "Создан ${cfg_dir}/sync-caps.cfg"
    if ! grep -q 'sync-caps.cfg' "${cfg_dir}/printer.cfg" 2>/dev/null; then
      echo ""
      echo "Добавьте в ${cfg_dir}/printer.cfg:"
      echo "  [include sync-caps.cfg]"
    fi
  else
    echo "Файл ${cfg_dir}/sync-caps.cfg уже существует"
  fi
done

# SSH-ключ для pull с мастера (если ещё нет)
if [[ ! -f "${HOME}/.ssh/id_ed25519" && ! -f "${HOME}/.ssh/id_rsa" ]]; then
  echo "Генерация SSH-ключа…"
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  ssh-keygen -t ed25519 -N "" -f "${HOME}/.ssh/id_ed25519"
  echo "Скопируйте ключ на мастер:"
  echo "  ssh-copy-id -i ${HOME}/.ssh/id_ed25519.pub ${INSTALL_USER}@<MASTER_IP>"
fi

echo ""
echo "Установка завершена. Дальше:"
echo "  1) nano ${CONFIG_DIR}/sync-caps.env"
echo "  2) [include sync-caps.cfg] в printer.cfg каждого принтера (если ещё нет)"
echo "  3) ssh-copy-id на мастер (если slave)"
echo "  4) rsync -avn ${INSTALL_USER}@MASTER_IP:gcodes/caps/ ${DATA_ROOT}/gcodes/caps/"
echo "  5) ${BIN_DIR}/sync-caps.sh"
