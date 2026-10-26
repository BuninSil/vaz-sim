# Прогон автотеста заезда.
$j = Start-Job { [Console]::OutputEncoding=[Text.Encoding]::UTF8; & C:\gdt\Godot_v4.7.2-stable_win64_console.exe --headless --path C:\Users\BuninSil\Documents\vaz-21061-simulator --script res://tests/drive_test.gd --fixed-fps 60 2>&1 | % { "$_" } }
Wait-Job $j -Timeout 500 | Out-Null
Receive-Job $j | Where-Object { $_ -notmatch 'backtrace|^\s+\[\d\]|leaked|PagedAllocator|instance_notify|ObjectDB|cleanup|utilities.cpp' } | Select-Object -First 40
Stop-Job $j
Get-Process Godot* -ErrorAction SilentlyContinue | Stop-Process -Force
