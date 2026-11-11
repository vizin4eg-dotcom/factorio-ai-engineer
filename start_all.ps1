$ErrorActionPreference = "Continue"

# ---------------------------------------------------------------------------
# Секреты и адреса не хранятся в этом файле. Значения берутся из переменных
# окружения, затем из packages/agent/.env.local (он в .gitignore).
# ---------------------------------------------------------------------------
$root = $PSScriptRoot
$envFile = Join-Path $root "packages\agent\.env.local"

function Get-LocalSetting {
    param([string]$Name)

    $fromEnv = Get-Item -Path "Env:$Name" -ErrorAction SilentlyContinue
    if ($fromEnv -and $fromEnv.Value) { return $fromEnv.Value }

    if (-not (Test-Path $envFile)) { return $null }

    foreach ($line in Get-Content $envFile) {
        if ($line -match "^\s*$([regex]::Escape($Name))\s*=\s*(.*)$") {
            $raw = $Matches[1].Trim()
            if ($raw.Length -ge 2 -and (($raw.StartsWith('"') -and $raw.EndsWith('"')) -or ($raw.StartsWith("'") -and $raw.EndsWith("'")))) {
                $raw = $raw.Substring(1, $raw.Length - 2)
            }
            return $raw
        }
    }
    return $null
}

$rconPassword = Get-LocalSetting "FACTORIO_RCON_PASSWORD"
if (-not $rconPassword) {
    Write-Host "[WARN] FACTORIO_RCON_PASSWORD не найден в окружении или .env.local" -ForegroundColor Yellow
    $rconPassword = Read-Host "Введите пароль RCON"
}

# Адрес хоста с точки зрения Docker-контейнера. По умолчанию host.docker.internal;
# на старых установках Docker Desktop может понадобиться LAN-IP в FACTORIO_RCON_HOST.
$rconHost = Get-LocalSetting "FACTORIO_RCON_HOST"
if (-not $rconHost) { $rconHost = "host.docker.internal" }

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "[1/3] Factorio World Selector..." -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan

$savesDir = "C:\Games\FactorioHeadless\saves"
if (-not (Test-Path $savesDir)) {
    $savesDir = Join-Path $root "packages\factorio-wrapper\factorio\saves"
}

$rawFiles = Get-ChildItem -Path $savesDir -Filter *.zip -ErrorAction SilentlyContinue
$saveList = @()
if ($rawFiles) {
    $saveList = @($rawFiles | Sort-Object LastWriteTime -Descending)
}

$selectedSave = ""
if ($saveList.Count -gt 0) {
    Write-Host "Dostupnye seivy v papke saves:" -ForegroundColor Green
    for ($i = 0; $i -lt $saveList.Count; $i++) {
        $item = $saveList[$i]
        $idx = $i + 1
        $t = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
        Write-Host " [$idx] $($item.Name) - $t" -ForegroundColor White
    }

    $defName = $saveList[0].Name
    $ans = Read-Host "Vvedite nomer seiva [Enter dlya $defName]"

    $choiceNum = 0
    if ([int]::TryParse($ans, [ref]$choiceNum)) {
        if ($choiceNum -ge 1 -and $choiceNum -le $saveList.Count) {
            $selectedSave = $saveList[$choiceNum - 1].Name
        }
        else {
            $selectedSave = $defName
        }
    }
    else {
        $selectedSave = $defName
    }
    Write-Host "-> Vybran seiv: $selectedSave`n" -ForegroundColor Cyan
}

$wrapperCmd = "pnpm exec tsx --env-file=.env.local src/main.ts $selectedSave"
$agentCmd = "docker restart factorio-rcon-api 2>&1 | Out-Null; Start-Sleep -Seconds 2; pnpm exec tsx --env-file=.env.local src/main.ts"

$historyDir = Join-Path $env:APPDATA "Microsoft\Windows\PowerShell\PSReadLine"
$historyFile = Join-Path $historyDir "ConsoleHost_history.txt"
if (-not (Test-Path $historyDir)) {
    New-Item -ItemType Directory -Path $historyDir -Force -ErrorAction SilentlyContinue | Out-Null
}
Add-Content -Path $historyFile -Value $wrapperCmd -ErrorAction SilentlyContinue
Add-Content -Path $historyFile -Value $agentCmd -ErrorAction SilentlyContinue

Start-Process powershell.exe -WorkingDirectory (Join-Path $root "packages\factorio-wrapper") -ArgumentList "-NoExit", "-Command", $wrapperCmd

Write-Host "Waiting for Factorio RCON port to initialize 15 sec..." -ForegroundColor Gray
Start-Sleep -Seconds 15

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "[2/3] Starting Docker RCON Bridge..." -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan

try {
    docker rm -f factorio-rcon-api 2>&1 | Out-Null
}
catch {}

$dockerArgs = @(
    "run", "--rm", "-d", "--name", "factorio-rcon-api",
    "-e", "FACTORIO_RCON_HOST=$rconHost",
    "-e", "FACTORIO_RCON_PORT=27015",
    "-e", "FACTORIO_RCON_PASSWORD=$rconPassword",
    "-p", "24180:24180",
    "factorio-rcon-api:local"
)

& docker @dockerArgs | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Docker RCON bridge did not start. Is Docker Desktop running and factorio-rcon-api:local built?" -ForegroundColor Red
}
Start-Sleep -Seconds 3

try {
    $pingObj = @{ input = "/c rcon.print(12345)" }
    $pingBody = ConvertTo-Json -InputObject $pingObj -Compress
    $null = Invoke-RestMethod -Method Post -Uri "http://localhost:24180/api/v2/factorio/console/command/raw" -ContentType "application/json" -Body $pingBody -TimeoutSec 5
    Write-Host "[OK] RCON Bridge connected successfully!" -ForegroundColor Green
}
catch {
    Write-Host "[WARN] RCON Bridge started, proceeding to Agent..." -ForegroundColor Yellow
}

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "[3/3] Starting AI Agent..." -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan

Start-Process powershell.exe -WorkingDirectory (Join-Path $root "packages\agent") -ArgumentList "-NoExit", "-Command", $agentCmd

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host " All systems successfully launched!" -ForegroundColor Green
Write-Host " In BOTH windows Wrapper and Agent:" -ForegroundColor Green
Write-Host " - Ctrl+C stops instantly" -ForegroundColor Green
Write-Host " - Up Arrow + Enter restarts from history" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
