@echo off
setlocal
echo Stopping any process listening on port 8000 ...
powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }"
timeout /t 1 >nul
set "PYTHON=%LocalAppData%\Programs\Python\Python313\python.exe"
if not exist "%PYTHON%" set "PYTHON=python.exe"
set PYTHONDONTWRITEBYTECODE=1
echo Starting server.py ...
"%PYTHON%" "%~dp0server.py"
pause
