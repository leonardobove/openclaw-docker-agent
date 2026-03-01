@echo off
:: ─────────────────────────────────────────────────────────────────────────────
:: Ollama SSH Reverse Tunnel — Windows (CMD / Command Prompt)
::
:: Opens a persistent reverse SSH tunnel so the OpenClaw agent on your VPS
:: can reach Ollama running on this Windows machine.
::
:: Usage:
::   scripts\tunnel.bat ubuntu@YOUR_VPS_IP
::
:: Requires: Windows 10+ (built-in OpenSSH client)
:: Keep this window open while using the agent.
:: ─────────────────────────────────────────────────────────────────────────────

if "%~1"=="" (
    echo Usage: %~n0 user@vps-ip
    echo Example: %~n0 ubuntu@203.0.113.42
    exit /b 1
)

set VPS=%~1
set OLLAMA_PORT=11434

echo [tunnel] Checking Ollama at http://localhost:%OLLAMA_PORT%...
curl -sf --connect-timeout 3 http://localhost:%OLLAMA_PORT%/api/tags >nul 2>&1
if errorlevel 1 (
    echo [tunnel] ERROR: Ollama is not running at localhost:%OLLAMA_PORT%.
    echo [tunnel] Start Ollama first, then re-run this script.
    pause
    exit /b 1
)
echo [tunnel] Ollama: reachable

echo.
echo [tunnel] Opening SSH reverse tunnel:
echo [tunnel]   VPS port %OLLAMA_PORT% --^> localhost:%OLLAMA_PORT%
echo [tunnel]   Target: %VPS%
echo [tunnel] Press Ctrl-C to stop.
echo.

ssh -N ^
    -R 0.0.0.0:%OLLAMA_PORT%:localhost:%OLLAMA_PORT% ^
    -o ServerAliveInterval=30 ^
    -o ServerAliveCountMax=5 ^
    -o ExitOnForwardFailure=yes ^
    -o StrictHostKeyChecking=accept-new ^
    -o ConnectTimeout=10 ^
    %VPS%

if errorlevel 1 (
    echo.
    echo [tunnel] SSH tunnel exited with an error.
    echo [tunnel] Check VPS connectivity and that GatewayPorts=yes in /etc/ssh/sshd_config on VPS.
    pause
)
