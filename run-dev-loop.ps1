# run-dev-loop.ps1 — Run dev-loop with project defaults
param(
    [string]$Model = 'claude-opus-4.6',
    [string]$BuildAgent = 'sjd-builder'
)

$buildAgentArgs = @{}
if ($BuildAgent) { $buildAgentArgs['BuildAgent'] = $BuildAgent }

pwsh /opt/dev-loop/dev-loop.ps1 `
    -SpecsDir ./daily-etl-specs `
    -ProjectDir . `
    -Model $Model `
    @buildAgentArgs
