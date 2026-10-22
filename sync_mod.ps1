$ErrorActionPreference = "Continue"

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " Autorio Mod Synchronizer (PowerShell)" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Cyan

$src = "C:\Temp\Ai\airi-factorio\packages\autorio\control.lua"

if (-not (Test-Path $src)) {
    Write-Host "[ERROR] Исходный файл не найден: $src" -ForegroundColor Red
    Read-Host "Нажмите Enter для выхода..."
    exit 1
}

$file = Get-Item $src
Write-Host "Файл:  $($file.Name)"
Write-Host "Правка: $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "Размер: $($file.Length) байт"
Write-Host "--------------------------------------------------------" -ForegroundColor Gray

$targets = @(
    "C:\Games\FactorioHeadless\mods\autorio\control.lua",
    "C:\Games\Factorio\mods\autorio\control.lua",
    (Join-Path $env:APPDATA "Factorio\mods\autorio\control.lua")
)

foreach ($dst in $targets) {
    try {
        $parentDir = Split-Path $dst -Parent
        if (-not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host " [OK] ==> $dst" -ForegroundColor Green
    } catch {
        Write-Host " [FAIL] ==> $dst" -ForegroundColor Red
    }
}

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Синхронизация завершена!" -ForegroundColor Green
Write-Host ""
Read-Host "Нажмите Enter для выхода..."