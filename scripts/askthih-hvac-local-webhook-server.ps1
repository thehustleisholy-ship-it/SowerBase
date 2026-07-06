#!/usr/bin/env pwsh
<#
.SYNOPSIS
    AskTHIH HVAC Local Webhook Server

.DESCRIPTION
    Listens on localhost for HVAC intake webhook payloads and writes them directly to SowerBase
    Intake Submissions table without requiring Airtable.

.PARAMETER Port
    Port to listen on (default: 8787)

.PARAMETER OutputLog
    Path to output log file
#>

param(
    [int]$Port = $(if ($env:ASKTHIH_WEBHOOK_PORT) { [int]$env:ASKTHIH_WEBHOOK_PORT } else { 8787 }),
    [string]$OutputLog = "$PSScriptRoot/../backups/WEBHOOK_SERVER_LOG.txt"
)

# ============================================================================
# Setup
# ============================================================================

$scriptName = "askthih-hvac-local-webhook-server"
$startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $OutputLog -Value $line -ErrorAction SilentlyContinue
}

function Send-JsonResponse {
    param(
        [Parameter(Mandatory = $true)] [System.Net.HttpListenerResponse]$Response,
        [Parameter(Mandatory = $true)] [int]$StatusCode,
        [Parameter(Mandatory = $true)] [hashtable]$Body
    )

    $responseBody = $Body | ConvertTo-Json
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($responseBody)

    $Response.StatusCode = $StatusCode
    $Response.Headers.Add("Content-Type", "application/json")
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.Close()
}

function Get-RecordIdFromApiRecord {
    param($Record)

    foreach ($propertyName in @("id", "Id", "ID")) {
        if ($Record.PSObject.Properties.Name -contains $propertyName) {
            return $Record.$propertyName
        }
    }

    return $null
}

function Find-SowerBaseRecordByChannel {
    param(
        [Parameter(Mandatory = $true)] [string]$ApiUrl,
        [Parameter(Mandatory = $true)] [hashtable]$Headers,
        [Parameter(Mandatory = $true)] [string]$Channel
    )

    $where = [System.Uri]::EscapeDataString("(Channel,eq,$Channel)")
    $lookupUrl = "${ApiUrl}?where=$where&limit=1"

    $lookupResponse = Invoke-WebRequest -Uri $lookupUrl `
        -Method GET `
        -Headers $Headers `
        -TimeoutSec 3 `
        -ErrorAction Stop

    if ($lookupResponse.StatusCode -ne 200) {
        return $null
    }

    $lookupData = $lookupResponse.Content | ConvertFrom-Json
    if ($lookupData.list -and $lookupData.list.Count -gt 0) {
        return $lookupData.list[0]
    }

    if ($lookupData.Count -gt 0) {
        return $lookupData[0]
    }

    return $null
}


function Get-RecordIdFromAirtableRecord {
    param($Record)

    if ($Record -and ($Record.PSObject.Properties.Name -contains "id")) {
        return $Record.id
    }

    return $null
}

function New-AirtableFieldsFromPayload {
    param($Payload)

    $fields = [ordered]@{
        "Name" = $Payload.contact_name
        "phoneNumber" = $Payload.phone
        "Email" = $Payload.email
        "Address" = $Payload.service_address
        "Transcript" = $(if ($Payload.transcript) { $Payload.transcript } else { $Payload.problem_description })
        "System Type" = $(if ($Payload.system_type) { $Payload.system_type } else { "" })
        "System Age" = $(if ($Payload.system_age_years) { $Payload.system_age_years } else { "" })
        "Preferred Service Window" = $(if ($Payload.preferred_service_window) { $Payload.preferred_service_window } else { "" })
        "Preferred Callback Time" = $(if ($Payload.preferred_callback_time) { $Payload.preferred_callback_time } else { "" })
        "Trace ID" = $(if ($Payload.trace_id) { $Payload.trace_id } else { "" })
        "Channel" = $Payload.channel
        "Status" = $Payload.status
        "Raw Payload" = ($Payload | ConvertTo-Json -Depth 12)
    }

    return $fields
}

