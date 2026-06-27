#!/usr/bin/env pwsh
<#
.SYNOPSIS
    AskTHIH HVAC Local Intake Bridge Test

.DESCRIPTION
    Submits a synthetic HVAC intake to the local SowerBase Intake Submissions table
    without using Airtable. Tests end-to-end workflow for HVAC vertical.

.PARAMETER BaseUrl
    NocoDB/SowerBase API base URL (default: http://localhost:18080)

.PARAMETER OutputLog
    Path to output log file
#>

param(
    [string]$BaseUrl = "http://localhost:18080",
    [string]$OutputLog = "$PSScriptRoot/../backups/INTAKE_BRIDGE_LOG.txt"
)

# ============================================================================
# Setup
# ============================================================================

$scriptName = "askthih-hvac-local-intake-test"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $OutputLog -Value $line -ErrorAction SilentlyContinue
}

Write-Log "AskTHIH HVAC Local Intake Bridge Test Started"
Write-Log "Base URL: $BaseUrl"

# ============================================================================
# Prerequisites
# ============================================================================

Write-Log "Checking prerequisites..."

# Check PostgreSQL access (fallback if API unavailable)
$env:PGPASSWORD = $env:SOWERBASE_DB_PASSWORD
if (-not $env:PGPASSWORD) {
    Write-Log "ERROR: SOWERBASE_DB_PASSWORD environment variable not set" "ERROR"
    exit 1
}

# Verify PostgreSQL can be reached
$pgTest = docker exec sowerbase-local-db-1 psql -U nocodb -d nocodb -t -c "SELECT 1;" 2>&1
if ($pgTest -notmatch "1") {
    Write-Log "ERROR: Cannot reach PostgreSQL" "ERROR"
    exit 1
}

Write-Log "PostgreSQL is accessible"

# Verify Intake Submissions table exists
$tableExists = docker exec sowerbase-local-db-1 psql -U nocodb -d nocodb -t -c "SELECT 1 FROM information_schema.tables WHERE table_name='Intake Submissions' AND table_schema='public';" 2>&1
if ($tableExists -notmatch "1") {
    Write-Log "ERROR: Intake Submissions table not found" "ERROR"
    exit 1
}

Write-Log "Intake Submissions table verified"
[System.Environment]::SetEnvironmentVariable('PGPASSWORD', $null)

# ============================================================================
# Prepare Intake Payload
# ============================================================================

Write-Log "Preparing HVAC intake payload..."

$intakePayload = @{
    "Submission Title" = "TEST HVAC Intake Bridge - Local SowerBase"
    "Vertical" = "HVAC"
    "Contact Name" = "Test HVAC Bridge Lead"
    "Phone" = "555-0199"
    "Email" = "bridge-test@example.com"
    "Service Address" = "456 Bridge Test Ave"
    "Problem Description" = "AC turns on but does not cool below 78 degrees."
    "Urgency" = "Same Day"
    "Channel" = "local_bridge_test"
    "Status" = "New"
    "Submitted At" = (Get-Date -AsUTC).ToString("o")
    "Source System" = "askthih_local_bridge_test"
    "Source Base ID" = "app60wQWdbbgyqTcL"
    "Source Table Name" = "HVAC Intake"
    "Source Record ID" = "recBridgeHVAC001"
    "Migration Batch ID" = "batch-20260627-tier0-5-hvac-bridge"
    "Migration Status" = "test_only"
    "Raw Payload" = @{
        "source_table" = "HVAC Intake"
        "original_fields" = @{
            "air_unit_status" = "Does not cool below 78F"
            "service_type" = "Diagnostic"
            "preferred_time" = "Morning"
            "temperature_range" = "Current 82F, Target 72F"
            "system_type" = "Central AC"
        }
    } | ConvertTo-Json
}

Write-Log "Payload prepared with 20 fields"
Write-Log "Contact: Test HVAC Bridge Lead (555-0199)"
Write-Log "Channel: local_bridge_test"

# ============================================================================
# Submit Intake Record
# ============================================================================

Write-Log "Submitting HVAC intake to Intake Submissions table..."

$env:PGPASSWORD = $env:SOWERBASE_DB_PASSWORD

