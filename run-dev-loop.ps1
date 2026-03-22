# run-dev-loop.ps1 — Run dev-loop with project defaults
param(
    [string]$Model = 'claude-opus-4.6',
    [string]$BuildAgent = 'sjd-builder',
    [string]$PlanEvalAgent = 'sjd-plan-eval',
    [string]$Resume,
    [int]$PauseBetweenSpecs = 10
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

# 2. Source DB connectivity check (authenticates + queries)
$sqlServer = 'adventureworksltmg.database.windows.net'
$sqlServerName = 'adventureworksltmg'
$sqlRg = 'sql'
Write-Host "  Checking source DB ($sqlServer)..." -NoNewline
$sqlResult = sqlcmd -S $sqlServer -d WideWorldImporters --authentication-method ActiveDirectoryDefault -Q "SELECT 1" -h -1 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ' FAIL' -ForegroundColor Red
    $isDenyPublic = "$sqlResult" -match 'Deny Public Network Access'
    $isIpBlocked  = "$sqlResult" -match 'is not allowed to access the server'
    if ($isDenyPublic -or $isIpBlocked) {
        if ($isDenyPublic) {
            Write-Host "  Public network access is denied on $sqlServerName." -ForegroundColor Yellow
        } else {
            Write-Host "  IP not in firewall rules for $sqlServerName." -ForegroundColor Yellow
        }
        $fix = Read-Host "  Add your current IP to the firewall? (y/n)"
        if ($fix -eq 'y') {
            if ($isDenyPublic) {
                Write-Host '  Enabling public network access...' -NoNewline
                az sql server update --name $sqlServerName --resource-group $sqlRg --set publicNetworkAccess=Enabled -o none 2>&1 | Out-Null
                Write-Host ' done' -ForegroundColor Green
            }

            Write-Host '  Adding firewall rule for current IP...' -NoNewline
            $myIp = (Invoke-RestMethod -Uri 'https://api.ipify.org')
            az sql server firewall-rule create --server $sqlServerName --resource-group $sqlRg `
                --name "devcontainer-$(Get-Date -Format 'yyyyMMdd')" `
                --start-ip-address $myIp --end-ip-address $myIp -o none 2>&1 | Out-Null
            Write-Host " done ($myIp)" -ForegroundColor Green

            Write-Host '  Retesting connection...' -NoNewline
            Start-Sleep -Seconds 5
            $sqlResult = sqlcmd -S $sqlServer -d WideWorldImporters --authentication-method ActiveDirectoryDefault -Q "SELECT 1" -h -1 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host ' STILL FAILING' -ForegroundColor Red
                Write-Error "Connection still failing after fix. Detail: $sqlResult"
            }
            Write-Host ' OK' -ForegroundColor Green
        }
        else {
            Write-Error "Cannot proceed without source DB access."
        }
    }
    else {
        Write-Error "Cannot connect to $sqlServer. Detail: $sqlResult"
    }
}
else {
    Write-Host ' OK' -ForegroundColor Green
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
    -PauseBetweenSpecs $PauseBetweenSpecs `
    @agentArgs
