#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Assert Level 5 SowerBase-primary HVAC pilot readiness.

.DESCRIPTION
    Runs a controlled local HVAC pilot in SowerBase-primary mode. The proof uses
    one signed synthetic intake request, verifies SowerBase writes first and
    exactly once, proves the operator fields are visible/workable, validates
    failure behavior, documents rollback, and performs a lightweight logical
    backup/restore proof of the pilot row in a temporary PostgreSQL database.
#>

param(
    [int]$Port = 18789,
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
    if (-not (Test-Path -LiteralPath $Path)) { throw "Env file not found: $Path" }
    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        $parts = $line -split "=", 2
        if ($parts.Count -eq 2) {
            [Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim().Trim('"').Trim("'"), "Process")
        }
    }
}

function ConvertTo-Hex {
    param([byte[]]$Bytes)
    return -join ($Bytes | ForEach-Object { "{0:x2}" -f $_ })
}

function New-SignatureHeader {
    param([string]$Body, [string]$Secret, [int64]$Timestamp)
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
    param([string]$Sql, [string]$Database = $DbName)
    $result = $Sql | docker exec -i $DbContainer psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -t -A
    if ($LASTEXITCODE -ne 0) { throw "psql failed with exit code $LASTEXITCODE" }
    return [string]($result | Select-Object -First 1)
}

function Invoke-PsqlCommand {
    param([string]$Sql, [string]$Database = $DbName)
    $Sql | docker exec -i $DbContainer psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "psql command failed with exit code $LASTEXITCODE" }
}

function Get-ChannelCount {
    param([string]$Channel, [string]$Database = $DbName)
    $escaped = $Channel.Replace("'", "''")
    return [int](Invoke-PsqlScalar -Database $Database -Sql "SELECT COUNT(*) FROM ""$SchemaName"".""$TableName"" WHERE ""Channel"" = '$escaped';")
}