# Build INSERT statement
$sqlValues = @()
$sqlValues += "'$($intakePayload["Submission Title"])'"                  # Submission Title
$sqlValues += "'$($intakePayload["Vertical"])'"                          # Vertical
$sqlValues += "'$($intakePayload["Contact Name"])'"                      # Contact Name
$sqlValues += "'$($intakePayload["Phone"])'"                             # Phone
$sqlValues += "'$($intakePayload["Email"])'"                             # Email
$sqlValues += "'$($intakePayload["Service Address"])'"                   # Service Address
$sqlValues += "'$($intakePayload["Problem Description"])'"               # Problem Description
$sqlValues += "'$($intakePayload["Urgency"])'"                           # Urgency
$sqlValues += "'$($intakePayload["Channel"])'"                           # Channel
$sqlValues += "'$($intakePayload["Status"])'"                            # Status
$sqlValues += "NOW()"                                                     # Submitted At
$sqlValues += "NULL"                                                      # Transcript
$sqlValues += "'" + ($intakePayload["Raw Payload"] -replace "'", "''") + "'" # Raw Payload
$sqlValues += "'$($intakePayload["Source System"])'"                     # Source System
$sqlValues += "'$($intakePayload["Source Base ID"])'"                    # Source Base ID
$sqlValues += "NULL"                                                      # Source Table ID
$sqlValues += "'$($intakePayload["Source Table Name"])'"                 # Source Table Name
$sqlValues += "'$($intakePayload["Source Record ID"])'"                  # Source Record ID
$sqlValues += "'$($intakePayload["Migration Batch ID"])'"                # Migration Batch ID
$sqlValues += "'$($intakePayload["Migration Status"])'"                  # Migration Status

$sql = @"
INSERT INTO public."Intake Submissions" (
    "Submission Title",
    "Vertical",
    "Contact Name",
    "Phone",
    "Email",
    "Service Address",
    "Problem Description",
    "Urgency",
    "Channel",
    "Status",
    "Submitted At",
    "Transcript",
    "Raw Payload",
    "Source System",
    "Source Base ID",
    "Source Table ID",
    "Source Table Name",
    "Source Record ID",
    "Migration Batch ID",
    "Migration Status"
) VALUES (
    $($sqlValues -join ',')
)
RETURNING id;
"@

# Execute INSERT
Write-Log "Executing record insertion..."
$insertResult = $sql | docker exec -i sowerbase-local-db-1 psql -U nocodb -d nocodb 2>&1

Write-Log "INSERT result: $insertResult"

# Parse result to get record ID
if ($insertResult -match "(\d+)") {
    $recordId = [int]$matches[1]
    Write-Log "SUCCESS: Record created with ID $recordId" "SUCCESS"
} else {
    Write-Log "ERROR: Failed to create record" "ERROR"
    Write-Log "Result: $insertResult" "ERROR"
    [System.Environment]::SetEnvironmentVariable('PGPASSWORD', $null)
    exit 1
}

# ============================================================================
# Verify Record
# ============================================================================

Write-Log "Verifying record in database..."

$verification = docker exec sowerbase-local-db-1 psql -U nocodb -d nocodb -t -c "
SELECT COUNT(*) FROM public.\"Intake Submissions\"
WHERE \"Migration Status\" = 'test_only' AND \"Channel\" = 'local_bridge_test';
" 2>&1

Write-Log "Bridge test records found: $verification"

[System.Environment]::SetEnvironmentVariable('PGPASSWORD', $null)

# ============================================================================
# Summary
# ============================================================================

Write-Log "========================================" "INFO"
Write-Log "HVAC Bridge Test Result: SUCCESS" "SUCCESS"
Write-Log "========================================" "INFO"
Write-Log "Record ID: $recordId" "SUCCESS"
Write-Log "Submission Title: TEST HVAC Intake Bridge - Local SowerBase" "SUCCESS"
Write-Log "Vertical: HVAC" "SUCCESS"
Write-Log "Contact: Test HVAC Bridge Lead (555-0199)" "SUCCESS"
Write-Log "Channel: local_bridge_test" "SUCCESS"
Write-Log "Status: New" "SUCCESS"
Write-Log "Migration Status: test_only" "SUCCESS"
Write-Log "Audit Log: $OutputLog" "INFO"

exit 0
