@echo off
echo Starting NVIDIA rate-limited proxy...
start "" /B node "%~dp0server.js" > "%TEMP%\nvidia-proxy.log" 2>&1
timeout /t 2 >nul
curl -s http://localhost:1340/health >nul
if %errorlevel% equ 0 (
    echo [OK] Proxy running at http://localhost:1340/v1
) else (
    echo [FAILED] Check %TEMP%\nvidia-proxy.log
)
pause
