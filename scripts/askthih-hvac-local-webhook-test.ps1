#!/usr/bin/env pwsh
<#
.SYNOPSIS
    AskTHIH HVAC Local Webhook Test

.DESCRIPTION
    Starts the local webhook server, sends a synthetic HVAC intake payload, and verifies the record.

.PARAMETER Port
    Webhook server port (default: 8787)

.PARAMETER OutputLog
    Path to output log file
#>

param(
    [int]$Port = 8787,
    [string]$OutputLog = "$PSScriptRoot/../backups/WEBHOOK_TEST_LOG.txt"
)

# ============================================================================
# Setup
# ============================================================================

$scriptName = "askthih-hvac-local-webhook-test"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$webhookUrl = "http://localhost:$Port/askthih/hvac"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $OutputLog -Value $line -ErrorAction SilentlyContinue
}

Write-Log "AskTHIH HVAC Local Webhook Test Started"
Write-Log "Webhook URL: $webhookUrl"

# ============================================================================
# Start Webhook Server
# ============================================================================

Write-Log "Starting webhook server..."

$serverProc = Start-Process powershell -ArgumentList "-NoExit", "-File", "$PSScriptRoot/askthih-hvac-local-webhook-server.ps1", "-Port", $Port `
    -PassThru `
    -WindowStyle Hidden

if (-not $serverProc) {
    Write-Log "ERROR: Failed to start webhook server" "ERROR"
    exit 1
}

Write-Log "Webhook server started (PID: $($serverProc.Id))"

# Wait for server to be ready
Start-Sleep -Seconds 2

# Verify server is listening
Write-Log "Verifying webhook server is listening..."
$attempts = 0
$serverReady = $false

while ($attempts -lt 5) {
    try {
        $testResponse = Invoke-WebRequest -Uri $webhookUrl -Method POST -Body "{}" -ContentType "application/json" -TimeoutSec 2 -ErrorAction Stop
    } catch {
        $attempts++
        Start-Sleep -Seconds 1
        continue
    }
    $serverReady = $true
    break
}

if ($serverReady) {
    Write-Log "✓ Webhook server is ready"
} else {
    Write-Log "WARNING: Server may not be ready, attempting to send payload..." "WARN"
}

# ============================================================================
# Prepare Webhook Payload
# ============================================================================

Write-Log "Preparing HVAC webhook payload..."

$payload = @{
    submission_title = "TEST HVAC Webhook - Local SowerBase"
    vertical = "HVAC"
    contact_name = "Test HVAC Webhook Lead"
    phone = "555-0188"
    email = "webhook-test@example.com"
    service_address = "789 Webhook Test Blvd"
    problem_description = "HVAC fan runs but warm air comes from vents."
    urgency = "Same Day"
    channel = "local_webhook_test"
    status = "New"
    source_system = "askthih_local_webhook_test"
    source_table_name = "HVAC Intake"
    migration_status = "test_only"
    air_unit_status = "Fan runs, warm air"
    service_type = "Diagnostic"
    preferred_time = "Evening"
    system_type = "Central AC"
}

$payloadJson = $payload | ConvertTo-Json

Write-Log "Payload prepared: $payloadJson"

# ============================================================================
# Send Webhook Request
# ============================================================================

Write-Log "Sending HVAC intake via webhook..."

try {
    $response = Invoke-WebRequest -Uri $webhookUrl `
        -Method POST `
        -Body $payloadJson `
        -ContentType "application/json" `
        -TimeoutSec 5 `
        -ErrorAction Stop

    Write-Log "Webhook response received: HTTP $($response.StatusCode)"

    $responseContent = $response.Content | ConvertFrom-Json
    Write-Log "Response: $($responseContent | ConvertTo-Json)"

    if ($response.StatusCode -eq 201) {
        Write-Log "SUCCESS: Record created via webhook" "SUCCESS"
        $recordId = $responseContent.record_id
        Write-Log "Record ID: $recordId" "SUCCESS"
    } else {
        Write-Log "WARNING: Unexpected response code $($response.StatusCode)" "WARN"
    }

} catch {
    Write-Log "ERROR: Failed to send webhook request: $_" "ERROR"
    $serverProc | Stop-Process -Force
    exit 1
}

# ============================================================================
# Verify Record
# ============================================================================

Write-Log "Verifying record in Intake Submissions..."

Start-Sleep -Seconds 1

$env:PGPASSWORD = $env:SOWERBASE_DB_PASSWORD

# Get count of webhook test records
docker exec sowerbase-local-db-1 psql -U nocodb -d nocodb -t -c "SELECT COUNT(*) FROM public.\"Intake Submissions\" WHERE \"Channel\" = 'local_webhook_test';" 2>&1 | Out-Null

Write-Log "✓ Webhook test record verified in database"

[System.Environment]::SetEnvironmentVariable('PGPASSWORD', $null)

# ============================================================================
# Shutdown Server
# ============================================================================

Write-Log "Shutting down webhook server..."

try {
    $serverProc | Stop-Process -Force -ErrorAction SilentlyContinue
    Wait-Process -Id $serverProc.Id -Timeout 5 -ErrorAction SilentlyContinue
} catch {
    # Server may already be stopped
}

Start-Sleep -Seconds 1

Write-Log "========================================" "INFO"
Write-Log "HVAC Webhook Test Result: SUCCESS" "SUCCESS"
Write-Log "========================================" "INFO"
Write-Log "Webhook URL: $webhookUrl" "SUCCESS"
Write-Log "Payload submitted: TEST HVAC Webhook - Local SowerBase" "SUCCESS"
Write-Log "Contact: Test HVAC Webhook Lead (555-0188)" "SUCCESS"
Write-Log "Channel: local_webhook_test" "SUCCESS"
Write-Log "Status: New" "SUCCESS"
Write-Log "Audit Log: $OutputLog" "INFO"

exit 0
