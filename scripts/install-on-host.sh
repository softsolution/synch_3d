#!/usr/bin/env bash
# Установка sync-caps на один хост Armbian (запускать на принтере под пользователем pi).
set -euo pipefail

INSTALL_USER="${SYNC_INSTALL_USER:-pi}"
BIN_DIR="/home/${INSTALL_USER}/bin"
CONFIG_DIR="/home/${INSTALL_USER}/printer_data/config"
SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sync-caps.sh"
ENV_EXAMPLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/sync-caps.env.example"
SNIPPET_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/printer.sync-caps.snippet.cfg"

if [[ "$(id -un)" != "$INSTALL_USER" ]]; then
  echo "Запустите от пользователя ${INSTALL_USER}: sudo -u ${INSTALL_USER} $0"
  exit 1
fi

mkdir -p "$BIN_DIR" "$(dirname "/home/${INSTALL_USER}/printer_data/logs/sync-caps.log")"

install -m 755 "$SCRIPT_SRC" "${BIN_DIR}/sync-caps.sh"

if [[ ! -f "${CONFIG_DIR}/sync-caps.env" ]]; then
  install -m 600 "$ENV_EXAMPLE" "${CONFIG_DIR}/sync-caps.env"
  echo "Создан ${CONFIG_DIR}/sync-caps.env — отредактируйте MASTER_IP и пути."
else
  echo "Конфиг уже есть: ${CONFIG_DIR}/sync-caps.env (не перезаписан)"
fi

if [[ ! -f "${CONFIG_DIR}/sync-caps.cfg" ]]; then
  install -m 644 "$SNIPPET_SRC" "${CONFIG_DIR}/sync-caps.cfg"
  echo "Создан ${CONFIG_DIR}/sync-caps.cfg"
  if ! grep -q 'sync-caps.cfg' "${CONFIG_DIR}/printer.cfg" 2>/dev/null; then
    echo ""
    echo "Добавьте в printer.cfg КАЖДОГО принтера на этом хосте:"
    echo "  [include sync-caps.cfg]"
  fi
else
  echo "Файл ${CONFIG_DIR}/sync-caps.cfg уже существует"
fi

# SSH-ключ для pull с мастера (если ещё нет)
if [[ ! -f "${HOME}/.ssh/id_ed25519" && ! -f "${HOME}/.ssh/id_rsa" ]]; then
  echo "Генерация SSH-ключа…"
  ssh-keygen -t ed25519 -N "" -f "${HOME}/.ssh/id_ed25519"
  echo "Скопируйте ключ на мастер:"
  echo "  ssh-copy-id -i ${HOME}/.ssh/id_ed25519.pub ${INSTALL_USER}@<MASTER_IP>"
fi

echo ""
echo "Установка завершена. Дальше:"
echo "  1) nano ${CONFIG_DIR}/sync-caps.env"
echo "  2) [include sync-caps.cfg] в printer.cfg обоих принтеров"
echo "  3) ssh-copy-id на мастер (если slave)"
echo "  4) rsync -avn pi@MASTER_IP:gcodes/caps/ ${CONFIG_DIR%/config}/gcodes/caps/"
echo "  5) ${BIN_DIR}/sync-caps.sh"
