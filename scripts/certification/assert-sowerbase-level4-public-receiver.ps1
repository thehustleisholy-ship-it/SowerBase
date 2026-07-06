#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Assert SowerBase Level 4 public receiver readiness without production cutover.

.DESCRIPTION
    Starts the local API-safe AskTHIH HVAC receiver on loopback, sends bad
    requests and one synthetic valid request, verifies only the valid request
    writes to SowerBase, and checks that receiver logs do not expose local
    secrets. This script does not start Cloudflare, touch DNS, call Airtable, or
    connect production routing.
#>

param(
    [int]$Port = 18787,
    [string]$EnvFile = ".env.askthih-hvac-staging",
    [string]$DbContainer = "sowerbase-local-db-1",
    [string]$DbUser = "nocodb",
    [string]$DbName = "nocodb",
    [string]$SchemaName = "peoc8ioej5ejtj7",
    [string]$TableName = "HVAC Intake",
    [string]$OutputDir = "outputs/certification",
    [int]$RequestTimeoutSec = 20
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host $Message
}

function Import-EnvFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Env file not found: $Path"
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        $parts = $line -split "=", 2
        if ($parts.Count -ne 2) { return }
        $name = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        if ($name) {
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

function Invoke-PsqlScalar {
    param([Parameter(Mandatory)][string]$Sql)

    $result = $Sql | docker exec -i $DbContainer psql -U $DbUser -d $DbName -v ON_ERROR_STOP=1 -t -A
    if ($LASTEXITCODE -ne 0) {
        throw "psql failed with exit code $LASTEXITCODE"
    }

    return [string]($result | Select-Object -First 1)
}

function Get-ChannelCount {
    param([Parameter(Mandatory)][string]$Channel)

    $escaped = $Channel.Replace("'", "''")
    $sql = "SELECT COUNT(*) FROM ""$SchemaName"".""$TableName"" WHERE ""Channel"" = '$escaped';"
    return [int](Invoke-PsqlScalar -Sql $sql)
}

function Invoke-Probe {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Url,
        [hashtable]$Headers = @{},
        [string]$Body = "",
        [string]$ContentType = $null,
        [Parameter(Mandatory)][int]$ExpectedStatus
    )

    $statusCode = $null
    $responseText = ""

    try {
        $parameters = @{
            Uri = $Url
            Method = $Method
            Headers = $Headers
            TimeoutSec = $RequestTimeoutSec
            ErrorAction = "Stop"
        }

        if ($null -ne $ContentType) {
            $parameters.ContentType = $ContentType
        }

        if ($Method -ne "GET" -and $Method -ne "HEAD") {
            $parameters.Body = $Body
        }

        $response = Invoke-WebRequest @parameters
        $statusCode = [int]$response.StatusCode
        $responseText = [string]$response.Content
    } catch {
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                if ($stream) {
                    $reader = [System.IO.StreamReader]::new($stream)
                    $responseText = $reader.ReadToEnd()
                    $reader.Dispose()
                }
            } catch {
                $responseText = ""
            }
        } else {
            $statusCode = -1
            $responseText = $_.Exception.Message
        }
    }

    [pscustomobject]@{
        name = $Name
        method = $Method
        expected_status = $ExpectedStatus
        actual_status = $statusCode
        passed = ($statusCode -eq $ExpectedStatus)
        response_preview = if ($responseText.Length -gt 160) { $responseText.Substring(0, 160) } else { $responseText }
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$runId = "level4-" + (Get-Date -AsUTC -Format "yyyyMMddTHHmmssZ")
$logPath = Join-Path $OutputDir "SOWERBASE_LEVEL4_PUBLIC_RECEIVER_$runId.log"
$jsonPath = Join-Path $OutputDir "SOWERBASE_LEVEL4_PUBLIC_RECEIVER_$runId.json"
$mdPath = Join-Path $OutputDir "SOWERBASE_LEVEL4_PUBLIC_RECEIVER_$runId.md"
$serverScript = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "askthih-hvac-local-webhook-server.ps1"

Write-Step "SowerBase Level 4 public receiver readiness proof"
Write-Step "Run ID: $runId"

Import-EnvFile -Path $EnvFile
[Environment]::SetEnvironmentVariable("ASKTHIH_WEBHOOK_PORT", [string]$Port, "Process")
[Environment]::SetEnvironmentVariable("ASKTHIH_WEBHOOK_AUTH_MODE", "shared-secret", "Process")

$requiredVars = @("ASKTHIH_WEBHOOK_SECRET", "SOWERBASE_BASE_URL", "SOWERBASE_API_TOKEN", "SOWERBASE_INTAKE_TABLE_ID")
$missing = @($requiredVars | Where-Object { [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_)) })
if ($missing.Count -gt 0) {
    throw "Missing required environment variables: $($missing -join ', ')"
}

$secret = [Environment]::GetEnvironmentVariable("ASKTHIH_WEBHOOK_SECRET")
$apiToken = [Environment]::GetEnvironmentVariable("SOWERBASE_API_TOKEN")

