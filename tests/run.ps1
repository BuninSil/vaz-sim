# Запуск тестов модели: powershell -File tests\run.ps1 [путь к godot]
param([string]$Godot = "C:\gdt\Godot_v4.7.2-stable_win64_console.exe")
Set-Location (Split-Path $PSScriptRoot)
& $Godot --headless --path . --script res://tests/sim_test.gd 2>&1 | ForEach-Object { "$_" }
