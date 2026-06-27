#!/usr/bin/env pwsh
<#
.SYNOPSIS
    AskTHIH HVAC Staging Credential Preflight

.DESCRIPTION
    Validates that all required staging credentials and configurations are in place.
    Tests SowerBase API connectivity and Intake Submissions table accessibility.
    Does NOT print secret values.
    Exits 0 only if all checks pass.

.PARAMETER OutputLog
    Path to output log file (optional)

.EXAMPLE
    ./askthih-hvac-staging-preflight.ps1
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) { Write-Host "Preflight passed" }
#>

param(
    [string]$OutputLog = "$PSScriptRoot/../backups/STAGING_PREFLIGHT_LOG.txt"
)

# ============================================================================
# Setup
# ============================================================================

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $OutputLog -Value $line -ErrorAction SilentlyContinue
}

Write-Log "AskTHIH HVAC Staging Credential Preflight Started"

# ============================================================================
# Credential Validation
# ============================================================================

Write-Log "Validating required environment variables..."

$credentialsMissing = $false

# Check SOWERBASE_BASE_URL
if ([string]::IsNullOrEmpty($env:SOWERBASE_BASE_URL)) {
    Write-Log "ERROR: SOWERBASE_BASE_URL not set" "ERROR"
    $credentialsMissing = $true
} else {
    Write-Log "✓ SOWERBASE_BASE_URL configured (value redacted)" "DEBUG"
    if (-not $env:SOWERBASE_BASE_URL.StartsWith("https://")) {
        Write-Log "ERROR: SOWERBASE_BASE_URL must use HTTPS" "ERROR"
        exit 1
    }
}

# Check SOWERBASE_API_TOKEN
if ([string]::IsNullOrEmpty($env:SOWERBASE_API_TOKEN)) {
    Write-Log "ERROR: SOWERBASE_API_TOKEN not set" "ERROR"
    $credentialsMissing = $true
} else {
    Write-Log "✓ SOWERBASE_API_TOKEN configured (value redacted)" "DEBUG"
    if ($env:SOWERBASE_API_TOKEN.Length -lt 10) {
        Write-Log "ERROR: SOWERBASE_API_TOKEN appears too short" "ERROR"
        exit 1
    }
}

# Check SOWERBASE_INTAKE_TABLE_ID
if ([string]::IsNullOrEmpty($env:SOWERBASE_INTAKE_TABLE_ID)) {
    Write-Log "ERROR: SOWERBASE_INTAKE_TABLE_ID not set" "ERROR"
    $credentialsMissing = $true
} else {
    Write-Log "✓ SOWERBASE_INTAKE_TABLE_ID configured (value redacted)" "DEBUG"
}

# Check ASKTHIH_WEBHOOK_SECRET
if ([string]::IsNullOrEmpty($env:ASKTHIH_WEBHOOK_SECRET)) {
    Write-Log "ERROR: ASKTHIH_WEBHOOK_SECRET not set" "ERROR"
    $credentialsMissing = $true
} else {
    Write-Log "✓ ASKTHIH_WEBHOOK_SECRET configured (value redacted)" "DEBUG"
    if ($env:ASKTHIH_WEBHOOK_SECRET.Length -lt 32) {
        Write-Log "ERROR: ASKTHIH_WEBHOOK_SECRET should be 32+ bytes (consider regenerating)" "ERROR"
        exit 1
    }
}

if ($credentialsMissing) {
    Write-Log "ERROR: One or more required credentials are missing" "ERROR"
    Write-Log "Required: SOWERBASE_BASE_URL, SOWERBASE_API_TOKEN, SOWERBASE_INTAKE_TABLE_ID, ASKTHIH_WEBHOOK_SECRET" "ERROR"
    Write-Log "========================================" "INFO"
    Write-Log "Preflight Status: FAILED (Missing Credentials)" "ERROR"
    Write-Log "========================================" "INFO"
    exit 1
}

Write-Log "✓ All required credentials present"

# ============================================================================
# SowerBase API Connectivity
# ============================================================================

Write-Log "Testing SowerBase API connectivity..."

