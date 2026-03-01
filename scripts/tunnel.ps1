# ─────────────────────────────────────────────────────────────────────────────
# Ollama SSH Reverse Tunnel — Windows (PowerShell)
#
# Opens a persistent reverse SSH tunnel so the OpenClaw agent on your VPS
# can reach Ollama running on this Windows machine.
#
# Usage:
#   .\scripts\tunnel.ps1 -VPS ubuntu@YOUR_VPS_IP
#
# If execution policy blocks this, use tunnel.bat instead, or run:
#   powershell -ExecutionPolicy Bypass -File .\scripts\tunnel.ps1 -VPS ubuntu@1.2.3.4
#
# Requires: Windows 10+ (built-in OpenSSH client)
# Keep this window open while using the agent.
# ─────────────────────────────────────────────────────────────────────────────

param(
    [Parameter(Mandatory = $true, HelpMessage = "VPS target in user@host format")]
    [string]$VPS,

    [Parameter(HelpMessage = "Ollama port (default: 11434)")]
    [int]$OllamaPort = 11434
)

$ErrorActionPreference = "Stop"
$LocalOllama = "http://localhost:$OllamaPort"

# ── Check Ollama ──────────────────────────────────────────────────────────
Write-Host "[tunnel] Checking Ollama at $LocalOllama..."
try {
    $response = Invoke-RestMethod -Uri "$LocalOllama/api/tags" -TimeoutSec 3
    Write-Host "[tunnel] Ollama: reachable ✓"
    if ($response.models) {
        Write-Host "[tunnel] Available models:"
        foreach ($model in $response.models) {
            $sizeGb = [math]::Round($model.size / 1GB, 1)
            Write-Host "  - $($model.name) ($sizeGb GB)"
        }
    }
} catch {
    Write-Error "[tunnel] Ollama is not running at $LocalOllama. Start Ollama first."
    exit 1
}

# ── Open tunnel ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[tunnel] Opening SSH reverse tunnel:"
Write-Host "[tunnel]   VPS port $OllamaPort -> localhost:$OllamaPort"
Write-Host "[tunnel]   Target: $VPS"
Write-Host "[tunnel] Press Ctrl-C to stop."
Write-Host ""

$sshArgs = @(
    "-N",
    "-R", "0.0.0.0:${OllamaPort}:localhost:${OllamaPort}",
    "-o", "ServerAliveInterval=30",
    "-o", "ServerAliveCountMax=5",
    "-o", "ExitOnForwardFailure=yes",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "ConnectTimeout=10",
    $VPS
)

try {
    & ssh @sshArgs
} catch {
    Write-Error "[tunnel] SSH tunnel failed: $_"
    Write-Host "[tunnel] Check VPS connectivity and that GatewayPorts=yes in /etc/ssh/sshd_config on VPS."
    exit 1
}
