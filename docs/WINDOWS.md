# Синхронизация caps с Windows на мастер-хост

Загрузка gcode с рабочего **Windows-ПК** на головной хост в `~/gcodes/caps/`. После копирования на мастере автоматически обновляются метаданные Moonraker (превью, exclude objects).

Это **push** с ПК на мастер. Остальные 7 хостов по-прежнему делают **pull** с мастера кнопкой `SYNC_CAPS` в Mainsail (см. [INSTALL.md](INSTALL.md)).

---

## Схема

```text
Windows (LOCAL_CAPS_PATH)  --rsync push-->  мастер ~/gcodes/caps/
                                                    |
                                                    +-- metascan (Moonraker 7125, 7126)
                                                    |
                                              slaves pull по SYNC_CAPS
```

---

## Требования на Windows

- **Git for Windows** (Git Bash) — рекомендуется
- В PATH: `ssh` / `scp` (есть в Git Bash и Windows OpenSSH)
- `rsync` **не обязателен** — без него скрипт копирует через `scp` (`SYNC_BACKEND=auto`)
- SSH-ключ с доступом на мастер (`klipper@MASTER_IP`)
- На мастере уже установлен `sync-caps.sh` через `install-on-host.sh`

> **Не запускайте `bash` из PowerShell или CMD напрямую.** В Windows 11 команда `bash` — это лаунчер **WSL**, а не Git Bash. Если по умолчанию в WSL выбран `docker-desktop` с битым диском, появится ошибка про `ext4.vhdx` (см. ниже).

---

## Быстрый старт

### 1. Конфиг

Скопируйте шаблон (если ещё нет рабочего файла):

```bash
cp config/sync-caps-from-windows.env.example config/sync-caps-from-windows.env
```

Отредактируйте `config/sync-caps-from-windows.env`:

| Параметр | Описание |
|----------|----------|
| `MASTER_IP` | IP головного хоста |
| `MASTER_USER` | Пользователь SSH на мастере (`klipper`, `pi`, …) |
| `LOCAL_CAPS_PATH` | Локальная папка с gcode (содержимое уйдёт в `caps/` на мастере) |
| `MASTER_CAPS_PATH` | Обычно `gcodes/caps` |
| `MASTER_SYNC_SCRIPT` | Путь к `sync-caps.sh` на мастере |
| `MASTER_SYNC_CONFIG` | Путь к `sync-caps.env` на мастере |

Пример путей в Git Bash:

```bash
LOCAL_CAPS_PATH=C:/Users/ИМЯ/caps
# или диск D:
LOCAL_CAPS_PATH=D:/3D/gcodes/caps
LOG_FILE=C:/OSPanel/home/sync/logs/sync-caps-from-windows.log
```

### 2. SSH-ключ (один раз)

