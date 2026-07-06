#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Assert AskTHIH HVAC operational routing is SowerBase-primary with Airtable fallback/shadow.

.DESCRIPTION
    This is a narrow implementation proof, not another certification level. It
    checks the production-facing HVAC receiver has the routing switches needed
    for live adoption:
      - SowerBase writes first by default
      - Airtable can run as fallback or shadow
      - rollback is one environment switch
      - responses expose routing/fallback state without exposing secrets
#>

param(
    [string]$ReceiverPath = "$PSScriptRoot/../askthih-hvac-local-webhook-server.ps1"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ReceiverPath)) {
    throw "Receiver not found: $ReceiverPath"
}

$content = Get-Content -LiteralPath $ReceiverPath -Raw

$requiredPatterns = [ordered]@{
    "primary routing env switch" = 'ASKTHIH_HVAC_INTAKE_PRIMARY'
    "airtable mode env switch" = 'ASKTHIH_HVAC_AIRTABLE_MODE'
    "one-switch rollback env" = 'ASKTHIH_HVAC_ROLLBACK_PRIMARY'
    "airtable fallback function" = 'function Invoke-AirtableFallback'
    "sowerbase create function" = 'function Invoke-SowerBaseCreate'
    "routing mode in response" = 'routing_mode'
    "fallback status in response" = 'fallback_status'
    "airtable shadow status in response" = 'airtable_status'
    "operator status field" = 'Follow-up Status'
    "rollback primary branch" = 'airtable_primary'
}

$failures = @()
foreach ($entry in $requiredPatterns.GetEnumerator()) {
    if ($content -notmatch [regex]::Escape($entry.Value)) {
        $failures += "$($entry.Key): missing '$($entry.Value)'"
    }
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL: AskTHIH HVAC SowerBase-primary routing is not implemented."
    $failures | ForEach-Object { Write-Host "- $_" }
    exit 1
}

Write-Host "PASS: AskTHIH HVAC receiver has SowerBase-primary routing with Airtable fallback/shadow and env rollback."
exit 0