function Invoke-AirtableFallback {
    param(
        [Parameter(Mandatory = $true)] $Payload,
        [Parameter(Mandatory = $true)] [string]$Mode
    )

    $token = if ($env:AIRTABLE_API_TOKEN) { $env:AIRTABLE_API_TOKEN } else { $env:AIRTABLE_TOKEN }
    $baseId = if ($env:AIRTABLE_BASE_ID) { $env:AIRTABLE_BASE_ID } else { "app60wQWdbbgyqTcL" }
    $tableName = if ($env:AIRTABLE_HVAC_TABLE_NAME) { $env:AIRTABLE_HVAC_TABLE_NAME } else { "HVAC Intake" }

    if ([string]::IsNullOrWhiteSpace($token)) {
        return [pscustomobject]@{
            ok = $false
            status = "unconfigured"
            record_id = $null
            message = "Airtable token not configured"
        }
    }

    $encodedTableName = [System.Uri]::EscapeDataString($tableName)
    $airtableUrl = "https://api.airtable.com/v0/$baseId/$encodedTableName"
    $airtableHeaders = @{
        "Authorization" = "Bearer $token"
        "Content-Type" = "application/json"
    }
    $airtableBody = @{
        records = @(
            @{
                fields = New-AirtableFieldsFromPayload -Payload $Payload
            }
        )
        typecast = $true
    } | ConvertTo-Json -Depth 12

    try {
        $airtableResponse = Invoke-WebRequest -Uri $airtableUrl `
            -Method POST `
            -Headers $airtableHeaders `
            -Body $airtableBody `
            -TimeoutSec 6 `
            -ErrorAction Stop

        $airtableData = $airtableResponse.Content | ConvertFrom-Json
        $recordId = $null
        if ($airtableData.records -and $airtableData.records.Count -gt 0) {
            $recordId = Get-RecordIdFromAirtableRecord -Record $airtableData.records[0]
        }

        return [pscustomobject]@{
            ok = $true
            status = if ($Mode -eq "shadow") { "shadow_created" } else { "fallback_created" }
            record_id = $recordId
            message = "Airtable write accepted"
        }
    } catch {
        return [pscustomobject]@{
            ok = $false
            status = if ($Mode -eq "shadow") { "shadow_failed" } else { "fallback_failed" }
            record_id = $null
            message = $_.Exception.Message
        }
    }
}

function Invoke-SowerBaseCreate {
    param(
        [Parameter(Mandatory = $true)] [hashtable]$ApiPayload,
        [Parameter(Mandatory = $true)] $OriginalPayload
    )

    $apiToken = $env:SOWERBASE_API_TOKEN
    if (-not $apiToken) {
        return [pscustomobject]@{
            ok = $false
            status = "configuration_error"
            record_id = $null
            method = "sowerbase-api"
            message = "SOWERBASE_API_TOKEN required"
        }
    }

    $baseUrl = $env:SOWERBASE_BASE_URL
    $tableId = $env:SOWERBASE_INTAKE_TABLE_ID
    $apiUrl = "$baseUrl/api/v2/tables/$tableId/records"
    $apiHeaders = @{
        "Authorization" = "Bearer $apiToken"
        "Content-Type" = "application/json"
        "xc-auth" = $apiToken
    }

    try {
        $response_api = Invoke-WebRequest -Uri $apiUrl `
            -Method POST `
            -Headers $apiHeaders `
            -Body ($ApiPayload | ConvertTo-Json -Depth 12) `
            -TimeoutSec 6 `
            -ErrorAction Stop

        if ($response_api.StatusCode -eq 200 -or $response_api.StatusCode -eq 201) {
            $responseData = $response_api.Content | ConvertFrom-Json
            return [pscustomobject]@{
                ok = $true
                status = "created"
                record_id = $responseData.id
                method = "sowerbase-api"
                message = "SowerBase write accepted"
            }
        }

        return [pscustomobject]@{
            ok = $false
            status = "unexpected_status"
            record_id = $null
            method = "sowerbase-api"
            message = "Unexpected SowerBase API status: $($response_api.StatusCode)"
        }
    } catch {
        try {
            Write-Log "Attempting recovery read-back by channel: $($OriginalPayload.channel)" "INFO"
            $recoveredRecord = Find-SowerBaseRecordByChannel -ApiUrl $apiUrl -Headers $apiHeaders -Channel $OriginalPayload.channel
            if ($recoveredRecord) {
                $recordId = Get-RecordIdFromApiRecord -Record $recoveredRecord
                return [pscustomobject]@{
                    ok = $true
                    status = "recovered_readback"
                    record_id = $recordId
                    method = "recovered_readback"
                    message = "Found record after create failure"
                }
            }
        } catch {
            Write-Log "ERROR: Recovery read-back failed: $($_.Exception.Message)" "ERROR"
        }

        return [pscustomobject]@{
            ok = $false
            status = "create_failed"
            record_id = $null
            method = "sowerbase-api"
            message = $_.Exception.Message
        }
    }
}

