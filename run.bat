@echo off
rem Launch VAZ-21061 simulator. Change the Godot path below if needed.
set GODOT=C:\gdt\Godot_v4.7.2-stable_win64.exe
if not exist "%GODOT%" (
  echo Godot not found: %GODOT%
  echo Download Godot 4.7 from https://godotengine.org and fix the path in run.bat
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
