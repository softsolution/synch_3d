# Установка синхронизации caps (8 хостов Klipper)

## Архитектура

- **1 головной хост** — вы сами кладёте файлы в `~/gcodes/caps/` (или общий gcodes с симлинком, как на остальных).
- **7 остальных хостов** — по кнопке `SYNC_CAPS` делают `rsync` **с мастера** в локальный `.../gcodes/caps/`.
- **Полное зеркало:** новые и изменённые файлы (в т.ч. другой размер с тем же именем) перезаписываются; лишнее в `caps/` на slave удаляется (`RSYNC_DELETE=1`).
- **Два Moonraker на хост** — после sync выполняется `metascan` на портах `7125` и `7126` (превью и exclude objects для обоих UI).
- **Во время печати** sync блокируется (настраивается).

---

## Требования

- Armbian 25.8.1, Klipper + Moonraker + Mainsail
- На всех хостах: общий `gcodes` для двух принтеров (симлинк), путь в `sync-caps.env` → `GCODES_ROOT`
- На мастере: каталог `gcodes/caps/` с вашими `.gcode`
- `rsync`, `curl`, `openssh-client`, `python3` (есть в Armbian)
- Расширение Klipper **`gcode_shell_command`** (обычно уже есть в `printer.cfg` / KIAUH)

---

## Шаг 0. Справочник IP (8 хостов)

Отредактируйте `config/hosts.env.example` под вашу сеть. Пример:

| Хост | IP (пример) | Роль |
|------|-------------|------|
| master | 192.168.1.10 | головной + печать |
| host-02 … host-08 | .11 – .17 | slaves |

На **каждом** хосте в `sync-caps.env` один и тот же `MASTER_IP` (IP головного).

---

## Шаг 1. Подготовка головного хоста

```bash
# На мастере (пользователь pi)
mkdir -p ~/gcodes/caps
# Проверьте, что printer_1_data/gcodes и printer_2_data/gcodes — симлинки на ~/gcodes или ~/printer_data/gcodes
ls -la ~/printer_data/gcodes
```

Заливайте gcode только в `caps/` (вручную, WinSCP, SMB — как удобно).

---

## Шаг 2. Копирование файлов с Windows

Из PowerShell (путь к этой папке на ПК):

```powershell
$SRC = "C:\OSPanel\home\sync"
$HOSTS = @(
  "192.168.1.10",  # master
  "192.168.1.11", "192.168.1.12", "192.168.1.13",
  "192.168.1.14", "192.168.1.15", "192.168.1.16", "192.168.1.17"
)
foreach ($ip in $HOSTS) {
  scp -r "$SRC\scripts" "${ip}:/home/pi/sync-install/"
  scp -r "$SRC\config"  "${ip}:/home/pi/sync-install/"
}
```

Или один раз на мастер, дальше `scp` по внутренней сети между Pi.

---

## Шаг 3. Установка на каждом из 8 хостов

SSH на хост:

```bash
cd ~/sync-install/scripts
chmod +x install-on-host.sh sync-caps.sh
```

Стандартный путь `~/printer_data/config`:

```bash
SYNC_INSTALL_USER=pi ./install-on-host.sh
```

Если каталоги Klipper названы иначе (пример: `fbg51_data` и `fbg52_data`, пользователь `klipper`):

```bash
SYNC_INSTALL_USER=klipper \
SYNC_CONFIG_DIR=/home/klipper/fbg51_data/config \
SYNC_CONFIG_DIRS="/home/klipper/fbg51_data/config /home/klipper/fbg52_data/config" \
./install-on-host.sh
```

`sync-caps.env` создаётся в `SYNC_CONFIG_DIR`; `sync-caps.cfg` — в каждом каталоге из `SYNC_CONFIG_DIRS`.

Отредактируйте конфиг:

```bash
nano ~/fbg51_data/config/sync-caps.env   # ваш реальный путь
```

Обязательно проверьте:

```bash
MASTER_IP=192.168.1.10          # IP головного
MASTER_USER=klipper               # пользователь SSH на мастере
MASTER_CAPS_PATH=gcodes/caps      # на мастере
GCODES_ROOT=/home/klipper/fbg51_data/gcodes   # общий gcodes (симлинк с обоих принтеров)
MOONRAKER_PORTS="7125 7126"     # оба экземпляра; если второй на другом порту — укажите свой
```

