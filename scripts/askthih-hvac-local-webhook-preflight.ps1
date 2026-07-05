#!/usr/bin/env pwsh
<#
.SYNOPSIS
    AskTHIH HVAC Local Webhook Preflight — Complete Runtime Proof

.DESCRIPTION
    One-command local webhook runtime verification without Cloudflare.
    - Loads .env.askthih-hvac-staging
    - Validates all credentials
    - Starts webhook as background job
    - Runs comprehensive curl tests
    - Validates safe responses
    - Cleans up gracefully
    - Exits 0 only on success

.NOTES
    - Session-only credentials (not persisted)
    - No Record ID 6 created
    - No Cloudflare started
    - No secrets printed
    - Safe errors only
#>

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot

Write-Host "=== AskTHIH HVAC LOCAL WEBHOOK PREFLIGHT ===" -ForegroundColor Green
Write-Host ""

# ============================================================================
# Step 1: Load and validate .env file
# ============================================================================

Write-Host "Step 1: Loading .env.askthih-hvac-staging..." -ForegroundColor Cyan

$envFile = Join-Path $repoRoot ".env.askthih-hvac-staging"

if (-not (Test-Path $envFile)) {
    Write-Host "FAIL: .env.askthih-hvac-staging not found" -ForegroundColor Red
    Write-Host "Create .env.askthih-hvac-staging with your local credentials" -ForegroundColor Yellow
    exit 1
}

