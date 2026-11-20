@echo off
setlocal
set "PYTHON=%LocalAppData%\Programs\Python\Python313\python.exe"
if not exist "%PYTHON%" set "PYTHON=python.exe"
set PYTHONDONTWRITEBYTECODE=1
echo FPGA Vision web console: open http://127.0.0.1:8000 in your browser.
"%PYTHON%" "%~dp0server.py"
pause
