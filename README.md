# Синхронизация gcode (caps) для фермы Klipper / Mainsail

Pull-синхронизация папки `gcodes/caps/` с **головного хоста** на остальные 7 хостов по кнопке в Mainsail. На каждом хосте два принтера с **общей** папкой gcodes (симлинк).

## Состав

| Файл | Назначение |
|------|------------|
| `scripts/sync-caps.sh` | Основной скрипт (rsync + metascan) |
| `scripts/install-on-host.sh` | Установка на один хост |
| `config/sync-caps.env.example` | Конфиг (копируется в `printer_data/config/`) |
| `config/hosts.env.example` | Таблица IP всех 8 хостов (справочно) |
| `config/printer.sync-caps.snippet.cfg` | Макрос и shell-команда для Klipper |
| `config/master-ssh-snippet.txt` | Подсказки по SSH на мастере |
| `docs/INSTALL.md` | **Полная инструкция по установке** |
| `docs/MAINSAIL.md` | Настройка кнопки в Mainsail |

## Быстрый старт

1. На **мастере** создайте `~/gcodes/caps/` и кладите туда gcode.
2. Скопируйте репозиторий на каждый хост (см. `docs/INSTALL.md`, раздел Windows).
3. На **каждом** из 8 хостов: `bash install-on-host.sh`, отредактируйте `sync-caps.env`, `[include sync-caps.cfg]`, `RESTART`.
4. Настройте SSH-ключи slave → master.
5. В Mainsail добавьте кнопку на макрос `SYNC_CAPS` (`docs/MAINSAIL.md`).

Подробности: **[docs/INSTALL.md](docs/INSTALL.md)**