function ConvertTo-Hex {
    param([byte[]]$Bytes)
    return -join ($Bytes | ForEach-Object { "{0:x2}" -f $_ })
}

function Test-FixedTimeHexEquals {
    param(
        [Parameter(Mandatory = $true)] [string]$ExpectedHex,
        [Parameter(Mandatory = $true)] [string]$ActualHex
    )

    if ($ExpectedHex.Length -ne $ActualHex.Length) { return $false }

    try {
        $expectedBytes = [Convert]::FromHexString($ExpectedHex)
        $actualBytes = [Convert]::FromHexString($ActualHex)
        return [System.Security.Cryptography.CryptographicOperations]::FixedTimeEquals($expectedBytes, $actualBytes)
    } catch {
        return $false
    }
}

function Test-WebhookSignature {
    param(
        [AllowEmptyString()] [string]$AuthorizationHeader,
        [Parameter(Mandatory = $true)] [string]$Body,
        [Parameter(Mandatory = $true)] [string]$Secret,
        [Parameter(Mandatory = $true)] [int]$ToleranceSeconds,
        [Parameter(Mandatory = $true)] [hashtable]$ReplayCache
    )

    if ([string]::IsNullOrWhiteSpace($AuthorizationHeader)) {
        return [pscustomobject]@{ ok = $false; status = 401; reason = "missing_signature" }
    }

    $match = [regex]::Match($AuthorizationHeader, '^Signature\s+(\d{10,})\.([0-9a-fA-F]{64})$')
    if (-not $match.Success) {
        return [pscustomobject]@{ ok = $false; status = 401; reason = "malformed_signature" }
    }

    $timestamp = [int64]$match.Groups[1].Value
    $providedSignature = $match.Groups[2].Value.ToLowerInvariant()
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    if ([math]::Abs($now - $timestamp) -gt $ToleranceSeconds) {
        return [pscustomobject]@{ ok = $false; status = 401; reason = "stale_timestamp" }
    }

    $signedPayload = "$timestamp.$Body"
    $hmac = [System.Security.Cryptography.HMACSHA256]::new([System.Text.Encoding]::UTF8.GetBytes($Secret))
    try {
        $expectedSignature = ConvertTo-Hex -Bytes $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($signedPayload))
    } finally {
        $hmac.Dispose()
    }

    if (-not (Test-FixedTimeHexEquals -ExpectedHex $expectedSignature -ActualHex $providedSignature)) {
        return [pscustomobject]@{ ok = $false; status = 401; reason = "bad_signature" }
    }

    $replayKey = "$timestamp.$providedSignature"
    if ($ReplayCache.ContainsKey($replayKey)) {
        return [pscustomobject]@{ ok = $false; status = 409; reason = "replay_detected" }
    }

    $ReplayCache[$replayKey] = $now
    foreach ($key in @($ReplayCache.Keys)) {
        if (($now - [int64]$ReplayCache[$key]) -gt $ToleranceSeconds) {
            $ReplayCache.Remove($key)
        }
    }

    return [pscustomobject]@{ ok = $true; status = 200; reason = "signature_valid" }
}

