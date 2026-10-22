Write-Host "========================================================" -ForegroundColor Cyan;
Write-Host "[1/3] Factorio World Selector..." -ForegroundColor Yellow;
Write-Host "========================================================" -ForegroundColor Cyan;

$savesDir = "C:\Games\FactorioHeadless\saves";
if (-not (Test-Path $savesDir)) {$savesDir = "C:\Temp\Ai\airi-factorio\packages\factorio-wrapper\factorio\saves";
}

$rawFiles = Get-ChildItem -Path $savesDir -Filter *.zip -ErrorAction SilentlyContinue;
$saveList = @();
if ($rawFiles) {
    $saveList = @($rawFiles | Sort-Object LastWriteTime -Descending);
}

$selectedSave = "";
if ($saveList.Count -gt 0) {
    Write-Host "Dostupnye seivy v papke saves:" -ForegroundColor Green;
    for ($i = 0; $i -lt$saveList.Count; $i++) {$item = $saveList[$i];
        $idx =$i + 1;
        $t =$item.LastWriteTime.ToString("yyyy-MM-dd HH:mm");
        $n =$item.Name;
        Write-Host " [$idx] $n -$t" -ForegroundColor White;
    }
    
    $defName =$saveList[0].Name;
    $ans = Read-Host "Vvedite nomer seiva [Enter dlya $defName]";
    
    $choiceNum = 0;
    if ([int]::TryParse($ans, [ref]$choiceNum)) {
        if ($choiceNum -ge 1 -and$choiceNum -le $saveList.Count) {$selectedSave = $saveList[$choiceNum - 1].Name;
        } else {
            $selectedSave =$defName;
        }
    } else {
        $selectedSave =$defName;
    }
    Write-Host "-> Vybran seiv: $selectedSave`n" -ForegroundColor Cyan;
}

$wrapperCmd = "pnpm exec tsx --env-file=.env.local src/main.ts $selectedSave";
$agentCmd = "docker restart factorio-rcon-api 2>&1 | Out-Null; Start-Sleep -Seconds 2; pnpm exec tsx --env-file=.env.local src/main.ts"

$historyDir = Join-Path $env:APPDATA "Microsoft\Windows\PowerShell\PSReadLine";
$historyFile = Join-Path $historyDir "ConsoleHost_history.txt";
if (-not (Test-Path $historyDir)) {
    New-Item -ItemType Directory -Path $historyDir -Force -ErrorAction SilentlyContinue | Out-Null;
}
Add-Content -Path $historyFile -Value $wrapperCmd -ErrorAction SilentlyContinue;
Add-Content -Path $historyFile -Value $agentCmd -ErrorAction SilentlyContinue;

Start-Process powershell.exe -WorkingDirectory "C:\Temp\Ai\airi-factorio\packages\factorio-wrapper" -ArgumentList "-NoExit", "-Command", $wrapperCmd;

Write-Host "Waiting for Factorio RCON port to initialize 15 sec..." -ForegroundColor Gray;
Start-Sleep -Seconds 15;

Write-Host "`n========================================================" -ForegroundColor Cyan;
Write-Host "[2/3] Starting Docker RCON Bridge..." -ForegroundColor Yellow;
Write-Host "========================================================" -ForegroundColor Cyan;

try {
    docker rm -f factorio-rcon-api 2>&1 | Out-Null;
} catch {}

docker run --rm -d --name factorio-rcon-api -e FACTORIO_RCON_HOST=192.168.31.64 -e FACTORIO_RCON_PORT=27015 -e FACTORIO_RCON_PASSWORD=4real -p 24180:24180 factorio-rcon-api:local | Out-Null;
Start-Sleep -Seconds 3;

try {
    $pingObj = @{ input = "/c rcon.print(12345)" };
    $pingBody = ConvertTo-Json -InputObject$pingObj -Compress;
    $null = Invoke-RestMethod -Method Post -Uri "http://localhost:24180/api/v2/factorio/console/command/raw" -ContentType "application/json" -Body $pingBody -TimeoutSec 5;
    Write-Host "[OK] RCON Bridge connected successfully!" -ForegroundColor Green;
} catch {
    Write-Host "[WARN] RCON Bridge started, proceeding to Agent..." -ForegroundColor Yellow;
}

Write-Host "`n========================================================" -ForegroundColor Cyan;
Write-Host "[3/3] Starting AI Agent..." -ForegroundColor Yellow;
Write-Host "========================================================" -ForegroundColor Cyan;

Start-Process powershell.exe -WorkingDirectory "C:\Temp\Ai\airi-factorio\packages\agent" -ArgumentList "-NoExit", "-Command", $agentCmd;

Write-Host "`n========================================================" -ForegroundColor Green;
Write-Host " All systems successfully launched!" -ForegroundColor Green;
Write-Host " In BOTH windows Wrapper and Agent:" -ForegroundColor Green;
Write-Host " - Ctrl+C stops instantly" -ForegroundColor Green;
Write-Host " - Up Arrow + Enter restarts from history" -ForegroundColor Green;
Write-Host "========================================================" -ForegroundColor Green;