$serverSource = Get-Content -LiteralPath $serverScript -Raw
$loopbackOnly = (
    $serverSource -match 'Prefixes\.Add\("http://localhost:\$Port/"\)' -and
    $serverSource -match 'Prefixes\.Add\("http://127\.0\.0\.1:\$Port/"\)' -and
    $serverSource -notmatch 'http://\+:' -and
    $serverSource -notmatch 'http://0\.0\.0\.0:'
)

$channel = "cert_level4_public_receiver_$runId"
$traceId = "trace-$runId"
$baseUrl = "http://localhost:$Port/askthih/hvac"
$headersValid = @{ "X-AskTHIH-Webhook-Secret" = $secret }
$headersWrong = @{ "X-AskTHIH-Webhook-Secret" = "wrong-secret-for-level4-proof" }

$beforeCount = Get-ChannelCount -Channel $channel
$serverProcess = $null

try {
    Write-Step "Starting local receiver on loopback port $Port..."
    $pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $powershellHost = if ($pwshCommand) { $pwshCommand.Source } else { "powershell.exe" }
    $serverProcess = Start-Process $powershellHost `
        -ArgumentList "-NoProfile", "-File", "`"$serverScript`"", "-Port", "$Port", "-OutputLog", "`"$logPath`"" `
        -PassThru `
        -WindowStyle Hidden `
        -ErrorAction Stop

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        try {
            $connection = Test-NetConnection -ComputerName localhost -Port $Port -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($connection.TcpTestSucceeded) {
                $ready = $true
                break
            }
        } catch {}
        Start-Sleep -Milliseconds 500
    }

    if (-not $ready) {
        throw "Receiver did not start listening on localhost:$Port"
    }

    $validPayload = [ordered]@{
        submission_title = "Level 4 Public Receiver Readiness Proof"
        vertical = "HVAC"
        contact_name = "Level 4 Synthetic Contact"
        phone = "555-4404"
        email = "level4-public-receiver@example.com"
        service_address = "404 Public Receiver Proof Way, Synthetic City, ST"
        problem_description = "Synthetic Level 4 readiness proof payload. No real customer data."
        urgency = "Normal"
        channel = $channel
        status = "New"
        source_system = "sowerbase_level4_public_receiver_proof"
        source_table_name = "HVAC Intake"
        migration_status = "test_only"
        trace_id = $traceId
        submitted_at = (Get-Date -AsUTC).ToString("o")
        transcript = "Synthetic transcript for Level 4 receiver proof."
        system_type = "Central AC"
        system_age_years = "7"
        preferred_service_window = "Certification window only"
        test_only = $true
        certification_run_id = $runId
    }

    $validBody = $validPayload | ConvertTo-Json -Depth 12
    $missingRequiredBody = (@{ submission_title = "Missing required proof"; channel = $channel } | ConvertTo-Json)

    $probes = @()
    $probes += Invoke-Probe -Name "HEAD blocked" -Method "HEAD" -Url $baseUrl -ExpectedStatus 405
    $probes += Invoke-Probe -Name "GET blocked" -Method "GET" -Url $baseUrl -ExpectedStatus 405
    $probes += Invoke-Probe -Name "Unknown path blocked before write" -Method "POST" -Url "http://localhost:$Port/invalid" -ContentType "application/json" -Body "{}" -ExpectedStatus 404
    $probes += Invoke-Probe -Name "Wrong content type blocked" -Method "POST" -Url $baseUrl -Headers $headersValid -ContentType "text/plain" -Body $validBody -ExpectedStatus 415
    $probes += Invoke-Probe -Name "Missing auth blocked" -Method "POST" -Url $baseUrl -ContentType "application/json" -Body $validBody -ExpectedStatus 401
    $probes += Invoke-Probe -Name "Wrong auth blocked" -Method "POST" -Url $baseUrl -Headers $headersWrong -ContentType "application/json" -Body $validBody -ExpectedStatus 401
    $probes += Invoke-Probe -Name "Invalid JSON blocked" -Method "POST" -Url $baseUrl -Headers $headersValid -ContentType "application/json" -Body "{ invalid json" -ExpectedStatus 400
    $probes += Invoke-Probe -Name "Missing required fields blocked" -Method "POST" -Url $baseUrl -Headers $headersValid -ContentType "application/json" -Body $missingRequiredBody -ExpectedStatus 400

    $afterBadCount = Get-ChannelCount -Channel $channel
    $probes += Invoke-Probe -Name "Valid synthetic intake accepted" -Method "POST" -Url $baseUrl -Headers $headersValid -ContentType "application/json" -Body $validBody -ExpectedStatus 201
    $afterValidCount = Get-ChannelCount -Channel $channel

    $rowSql = @"
SELECT COUNT(*)
FROM "$SchemaName"."$TableName"
WHERE "Channel" = '$($channel.Replace("'", "''"))'
  AND "Trace_ID" = '$($traceId.Replace("'", "''"))'
  AND "Raw_Payload" LIKE '%$($runId.Replace("'", "''"))%'
  AND "System_Type" = 'Central AC'
  AND "Submitted_At" IS NOT NULL;
"@
    $acceptedRowCount = [int](Invoke-PsqlScalar -Sql $rowSql)

    $stillRunning = $false
    try {
        $runningProcess = Get-Process -Id $serverProcess.Id -ErrorAction SilentlyContinue
        $stillRunning = ($runningProcess -and -not $runningProcess.HasExited)
    } catch {}

    $logContent = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw } else { "" }
    $secretLeaked = (-not [string]::IsNullOrWhiteSpace($secret) -and $logContent.Contains($secret))
    $tokenLeaked = (-not [string]::IsNullOrWhiteSpace($apiToken) -and $logContent.Contains($apiToken))
    $authorizationLeak = ($logContent -match 'Bearer\s+[A-Za-z0-9_\-\.]+')

    $badRequestsDidNotWrite = ($afterBadCount -eq $beforeCount)
    $validRequestWroteOnce = (($afterValidCount - $afterBadCount) -eq 1)
    $allProbeStatusesPassed = @($probes | Where-Object { -not $_.passed }).Count -eq 0
    $acceptedRowVerified = ($acceptedRowCount -eq 1)
    $secretsClean = (-not $secretLeaked -and -not $tokenLeaked -and -not $authorizationLeak)

    $passed = (
        $loopbackOnly -and
        $allProbeStatusesPassed -and
        $badRequestsDidNotWrite -and
        $validRequestWroteOnce -and
        $acceptedRowVerified -and
        $stillRunning -and
        $secretsClean
    )

    $report = [ordered]@{
        run_id = $runId
        status = if ($passed) { "pass" } else { "fail" }
        question = "Can SowerBase safely receive intake records from a public endpoint without exposing secrets, accepting bad requests, or breaking Airtable-primary production?"
        production_connected = $false
        cloudflare_started = $false
        airtable_touched = $false
        receiver = [ordered]@{
            url = $baseUrl
            loopback_only = $loopbackOnly
            port = $Port
        }
        write_counts = [ordered]@{
            before = $beforeCount
            after_bad_requests = $afterBadCount
            after_valid_request = $afterValidCount
            bad_requests_did_not_write = $badRequestsDidNotWrite
            valid_request_wrote_once = $validRequestWroteOnce
            accepted_row_verified = $acceptedRowVerified
        }
        security = [ordered]@{
            secret_value_leaked_to_log = $secretLeaked
            token_value_leaked_to_log = $tokenLeaked
            bearer_header_leaked_to_log = $authorizationLeak
            secrets_clean = $secretsClean
        }
        process = [ordered]@{
            stayed_alive = $stillRunning
        }
        probes = $probes
        outputs = [ordered]@{
            log = $logPath
            json = $jsonPath
            markdown = $mdPath
        }
    }

    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -NoNewline

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# SowerBase Level 4 Public Receiver Readiness Run")
    $lines.Add("")
    $lines.Add("Run ID: ``$runId``")
    $lines.Add("Status: $($report.status)")
    $lines.Add("Production connected: false")
    $lines.Add("Cloudflare started: false")
    $lines.Add("Airtable touched: false")
    $lines.Add("")
    $lines.Add("## Probe Results")
    $lines.Add("")
    $lines.Add("| Probe | Expected | Actual | Result |")
    $lines.Add("| --- | ---: | ---: | --- |")
    foreach ($probe in $probes) {
        $lines.Add("| $($probe.name) | $($probe.expected_status) | $($probe.actual_status) | $(if ($probe.passed) { 'PASS' } else { 'FAIL' }) |")
    }
    $lines.Add("")
    $lines.Add("## Write Safety")
    $lines.Add("")
    $lines.Add("- Before: $beforeCount")
    $lines.Add("- After bad requests: $afterBadCount")
    $lines.Add("- After valid request: $afterValidCount")
    $lines.Add("- Accepted row verified with promoted metadata: $acceptedRowVerified")
    $lines.Add("")
    $lines.Add("## Secret Hygiene")
    $lines.Add("")
    $lines.Add("- Secret value leaked to log: $secretLeaked")
    $lines.Add("- Token value leaked to log: $tokenLeaked")
    $lines.Add("- Bearer header leaked to log: $authorizationLeak")
    $lines.Add("")
    $lines.Add("## Verdict")
    $lines.Add("")
    $lines.Add($(if ($passed) { "PASS" } else { "FAIL" }))
    $lines | Set-Content -LiteralPath $mdPath

    if ($passed) {
        Write-Host "PASS: Level 4 public receiver readiness proof passed."
        Write-Host "Report: $mdPath"
        exit 0
    }

    Write-Host "FAIL: Level 4 public receiver readiness proof failed."
    Write-Host "Report: $mdPath"
    exit 1
} finally {
    if ($serverProcess) {
        try {
            Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 300
        } catch {}
    }
}
