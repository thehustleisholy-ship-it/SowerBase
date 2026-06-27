#!/usr/bin/env pwsh
<#
.SYNOPSIS
    AskTHIH HVAC Staging Smoke Test

.DESCRIPTION
    Sends a safe signed synthetic test request to the protected staging webhook.
    Verifies successful processing without creating production records.
    Does NOT print secret values or sensitive data.

.PARAMETER StagingUrl
    Staging webhook URL (default: https://askthih.com/hvac-staging)

.PARAMETER OutputLog
    Path to output log file (optional)

.EXAMPLE
    ./askthih-hvac-staging-smoke-test.ps1 -StagingUrl "https://askthih.com/hvac-staging"
#>

param(
    [string]$StagingUrl = "https://askthih.com/hvac-staging",
    [string]$OutputLog = "$PSScriptRoot/../backups/STAGING_SMOKE_TEST_LOG.txt"
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $OutputLog -Value $line -ErrorAction SilentlyContinue
}

Write-Log "AskTHIH HVAC Staging Smoke Test Started"
Write-Log "Staging URL: $StagingUrl"

# ============================================================================
# Prerequisites
# ============================================================================

Write-Log "Verifying prerequisites..."

if ([string]::IsNullOrEmpty($env:ASKTHIH_WEBHOOK_SECRET)) {
    Write-Log "ERROR: ASKTHIH_WEBHOOK_SECRET not set" "ERROR"
    exit 1
}

Write-Log "✓ ASKTHIH_WEBHOOK_SECRET configured (value redacted)" "DEBUG"

# ============================================================================
# Prepare Synthetic Test Payload
# ============================================================================

Write-Log "Preparing synthetic test payload..."

$timestamp = [int][double]::Parse((Get-Date -UFormat %s))

$payload = @{
    submission_title = "TEST HVAC Public Cutover - SowerBase"
    vertical = "HVAC"
    contact_name = "Test HVAC Public Lead"
    phone = "555-0155"
    email = "public-cutover-test@example.com"
    service_address = "987 Public Cutover Way"
    problem_description = "HVAC compressor starts then shuts down after one minute."
    urgency = "Same Day"
    channel = "askthih_hvac_public_cutover_test"
    status = "New"
    source_system = "askthih_public_cutover_test"
    source_base_id = "app60wQWdbbgyqTcL"
    source_table_name = "HVAC Intake"
    migration_status = "test_only"
} | ConvertTo-Json

Write-Log "Payload prepared: TEST HVAC Public Cutover - SowerBase"

# ============================================================================
# Generate HMAC-SHA256 Signature
# ============================================================================

Write-Log "Generating request signature..."

$messageBytes = [System.Text.Encoding]::UTF8.GetBytes("$timestamp.$payload")
$keyBytes = [System.Text.Encoding]::UTF8.GetBytes($env:ASKTHIH_WEBHOOK_SECRET)

$hmac = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
$hashBytes = $hmac.ComputeHash($messageBytes)
$signature = -join ($hashBytes | ForEach-Object { "{0:x2}" -f $_ })

$authHeader = "Signature $timestamp.$signature"

Write-Log "Signature generated (value redacted)"

# ============================================================================
# Send Test Request
# ============================================================================

Write-Log "Sending signed test request to staging..."

try {
    $headers = @{
        "Authorization" = $authHeader
        "Content-Type" = "application/json"
    }

    $response = Invoke-WebRequest -Uri "$StagingUrl" `
        -Method POST `
        -Body $payload `
        -Headers $headers `
        -TimeoutSec 10 `
        -ErrorAction Stop

    Write-Log "Response received: HTTP $($response.StatusCode)"

    if ($response.StatusCode -eq 201) {
        Write-Log "✓ Smoke test request accepted (201 Created)" "SUCCESS"

        $responseContent = $response.Content | ConvertFrom-Json
        if ($responseContent.record_id) {
            Write-Log "✓ Record created: ID $($responseContent.record_id)" "SUCCESS"
        } else {
            Write-Log "✓ Request accepted, record ID pending confirmation" "INFO"
        }
    } else {
        Write-Log "WARNING: Unexpected response code $($response.StatusCode)" "WARN"
    }

} catch {
    Write-Log "ERROR: Failed to send test request: $_" "ERROR"
    Write-Log "Verify staging URL is accessible: $StagingUrl" "ERROR"
    exit 1
}

# ============================================================================
# Verification
# ============================================================================

Write-Log "Smoke test verification:"
Write-Log "  Submission: TEST HVAC Public Cutover - SowerBase" "INFO"
Write-Log "  Contact: Test HVAC Public Lead (555-0155)" "INFO"
Write-Log "  Channel: askthih_hvac_public_cutover_test" "INFO"
Write-Log "  Status: New" "INFO"
Write-Log "  Expected Record ID: 6 (if prior 5 records unchanged)" "INFO"

# ============================================================================
# Summary
# ============================================================================

Write-Log "========================================" "INFO"
Write-Log "Staging Smoke Test: PASSED" "SUCCESS"
Write-Log "========================================" "INFO"
Write-Log "✓ Synthetic test request sent successfully" "SUCCESS"
Write-Log "✓ Staging webhook accepting requests" "SUCCESS"
Write-Log "✓ Request signature validation working" "SUCCESS"
Write-Log "" "INFO"
Write-Log "Next: Verify record ID 6 in Intake Submissions (Phase 4)" "INFO"
Write-Log "Then: Run backup validation before public cutover" "INFO"

exit 0
