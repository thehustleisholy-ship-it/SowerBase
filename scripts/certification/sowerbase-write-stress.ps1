#!/usr/bin/env pwsh
<#
.SYNOPSIS
    SowerBase Certification Level 1 local write stress harness.

.DESCRIPTION
    Runs synthetic-only local webhook probes for SowerBase Level 1 certification.
    The harness can run auth probes, a single valid write probe, and optional
    volume writes. It never prints ASKTHIH_WEBHOOK_SECRET or SowerBase API tokens.

    This script is local-only by default. Do not point it at production or public
    endpoints without an explicit approval gate.
#>

[CmdletBinding()]
param(
    [string]$WebhookUrl = "http://localhost:8787/askthih/hvac",
    [int]$RecordCount = 25,
    [int]$Concurrency = 1,
    [string]$Vertical = "HVAC",
    [string]$MarkerPrefix = "cert_level1_hvac",
    [string]$TestRunId = "",
    [string]$OutputDir = "outputs/certification",
    [switch]$DryRun,
    [switch]$SkipVolume,
    [int]$TimeoutSec = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($RecordCount -lt 1) {
    throw "RecordCount must be at least 1."
}

if ($Concurrency -lt 1) {
    throw "Concurrency must be at least 1."
}

if ($TimeoutSec -lt 1) {
    throw "TimeoutSec must be at least 1."
}

if ([string]::IsNullOrWhiteSpace($TestRunId)) {
    $TestRunId = "cert-" + (Get-Date -AsUTC -Format "yyyyMMddTHHmmssZ")
}

$runStartedAt = Get-Date -AsUTC
$mainChannel = "$MarkerPrefix-$TestRunId"
$authMissingChannel = "$MarkerPrefix-$TestRunId-auth-missing"
$authWrongChannel = "$MarkerPrefix-$TestRunId-auth-wrong"
$singleChannel = "$MarkerPrefix-$TestRunId-single"

function Get-GitInfo {
    $branch = "unknown"
    $commit = "unknown"

    try {
        $branchValue = git branch --show-current 2>$null
        if (-not [string]::IsNullOrWhiteSpace($branchValue)) {
            $branch = $branchValue.Trim()
        }
    } catch {
        $branch = "unknown"
    }

    try {
        $commitValue = git rev-parse HEAD 2>$null
        if (-not [string]::IsNullOrWhiteSpace($commitValue)) {
            $commit = $commitValue.Trim()
        }
    } catch {
        $commit = "unknown"
    }

    [pscustomobject]@{
        branch = $branch
        commit = $commit
    }
}

function Get-WebhookSurface {
    param([Parameter(Mandatory = $true)] [string]$Url)

    try {
        $uri = [System.Uri]$Url
        [pscustomobject]@{
            scheme = $uri.Scheme
            host = $uri.Host
            port = $uri.Port
            path = $uri.AbsolutePath
        }
    } catch {
        [pscustomobject]@{
            scheme = "invalid"
            host = "invalid"
            port = -1
            path = "invalid"
        }
    }
}

function New-TraceId {
    param(
        [Parameter(Mandatory = $true)] [string]$Prefix,
        [Parameter(Mandatory = $true)] [int]$Index
    )

    "$Prefix-$TestRunId-$Index-$([guid]::NewGuid().ToString())"
}

function New-SyntheticPayload {
    param(
        [Parameter(Mandatory = $true)] [int]$Index,
        [Parameter(Mandatory = $true)] [string]$TraceId,
        [Parameter(Mandatory = $true)] [string]$Channel
    )

    $phoneSuffix = "{0:D4}" -f ($Index % 10000)

    [ordered]@{
        submission_title = "Certification Test HVAC Proof $Index"
        vertical = $Vertical
        contact_name = "Certification Test HVAC Contact $Index"
        phone = "555-$phoneSuffix"
        email = "cert-hvac+$Index@example.com"
        service_address = "$Index Certification Test Way, Synthetic City, ST"
        problem_description = "Synthetic certification HVAC proof payload. No real customer data."
        urgency = "Normal"
        channel = $Channel
        status = "New"
        source_system = "sowerbase_certification_harness"
        source_table_name = "HVAC Intake"
        migration_status = "test_only"
        trace_id = $TraceId
        certification_run_id = $TestRunId
        marker_prefix = $MarkerPrefix
        test_only = $true
        synthetic_city = "Synthetic City"
        synthetic_state = "ST"
        system_type = "Central AC"
        system_age_years = "7"
        preferred_service_window = "Certification window only"
    }
}

function Invoke-CertWebhookRequest {
    param(
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)] [hashtable]$Payload,
        [ValidateSet("missing", "wrong", "valid")]
        [string]$SecretMode = "valid"
    )

    $traceId = if ($Payload.Contains("trace_id")) { [string]$Payload.trace_id } else { "" }

    if ($DryRun) {
        return [pscustomobject]@{
            name = $Name
            trace_id = $traceId
            secret_mode = $SecretMode
            status_code = "DRYRUN"
            elapsed_ms = 0
            timed_out = $false
            success = $false
            error = ""
        }
    }

    $headers = @{}
    if ($SecretMode -eq "wrong") {
        $headers["X-AskTHIH-Webhook-Secret"] = "wrong-secret-for-certification-test"
    } elseif ($SecretMode -eq "valid") {
        if ([string]::IsNullOrWhiteSpace($env:ASKTHIH_WEBHOOK_SECRET)) {
            return [pscustomobject]@{
                name = $Name
                trace_id = $traceId
                secret_mode = $SecretMode
                status_code = "NO_SECRET_ENV"
                elapsed_ms = 0
                timed_out = $false
                success = $false
                error = "ASKTHIH_WEBHOOK_SECRET is not set in the current process environment."
            }
        }
        $headers["X-AskTHIH-Webhook-Secret"] = $env:ASKTHIH_WEBHOOK_SECRET
    }

    $jsonBody = $Payload | ConvertTo-Json -Depth 12
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $response = Invoke-WebRequest `
            -Uri $WebhookUrl `
            -Method POST `
            -Headers $headers `
            -ContentType "application/json" `
            -Body $jsonBody `
            -TimeoutSec $TimeoutSec `
            -ErrorAction Stop

        $stopwatch.Stop()
        $statusCode = [int]$response.StatusCode

        [pscustomobject]@{
            name = $Name
            trace_id = $traceId
            secret_mode = $SecretMode
            status_code = $statusCode
            elapsed_ms = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
            timed_out = $false
            success = ($statusCode -ge 200 -and $statusCode -lt 300)
            error = ""
        }
    } catch {
        $stopwatch.Stop()
        $statusCode = "ERROR"
        $timedOut = $false
        $message = $_.Exception.Message

        if ($_.Exception.PSObject.Properties.Name -contains "Response" -and $_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        } elseif ($_.Exception.PSObject.Properties.Name -contains "StatusCode" -and $_.Exception.StatusCode) {
            $statusCode = [int]$_.Exception.StatusCode
        } elseif ($message -match "timed out|timeout|operation has timed out") {
            $statusCode = "TIMEOUT"
            $timedOut = $true
        }

        [pscustomobject]@{
            name = $Name
            trace_id = $traceId
            secret_mode = $SecretMode
            status_code = $statusCode
            elapsed_ms = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
            timed_out = $timedOut
            success = $false
            error = $message
        }
    }
}

function Invoke-CertWebhookBatch {
    param(
        [Parameter(Mandatory = $true)] [object[]]$Payloads
    )

    if ($DryRun -or $Concurrency -eq 1) {
        $sequentialResults = New-Object System.Collections.Generic.List[object]
        $index = 0
        foreach ($payload in $Payloads) {
            $index++
            $sequentialResults.Add((Invoke-CertWebhookRequest -Name "volume-$index" -Payload $payload -SecretMode "valid"))
        }
        return $sequentialResults.ToArray()
    }

    $jobResults = New-Object System.Collections.Generic.List[object]
    $queue = [System.Collections.Queue]::new()
    foreach ($payload in $Payloads) {
        $queue.Enqueue($payload)
    }

    $jobs = New-Object System.Collections.Generic.List[object]
    $jobMetadata = @{}
    $requestIndex = 0

    $worker = {
        param(
            [string]$RequestName,
            [string]$TraceId,
            [string]$WebhookUrl,
            [string]$PayloadJson,
            [string]$Secret,
            [int]$TimeoutSec
        )

        $headers = @{ "X-AskTHIH-Webhook-Secret" = $Secret }
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $response = Invoke-WebRequest `
                -Uri $WebhookUrl `
                -Method POST `
                -Headers $headers `
                -ContentType "application/json" `
                -Body $PayloadJson `
                -TimeoutSec $TimeoutSec `
                -ErrorAction Stop

            $stopwatch.Stop()
            $statusCode = [int]$response.StatusCode

            [pscustomobject]@{
                name = $RequestName
                trace_id = $TraceId
                secret_mode = "valid"
                status_code = $statusCode
                elapsed_ms = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
                timed_out = $false
                success = ($statusCode -ge 200 -and $statusCode -lt 300)
                error = ""
            }
        } catch {
            $stopwatch.Stop()
            $statusCode = "ERROR"
            $timedOut = $false
            $message = $_.Exception.Message

            if ($_.Exception.PSObject.Properties.Name -contains "Response" -and $_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            } elseif ($_.Exception.PSObject.Properties.Name -contains "StatusCode" -and $_.Exception.StatusCode) {
                $statusCode = [int]$_.Exception.StatusCode
            } elseif ($message -match "timed out|timeout|operation has timed out") {
                $statusCode = "TIMEOUT"
                $timedOut = $true
            }

            [pscustomobject]@{
                name = $RequestName
                trace_id = $TraceId
                secret_mode = "valid"
                status_code = $statusCode
                elapsed_ms = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
                timed_out = $timedOut
                success = $false
                error = $message
            }
        }
    }

    while ($queue.Count -gt 0 -or $jobs.Count -gt 0) {
        while ($queue.Count -gt 0 -and $jobs.Count -lt $Concurrency) {
            if ([string]::IsNullOrWhiteSpace($env:ASKTHIH_WEBHOOK_SECRET)) {
                $requestIndex++
                $payload = $queue.Dequeue()
                $jobResults.Add([pscustomobject]@{
                    name = "volume-$requestIndex"
                    trace_id = [string]$payload.trace_id
                    secret_mode = "valid"
                    status_code = "NO_SECRET_ENV"
                    elapsed_ms = 0
                    timed_out = $false
                    success = $false
                    error = "ASKTHIH_WEBHOOK_SECRET is not set in the current process environment."
                })
                continue
            }

            $requestIndex++
            $nextPayload = $queue.Dequeue()
            $requestName = "volume-$requestIndex"
            $payloadJson = $nextPayload | ConvertTo-Json -Depth 12
            $job = Start-Job -ScriptBlock $worker -ArgumentList @(
                $requestName,
                [string]$nextPayload.trace_id,
                $WebhookUrl,
                $payloadJson,
                $env:ASKTHIH_WEBHOOK_SECRET,
                $TimeoutSec
            )
            $jobs.Add($job)
            $jobMetadata[[string]$job.Id] = $requestName
        }

        $completed = $jobs | Where-Object { $_.State -ne "Running" }
        foreach ($job in $completed) {
            $received = Receive-Job -Job $job -ErrorAction SilentlyContinue
            if ($received) {
                foreach ($item in $received) {
                    $jobResults.Add($item)
                }
            } else {
                $jobResults.Add([pscustomobject]@{
                    name = $jobMetadata[[string]$job.Id]
                    trace_id = ""
                    secret_mode = "valid"
                    status_code = "JOB_ERROR"
                    elapsed_ms = 0
                    timed_out = $false
                    success = $false
                    error = "Background job completed without a result."
                })
            }
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            [void]$jobs.Remove($job)
        }

        if ($jobs.Count -gt 0) {
            Start-Sleep -Milliseconds 100
        }
    }

    return $jobResults.ToArray()
}

