$ErrorActionPreference = "Continue"

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " Autorio Mod Synchronizer (PowerShell)" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan

$srcDir = Join-Path $PSScriptRoot "packages\autorio"
$src = Join-Path $srcDir "control.lua"

if (-not (Test-Path $src)) {
    Write-Host "[ERROR] Источник не найден: $src" -ForegroundColor Red
    Read-Host "Нажмите Enter для выхода..."
    exit 1
}

$file = Get-Item $src
Write-Host "Файл:  $($file.Name)"
Write-Host "Правка: $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "Размер: $($file.Length) байт"
Write-Host "--------------------------------------------------------" -ForegroundColor Gray

# Мод без info.json не загрузится, поэтому копируем и его: раньше на чистой
# машине создавалась пустая папка с одним control.lua.
$files = @("control.lua", "info.json")

$targets = @(
    "C:\Games\FactorioHeadless\mods\autorio",
    "C:\Games\Factorio\mods\autorio",
    (Join-Path $env:APPDATA "Factorio\mods\autorio")
)

foreach ($dir in $targets) {
    try {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        foreach ($name in $files) {
            $from = Join-Path $srcDir $name
            if (Test-Path $from) {
                Copy-Item -Path $from -Destination (Join-Path $dir $name) -Force
                Write-Host " [OK] ==> $(Join-Path $dir $name)" -ForegroundColor Green
            }
            else {
                Write-Host " [SKIP] нет файла: $from" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host " [FAIL] ==> $dir ($($_.Exception.Message))" -ForegroundColor Red
    }
}

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Синхронизация завершена!" -ForegroundColor Green
Write-Host ""
Read-Host "Нажмите Enter для выхода..."
