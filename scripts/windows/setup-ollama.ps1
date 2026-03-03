# setup-ollama.ps1
# ─────────────────────────────────────────────────────────────────────────────
# Configure Ollama on Windows for LAN access with AMD GPU
#
# Run in PowerShell as Administrator on the Windows machine:
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\scripts\windows\setup-ollama.ps1
#
# What it does:
#   1. Checks if Ollama is installed
#   2. Sets OLLAMA_HOST=0.0.0.0:11434 so Ollama listens on all interfaces
#   3. Adds a Windows Firewall rule to allow inbound on port 11434 (LAN only)
#   4. Reports AMD GPU detection
#   5. Pulls the default model (qwen2.5-coder:7b)
#   6. Prints the LAN IP to use in your Linux .env file
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "OpenClaw - Windows Ollama Setup" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Check Ollama installation ───────────────────────────────────────────
Write-Host "[1/5] Checking Ollama installation..." -ForegroundColor Yellow

$ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ollamaCmd) {
    Write-Host ""
    Write-Host "  Ollama is NOT installed." -ForegroundColor Red
    Write-Host "  Download and install it from: https://ollama.com/download/windows" -ForegroundColor White
    Write-Host "  Then re-run this script." -ForegroundColor White
    Write-Host ""
    exit 1
}

$ollamaVersion = & ollama --version 2>&1
Write-Host "  Ollama found: $ollamaVersion" -ForegroundColor Green

# ── 2. Configure OLLAMA_HOST system-wide ──────────────────────────────────
Write-Host ""
Write-Host "[2/5] Configuring Ollama to listen on all interfaces (0.0.0.0:11434)..." -ForegroundColor Yellow

# Set at Machine scope so it persists and applies to the Ollama service
[System.Environment]::SetEnvironmentVariable("OLLAMA_HOST", "0.0.0.0:11434", "Machine")
Write-Host "  OLLAMA_HOST=0.0.0.0:11434 set in system environment." -ForegroundColor Green
Write-Host "  NOTE: Restart Ollama after this script for the change to take effect." -ForegroundColor White

# ── 3. Windows Firewall rule ───────────────────────────────────────────────
Write-Host ""
Write-Host "[3/5] Adding Windows Firewall rule for Ollama (port 11434, private networks)..." -ForegroundColor Yellow

$ruleName = "Ollama LAN (OpenClaw)"
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

if ($existingRule) {
    Write-Host "  Firewall rule already exists: '$ruleName'" -ForegroundColor Green
} else {
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 11434 `
        -Action Allow `
        -Profile Private `
        -Description "Allows OpenClaw (Linux Docker) to reach Ollama on the LAN" | Out-Null
    Write-Host "  Firewall rule created: '$ruleName' (TCP 11434, Private profile)" -ForegroundColor Green
}

# ── 4. AMD GPU detection ───────────────────────────────────────────────────
Write-Host ""
Write-Host "[4/5] Checking AMD GPU..." -ForegroundColor Yellow

$gpus = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -match "AMD|Radeon|RX" }
if ($gpus) {
    foreach ($gpu in $gpus) {
        Write-Host "  Found AMD GPU: $($gpu.Name)" -ForegroundColor Green
    }
    Write-Host "  Ollama on Windows supports AMD GPUs via ROCm (RX 6000+ / RX 7000+)." -ForegroundColor White
    Write-Host "  Ensure you have the latest AMD Radeon Software drivers installed." -ForegroundColor White
    Write-Host "  Ollama will auto-detect the GPU - no extra configuration needed." -ForegroundColor White
} else {
    $allGpus = Get-WmiObject Win32_VideoController
    Write-Host "  No AMD GPU detected. Available graphics adapters:" -ForegroundColor Yellow
    foreach ($gpu in $allGpus) {
        Write-Host "    - $($gpu.Name)" -ForegroundColor White
    }
}

# ── 5. Pull default model ──────────────────────────────────────────────────
Write-Host ""
Write-Host "[5/5] Pulling default model (qwen2.5-coder:7b)..." -ForegroundColor Yellow
Write-Host "  This may take a few minutes on first run." -ForegroundColor White

try {
    & ollama pull qwen2.5-coder:7b
    Write-Host "  Model ready." -ForegroundColor Green
} catch {
    Write-Host "  WARNING: Model pull failed. Make sure Ollama is running." -ForegroundColor Red
    Write-Host "  Start Ollama from the system tray, then run: ollama pull qwen2.5-coder:7b" -ForegroundColor White
}

# ── Print LAN IPs ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Done! Your Windows machine LAN IPs:" -ForegroundColor Cyan
Write-Host ""

$ips = Get-NetIPAddress -AddressFamily IPv4 |
       Where-Object { $_.IPAddress -notmatch "^127\." -and $_.IPAddress -notmatch "^169\." } |
       Select-Object -ExpandProperty IPAddress

foreach ($ip in $ips) {
    Write-Host "  http://${ip}:11434" -ForegroundColor Green
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Restart Ollama (right-click tray icon -> Quit, then relaunch)" -ForegroundColor White
Write-Host "  2. On the Linux machine, set OLLAMA_HOST in .env to one of the URLs above" -ForegroundColor White
Write-Host "  3. Test connectivity: make test-ollama  (from the Linux repo)" -ForegroundColor White
Write-Host ""
Write-Host "To pull more models later:" -ForegroundColor Cyan
Write-Host "  ollama pull qwen3:30b-a3b" -ForegroundColor White
Write-Host "  ollama pull kimi-k2.5:cloud   # cloud model, no download needed" -ForegroundColor White
Write-Host "  ollama list                   # show all downloaded models" -ForegroundColor White
Write-Host ""