Подключите макрос **в printer.cfg обоих принтеров** (или в общий include):

```ini
[include sync-caps.cfg]
```

Перезапуск Klipper (в Mainsail или SSH):

```text
RESTART
```

Повторите шаги 3 на всех 8 хостах.

---

## Шаг 4. SSH: доступ slave → master (только чтение каталога)

На **каждом slave** (не обязательно на мастере для pull, но ключ нужен для rsync **к** мастеру):

```bash
# если install-on-host.sh уже создал ключ:
ssh-copy-id -i ~/.ssh/id_ed25519.pub pi@192.168.1.10

# проверка (dry-run)
rsync -avn pi@192.168.1.10:gcodes/caps/ ~/printer_data/gcodes/caps/
```

На **мастере** в `~/.ssh/authorized_keys` должны быть pub-ключи всех хостов, которые синхронизируются. Подсказка по ограничению команд: `config/master-ssh-snippet.txt`.

Проверка с slave:

```bash
~/bin/sync-caps.sh
tail -20 ~/printer_data/logs/sync-caps.log
```

---

## Шаг 5. Кнопка в Mainsail

См. [MAINSAIL.md](MAINSAIL.md): пользовательская кнопка → макрос `SYNC_CAPS`.

---

## Шаг 6. Проверка

1. На мастере положите тестовый `test.gcode` в `~/gcodes/caps/`.
2. На slave нажмите **Синхронизация CAPS** (или в консоли: `SYNC_CAPS`).
3. Файл появился в `~/printer_data/gcodes/caps/` (или в целевом gcodes).
4. В Mainsail — превью и метаданные; для exclude objects нужен gcode с поддержкой от слайсера.
5. Измените размер файла на мастере, снова sync — на slave файл должен замениться.
6. Удалите файл на мастере, sync с `RSYNC_DELETE=1` — на slave он исчезнет из `caps/`.

---

## Поведение на головном хосте

Мастер **тоже печатает**. При нажатии кнопки на мастере скрипт видит свой IP = `MASTER_IP` и **не делает rsync**, только **metascan** всех gcode в локальном `caps/` для обоих Moonraker. Файлы вы добавляете на мастер вручную.

---

## Параметры `sync-caps.env`

| Параметр | Описание |
|----------|----------|
| `RSYNC_DELETE=1` | Зеркало: удалять на slave то, чего нет на мастере в `caps/` |
| `RSYNC_CHECKSUM=1` | Сравнение по хешу (медленнее; при одинаковом размере и разном содержимом) |
| `BLOCK_WHILE_PRINTING=0` | Разрешить sync во время печати (не рекомендуется) |
| `FORCE_MASTER_MODE=1` | Всегда режим «только metascan» без rsync |

---

## Устранение неполадок

| Симптом | Действие |
|---------|----------|
| `Permission denied (publickey)` | `ssh-copy-id` на мастер, проверить `authorized_keys` |
| `No such file or directory` remote | На мастере есть `~/gcodes/caps/` и путь в `MASTER_CAPS_PATH` |
| Файл есть, нет превью | Проверить лог; вручную: `curl -sS -X POST "http://127.0.0.1:7125/server/jsonrpc" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"server.files.metascan","params":{"filename":"caps/имя.gcode"},"id":1}'` |
| Печать активна | Дождаться окончания или `BLOCK_WHILE_PRINTING=0` |
| Второй принтер без метаданных | Убедиться, что `MOONRAKER_PORTS` содержит оба порта |
| `gcode_shell_command … is not a valid config section` | Установить расширение `gcode_shell_command.py` в `klipper/klippy/extras/` (KIAUH → Advanced → Shell Command), перезапустить Klipper |
| `RUN_SHELL_COMMAND` unknown | То же — расширение не установлено или Klipper не перезапущен |

Лог: `~/printer_data/logs/sync-caps.log`

---

## Безопасность

- SSH-ключи без пароля — только в доверенной LAN.
- По возможности отдельный пользователь на мастере с доступом только к `gcodes/caps` (см. `master-ssh-snippet.txt`).
- Moonraker API доступен локально; скрипт ходит на `127.0.0.1`.

---

## Обновление скриптов

С Windows снова `scp` новый `sync-caps.sh` в `/home/pi/bin/sync-caps.sh` на все хосты или через одну команду `for ip in ...`. Конфиг `sync-caps.env` не перезаписывайте.