function Get-SowerBaseRowsByChannel {
    param([Parameter(Mandatory = $true)] [string]$Channel)

    $required = @("SOWERBASE_BASE_URL", "SOWERBASE_API_TOKEN", "SOWERBASE_INTAKE_TABLE_ID")
    foreach ($name in $required) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
            return [pscustomobject]@{
                available = $false
                reason = "Optional SowerBase readback env is incomplete."
                channel = $Channel
                count = $null
                duplicate_trace_ids = @()
            }
        }
    }

    if ($DryRun) {
        return [pscustomobject]@{
            available = $false
            reason = "DryRun mode does not query SowerBase."
            channel = $Channel
            count = $null
            duplicate_trace_ids = @()
        }
    }

    $baseUrl = $env:SOWERBASE_BASE_URL.TrimEnd("/")
    $tableId = $env:SOWERBASE_INTAKE_TABLE_ID
    $apiToken = $env:SOWERBASE_API_TOKEN
    $where = [System.Uri]::EscapeDataString("(Channel,eq,$Channel)")
    $apiUrl = "$baseUrl/api/v2/tables/$tableId/records?where=$where&limit=10000"
    $headers = @{
        "Authorization" = "Bearer $apiToken"
        "xc-auth" = $apiToken
    }

    try {
        $response = Invoke-WebRequest -Uri $apiUrl -Method GET -Headers $headers -TimeoutSec $TimeoutSec -ErrorAction Stop
        $data = $response.Content | ConvertFrom-Json
        $rows = @()

        if ($data.PSObject.Properties.Name -contains "list") {
            $rows = @($data.list)
        } elseif ($data -is [System.Array]) {
            $rows = @($data)
        }

        $traceCounts = @{}
        foreach ($row in $rows) {
            $traceId = $null

            foreach ($candidate in @("trace_id", "Trace ID", "TraceId")) {
                if ($row.PSObject.Properties.Name -contains $candidate) {
                    $traceId = [string]$row.$candidate
                    break
                }
            }

            if (-not $traceId -and ($row.PSObject.Properties.Name -contains "Raw Payload")) {
                try {
                    $raw = $row."Raw Payload" | ConvertFrom-Json
                    if ($raw.PSObject.Properties.Name -contains "trace_id") {
                        $traceId = [string]$raw.trace_id
                    }
                } catch {
                    $traceId = $null
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($traceId)) {
                if (-not $traceCounts.ContainsKey($traceId)) {
                    $traceCounts[$traceId] = 0
                }
                $traceCounts[$traceId]++
            }
        }

        $duplicates = @($traceCounts.GetEnumerator() | Where-Object { $_.Value -gt 1 } | ForEach-Object { $_.Key })

        [pscustomobject]@{
            available = $true
            reason = ""
            channel = $Channel
            count = $rows.Count
            duplicate_trace_ids = $duplicates
        }
    } catch {
        [pscustomobject]@{
            available = $false
            reason = "Readback query failed: $($_.Exception.Message)"
            channel = $Channel
            count = $null
            duplicate_trace_ids = @()
        }
    }
}

