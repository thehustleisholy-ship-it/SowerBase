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
        # Call SowerBase/NocoDB API (API-Safe Pattern Only)
        # ====================================================================

        Write-Log "Creating intake record via SowerBase/NocoDB API..." "INFO"

        $apiToken = $env:SOWERBASE_API_TOKEN
        if (-not $apiToken) {
            Write-Log "ERROR: SOWERBASE_API_TOKEN required (no fallback available)" "ERROR"
            $response.StatusCode = 500
            $response.Headers.Add("Content-Type", "application/json")
            $responseBody = @{
                status = "error"
                message = "Server configuration error"
            } | ConvertTo-Json
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.Close()
            continue
        }

        # Construct NocoDB API endpoint
        $baseUrl = $env:SOWERBASE_BASE_URL
        $tableId = $env:SOWERBASE_INTAKE_TABLE_ID
        $apiUrl = "$baseUrl/api/v2/tables/$tableId/records"
        $apiHeaders = @{
            "Authorization" = "Bearer $apiToken"
            "Content-Type" = "application/json"
            "xc-auth" = $apiToken
        }

        Write-Log "API endpoint: [redacted for security]" "DEBUG"

        # Call SowerBase API to create record
        try {
            $response_api = Invoke-WebRequest -Uri $apiUrl `
                -Method POST `
                -Headers $apiHeaders `
                -Body ($apiPayload | ConvertTo-Json) `
                -TimeoutSec 6 `
                -ErrorAction Stop

            if ($response_api.StatusCode -eq 200 -or $response_api.StatusCode -eq 201) {
                Write-Log "SUCCESS: Record created via SowerBase/NocoDB API" "SUCCESS"

                $responseData = $response_api.Content | ConvertFrom-Json
                $recordId = $responseData.id

                Write-Log "Record ID: $recordId" "SUCCESS"

                Send-JsonResponse -Response $response -StatusCode 201 -Body @{
                    status = "success"
                    message = "HVAC intake received and stored"
                    record_id = $recordId
                    method = "sowerbase-api"
                }

                Write-Log "Response: 201 Created (SowerBase API)"
                continue
            } else {
                Write-Log "ERROR: Unexpected response from SowerBase API: $($response_api.StatusCode)" "ERROR"
                Send-JsonResponse -Response $response -StatusCode 500 -Body @{
                    status = "error"
                    message = "SowerBase API error"
                }
                continue
            }
        } catch {
            Write-Log "ERROR: SowerBase API request failed: $($_.Exception.Message)" "ERROR"

            try {
                Write-Log "Attempting recovery read-back by channel: $($payload.channel)" "INFO"
                $recoveredRecord = Find-SowerBaseRecordByChannel -ApiUrl $apiUrl -Headers $apiHeaders -Channel $payload.channel
                if ($recoveredRecord) {
                    $recordId = Get-RecordIdFromApiRecord -Record $recoveredRecord
                    Write-Log "RECOVERED: Found record after create failure. Record ID: $recordId" "SUCCESS"
                    Send-JsonResponse -Response $response -StatusCode 201 -Body @{
                        status = "success"
                        message = "HVAC intake received and stored"
                        record_id = $recordId
                        method = "recovered_readback"
                    }
                    continue
                }
            } catch {
                Write-Log "ERROR: Recovery read-back failed: $($_.Exception.Message)" "ERROR"
            }

            Send-JsonResponse -Response $response -StatusCode 500 -Body @{
                status = "error"
                message = "Failed to create record and recovery read-back found no matching row"
            }
            continue
        }

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
