# Быстрая проверка компиляции: загружает главную сцену и выводит первые ошибки.
$j = Start-Job { [Console]::OutputEncoding=[Text.Encoding]::UTF8; & C:\gdt\Godot_v4.7.2-stable_win64_console.exe --headless --path C:\Users\BuninSil\Documents\vaz-21061-simulator --script res://tests/smoke.gd --fixed-fps 60 2>&1 | % { "$_" } }
Wait-Job $j -Timeout 280 | Out-Null
Receive-Job $j | Where-Object { $_ -notmatch 'GDScript backtrace|^\s+\[\d\]' } | Select-Object -First 30
Stop-Job $j
Get-Process Godot* -ErrorAction SilentlyContinue | Stop-Process -Force
