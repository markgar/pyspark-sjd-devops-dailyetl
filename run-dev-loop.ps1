# run-dev-loop.ps1 — Run dev-loop with project defaults
param(
    [string]$Model = 'claude-opus-4.6'
)

pwsh /opt/dev-loop/dev-loop.ps1 `
    -SpecsDir ./daily-etl-specs `
    -ProjectDir . `
    -BuildAgent sjd-builder `
    -Model $Model
