#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Assert Level 4B receiver security hardening for the AskTHIH SowerBase receiver.

.DESCRIPTION
    Proves local-only HMAC/timestamp receiver behavior without production
    routing. The proof starts the loopback receiver, sends signed and invalid
    synthetic requests, verifies only the valid signed request writes one row,
    verifies replay/stale/bad signatures write zero rows, and checks logs for
    secret or bearer leakage.
#>

param(
    [int]$Port = 18788,
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
        [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim().Trim('"').Trim("'"), "Process")
    }
}

function ConvertTo-Hex {
    param([byte[]]$Bytes)
    return -join ($Bytes | ForEach-Object { "{0:x2}" -f $_ })
}

function New-SignatureHeader {
    param(
        [Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)][string]$Secret,
        [Parameter(Mandatory)][int64]$Timestamp
    )

    $payload = "$Timestamp.$Body"
    $hmac = [System.Security.Cryptography.HMACSHA256]::new([System.Text.Encoding]::UTF8.GetBytes($Secret))
    try {
        $signature = ConvertTo-Hex -Bytes $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payload))
    } finally {
        $hmac.Dispose()
    }

    return "Signature $Timestamp.$signature"
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
    return [int](Invoke-PsqlScalar -Sql "SELECT COUNT(*) FROM ""$SchemaName"".""$TableName"" WHERE ""Channel"" = '$escaped';")
}