Write-Log "AskTHIH HVAC Local Webhook Server Starting"
Write-Log "Port: $Port"
Write-Log "Endpoint: http://localhost:$Port/askthih/hvac"

# ============================================================================
# Prerequisites
# ============================================================================

Write-Log "Checking prerequisites..."

# Verify SowerBase API environment variables
$requiredVars = @(
    "SOWERBASE_BASE_URL",
    "SOWERBASE_API_TOKEN",
    "SOWERBASE_INTAKE_TABLE_ID",
    "ASKTHIH_WEBHOOK_SECRET"
)

foreach ($var in $requiredVars) {
    if (-not (Get-Item -Path "env:$var" -ErrorAction SilentlyContinue)) {
        Write-Log "ERROR: $var environment variable not set" "ERROR"
        exit 1
    }
}

Write-Log "SowerBase API environment variables verified"
Write-Log "SOWERBASE_BASE_URL configured (token redacted)" "DEBUG"
$webhookSecret = $env:ASKTHIH_WEBHOOK_SECRET
$authMode = if ($env:ASKTHIH_WEBHOOK_AUTH_MODE) { $env:ASKTHIH_WEBHOOK_AUTH_MODE } else { "signature" }
$signatureToleranceSeconds = if ($env:ASKTHIH_WEBHOOK_SIGNATURE_TOLERANCE_SECONDS) { [int]$env:ASKTHIH_WEBHOOK_SIGNATURE_TOLERANCE_SECONDS } else { 300 }
$signatureReplayCache = @{}
Write-Log "Webhook auth mode: $authMode" "DEBUG"

# ============================================================================
# HTTP Listener Setup
# ============================================================================

Write-Log "Starting HTTP listener on port $Port..."

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Prefixes.Add("http://127.0.0.1:$Port/")

try {
    $listener.Start()
    Write-Log "HTTP listener started successfully"
} catch {
    Write-Log "ERROR: Failed to start HTTP listener: $_" "ERROR"
    exit 1
}

# ============================================================================
# Request Handler Loop
# ============================================================================

Write-Log "Ready to receive webhook requests..."

$requestCount = 0
$shutdown = $false

# Handle Ctrl+C gracefully
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { $shutdown = $true }

