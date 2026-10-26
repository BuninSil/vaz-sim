# Обновляет кэш глобальных классов (нужно после добавления нового class_name).
$p = Start-Process C:\gdt\Godot_v4.7.2-stable_win64_console.exe -ArgumentList '--headless','--path',(Split-Path $PSScriptRoot),'--editor' -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\ed_out.txt" -RedirectStandardError "$env:TEMP\ed_err.txt"
Start-Sleep 40
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Select-String -Path (Join-Path (Split-Path $PSScriptRoot) '.godot\global_script_class_cache.cfg') -Pattern 'class":' | ForEach-Object { $_.Line.Trim() }
