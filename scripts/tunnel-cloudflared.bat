@echo off
:: ─────────────────────────────────────────────────────────────────────────────
:: tunnel-cloudflared.bat — Expose local Ollama via Cloudflare Tunnel
::
:: Use this when you CANNOT reach your home server via Tailscale or SSH
:: (e.g., locked-down work PC without Tailscale installed).
::
:: How it works:
::   1. Downloads cloudflared.exe if not already present (uses curl — built in Windows 10+)
::   2. Exposes http://localhost:11434 as a public HTTPS URL
::   3. Prints the URL — copy it to your Linux server's .env file
::
:: After running this, on your Linux server:
::   nano .env
::     → set OLLAMA_BASE_URL=https://<the-url-printed-below>
::   make restart
::
:: Keep this window open while using the agent.
:: The URL changes every time you restart this script.
:: ─────────────────────────────────────────────────────────────────────────────
setlocal

set SCRIPT_DIR=%~dp0
set CLOUDFLARED=%SCRIPT_DIR%cloudflared.exe
set OLLAMA_PORT=11434
set OLLAMA_URL=http://localhost:%OLLAMA_PORT%

:: ── Check Ollama ──────────────────────────────────────────────────────────
echo [tunnel-cf] Checking Ollama at %OLLAMA_URL%...
curl -sf --connect-timeout 3 %OLLAMA_URL%/api/tags >nul 2>&1
if errorlevel 1 (
    echo [tunnel-cf] ERROR: Ollama is not running at %OLLAMA_URL%.
    echo [tunnel-cf] Start Ollama first, then re-run this script.
    pause
    exit /b 1
)
echo [tunnel-cf] Ollama: reachable

:: ── Download cloudflared.exe if missing ───────────────────────────────────
if not exist "%CLOUDFLARED%" (
    echo.
    echo [tunnel-cf] cloudflared.exe not found. Downloading...
    echo [tunnel-cf] Saving to: %CLOUDFLARED%
    echo.
    curl -L --progress-bar -o "%CLOUDFLARED%" ^
        "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    if errorlevel 1 (
        echo [tunnel-cf] ERROR: Download failed. Check your internet connection.
        echo [tunnel-cf] Or download manually from:
        echo [tunnel-cf]   https://github.com/cloudflare/cloudflared/releases/latest
        echo [tunnel-cf] Save as: %CLOUDFLARED%
        pause
        exit /b 1
    )
    echo [tunnel-cf] cloudflared.exe downloaded.
) else (
    echo [tunnel-cf] cloudflared.exe found: %CLOUDFLARED%
)

:: ── Start tunnel ──────────────────────────────────────────────────────────
echo.
echo [tunnel-cf] Starting Cloudflare Tunnel for Ollama...
echo.
echo ┌──────────────────────────────────────────────────────────────────────┐
echo │  Watch for a line like:                                              │
echo │    https://some-random-words.trycloudflare.com                       │
echo │                                                                      │
echo │  Copy that URL, then on your Linux server run:                       │
echo │    nano .env                                                         │
echo │    (set OLLAMA_BASE_URL=https://some-random-words.trycloudflare.com) │
echo │    make restart                                                      │
echo └──────────────────────────────────────────────────────────────────────┘
echo.
echo [tunnel-cf] Press Ctrl-C to stop.
echo.

"%CLOUDFLARED%" tunnel --no-autoupdate --url %OLLAMA_URL%

echo.
echo [tunnel-cf] Tunnel stopped.
pause
