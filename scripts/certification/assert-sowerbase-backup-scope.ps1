<#
.SYNOPSIS
    Static guardrail for SowerBase PostgreSQL backup scope.

.DESCRIPTION
    Verifies that the backup script does not restrict pg_dump or validation
    queries to the public schema only. This check is intentionally static so it
    can run before the isolated Level 2B restore proof.
#>

param(
    [string]$BackupScriptPath = (Join-Path $PSScriptRoot "..\thih-backup-sowerbase.ps1")
)

$resolvedPath = Resolve-Path -LiteralPath $BackupScriptPath -ErrorAction Stop
$scriptText = Get-Content -LiteralPath $resolvedPath -Raw

$failures = @()

if ($scriptText -match '(?m)^\s*--schema(?:=|\s)' -or $scriptText -match '(?m)^\s*-n\s+') {
    $failures += "PostgreSQL pg_dump must not restrict the backup to a single schema."
}

if ($scriptText -match "sequence_schema\s*=\s*'public'") {
    $failures += "Sequence discovery must not be limited to the public schema."
}

if ($scriptText -notmatch "pg_namespace") {
    $failures += "Backup validation must inspect non-system PostgreSQL schemas."
}

if ($scriptText -notmatch "CREATE SCHEMA") {
    $failures += "Dump validation must check for schema definitions from non-public NocoDB user-data schemas."
}

if ($failures.Count -gt 0) {
    Write-Host "SowerBase backup scope guard failed:" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host " - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "SowerBase backup scope guard passed."
exit 0
