# reset-to-clean-slate.ps1 — Reset repo to the clean-slate tag
# Restores all tracked files, removes untracked files, and purges gitignored artifacts.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Push-Location $PSScriptRoot
try {
    # Verify the tag exists
    $tag = git tag -l 'clean-slate'
    if (-not $tag) { throw "Tag 'clean-slate' not found." }

    # Restore tracked files to tag state
    git checkout clean-slate -- .

    # Remove untracked files (not gitignored)
    git clean -fd

    # Remove gitignored build artifacts
    git clean -fdX

    Write-Host 'Reset complete. Repo matches clean-slate tag.' -ForegroundColor Green
}
finally {
    Pop-Location
}
