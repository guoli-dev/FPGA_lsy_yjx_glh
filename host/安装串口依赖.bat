@echo off
setlocal
set "PYTHON=%LocalAppData%\Programs\Python\Python313\python.exe"
if not exist "%PYTHON%" set "PYTHON=python.exe"

echo === Python in use ===
"%PYTHON%" -c "import sys;print(sys.executable);print(sys.version)"
echo.

echo === Install pyserial ===
"%PYTHON%" -m pip install --upgrade pyserial
echo.

echo === pyserial check ===
"%PYTHON%" -c "import serial;print('pyserial', serial.__version__)"
echo.

echo === COM ports on this PC ===
"%PYTHON%" -m serial.tools.list_ports -v
echo.

echo === Windows port devices ===
powershell -NoProfile -Command "Get-PnpDevice -Class Ports -ErrorAction SilentlyContinue | Select-Object Status,FriendlyName,InstanceId | Format-Table -AutoSize"
echo.

echo === USB devices that may need a driver ===
powershell -NoProfile -Command "Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'CH34|CP210|USB-SERIAL|USB Serial|Silicon|Unknown' } | Select-Object Status,Class,FriendlyName | Format-Table -AutoSize"
echo.

echo If the COM list is empty:
echo   1) The module may need a USB-serial driver (CH340 or CP210x).
echo   2) Try another USB cable / USB port (power-only cables exist).
echo   3) Make sure this is the PC-side module, not the one on the car.
echo After installing pyserial, close and restart server.py, then refresh the web page.
pause