while (-not $shutdown) {
    $context = $null
    $request = $null
    $response = $null

    try {
        # Wait for incoming request (with timeout)
        # Use blocking GetContext instead of async to avoid runspace issues
        if ($listener.IsListening) {
            $context = $listener.GetContext()
        } else {
            Start-Sleep -Milliseconds 100
            continue
        }
        $request = $context.Request
        $response = $context.Response

        $requestCount++

        # Log request
        Write-Log "Request #${requestCount}: $($request.HttpMethod) $($request.RawUrl)" "DEBUG"

        # ====================================================================
        # Handle non-POST requests safely (HEAD, GET, OPTIONS, etc.)
        # ====================================================================

        if ($request.HttpMethod -eq "HEAD") {
            Write-Log "HEAD request to $($request.RawUrl) - returning 405" "DEBUG"
            $response.StatusCode = 405
            $response.Close()
            continue
        }

        if ($request.HttpMethod -eq "OPTIONS") {
            Write-Log "OPTIONS preflight request to $($request.RawUrl)" "DEBUG"
            $response.StatusCode = 405
            $response.Headers.Add("Allow", "POST")
            $response.Close()
            continue
        }

        if ($request.HttpMethod -eq "GET") {
            Write-Log "GET request to $($request.RawUrl) - returning 405" "DEBUG"
            $response.StatusCode = 405
            $response.Headers.Add("Content-Type", "application/json")
            $responseBody = @{
                status = "error"
                message = "Method not allowed. Use POST."
            } | ConvertTo-Json
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.Close()
            continue
        }

        # ====================================================================
        # Validate path before processing POST
        # ====================================================================

        if ($request.RawUrl -ne "/askthih/hvac") {
            Write-Log "Rejected unknown path: $($request.RawUrl)" "DEBUG"
            $response.StatusCode = 404
            $response.Headers.Add("Content-Type", "application/json")
            $responseBody = @{
                status = "error"
                message = "Endpoint not found"
            } | ConvertTo-Json
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.Close()
            continue
        }

        # ====================================================================
        # Only POST to /askthih/hvac is processed
        # ====================================================================

        if ($request.HttpMethod -ne "POST") {
            Write-Log "Rejected non-POST request: $($request.HttpMethod)" "DEBUG"
            Send-JsonResponse -Response $response -StatusCode 405 -Body @{
                status = "error"
                message = "Method not allowed. Use POST."
            }
            continue
        }

        if ($request.ContentType -notmatch "^application/json($|;)") {
            Write-Log "Rejected unsupported content type: $($request.ContentType)" "DEBUG"
            Send-JsonResponse -Response $response -StatusCode 415 -Body @{
                status = "error"
                message = "Unsupported media type. Use application/json."
            }
            continue
        }

        # Read request body safely
        $body = ""
        try {
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $body = $reader.ReadToEnd()
            $reader.Dispose()
        } catch {
            Write-Log "ERROR: Failed to read request body: $($_.Exception.Message)" "ERROR"
            $response.StatusCode = 400
            $response.Headers.Add("Content-Type", "application/json")
            $responseBody = @{
                status = "error"
                message = "Failed to read request body"
            } | ConvertTo-Json
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.Close()
            continue
        }

        Write-Log "Request body length: $($body.Length) bytes" "DEBUG"

        if ($authMode -eq "shared-secret") {
            $providedSecret = $request.Headers["X-AskTHIH-Webhook-Secret"]
            if ([string]::IsNullOrWhiteSpace($providedSecret) -or -not [System.String]::Equals($providedSecret, $webhookSecret, [System.StringComparison]::Ordinal)) {
                Write-Log "Rejected unauthorized webhook request" "WARN"
                Send-JsonResponse -Response $response -StatusCode 401 -Body @{
                    status = "error"
                    message = "Unauthorized"
                }
                continue
            }
        } else {
            $signatureResult = Test-WebhookSignature `
                -AuthorizationHeader $request.Headers["Authorization"] `
                -Body $body `
                -Secret $webhookSecret `
                -ToleranceSeconds $signatureToleranceSeconds `
                -ReplayCache $signatureReplayCache

            if (-not $signatureResult.ok) {
                Write-Log "Rejected signed webhook request: $($signatureResult.reason)" "WARN"
                Send-JsonResponse -Response $response -StatusCode $signatureResult.status -Body @{
                    status = "error"
                    message = $(if ($signatureResult.status -eq 409) { "Replay detected" } else { "Unauthorized" })
                }
                continue
            }
        }

        # Parse JSON
        $payload = $null
        try {
            $payload = $body | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Log "ERROR: Invalid JSON payload" "ERROR"
            $response.StatusCode = 400
            $response.Headers.Add("Content-Type", "application/json")
            $responseBody = @{
                status = "error"
                message = "Invalid JSON payload"
            } | ConvertTo-Json
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.Close()
            continue
        }

        # Validate required fields
        $requiredFields = @(
            "submission_title", "vertical", "contact_name", "phone", "email",
            "service_address", "problem_description", "urgency", "channel", "status"
        )

        $missingFields = $requiredFields | Where-Object { -not $payload.$_ }
        if ($missingFields.Count -gt 0) {
            Write-Log "ERROR: Missing required fields: $($missingFields -join ', ')" "ERROR"
            $response.StatusCode = 400
            $response.Headers.Add("Content-Type", "application/json")
            $responseBody = @{
                status = "error"
                message = "Missing required fields: $($missingFields -join ', ')"
            } | ConvertTo-Json
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.Close()
            continue
        }

        Write-Log "Payload validation passed"

        # ====================================================================
        # Prepare SowerBase API payload
        # ====================================================================

        # Prepare API request payload
        $apiPayload = @{
            "Submission Title" = $payload.submission_title
            "Vertical" = $payload.vertical
            "Contact Name" = $payload.contact_name
            "Phone" = $payload.phone
            "Email" = $payload.email
            "Service Address" = $payload.service_address
            "Problem Description" = $payload.problem_description
            "Urgency" = $payload.urgency
            "Channel" = $payload.channel
            "Status" = $payload.status
            "Follow-up Status" = $(if ($payload.follow_up_status) { $payload.follow_up_status } else { "New" })
            "Trace ID" = $(if ($payload.trace_id) { $payload.trace_id } else { "" })
            "Submitted At" = $(if ($payload.submitted_at) { $payload.submitted_at } else { (Get-Date -AsUTC).ToString("o") })
            "Transcript" = $(if ($payload.transcript) { $payload.transcript } else { "" })
            "System Type" = $(if ($payload.system_type) { $payload.system_type } else { "" })
            "System Age" = $(if ($payload.system_age_years) { $payload.system_age_years } else { "" })
            "Preferred Service Window" = $(if ($payload.preferred_service_window) { $payload.preferred_service_window } else { "" })
            "Preferred Callback Time" = $(if ($payload.preferred_callback_time) { $payload.preferred_callback_time } else { "" })
            "Source System" = $(if ($payload.source_system) { $payload.source_system } else { "askthih_webhook_api" })
            "Source Base ID" = "app60wQWdbbgyqTcL"
            "Source Table Name" = $(if ($payload.source_table_name) { $payload.source_table_name } else { "HVAC Intake" })
            "Migration Status" = $(if ($payload.migration_status) { $payload.migration_status } else { "webhook" })
            "Raw Payload" = ($payload | Select-Object -Property * -ExcludeProperty @(
                "submission_title", "vertical", "contact_name", "phone", "email",
                "service_address", "problem_description", "urgency", "channel", "status"
            ) | ConvertTo-Json)
        }

        # ====================================================================
        # Operational routing: SowerBase primary, Airtable fallback/shadow
        # ====================================================================

        $routingMode = if ($env:ASKTHIH_HVAC_INTAKE_PRIMARY) { $env:ASKTHIH_HVAC_INTAKE_PRIMARY.ToLowerInvariant() } else { "sowerbase" }
        $airtableMode = if ($env:ASKTHIH_HVAC_AIRTABLE_MODE) { $env:ASKTHIH_HVAC_AIRTABLE_MODE.ToLowerInvariant() } else { "fallback" }
        $rollbackPrimary = if ($env:ASKTHIH_HVAC_ROLLBACK_PRIMARY) { $env:ASKTHIH_HVAC_ROLLBACK_PRIMARY.ToLowerInvariant() } else { "" }

        if ($rollbackPrimary -in @("1", "true", "airtable", "airtable_primary")) {
            $routingMode = "airtable_primary"
        }

        Write-Log "HVAC routing mode: $routingMode" "INFO"
        Write-Log "Airtable mode: $airtableMode" "INFO"

        if ($routingMode -eq "airtable_primary") {
            Write-Log "Rollback active: writing HVAC intake to Airtable primary path" "WARN"
            $airtableResult = Invoke-AirtableFallback -Payload $payload -Mode "fallback"

            if ($airtableResult.ok) {
                Send-JsonResponse -Response $response -StatusCode 201 -Body @{
                    status = "success"
                    message = "HVAC intake received through Airtable rollback path"
                    record_id = $airtableResult.record_id
                    method = "airtable-api"
                    routing_mode = "airtable_primary"
                    fallback_status = $airtableResult.status
                    airtable_status = $airtableResult.status
                }
                continue
            }

            Write-Log "ERROR: Airtable rollback write failed: $($airtableResult.status)" "ERROR"
            Send-JsonResponse -Response $response -StatusCode 500 -Body @{
                status = "error"
                message = "Airtable rollback path failed"
                routing_mode = "airtable_primary"
                fallback_status = $airtableResult.status
                airtable_status = $airtableResult.status
            }
            continue
        }

        if ($routingMode -ne "sowerbase") {
            Write-Log "ERROR: Unsupported HVAC routing mode: $routingMode" "ERROR"
            Send-JsonResponse -Response $response -StatusCode 500 -Body @{
                status = "error"
                message = "Unsupported HVAC routing mode"
                routing_mode = $routingMode
                fallback_status = "not_attempted"
                airtable_status = "not_attempted"
            }
            continue
        }

        Write-Log "Creating intake record via SowerBase/NocoDB API first..." "INFO"
        Write-Log "API endpoint: [redacted for security]" "DEBUG"
        $sowerBaseResult = Invoke-SowerBaseCreate -ApiPayload $apiPayload -OriginalPayload $payload

        if ($sowerBaseResult.ok) {
            Write-Log "SUCCESS: Record created via SowerBase primary path. Record ID: $($sowerBaseResult.record_id)" "SUCCESS"

            $airtableStatus = "not_attempted"
            if ($airtableMode -eq "shadow") {
                Write-Log "Writing Airtable shadow copy for HVAC intake" "INFO"
                $airtableShadow = Invoke-AirtableFallback -Payload $payload -Mode "shadow"
                $airtableStatus = $airtableShadow.status
                if ($airtableShadow.ok) {
                    Write-Log "SUCCESS: Airtable shadow write accepted" "SUCCESS"
                } else {
                    Write-Log "WARN: Airtable shadow write did not complete: $airtableStatus" "WARN"
                }
            }

            Send-JsonResponse -Response $response -StatusCode 201 -Body @{
                status = "success"
                message = "HVAC intake received and stored"
                record_id = $sowerBaseResult.record_id
                method = $sowerBaseResult.method
                routing_mode = "sowerbase_primary"
                fallback_status = "not_needed"
                airtable_status = $airtableStatus
            }

            Write-Log "Response: 201 Created (SowerBase primary)"
            continue
        }

        Write-Log "ERROR: SowerBase primary write failed: $($sowerBaseResult.status)" "ERROR"

        if ($airtableMode -eq "fallback") {
            Write-Log "Attempting Airtable fallback for HVAC intake" "WARN"
            $airtableFallback = Invoke-AirtableFallback -Payload $payload -Mode "fallback"

            if ($airtableFallback.ok) {
                Write-Log "SUCCESS: Airtable fallback write accepted. Record ID: $($airtableFallback.record_id)" "SUCCESS"
                Send-JsonResponse -Response $response -StatusCode 202 -Body @{
                    status = "success"
                    message = "HVAC intake stored through Airtable fallback after SowerBase failure"
                    record_id = $airtableFallback.record_id
                    method = "airtable-fallback"
                    routing_mode = "sowerbase_primary"
                    fallback_status = $airtableFallback.status
                    airtable_status = $airtableFallback.status
                }
                continue
            }

            Write-Log "ERROR: Airtable fallback failed: $($airtableFallback.status)" "ERROR"
            Send-JsonResponse -Response $response -StatusCode 500 -Body @{
                status = "error"
                message = "SowerBase primary failed and Airtable fallback failed"
                routing_mode = "sowerbase_primary"
                fallback_status = $airtableFallback.status
                airtable_status = $airtableFallback.status
            }
            continue
        }

        Send-JsonResponse -Response $response -StatusCode 500 -Body @{
            status = "error"
            message = "SowerBase primary failed and Airtable fallback is disabled"
            routing_mode = "sowerbase_primary"
            fallback_status = "disabled"
            airtable_status = "not_attempted"
        }
        continue
    } catch {
        Write-Log "ERROR: Request handler exception: $($_.Exception.Message)" "ERROR"
        try {
            if ($response) {
                if (-not $response.OutputStream.CanWrite) {
                    $response.Close()
                } else {
                    $response.StatusCode = 500
                    $response.Headers.Add("Content-Type", "application/json")
                    $responseBody = @{
                        status = "error"
                        message = "Internal server error"
                    } | ConvertTo-Json
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
                    $response.ContentLength64 = $bytes.Length
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                    $response.Close()
                }
            }
        } catch {
            Write-Log "ERROR: Failed to close response: $($_.Exception.Message)" "ERROR"
        }
    }
}

# ============================================================================
# Shutdown
# ============================================================================

Write-Log "Shutting down webhook server..."
$listener.Stop()
$listener.Close()

Write-Log "Webhook server stopped"
Write-Log "Total requests handled: $requestCount"

exit 0