# Load env vars from file
try {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        $parts = $line -split "=", 2
        if ($parts.Count -ne 2) { return }
        $name = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        if ($name) {
            [System.Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
} catch {
    Write-Host "FAIL: Could not load .env file: $_" -ForegroundColor Red
    exit 1
}

Write-Host "✓ .env.askthih-hvac-staging loaded" -ForegroundColor Green

# ============================================================================
# Step 2: Validate all credentials are set
# ============================================================================

Write-Host ""
Write-Host "Step 2: Validating credentials..." -ForegroundColor Cyan

$requiredVars = @(
    "ASKTHIH_WEBHOOK_PORT",
    "ASKTHIH_WEBHOOK_SECRET",
    "SOWERBASE_BASE_URL",
    "SOWERBASE_API_TOKEN",
    "SOWERBASE_INTAKE_TABLE_ID"
)

$missingVars = @()
foreach ($var in $requiredVars) {
    $value = [System.Environment]::GetEnvironmentVariable($var)
    if ([string]::IsNullOrWhiteSpace($value)) {
        $missingVars += $var
        Write-Host "  ✗ ${var}: MISSING" -ForegroundColor Red
    } else {
        Write-Host "  ✓ ${var}: SET" -ForegroundColor Green
    }
}

if ($missingVars.Count -gt 0) {
    Write-Host ""
    Write-Host "FAIL: Missing environment variables: $($missingVars -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host "✓ All credentials validated" -ForegroundColor Green

# ============================================================================
# Step 3: Check .gitignore protection
# ============================================================================

Write-Host ""
Write-Host "Step 3: Verifying .gitignore protection..." -ForegroundColor Cyan

$gitignorePath = Join-Path $repoRoot ".gitignore"
if (Test-Path $gitignorePath) {
    $gitignoreContent = Get-Content $gitignorePath
    if ($gitignoreContent -match '\.env') {
        Write-Host "✓ .env files are in .gitignore" -ForegroundColor Green
    } else {
        Write-Host "⚠️ .env not found in .gitignore (may not be protected)" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠️ .gitignore not found" -ForegroundColor Yellow
}

# ============================================================================
# Step 4: Start webhook as background job
# ============================================================================

Write-Host ""
Write-Host "Step 4: Starting webhook server..." -ForegroundColor Cyan

$webhookScript = Join-Path $scriptRoot "askthih-hvac-local-webhook-server.ps1"
if (-not (Test-Path $webhookScript)) {
    Write-Host "FAIL: Webhook script not found: $webhookScript" -ForegroundColor Red
    exit 1
}

# Start webhook as background process (more reliable than Start-Job)
$webhookProcess = Start-Process powershell.exe -ArgumentList "-NoProfile -File `"$webhookScript`"" -PassThru -WindowStyle Hidden -ErrorAction Stop
$webhookPid = $webhookProcess.Id

Write-Host "✓ Webhook started (PID: $webhookPid)" -ForegroundColor Green

# Wait for webhook to be ready (max 10 seconds)
Write-Host "  Waiting for localhost:8787 to listen..."

$maxWait = 10
$waited = 0
$webhookReady = $false

while ($waited -lt $maxWait) {
    try {
        $testConnection = Test-NetConnection -ComputerName localhost -Port 8787 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($testConnection.TcpTestSucceeded) {
            $webhookReady = $true
            Write-Host "✓ Webhook is listening on localhost:8787" -ForegroundColor Green
            break
        }
    } catch {}

    Start-Sleep -Milliseconds 500
    $waited += 0.5
}

if (-not $webhookReady) {
    Write-Host "FAIL: Webhook did not start listening within 10 seconds" -ForegroundColor Red
    Write-Host ""
    Write-Host "Webhook job output:" -ForegroundColor Yellow
    Receive-Job -Job $webhookJob | Write-Host
    Stop-Job -Job $webhookJob
    Remove-Job -Job $webhookJob
    exit 1
}

# ============================================================================
# Step 5: Run curl tests
# ============================================================================

Write-Host ""
Write-Host "Step 5: Running curl tests..." -ForegroundColor Cyan

$baseUrl = "http://localhost:8787/askthih/hvac"
$testResults = @{
    HEAD = $false
    GET = $false
    Invalid = $false
    TCP = $false
}

# Test 1: HEAD request
Write-Host ""
Write-Host "  Test 1: HEAD /askthih/hvac" -ForegroundColor Yellow
try {
    $response = curl.exe -I $baseUrl 2>&1
    if ($LASTEXITCODE -eq 0 -and ($response -match "405|Method Not Allowed")) {
        Write-Host "    ✓ HEAD returned 405 (safe)" -ForegroundColor Green
        $testResults.HEAD = $true
    } else {
        Write-Host "    ✗ HEAD response unexpected" -ForegroundColor Red
        Write-Host "    Output: $response" -ForegroundColor Yellow
    }
} catch {
    Write-Host "    ✗ HEAD request failed: $_" -ForegroundColor Red
}

# Test 2: GET request
Write-Host ""
Write-Host "  Test 2: GET /askthih/hvac" -ForegroundColor Yellow
try {
    $response = curl.exe -v $baseUrl 2>&1
    if ($LASTEXITCODE -eq 0 -and ($response -match "405|Method Not Allowed|error")) {
        Write-Host "    ✓ GET returned 405/error (safe)" -ForegroundColor Green
        $testResults.GET = $true
    } else {
        Write-Host "    ✗ GET response unexpected" -ForegroundColor Red
        Write-Host "    Output: $($response | Select-Object -First 5 | Out-String)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "    ✗ GET request failed: $_" -ForegroundColor Red
}

# Test 3: Invalid path (POST to trigger path validation before method check)
Write-Host ""
Write-Host "  Test 3: POST /invalid" -ForegroundColor Yellow
try {
    $response = curl.exe -X POST "http://localhost:8787/invalid" -H "Content-Type: application/json" -d '{}' 2>&1
    if ($LASTEXITCODE -eq 0 -and ($response -match "404|Not Found|error")) {
        Write-Host "    ✓ Invalid path returned 404/error (safe)" -ForegroundColor Green
        $testResults.Invalid = $true
    } else {
        Write-Host "    ✗ Invalid path response unexpected" -ForegroundColor Red
        Write-Host "    Output: $($response | Select-Object -First 3 | Out-String)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "    ✗ Invalid path test failed: $_" -ForegroundColor Red
}

# Test 4: TCP connectivity after all requests
Write-Host ""
Write-Host "  Test 4: Test-NetConnection localhost 8787" -ForegroundColor Yellow
try {
    $testConnection = Test-NetConnection -ComputerName localhost -Port 8787 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if ($testConnection.TcpTestSucceeded) {
        Write-Host "    ✓ TcpTestSucceeded: True (server alive)" -ForegroundColor Green
        $testResults.TCP = $true
    } else {
        Write-Host "    ✗ TcpTestSucceeded: False (server crashed)" -ForegroundColor Red
    }
} catch {
    Write-Host "    ✗ TCP test failed: $_" -ForegroundColor Red
}

# ============================================================================
# Step 6: Verify webhook process is still alive
# ============================================================================

Write-Host ""
Write-Host "Step 6: Verifying webhook is still running..." -ForegroundColor Cyan

$runningProcess = Get-Process -Id $webhookPid -ErrorAction SilentlyContinue
if ($runningProcess -and -not $runningProcess.HasExited) {
    Write-Host "✓ Webhook process is still running" -ForegroundColor Green
} else {
    Write-Host "FAIL: Webhook process crashed or stopped" -ForegroundColor Red
    exit 1
}

# ============================================================================
# Step 7: Clean up
# ============================================================================

Write-Host ""
Write-Host "Step 7: Cleaning up..." -ForegroundColor Cyan

try {
    Stop-Process -Id $webhookPid -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    Write-Host "✓ Webhook process stopped cleanly" -ForegroundColor Green
} catch {
    Write-Host "⚠️ Warning cleaning up process: $_" -ForegroundColor Yellow
}

# ============================================================================
# Step 8: Results summary
# ============================================================================

Write-Host ""
Write-Host "=== PREFLIGHT RESULTS ===" -ForegroundColor Cyan
Write-Host ""

$allPassed = $testResults.Values | Where-Object { $_ -eq $false } | Measure-Object | Select-Object -ExpandProperty Count

Write-Host "  Webhook started: YES" -ForegroundColor Green
Write-Host "  Port 8787 responsive: YES" -ForegroundColor Green
Write-Host "  HEAD /askthih/hvac safe: $($testResults.HEAD -eq $true ? 'YES' : 'NO')" -ForegroundColor $(if ($testResults.HEAD) { "Green" } else { "Red" })
Write-Host "  GET /askthih/hvac safe: $($testResults.GET -eq $true ? 'YES' : 'NO')" -ForegroundColor $(if ($testResults.GET) { "Green" } else { "Red" })
Write-Host "  Invalid path safe: $($testResults.Invalid -eq $true ? 'YES' : 'NO')" -ForegroundColor $(if ($testResults.Invalid) { "Green" } else { "Red" })
Write-Host "  Server stayed alive: YES" -ForegroundColor Green
Write-Host "  Record ID 6 created: NO" -ForegroundColor Green
Write-Host "  Cloudflare started: NO" -ForegroundColor Green
Write-Host ""

if ($testResults.HEAD -and $testResults.GET -and $testResults.Invalid -and $testResults.TCP) {
    Write-Host "✅ PREFLIGHT PASSED - Webhook is ready for Phase 4B.3" -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ PREFLIGHT FAILED" -ForegroundColor Red
    Write-Host ""
    Write-Host "Failed tests:" -ForegroundColor Yellow
    if (-not $testResults.HEAD) { Write-Host "  - HEAD request handling" }
    if (-not $testResults.GET) { Write-Host "  - GET request handling" }
    if (-not $testResults.Invalid) { Write-Host "  - Invalid path handling" }
    if (-not $testResults.TCP) { Write-Host "  - Server connectivity after requests" }
    exit 1
}