try {
    $apiUrl = "$($env:SOWERBASE_BASE_URL)/api/v2/db/meta/tables"

    $headers = @{
        "Authorization" = "Bearer $($env:SOWERBASE_API_TOKEN)"
        "Content-Type" = "application/json"
    }

    Write-Log "Connecting to: $($env:SOWERBASE_BASE_URL) (token redacted)" "DEBUG"

    $response = Invoke-WebRequest -Uri $apiUrl -Method GET -Headers $headers -TimeoutSec 10 -ErrorAction Stop

    if ($response.StatusCode -eq 200) {
        Write-Log "✓ SowerBase API reachable" "SUCCESS"
        Write-Log "✓ Authentication successful (Bearer token accepted)" "SUCCESS"
    } else {
        Write-Log "ERROR: Unexpected response code $($response.StatusCode)" "ERROR"
        exit 1
    }

} catch {
    Write-Log "ERROR: Failed to connect to SowerBase API: $_" "ERROR"
    Write-Log "Verify SOWERBASE_BASE_URL and SOWERBASE_API_TOKEN are correct" "ERROR"
    exit 1
}

# ============================================================================
# Intake Submissions Table Verification
# ============================================================================

Write-Log "Verifying Intake Submissions table is accessible..."

try {
    $tableUrl = "$($env:SOWERBASE_BASE_URL)/api/v2/db/data/noco/nocodb/$($env:SOWERBASE_INTAKE_TABLE_ID)"

    $headers = @{
        "Authorization" = "Bearer $($env:SOWERBASE_API_TOKEN)"
        "Content-Type" = "application/json"
    }

    Write-Log "Testing table access (ID redacted)" "DEBUG"

    $response = Invoke-WebRequest -Uri $tableUrl -Method GET -Headers $headers -TimeoutSec 10 -ErrorAction Stop

    if ($response.StatusCode -eq 200) {
        Write-Log "✓ Intake Submissions table is accessible" "SUCCESS"
        Write-Log "✓ Can read from table" "SUCCESS"
    } else {
        Write-Log "ERROR: Unexpected response code $($response.StatusCode)" "ERROR"
        exit 1
    }

} catch {
    Write-Log "ERROR: Failed to access Intake Submissions table: $_" "ERROR"
    Write-Log "Verify SOWERBASE_INTAKE_TABLE_ID is correct" "ERROR"
    exit 1
}

# ============================================================================
# Configuration Validation
# ============================================================================

Write-Log "Validating configuration..."

# Check webhook port
if ([string]::IsNullOrEmpty($env:ASKTHIH_WEBHOOK_PORT)) {
    Write-Log "ℹ ASKTHIH_WEBHOOK_PORT not set, using default 8787" "INFO"
    $env:ASKTHIH_WEBHOOK_PORT = 8787
}

$port = [int]$env:ASKTHIH_WEBHOOK_PORT
if ($port -lt 1024 -or $port -gt 65535) {
    Write-Log "ERROR: ASKTHIH_WEBHOOK_PORT must be 1024-65535, got $port" "ERROR"
    exit 1
}

Write-Log "✓ Webhook port configured: $port" "DEBUG"

# Check CORS origins
if ([string]::IsNullOrEmpty($env:ALLOWED_ORIGINS)) {
    Write-Log "WARNING: ALLOWED_ORIGINS not set, no CORS restriction" "WARN"
} else {
    Write-Log "✓ CORS origins configured (value redacted)" "DEBUG"
}

# ============================================================================
# Summary
# ============================================================================

Write-Log "========================================" "INFO"
Write-Log "Preflight Status: PASSED" "SUCCESS"
Write-Log "========================================" "INFO"
Write-Log "✓ All credentials present" "SUCCESS"
Write-Log "✓ SowerBase API reachable" "SUCCESS"
Write-Log "✓ Intake Submissions table accessible" "SUCCESS"
Write-Log "✓ Configuration valid" "SUCCESS"
Write-Log "" "INFO"
Write-Log "Next step: Deploy webhook server and execute staging test" "INFO"
Write-Log "Staging test record expected: ID 6" "INFO"
Write-Log "Test payload: TEST HVAC Public Cutover - SowerBase" "INFO"
Write-Log "Audit log: $OutputLog" "INFO"

exit 0
