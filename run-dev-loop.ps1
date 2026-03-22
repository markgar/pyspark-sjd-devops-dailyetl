# run-dev-loop.ps1 — Run dev-loop with project defaults
param(
    [string]$Model = 'claude-opus-4.6',
    [string]$BuildAgent = 'sjd-builder',
    [string]$PlanEvalAgent = 'sjd-plan-eval',
    [string]$Resume
)

# --- Pre-flight checks ---
$ErrorActionPreference = 'Stop'

# 1. Azure login check
Write-Host '  Checking Azure login...' -NoNewline
$azCheck = az account show --query "user.name" -o tsv 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ' FAIL' -ForegroundColor Red
    Write-Error "Not logged in to Azure. Run 'az login --use-device-code' first."
}
Write-Host " OK ($azCheck)" -ForegroundColor Green

# 2. Source DB reachability check
$sqlServer = 'adventureworksltmg.database.windows.net'
Write-Host "  Checking source DB ($sqlServer:1433)..." -NoNewline
$tcp = [System.Net.Sockets.TcpClient]::new()
try {
    $tcp.ConnectAsync($sqlServer, 1433).Wait(5000) | Out-Null
    if (-not $tcp.Connected) { throw 'timeout' }
    Write-Host ' OK' -ForegroundColor Green
}
catch {
    Write-Host ' FAIL' -ForegroundColor Red
    Write-Error "Cannot reach $sqlServer on port 1433. Check network/firewall."
}
finally {
    $tcp.Dispose()
}

$ErrorActionPreference = 'Continue'

# --- Launch dev-loop ---
$agentArgs = @{}
if ($BuildAgent) { $agentArgs['BuildAgent'] = $BuildAgent }
if ($PlanEvalAgent) { $agentArgs['PlanEvalAgent'] = $PlanEvalAgent }
if ($Resume) { $agentArgs['Resume'] = $Resume }

pwsh /opt/dev-loop/dev-loop.ps1 `
    -SpecsDir ./daily-etl-specs `
    -ProjectDir . `
    -Model $Model `
    @agentArgs