function Get-StatusSummary {
    param([Parameter(Mandatory = $true)] [object[]]$Results)

    $summary = [ordered]@{
        total = $Results.Count
        success = @($Results | Where-Object { $_.success }).Count
        failure = @($Results | Where-Object { -not $_.success }).Count
        status_401 = @($Results | Where-Object { "$($_.status_code)" -eq "401" }).Count
        status_400 = @($Results | Where-Object { "$($_.status_code)" -eq "400" }).Count
        status_405 = @($Results | Where-Object { "$($_.status_code)" -eq "405" }).Count
        status_5xx = @($Results | Where-Object { "$($_.status_code)" -match "^5\d\d$" }).Count
        timeouts = @($Results | Where-Object { $_.timed_out }).Count
        dryrun = @($Results | Where-Object { "$($_.status_code)" -eq "DRYRUN" }).Count
    }

    $statusGroups = $Results | Group-Object -Property status_code | Sort-Object Name
    $byStatus = [ordered]@{}
    foreach ($group in $statusGroups) {
        $byStatus[[string]$group.Name] = $group.Count
    }

    [pscustomobject]@{
        counts = $summary
        by_status = $byStatus
    }
}

function Get-TimingSummary {
    param([Parameter(Mandatory = $true)] [object[]]$Results)

    $times = @($Results | Where-Object { $_.elapsed_ms -gt 0 } | ForEach-Object { [double]$_.elapsed_ms } | Sort-Object)
    if ($times.Count -eq 0) {
        return [pscustomobject]@{
            min_ms = 0
            max_ms = 0
            avg_ms = 0
        }
    }

    [pscustomobject]@{
        min_ms = [math]::Round(($times | Select-Object -First 1), 2)
        max_ms = [math]::Round(($times | Select-Object -Last 1), 2)
        avg_ms = [math]::Round((($times | Measure-Object -Average).Average), 2)
    }
}