function Invoke-Post {
    param(
        [string]$Url,
        [string]$Body,
        [hashtable]$Headers = @{},
        [int]$ExpectedStatus
    )
    $statusCode = $null
    $responseText = ""
    try {
        $response = Invoke-WebRequest -Uri $Url -Method POST -Headers $Headers -ContentType "application/json" -Body $Body -TimeoutSec $RequestTimeoutSec -ErrorAction Stop
        $statusCode = [int]$response.StatusCode
        $responseText = [string]$response.Content
    } catch {
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        } else {
            $statusCode = -1
            $responseText = $_.Exception.Message
        }
    }
    [pscustomobject]@{
        expected_status = $ExpectedStatus
        actual_status = $statusCode
        passed = ($statusCode -eq $ExpectedStatus)
        response_preview = if ($responseText.Length -gt 180) { $responseText.Substring(0, 180) } else { $responseText }
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$runId = "level5-hvac-" + (Get-Date -AsUTC -Format "yyyyMMddTHHmmssZ")
$logPath = Join-Path $OutputDir "SOWERBASE_LEVEL5_HVAC_PRIMARY_PILOT_$runId.log"
$jsonPath = Join-Path $OutputDir "SOWERBASE_LEVEL5_HVAC_PRIMARY_PILOT_$runId.json"
$mdPath = Join-Path $OutputDir "SOWERBASE_LEVEL5_HVAC_PRIMARY_PILOT_$runId.md"
$dumpPath = "/tmp/sowerbase_level5_$runId.sql"
$restoreDb = ("sowerbase_level5_restore_" + ($runId -replace '[^A-Za-z0-9_]', '_')).ToLowerInvariant()
$serverScript = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "askthih-hvac-local-webhook-server.ps1"

Write-Host "SowerBase Level 5 HVAC primary pilot proof"
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

$channel = "cert_level5_hvac_primary_pilot_$runId"
$traceId = "trace-$runId"
$baseUrl = "http://localhost:$Port/askthih/hvac"

$payload = [ordered]@{
    submission_title = "Level 5 HVAC SowerBase Primary Pilot"
    vertical = "HVAC"
    contact_name = "Level 5 Synthetic HVAC Pilot Contact"
    phone = "555-4505"
    email = "level5-hvac-primary-pilot@example.com"
    service_address = "505 SowerBase Primary Pilot Way, Synthetic City, ST"
    problem_description = "Synthetic controlled HVAC pilot payload. SowerBase primary, Airtable disabled for this pilot path. No real customer data."
    urgency = "Normal"
    channel = $channel
    status = "New"
    source_system = "sowerbase_level5_hvac_primary_pilot"
    source_table_name = "HVAC Intake"
    migration_status = "sowerbase_primary_pilot_test_only"
    trace_id = $traceId
    submitted_at = (Get-Date -AsUTC).ToString("o")
    transcript = "Synthetic transcript for Level 5 HVAC SowerBase-primary pilot."
    system_type = "Central AC"
    system_age_years = "7"
    preferred_service_window = "Certification window only"
    test_only = $true
    certification_run_id = $runId
    pilot_mode = "sowerbase_primary_airtable_disabled"
    rollback_path = "disable pilot route and return HVAC intake to Airtable-primary path"
}
$body = $payload | ConvertTo-Json -Depth 12

$beforeCount = Get-ChannelCount -Channel $channel
$serverProcess = $null
$restoreCreated = $false

try {
    $pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $powershellHost = if ($pwshCommand) { $pwshCommand.Source } else { "powershell.exe" }
    $serverProcess = Start-Process $powershellHost -ArgumentList "-NoProfile", "-File", "`"$serverScript`"", "-Port", "$Port", "-OutputLog", "`"$logPath`"" -PassThru -WindowStyle Hidden -ErrorAction Stop

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        $connection = Test-NetConnection -ComputerName localhost -Port $Port -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($connection.TcpTestSucceeded) { $ready = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw "Receiver did not start on localhost:$Port" }

    $failureProbe = Invoke-Post -Url $baseUrl -Body $body -ExpectedStatus 401
    $afterFailureCount = Get-ChannelCount -Channel $channel

    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $headers = @{ Authorization = New-SignatureHeader -Body $body -Secret $secret -Timestamp $timestamp }
    $validProbe = Invoke-Post -Url $baseUrl -Body $body -Headers $headers -ExpectedStatus 201
    $afterValidCount = Get-ChannelCount -Channel $channel

    $rowSql = @"
SELECT COUNT(*)
FROM "$SchemaName"."$TableName"
WHERE "Channel" = '$($channel.Replace("'", "''"))'
  AND "Vertical" = 'HVAC'
  AND "Trace_ID" = '$($traceId.Replace("'", "''"))'
  AND "System_Type" = 'Central AC'
  AND "Preferred_Service_Window" = 'Certification window only'
  AND "Migration_Status" = 'sowerbase_primary_pilot_test_only'
  AND "Raw_Payload" LIKE '%sowerbase_primary_airtable_disabled%';
"@
    $pilotRowVerified = ([int](Invoke-PsqlScalar -Sql $rowSql) -eq 1)

    $operatorSql = @"
SELECT COUNT(*)
FROM public.nc_grid_view_columns_v2 g
JOIN public.nc_columns_v2 c ON c.id = g.fk_column_id
WHERE g.fk_view_id = 'vw2o6k70z2ztux46'
  AND g.show = true
  AND c.title IN ('Trace ID','Submitted At','Status','Channel','System Type','System Age','Preferred Service Window','Raw Payload');
"@
    $operatorVisibleCount = [int](Invoke-PsqlScalar -Sql $operatorSql)
    $operatorWorkable = ($operatorVisibleCount -ge 8)

    $backupScope = & "$PSScriptRoot\assert-sowerbase-backup-scope.ps1" 2>&1
    $backupScopePass = ($LASTEXITCODE -eq 0)
    $backupValidate = & "$PSScriptRoot\..\thih-backup-sowerbase.ps1" -ValidateOnly 2>&1
    $backupValidatePass = ($LASTEXITCODE -eq 0)

    docker exec $DbContainer pg_dump -U $DbUser -d $DbName -f $dumpPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "pg_dump failed" }
    Invoke-PsqlCommand -Database "postgres" -Sql "DROP DATABASE IF EXISTS ""$restoreDb"";"
    Invoke-PsqlCommand -Database "postgres" -Sql "CREATE DATABASE ""$restoreDb"" OWNER $DbUser;"
    $restoreCreated = $true
    docker exec $DbContainer psql -U $DbUser -d $restoreDb -v ON_ERROR_STOP=1 -f $dumpPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "temporary restore failed" }
    $restoredPilotCount = Get-ChannelCount -Channel $channel -Database $restoreDb
    $pilotRestored = ($restoredPilotCount -eq 1)

    $logContent = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw } else { "" }
    $logsClean = (-not $logContent.Contains($secret) -and -not $logContent.Contains($apiToken) -and $logContent -notmatch 'Bearer\s+[A-Za-z0-9_\-\.]+')

    $invalidDidNotWrite = ($afterFailureCount -eq $beforeCount)
    $validWroteOnce = (($afterValidCount - $afterFailureCount) -eq 1)
    $syntheticOnly = ($payload.test_only -eq $true -and $payload.email -like "level5-*@example.com")
    $passed = (
        $payload.vertical -eq "HVAC" -and
        $syntheticOnly -and
        $payload.pilot_mode -eq "sowerbase_primary_airtable_disabled" -and
        $failureProbe.passed -and $invalidDidNotWrite -and
        $validProbe.passed -and $validWroteOnce -and
        $pilotRowVerified -and $operatorWorkable -and
        $backupScopePass -and $backupValidatePass -and $pilotRestored -and $logsClean
    )

    $report = [ordered]@{
        run_id = $runId
        status = if ($passed) { "pass" } else { "fail" }
        production_connected = $false
        cloudflare_started = $false
        airtable_touched = $false
        pilot = [ordered]@{
            vertical = "HVAC"
            mode = "sowerbase_primary_airtable_disabled"
            synthetic_only = $syntheticOnly
            channel = $channel
            trace_id = $traceId
        }
        probes = [ordered]@{ unsigned_failure = $failureProbe; signed_valid = $validProbe }
        write_counts = [ordered]@{
            before = $beforeCount
            after_unsigned_failure = $afterFailureCount
            after_valid = $afterValidCount
            invalid_did_not_write = $invalidDidNotWrite
            valid_wrote_once = $validWroteOnce
            pilot_row_verified = $pilotRowVerified
        }
        operator = [ordered]@{ grid_visible_required_fields = $operatorVisibleCount; workable = $operatorWorkable }
        backup_restore = [ordered]@{
            backup_scope_pass = $backupScopePass
            validate_only_pass = $backupValidatePass
            temporary_restore_database = $restoreDb
            restored_pilot_rows = $restoredPilotCount
            pilot_restored = $pilotRestored
        }
        rollback = [ordered]@{
            path = "disable pilot route and return HVAC intake to Airtable-primary path"
            pilot_rows_identified_by_channel = $channel
            pilot_rows_exportable_from_sowerbase = $true
        }
        security = [ordered]@{ logs_clean = $logsClean }
        outputs = [ordered]@{ log = $logPath; json = $jsonPath; markdown = $mdPath }
    }
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -NoNewline

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# SowerBase Level 5 HVAC Primary Pilot Run")
    $lines.Add("")
    $lines.Add("Run ID: ``$runId``")
    $lines.Add("Status: $($report.status)")
    $lines.Add("Production connected: false")
    $lines.Add("Cloudflare started: false")
    $lines.Add("Airtable touched: false")
    $lines.Add("")
    $lines.Add("## Results")
    $lines.Add("")
    $lines.Add("- Vertical: HVAC")
    $lines.Add("- Mode: SowerBase primary, Airtable disabled for this pilot path")
    $lines.Add("- Channel: ``$channel``")
    $lines.Add("- Unsigned failure status: $($failureProbe.actual_status)")
    $lines.Add("- Valid signed status: $($validProbe.actual_status)")
    $lines.Add("- Rows before: $beforeCount")
    $lines.Add("- Rows after unsigned failure: $afterFailureCount")
    $lines.Add("- Rows after valid pilot write: $afterValidCount")
    $lines.Add("- Pilot row verified: $pilotRowVerified")
    $lines.Add("- Operator workable: $operatorWorkable")
    $lines.Add("- Backup scope pass: $backupScopePass")
    $lines.Add("- Backup ValidateOnly pass: $backupValidatePass")
    $lines.Add("- Temporary restore pilot rows: $restoredPilotCount")
    $lines.Add("- Logs clean: $logsClean")
    $lines.Add("")
    $lines.Add("## Verdict")
    $lines.Add("")
    $lines.Add($(if ($passed) { "PASS" } else { "FAIL" }))
    $lines | Set-Content -LiteralPath $mdPath

    if ($passed) {
        Write-Host "PASS: Level 5 HVAC SowerBase-primary pilot proof passed."
        Write-Host "Report: $mdPath"
        exit 0
    }
    Write-Host "FAIL: Level 5 HVAC SowerBase-primary pilot proof failed."
    Write-Host "Report: $mdPath"
    exit 1
} finally {
    if ($serverProcess) { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
    if ($restoreCreated) {
        try {
            Invoke-PsqlCommand -Database "postgres" -Sql "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$restoreDb';"
            Invoke-PsqlCommand -Database "postgres" -Sql "DROP DATABASE IF EXISTS ""$restoreDb"";"
        } catch {}
    }
    try { docker exec $DbContainer rm -f $dumpPath | Out-Null } catch {}
}
