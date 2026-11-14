@echo off
rem ============================================================
rem  The Gauss Vina - MES TV dashboard setup (mini PC)
rem  1) Auto start MES (full screen) when Windows starts
rem  2) Never turn off screen / never sleep
rem  3) Open MES now
rem  Exit full screen: Alt+F4
rem ============================================================
set "URL=https://thegauss0075-prog.github.io/erp/mes/"
set "EDGE=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE%" set "EDGE=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE%" (echo [ERROR] Microsoft Edge not found. & pause & exit /b 1)

echo [1/3] Creating startup shortcut...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$w=New-Object -ComObject WScript.Shell; foreach($d in @([Environment]::GetFolderPath('Startup'),[Environment]::GetFolderPath('Desktop'))){ $s=$w.CreateShortcut((Join-Path $d 'MES TV.lnk')); $s.TargetPath=$env:EDGE; $s.Arguments='--app='+$env:URL+' --start-fullscreen --no-first-run'; $s.WorkingDirectory=(Split-Path $env:EDGE); $s.Save() }"

echo [2/3] Power: screen and sleep never off...
powercfg /change monitor-timeout-ac 0
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /change monitor-timeout-dc 0
powercfg /change standby-timeout-dc 0

echo [3/3] Opening MES...
taskkill /im msedge.exe /f >nul 2>&1
timeout /t 2 /nobreak >nul
start "" "%EDGE%" --app=%URL% --start-fullscreen --no-first-run

echo.
echo Done. Log in once with the VIEWER account. (Exit: Alt+F4)
timeout /t 8