function New-MarkdownReport {
    param(
        [Parameter(Mandatory = $true)] [object]$Report
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# SowerBase Level 1 Local Stress Report")
    $lines.Add("")
    $lines.Add("## Run Metadata")
    $lines.Add("")
    $lines.Add("- Timestamp: $($Report.timestamp)")
    $lines.Add("- Branch: $($Report.git.branch)")
    $lines.Add("- Commit: $($Report.git.commit)")
    $lines.Add("- Webhook: $($Report.webhook.scheme)://$($Report.webhook.host):$($Report.webhook.port)")
    $lines.Add("- Webhook path: $($Report.webhook.path)")
    $lines.Add("- Marker prefix: $($Report.marker_prefix)")
    $lines.Add("- Test run ID: $($Report.test_run_id)")
    $lines.Add("- Record count: $($Report.record_count)")
    $lines.Add("- Concurrency: $($Report.concurrency)")
    $lines.Add("- Dry run: $($Report.dry_run)")
    $lines.Add("- Skip volume: $($Report.skip_volume)")
    $lines.Add("")
    $lines.Add("## Status-Code Summary")
    $lines.Add("")
    $lines.Add("| Status | Count |")
    $lines.Add("|---|---:|")
    foreach ($entry in $Report.status_summary.by_status.GetEnumerator()) {
        $lines.Add("| $($entry.Key) | $($entry.Value) |")
    }
    $lines.Add("")
    $lines.Add("## Response-Time Summary")
    $lines.Add("")
    $lines.Add("- Minimum ms: $($Report.timing_summary.min_ms)")
    $lines.Add("- Average ms: $($Report.timing_summary.avg_ms)")
    $lines.Add("- Maximum ms: $($Report.timing_summary.max_ms)")
    $lines.Add("")
    $lines.Add("## Auth Rejection Proof")
    $lines.Add("")
    $lines.Add("- Missing-secret status: $($Report.probes.missing_secret.status_code)")
    $lines.Add("- Wrong-secret status: $($Report.probes.wrong_secret.status_code)")
    $lines.Add("- Missing-secret row count: $($Report.readback.auth_missing.count)")
    $lines.Add("- Wrong-secret row count: $($Report.readback.auth_wrong.count)")
    $lines.Add("- Readback available: $($Report.readback.main.available)")
    $lines.Add("")
    $lines.Add("## Single-Write Proof")
    $lines.Add("")
    $lines.Add("- Single-write status: $($Report.probes.single_valid.status_code)")
    $lines.Add("- Single-write elapsed ms: $($Report.probes.single_valid.elapsed_ms)")
    $lines.Add("- Single-write trace ID: $($Report.probes.single_valid.trace_id)")
    $lines.Add("- Single-write row count: $($Report.readback.single.count)")
    $lines.Add("")
    $lines.Add("## Volume Summary")
    $lines.Add("")
    $lines.Add("- Volume requested: $($Report.volume.requested)")
    $lines.Add("- Volume sent: $($Report.volume.sent)")
    $lines.Add("- Volume successes: $($Report.volume.successes)")
    $lines.Add("- Volume failures: $($Report.volume.failures)")
    $lines.Add("- Main channel row count: $($Report.readback.main.count)")
    $lines.Add("")
    $lines.Add("## Duplicate Findings")
    $lines.Add("")
    $lines.Add("- Duplicate trace IDs found: $($Report.duplicates.count)")
    if ($Report.duplicates.items.Count -gt 0) {
        foreach ($item in $Report.duplicates.items) {
            $lines.Add("  - $item")
        }
    } else {
        $lines.Add("- Duplicate trace ID list: none reported")
    }
    $lines.Add("")
    $lines.Add("## Failures")
    $lines.Add("")
    if ($Report.failures.Count -gt 0) {
        foreach ($failure in $Report.failures) {
            $lines.Add("- $($failure.name): status=$($failure.status_code), trace=$($failure.trace_id), error=$($failure.error)")
        }
    } else {
        $lines.Add("- None recorded by harness.")
    }
    $lines.Add("")
    $lines.Add("## Candidate Ruling")
    $lines.Add("")
    $lines.Add($Report.candidate_ruling)
    $lines.Add("")
    $lines.Add("## Non-Claims")
    $lines.Add("")
    $lines.Add("- Airtable has not been replaced.")
    $lines.Add("- SowerBase is not certified as Airtable replacement from this report alone.")
    $lines.Add("- Public SowerBase receiver is not proven.")
    $lines.Add("- CRM is not connected.")
    $lines.Add("- Canon is not connected.")
    $lines.Add("- Cloudflare is not adopted.")
    $lines.Add("- No production deployment or Vercel env change is implied.")

    $lines -join [Environment]::NewLine
}

$git = Get-GitInfo
$webhook = Get-WebhookSurface -Url $WebhookUrl

$missingPayload = New-SyntheticPayload -Index 0 -TraceId (New-TraceId -Prefix "missing-secret" -Index 0) -Channel $authMissingChannel
$wrongPayload = New-SyntheticPayload -Index 0 -TraceId (New-TraceId -Prefix "wrong-secret" -Index 0) -Channel $authWrongChannel
$singlePayload = New-SyntheticPayload -Index 1 -TraceId (New-TraceId -Prefix "single" -Index 1) -Channel $singleChannel

$allResults = New-Object System.Collections.Generic.List[object]

$missingSecretProbe = Invoke-CertWebhookRequest -Name "missing-secret-probe" -Payload $missingPayload -SecretMode "missing"
$wrongSecretProbe = Invoke-CertWebhookRequest -Name "wrong-secret-probe" -Payload $wrongPayload -SecretMode "wrong"
$singleValidProbe = Invoke-CertWebhookRequest -Name "single-valid-probe" -Payload $singlePayload -SecretMode "valid"

$allResults.Add($missingSecretProbe)
$allResults.Add($wrongSecretProbe)
$allResults.Add($singleValidProbe)

$volumeResults = @()
if (-not $SkipVolume) {
    $payloads = New-Object System.Collections.Generic.List[object]
    for ($i = 1; $i -le $RecordCount; $i++) {
        $payloads.Add((New-SyntheticPayload -Index $i -TraceId (New-TraceId -Prefix "volume" -Index $i) -Channel $mainChannel))
    }
    $volumeResults = @(Invoke-CertWebhookBatch -Payloads $payloads.ToArray())
    foreach ($result in $volumeResults) {
        $allResults.Add($result)
    }
}

$authMissingReadback = Get-SowerBaseRowsByChannel -Channel $authMissingChannel
$authWrongReadback = Get-SowerBaseRowsByChannel -Channel $authWrongChannel
$singleReadback = Get-SowerBaseRowsByChannel -Channel $singleChannel
$mainReadback = Get-SowerBaseRowsByChannel -Channel $mainChannel

$duplicates = @()
if ($singleReadback.available -and $singleReadback.duplicate_trace_ids) {
    $duplicates += @($singleReadback.duplicate_trace_ids)
}
if ($mainReadback.available -and $mainReadback.duplicate_trace_ids) {
    $duplicates += @($mainReadback.duplicate_trace_ids)
}
$duplicates = @($duplicates | Sort-Object -Unique)

$statusSummary = Get-StatusSummary -Results $allResults.ToArray()
$timingSummary = Get-TimingSummary -Results $allResults.ToArray()
$failures = @($allResults | Where-Object {
    "$($_.status_code)" -notin @("DRYRUN") -and
    -not (
        ($_.name -eq "missing-secret-probe" -and "$($_.status_code)" -eq "401") -or
        ($_.name -eq "wrong-secret-probe" -and "$($_.status_code)" -eq "401") -or
        ($_.name -eq "single-valid-probe" -and $_.success) -or
        ($_.name -like "volume-*" -and $_.success)
    )
})

$volumeSuccesses = @($volumeResults | Where-Object { $_.success }).Count
$volumeFailures = @($volumeResults | Where-Object { -not $_.success }).Count

$candidateRuling = "NOT_RUN: DryRun mode generated reports without sending requests."
if (-not $DryRun) {
    $authPass = ("$($missingSecretProbe.status_code)" -eq "401" -and "$($wrongSecretProbe.status_code)" -eq "401")
    $singlePass = $singleValidProbe.success
    $volumePass = ($SkipVolume -or ($volumeResults.Count -eq $RecordCount -and $volumeFailures -eq 0))
    $readbackRequiredPass = $true

    if ($authMissingReadback.available) {
        $readbackRequiredPass = $readbackRequiredPass -and ($authMissingReadback.count -eq 0)
    }
    if ($authWrongReadback.available) {
        $readbackRequiredPass = $readbackRequiredPass -and ($authWrongReadback.count -eq 0)
    }
    if ($mainReadback.available -and -not $SkipVolume) {
        $readbackRequiredPass = $readbackRequiredPass -and ($mainReadback.count -eq $RecordCount)
    }

    if ($authPass -and $singlePass -and $volumePass -and $readbackRequiredPass -and $duplicates.Count -eq 0) {
        if ($SkipVolume) {
            $candidateRuling = "PARTIAL_PASS_CANDIDATE: Auth and single-write probes passed; volume was skipped."
        } else {
            $candidateRuling = "PASS_CANDIDATE: Harness observations satisfy the configured local Level 1 run. Human review still required."
        }
    } else {
        $candidateRuling = "FAIL_CANDIDATE: One or more probes, volume writes, readback checks, or duplicate checks failed."
    }
}

$report = [pscustomobject]@{
    timestamp = (Get-Date -AsUTC).ToString("o")
    git = $git
    webhook = $webhook
    marker_prefix = $MarkerPrefix
    test_run_id = $TestRunId
    record_count = $RecordCount
    concurrency = $Concurrency
    vertical = $Vertical
    dry_run = [bool]$DryRun
    skip_volume = [bool]$SkipVolume
    timeout_sec = $TimeoutSec
    probes = [pscustomobject]@{
        missing_secret = $missingSecretProbe
        wrong_secret = $wrongSecretProbe
        single_valid = $singleValidProbe
    }
    volume = [pscustomobject]@{
        requested = if ($SkipVolume) { 0 } else { $RecordCount }
        sent = $volumeResults.Count
        successes = $volumeSuccesses
        failures = $volumeFailures
    }
    status_summary = $statusSummary
    timing_summary = $timingSummary
    readback = [pscustomobject]@{
        auth_missing = $authMissingReadback
        auth_wrong = $authWrongReadback
        single = $singleReadback
        main = $mainReadback
    }
    duplicates = [pscustomobject]@{
        count = $duplicates.Count
        items = $duplicates
    }
    failures = $failures
    candidate_ruling = $candidateRuling
    non_claims = @(
        "Airtable has not been replaced.",
        "SowerBase is not certified as Airtable replacement from this report alone.",
        "Public SowerBase receiver is not proven.",
        "CRM is not connected.",
        "Canon is not connected.",
        "Cloudflare is not adopted."
    )
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$jsonPath = Join-Path $OutputDir "SOWERBASE_LEVEL1_LOCAL_STRESS_REPORT_$TestRunId.json"
$markdownPath = Join-Path $OutputDir "SOWERBASE_LEVEL1_LOCAL_STRESS_REPORT_$TestRunId.md"

$report | ConvertTo-Json -Depth 20 | Set-Content -Path $jsonPath -Encoding UTF8
New-MarkdownReport -Report $report | Set-Content -Path $markdownPath -Encoding UTF8

Write-Host "SowerBase Level 1 local stress harness report written."
Write-Host "Markdown: $markdownPath"
Write-Host "JSON: $jsonPath"
Write-Host "Candidate ruling: $candidateRuling"

if ($candidateRuling -like "FAIL*") {
    exit 1
}

exit 0




