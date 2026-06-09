# Копирует актуальный sync-caps.sh на один хост (для быстрого деплоя после правок).
# Использование:
#   .\scripts\deploy-sync-caps.ps1 -PrinterIp 192.168.1.114
#   .\scripts\deploy-sync-caps.ps1 -PrinterIp 192.168.1.114 -Password klipper

param(
    [Parameter(Mandatory = $true)]
    [string]$PrinterIp,

    [string]$User = "klipper",
    [string]$Password = "",
    [string]$RemotePath = ""
)

if (-not $RemotePath) {
    $RemotePath = "/home/$User/bin/sync-caps.sh"
}

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LocalScript = Join-Path $RepoRoot "scripts\sync-caps.sh"
$Plink = "C:\Program Files\PuTTY\plink.exe"
$Pscp = "C:\Program Files\PuTTY\pscp.exe"

if (-not (Test-Path $LocalScript)) {
    throw "Не найден: $LocalScript"
}

# Unix LF — иначе на Armbian: env: 'bash\r': No such file or directory
$lfBody = ([IO.File]::ReadAllText($LocalScript) -replace "`r`n", "`n" -replace "`r", "`n")
$uploadPath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "sync-caps.sh")
[IO.File]::WriteAllText($uploadPath, $lfBody, [Text.UTF8Encoding]::new($false))

$remote = "${User}@${PrinterIp}:${RemotePath}"
$remoteFix = "chmod +x '$RemotePath' && sed -i 's/\r$//' '$RemotePath' && grep -n 'SYNC_CAPS_SCRIPT_REV\|=~' '$RemotePath' || true"

try {
    if ($Password -and (Test-Path $Pscp) -and (Test-Path $Plink)) {
        Write-Host "pscp $uploadPath -> $remote"
        & $Pscp -pw $Password $uploadPath "${User}@${PrinterIp}:${RemotePath}"
        & $Plink -batch -pw $Password "${User}@${PrinterIp}" $remoteFix
    }
    else {
        Write-Host "scp $uploadPath -> $remote"
        scp $uploadPath $remote
        ssh "${User}@${PrinterIp}" $remoteFix
    }
}
finally {
    Remove-Item -Force $uploadPath -ErrorAction SilentlyContinue
}