function Invoke-Probe {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Url,
        [hashtable]$Headers = @{},
        [Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)][int]$ExpectedStatus
    )

    $statusCode = $null
    $responseText = ""

    try {
        $response = Invoke-WebRequest `
            -Uri $Url `
            -Method POST `
            -Headers $Headers `
            -ContentType "application/json" `
            -Body $Body `
            -TimeoutSec $RequestTimeoutSec `
            -ErrorAction Stop
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
        expected_status = $ExpectedStatus
        actual_status = $statusCode
        passed = ($statusCode -eq $ExpectedStatus)
        response_preview = if ($responseText.Length -gt 160) { $responseText.Substring(0, 160) } else { $responseText }
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$runId = "level4b-" + (Get-Date -AsUTC -Format "yyyyMMddTHHmmssZ")
$logPath = Join-Path $OutputDir "SOWERBASE_LEVEL4B_RECEIVER_SECURITY_$runId.log"
$jsonPath = Join-Path $OutputDir "SOWERBASE_LEVEL4B_RECEIVER_SECURITY_$runId.json"
$mdPath = Join-Path $OutputDir "SOWERBASE_LEVEL4B_RECEIVER_SECURITY_$runId.md"
$serverScript = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "askthih-hvac-local-webhook-server.ps1"

Write-Host "SowerBase Level 4B receiver security hardening proof"
Write-Host "Run ID: $runId"

Import-EnvFile -Path $EnvFile
[Environment]::SetEnvironmentVariable("ASKTHIH_WEBHOOK_PORT", [string]$Port, "Process")
[Environment]::SetEnvironmentVariable("ASKTHIH_WEBHOOK_AUTH_MODE", "signature", "Process")
[Environment]::SetEnvironmentVariable("ASKTHIH_WEBHOOK_SIGNATURE_TOLERANCE_SECONDS", "300", "Process")

$secret = [Environment]::GetEnvironmentVariable("ASKTHIH_WEBHOOK_SECRET")
$apiToken = [Environment]::GetEnvironmentVariable("SOWERBASE_API_TOKEN")
if ([string]::IsNullOrWhiteSpace($secret) -or [string]::IsNullOrWhiteSpace($apiToken)) {
    throw "Required secret/token environment variables are missing."
}

$channel = "cert_level4b_receiver_security_$runId"
$traceId = "trace-$runId"
$baseUrl = "http://localhost:$Port/askthih/hvac"
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$stale = $now - 900

$validPayload = [ordered]@{
    submission_title = "Level 4B Receiver Security Proof"
    vertical = "HVAC"
    contact_name = "Level 4B Synthetic Contact"
    phone = "555-4405"
    email = "level4b-receiver-security@example.com"
    service_address = "405 Receiver Security Proof Way, Synthetic City, ST"
    problem_description = "Synthetic Level 4B HMAC/timestamp proof payload. No real customer data."
    urgency = "Normal"
    channel = $channel
    status = "New"
    source_system = "sowerbase_level4b_receiver_security_proof"
    source_table_name = "HVAC Intake"
    migration_status = "test_only"
    trace_id = $traceId
    submitted_at = (Get-Date -AsUTC).ToString("o")
    transcript = "Synthetic transcript for Level 4B receiver security proof."
    system_type = "Central AC"
    system_age_years = "7"
    preferred_service_window = "Certification window only"
    test_only = $true
    certification_run_id = $runId
}

$validBody = $validPayload | ConvertTo-Json -Depth 12
$wrongSigHeader = "Signature $now." + ("0" * 64)
$validHeader = New-SignatureHeader -Body $validBody -Secret $secret -Timestamp $now
$staleHeader = New-SignatureHeader -Body $validBody -Secret $secret -Timestamp $stale

$beforeCount = Get-ChannelCount -Channel $channel
$serverProcess = $null

try {
    $pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $powershellHost = if ($pwshCommand) { $pwshCommand.Source } else { "powershell.exe" }
    $serverProcess = Start-Process $powershellHost `
        -ArgumentList "-NoProfile", "-File", "`"$serverScript`"", "-Port", "$Port", "-OutputLog", "`"$logPath`"" `
        -PassThru `
        -WindowStyle Hidden `
        -ErrorAction Stop

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        $connection = Test-NetConnection -ComputerName localhost -Port $Port -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($connection.TcpTestSucceeded) {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw "Receiver did not start on localhost:$Port" }

    $probes = @()
    $probes += Invoke-Probe -Name "Missing signature rejected" -Url $baseUrl -Body $validBody -ExpectedStatus 401
    $probes += Invoke-Probe -Name "Wrong signature rejected" -Url $baseUrl -Headers @{ Authorization = $wrongSigHeader } -Body $validBody -ExpectedStatus 401
    $probes += Invoke-Probe -Name "Stale timestamp rejected" -Url $baseUrl -Headers @{ Authorization = $staleHeader } -Body $validBody -ExpectedStatus 401
    $afterInvalidCount = Get-ChannelCount -Channel $channel

    $probes += Invoke-Probe -Name "Valid signed synthetic intake accepted" -Url $baseUrl -Headers @{ Authorization = $validHeader } -Body $validBody -ExpectedStatus 201
    $afterValidCount = Get-ChannelCount -Channel $channel

    $probes += Invoke-Probe -Name "Replay signature rejected" -Url $baseUrl -Headers @{ Authorization = $validHeader } -Body $validBody -ExpectedStatus 409
    $afterReplayCount = Get-ChannelCount -Channel $channel

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

    $logContent = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw } else { "" }
    $secretLeaked = $logContent.Contains($secret)
    $tokenLeaked = $logContent.Contains($apiToken)
    $bearerLeaked = ($logContent -match 'Bearer\s+[A-Za-z0-9_\-\.]+')
    $signatureLeaked = ($logContent -match 'Signature\s+\d+\.[0-9a-fA-F]{64}')

    $invalidDidNotWrite = ($afterInvalidCount -eq $beforeCount)
    $validWroteOnce = (($afterValidCount - $afterInvalidCount) -eq 1)
    $replayDidNotWrite = ($afterReplayCount -eq $afterValidCount)
    $allProbeStatusesPassed = @($probes | Where-Object { -not $_.passed }).Count -eq 0
    $acceptedRowVerified = ($acceptedRowCount -eq 1)
    $logsClean = (-not $secretLeaked -and -not $tokenLeaked -and -not $bearerLeaked -and -not $signatureLeaked)
    $passed = ($allProbeStatusesPassed -and $invalidDidNotWrite -and $validWroteOnce -and $replayDidNotWrite -and $acceptedRowVerified -and $logsClean)

    $report = [ordered]@{
        run_id = $runId
        status = if ($passed) { "pass" } else { "fail" }
        production_connected = $false
        cloudflare_started = $false
        airtable_touched = $false
        write_counts = [ordered]@{
            before = $beforeCount
            after_invalid = $afterInvalidCount
            after_valid = $afterValidCount
            after_replay = $afterReplayCount
            invalid_did_not_write = $invalidDidNotWrite
            valid_wrote_once = $validWroteOnce
            replay_did_not_write = $replayDidNotWrite
            accepted_row_verified = $acceptedRowVerified
        }
        security = [ordered]@{
            secret_value_leaked_to_log = $secretLeaked
            token_value_leaked_to_log = $tokenLeaked
            bearer_header_leaked_to_log = $bearerLeaked
            signature_header_leaked_to_log = $signatureLeaked
            logs_clean = $logsClean
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
    $lines.Add("# SowerBase Level 4B Receiver Security Run")
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
    $lines.Add("- After invalid signed requests: $afterInvalidCount")
    $lines.Add("- After valid signed request: $afterValidCount")
    $lines.Add("- After replay attempt: $afterReplayCount")
    $lines.Add("- Accepted row verified with promoted metadata: $acceptedRowVerified")
    $lines.Add("")
    $lines.Add("## Secret Hygiene")
    $lines.Add("")
    $lines.Add("- Secret value leaked to log: $secretLeaked")
    $lines.Add("- Token value leaked to log: $tokenLeaked")
    $lines.Add("- Bearer header leaked to log: $bearerLeaked")
    $lines.Add("- Signature header leaked to log: $signatureLeaked")
    $lines.Add("")
    $lines.Add("## Verdict")
    $lines.Add("")
    $lines.Add($(if ($passed) { "PASS" } else { "FAIL" }))
    $lines | Set-Content -LiteralPath $mdPath

    if ($passed) {
        Write-Host "PASS: Level 4B receiver security hardening proof passed."
        Write-Host "Report: $mdPath"
        exit 0
    }

    Write-Host "FAIL: Level 4B receiver security hardening proof failed."
    Write-Host "Report: $mdPath"
    exit 1
} finally {
    if ($serverProcess) {
        Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
    }
}