В Git Bash:

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
ssh-copy-id klipper@192.168.1.109
ssh klipper@192.168.1.109 'ls ~/gcodes/caps'
```

### 3. Запуск

**Вариант A — из PowerShell (проще всего):**

```powershell
cd C:\OSPanel\home\sync
.\scripts\sync-caps-from-windows.ps1
```

Скрипт `.ps1` сам вызывает Git Bash и не трогает WSL.

**Вариант B — Git Bash:**

```bash
cd /c/OSPanel/home/sync
"C:/Program Files/Git/bin/bash.exe" scripts/sync-caps-from-windows.sh
```

Проверка без копирования (dry-run rsync вручную):

```bash
rsync -avn /c/path/to/caps/ klipper@192.168.1.109:gcodes/caps/
```

Лог: путь из `LOG_FILE` в конфиге (по умолчанию `logs/sync-caps-from-windows.log`).

---

## Что делает скрипт

1. **rsync** — `LOCAL_CAPS_PATH/` → `MASTER_USER@MASTER_IP:gcodes/caps/`
2. **metascan на мастере** — по SSH запускает `FORCE_MASTER_MODE=1 sync-caps.sh`  
   Мастер тоже печатает: rsync с самого себя не нужен, только обновление метаданных для обоих Moonraker.

Отключить metascan: `REMOTE_METASCAN=0` в конфиге.

---

## Параметры поведения

| Параметр | По умолчанию | Описание |
|----------|--------------|----------|
| `RSYNC_DELETE=1` | да | Зеркало: на мастере удаляются файлы, которых нет в локальной папке |
| `RSYNC_CHECKSUM=0` | нет | Сравнение по хешу (медленнее, надёжнее при одинаковом размере) |
| `FORCE_MASTER_METASCAN=1` | да | Только metascan на мастере, без pull |
| `SSH_IDENTITY_FILE` | — | Явный путь к ключу, если не стандартный `~/.ssh/id_ed25519` |

---

## Типичный рабочий процесс

1. Слайсер сохраняет gcode в локальную папку (`LOCAL_CAPS_PATH`).
2. Запускаете `sync-caps-from-windows.sh`.
3. На мастере файлы в `caps/`, превью в Mainsail обновлены.
4. На остальных хостах нажимаете **Синхронизация CAPS** — они подтягивают с мастера.

---

## Устранение неполадок

### Ошибка WSL / Docker: `ext4.vhdx` / `ERROR_FILE_NOT_FOUND`

Типичный текст:

```text
Не удалось подключить диск "...\Docker\wsl\main\ext4.vhdx" к WSL2
Error code: Bash/Service/CreateInstance/MountVhd/HCS/ERROR_FILE_NOT_FOUND
```

**Причина:** в PowerShell команда `bash` запускает WSL. Дистрибутив по умолчанию — `docker-desktop`, а его виртуальный диск удалён или повреждён (Docker не установлен / сброшен).

**Решение для синхронизации (без починки Docker):**

1. Используйте `.\scripts\sync-caps-from-windows.ps1` или Git Bash (см. выше).
2. Не вводите просто `bash` в PowerShell.

**Если нужен именно WSL:** установите Ubuntu из Microsoft Store, затем:

```powershell
wsl --set-default Ubuntu
```

**Если нужен Docker Desktop:** переустановите Docker Desktop — он пересоздаст `ext4.vhdx`.

---

### `rsync: command not found`

По умолчанию скрипт работает в режиме **`SYNC_BACKEND=auto`**: если `rsync` нет, используется **`scp`** (уже есть в Git Bash). Перезапустите скрипт — ошибки быть не должно.

Ограничение **scp**: не удаляет на мастере файлы, которых нет локально (`RSYNC_DELETE` не действует). Для полного зеркала `caps/` установите rsync:

1. **cwRsync** — [itefix.net/cwrsync](https://itefix.net/cwrsync), путь к `rsync.exe` в PATH или в конфиге: `RSYNC_BIN=C:/Program Files/cwRsync/bin/rsync.exe`
2. **Chocolatey:** `choco install rsync`
3. Явно в конфиге: `SYNC_BACKEND=scp` (только копирование, без зеркала)

Проверка в Git Bash:

```bash
rsync --version   # опционально
scp               # должно показать usage
```

---

| Симптом | Действие |
|---------|----------|
| `ext4.vhdx` / WSL ERROR_FILE_NOT_FOUND | Запуск через `.ps1` или Git Bash, не через `bash` в PowerShell |
| `rsync: command not found` | Обновите скрипт: при `SYNC_BACKEND=auto` переключится на scp; для зеркала — установите rsync |
| `Permission denied (publickey)` | `ssh-copy-id` на мастер, проверьте `SSH_IDENTITY_FILE` |
| `Локальная папка caps не найдена` | Проверьте `LOCAL_CAPS_PATH` (слэши `/`, не `\`) |
| Файлы на мастере есть, нет превью | Смотрите лог; на мастере вручную: `FORCE_MASTER_MODE=1 ~/bin/sync-caps.sh` |
| metascan не удался | Проверьте `MASTER_SYNC_SCRIPT` и `MASTER_SYNC_CONFIG` на мастере |
| Лишние файлы удалились на мастере | При `RSYNC_DELETE=1` локальная папка — эталон; отключите или синхронизируйте полный набор |

---

## См. также

- [INSTALL.md](INSTALL.md) — установка на 8 хостов, pull slave → master
- [MAINSAIL.md](MAINSAIL.md) — кнопка `SYNC_CAPS` на принтерах
