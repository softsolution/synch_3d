# Запуск push caps с Windows без WSL (использует Git Bash).
# Из PowerShell:  .\scripts\sync-caps-from-windows.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$GitBash = "C:\Program Files\Git\bin\bash.exe"
$Script = Join-Path $RepoRoot "scripts\sync-caps-from-windows.sh"

if (-not (Test-Path $GitBash)) {
    Write-Error @"
Git Bash не найден: $GitBash
Установите Git for Windows: https://git-scm.com/download/win
Не используйте команду bash из PowerShell — она запускает WSL (см. docs/WINDOWS.md).
"@
}

if (-not (Get-Command rsync -ErrorAction SilentlyContinue)) {
    Write-Host "rsync не найден — скрипт использует scp (OpenSSH). Для зеркала caps/ установите cwRsync." -ForegroundColor Yellow
}

& $GitBash -lc "cd '$(($RepoRoot -replace '\\','/'))' && bash scripts/sync-caps-from-windows.sh"
exit $LASTEXITCODE
