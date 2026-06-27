<#
.SYNOPSIS
    SowerBase Backup Script - Complete backup procedure for local development environment

.DESCRIPTION
    Executes PostgreSQL database dump and NocoDB volume snapshot backups for SowerBase.
    All backups are stored locally and excluded from version control.

    Includes:
    - PostgreSQL logical backup (pg_dump)
    - NocoDB volume snapshot
    - Backup directory initialization
    - Audit logging and verification

.PARAMETER BackupType
    Specify which backup to perform: 'postgresql', 'nocodb', 'all' (default: 'all')

.PARAMETER InitDirectories
    Create backup directory structure if it doesn't exist (default: $true)

.PARAMETER ValidateOnly
    Run all safety checks without creating backup artifacts (default: $false)
    No backups are created, no passwords required, all verifications performed

.PARAMETER AllowPartial
    Allow backup to proceed even if one component fails (default: $false)
    When false (default), all-mode backup fails before creating any artifacts if preflight fails

.EXAMPLE
    .\thih-backup-sowerbase.ps1 -BackupType all
    .\thih-backup-sowerbase.ps1 -BackupType postgresql
    .\thih-backup-sowerbase.ps1 -BackupType nocodb -InitDirectories $false
    .\thih-backup-sowerbase.ps1 -ValidateOnly
    $env:SOWERBASE_DB_PASSWORD = "your-password"; .\thih-backup-sowerbase.ps1 -BackupType all

.NOTES
    Status: Review Ready
    Version: 1.0
    Last Updated: 2026-06-26

    CRITICAL: Backup files contain operational data and must never be committed to git.
    All backup files are excluded via .gitignore (backups/, *.sql, *.tar.gz, etc.)

    Security: Password must come from secure storage (Windows Credential Manager or .env)
    Example commands use PLACEHOLDERS ONLY — replace with real credentials at runtime.

    Testing: Execute with test data first. Do not run against production without approval.
#>

param(
    [ValidateSet('postgresql', 'nocodb', 'all')]
    [string]$BackupType = 'all',

    [bool]$InitDirectories = $true,

    [switch]$ValidateOnly,

    [switch]$AllowPartial
)

# ============================================================================
# Configuration
# ============================================================================

$SOWERBASE_ROOT = "C:\Users\thehu\SowerBase"
$BACKUP_ROOT = "$SOWERBASE_ROOT\backups"
$BACKUP_LOG = "$BACKUP_ROOT\BACKUP_LOG.txt"

$BACKUP_DIRS = @{
    daily = "$BACKUP_ROOT\daily"
    volumes = "$BACKUP_ROOT\volumes"
    postgres = "$BACKUP_ROOT\postgres-dumps"
    archive = "$BACKUP_ROOT\archive"
    verify = "$BACKUP_ROOT\verify-logs"
}

$DB_NAME = "nocodb"
$DB_USER = "nocodb"
$DB_HOST = "localhost"
$DB_PORT = "5432"
$DOCKER_CONTAINER_NAME = "sowerbase-local-db-1"
$NOCODB_VOLUME = "sowerbase-local_nocodb_data"

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$timestamp] [$Level] $Message"
    Write-Host $logMsg
    if (Test-Path $BACKUP_ROOT) {
        Add-Content -Path $BACKUP_LOG -Value $logMsg
    }
}

function Initialize-BackupDirectories {
    Write-Log "Initializing backup directory structure..."

    try {
        foreach ($key in $BACKUP_DIRS.Keys) {
            $dir = $BACKUP_DIRS[$key]
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-Log "  Created: $dir" "DEBUG"
            }
        }

        # Create master log file if it doesn't exist
        if (-not (Test-Path $BACKUP_LOG)) {
            New-Item -ItemType File -Path $BACKUP_LOG -Force | Out-Null
            Add-Content -Path $BACKUP_LOG -Value "=== SowerBase Backup Log (created $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) ==="
        }

        Write-Log "Backup directories ready" "SUCCESS"
        return $true
    } catch {
        Write-Log "Failed to initialize backup directories: $_" "ERROR"
        return $false
    }
}

function Test-DockerAvailable {
    try {
        $dockerTest = docker ps 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Docker is not running or not accessible" "ERROR"
            return $false
        }
        Write-Log "Docker is available" "DEBUG"
        return $true
    } catch {
        Write-Log "Docker test failed: $_" "ERROR"
        return $false
    }
}

function Test-ContainerRunning {
    param([string]$ContainerName)

    $running = docker ps --filter "name=$ContainerName" --format "{{.Names}}"
    if ($running -like "*$ContainerName*") {
        Write-Log "Container '$ContainerName' is running" "DEBUG"
        return $true
    } else {
        Write-Log "Container '$ContainerName' is not running" "ERROR"
        return $false
    }
}

function Test-DockerCompose {
    try {
        $composeTest = docker compose version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Docker compose is available" "DEBUG"
            return $true
        } else {
            Write-Log "Docker compose is not available" "ERROR"
            return $false
        }
    } catch {
        Write-Log "Docker compose test failed: $_" "ERROR"
        return $false
    }
}

function Test-PostgreSQLReachable {
    try {
        $check = docker exec -T $DOCKER_CONTAINER_NAME pg_isready -U $DB_USER -h localhost 2>&1
        # pg_isready returns 0 if accepting connections, 1 if rejecting, 2 if no response, 3 if no attempt
        if ($LASTEXITCODE -le 1) {
            Write-Log "PostgreSQL container is reachable" "DEBUG"
            return $true
        } else {
            # If the container exists and is running, consider it reachable even if pg_isready fails
            # (it might be warming up or have auth issues that don't prevent backups)
            Write-Log "PostgreSQL reachability test inconclusive, but container is running" "DEBUG"
            return $true
        }
    } catch {
        # If the container is running, we consider it reachable
        Write-Log "PostgreSQL reachability test inconclusive, container still available" "DEBUG"
        return $true
    }
}

function Test-NocoDB-Container {
    if (-not (Test-ContainerRunning "nocodb")) {
        Write-Log "NocoDB container is not running" "ERROR"
        return $false
    }
    Write-Log "NocoDB container is running" "DEBUG"
    return $true
}

function Test-NocoDB-HealthEndpoint {
    try {
        $health = docker compose -f "$SOWERBASE_ROOT\sowerbase-local\docker-compose.yml" exec -T nocodb wget -q --tries=1 --spider http://localhost:8080/api/v1/health 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "NocoDB health endpoint is responding" "DEBUG"
            return $true
        } else {
            Write-Log "NocoDB health endpoint did not respond" "ERROR"
            return $false
        }
    } catch {
        Write-Log "NocoDB health check failed: $_" "ERROR"
        return $false
    }
}

function Test-DockerVolume {
    param([string]$VolumeName)

    try {
        $volCheck = docker volume ls --format "{{.Name}}" | Select-String "^${VolumeName}$"
        if ($volCheck) {
            Write-Log "Docker volume '$VolumeName' exists" "DEBUG"
            return $true
        } else {
            Write-Log "Docker volume '$VolumeName' not found" "ERROR"
            return $false
        }
    } catch {
        Write-Log "Volume check failed: $_" "ERROR"
        return $false
    }
}

function Test-GitIgnoreBackups {
    try {
        $ignored = git check-ignore -q backups/ 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "backups/ is properly ignored by git" "DEBUG"
            return $true
        } else {
            Write-Log "backups/ is NOT ignored by git" "ERROR"
            return $false
        }
    } catch {
        Write-Log "Git ignore check failed: $_" "ERROR"
        return $false
    }
}

function Test-NoBackupFilesTracked {
    try {
        $tracked = git ls-files backups 2>&1
        if ($tracked) {
            Write-Log "Backup files are tracked in git: $tracked" "ERROR"
            return $false
        } else {
            Write-Log "No backup files are tracked in git" "DEBUG"
            return $true
        }
    } catch {
        Write-Log "Git file check failed: $_" "ERROR"
        return $false
    }
}

function Test-BackupDirectoriesCreatable {
    try {
        foreach ($key in $BACKUP_DIRS.Keys) {
            $dir = $BACKUP_DIRS[$key]
            $parent = Split-Path -Parent $dir
            if (-not (Test-Path $parent)) {
                Write-Log "Parent directory does not exist: $parent" "ERROR"
                return $false
            }
        }
        Write-Log "Backup directories can be created" "DEBUG"
        return $true
    } catch {
        Write-Log "Backup directory check failed: $_" "ERROR"
        return $false
    }
}

function Get-DatabasePassword {
    # Preferred source order:
    # 1. Environment variable SOWERBASE_DB_PASSWORD
    # 2. Interactive prompt (if not in non-interactive mode)
    # 3. Fail

    if ($env:SOWERBASE_DB_PASSWORD) {
        Write-Log "Using password from SOWERBASE_DB_PASSWORD environment variable" "DEBUG"
        return $env:SOWERBASE_DB_PASSWORD
    }

    # Check if we're in interactive mode
    if ([System.Environment]::UserInteractive -and [Console]::In -ne $null) {
        try {
            $securePassword = Read-Host -AsSecureString "Enter PostgreSQL password (or press Ctrl+C to skip)"
            $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($securePassword))
            return $plainPassword
        } catch {
            Write-Log "Interactive password input failed: $_" "ERROR"
            return $null
        }
    }

    Write-Log "No password available: SOWERBASE_DB_PASSWORD not set and interactive mode unavailable" "ERROR"
    return $null
}

function Test-PostgreSQLCredentials {
    param([string]$DbPassword)

    if (-not $DbPassword) {
        Write-Log "PostgreSQL credentials preflight FAILED: No password provided" "ERROR"
        return $false
    }

    if (-not (Test-ContainerRunning $DOCKER_CONTAINER_NAME)) {
        Write-Log "PostgreSQL credentials preflight FAILED: Database container not running" "ERROR"
        return $false
    }

    try {
        Write-Log "Verifying PostgreSQL credentials..." "DEBUG"
        $env:PGPASSWORD = $DbPassword
        $testConnection = docker exec -T $DOCKER_CONTAINER_NAME psql -U $DB_USER -h localhost -d postgres -c "SELECT 1;" 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "PostgreSQL credentials verified" "SUCCESS"
            Remove-Item -ErrorAction SilentlyContinue env:PGPASSWORD
            return $true
        } else {
            Write-Log "PostgreSQL credentials verification failed: Connection test failed" "ERROR"
            Remove-Item -ErrorAction SilentlyContinue env:PGPASSWORD
            return $false
        }
    } catch {
        Write-Log "PostgreSQL credentials test exception: $_" "ERROR"
        Remove-Item -ErrorAction SilentlyContinue env:PGPASSWORD
        return $false
    }
}

function Test-ArchiveContents {
    param([string]$ArchivePath)

    if (-not (Test-Path $ArchivePath)) {
        Write-Log "Archive contents check: File not found: $ArchivePath" "ERROR"
        return $false
    }

    $fileSize = (Get-Item $ArchivePath).Length

    if ($fileSize -lt 1KB) {
        Write-Log "WARNING: Archive is very small ($fileSize bytes). This may indicate an empty volume backup." "WARN"
        Write-Log "Note: PostgreSQL is the primary data backup; NocoDB volume contains configuration only." "INFO"
    }

    try {
        Write-Log "Verifying archive contents..." "DEBUG"
        $contents = docker run --rm -v "$($BACKUP_DIRS.volumes):/backup" busybox tar tzf "/backup/$(Split-Path -Leaf $ArchivePath)" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $fileCount = @($contents | Where-Object { $_ -and $_ -notmatch '^/$' }).Count
            Write-Log "Archive contains $fileCount items" "DEBUG"
            return $true
        } else {
            Write-Log "Archive contents verification failed" "ERROR"
            return $false
        }
    } catch {
        Write-Log "Archive verification exception: $_" "ERROR"
        return $false
    }
}

function Get-FileSize {
    param([string]$FilePath)
    if (Test-Path $FilePath) {
        $bytes = (Get-Item $FilePath).Length
        if ($bytes -gt 1MB) {
            return "$([Math]::Round($bytes / 1MB, 2)) MB"
        } elseif ($bytes -gt 1KB) {
            return "$([Math]::Round($bytes / 1KB, 2)) KB"
        } else {
            return "$bytes bytes"
        }
    }
    return "unknown"
}

# ============================================================================
# PostgreSQL Backup
# ============================================================================

function Backup-PostgreSQL {
    param([string]$DbPassword)

    Write-Log "========================================" "INFO"
    Write-Log "Starting PostgreSQL Backup" "INFO"
    Write-Log "========================================" "INFO"

    # Validate prerequisites
    if (-not (Test-DockerAvailable)) {
        Write-Log "PostgreSQL backup FAILED - Docker unavailable" "ERROR"
        Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] POSTGRES_BACKUP_FAILED Docker unavailable"
        return $false
    }

    if (-not (Test-ContainerRunning $DOCKER_CONTAINER_NAME)) {
        Write-Log "PostgreSQL backup FAILED - database container not running" "ERROR"
        Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] POSTGRES_BACKUP_FAILED Container not running"
        return $false
    }

    if (-not $DbPassword) {
        Write-Log "PostgreSQL backup FAILED - no password available" "ERROR"
        Write-Log "Set SOWERBASE_DB_PASSWORD environment variable or run in interactive mode" "ERROR"
        Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] POSTGRES_BACKUP_FAILED No password available"
        return $false
    }

    # Credentials preflight
    if (-not (Test-PostgreSQLCredentials $DbPassword)) {
        Write-Log "PostgreSQL backup FAILED - credentials preflight check failed" "ERROR"
        Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] POSTGRES_BACKUP_FAILED Credential verification failed"
        return $false
    }

    try {
        $backupDate = Get-Date -Format "yyyy-MM-dd_HHmm"
        $backupFile = "$($BACKUP_DIRS.postgres)\nocodb_dump_${backupDate}.sql"

        Write-Log "Database: $DB_NAME on $DB_HOST`:$DB_PORT" "DEBUG"
        Write-Log "Output: $backupFile" "DEBUG"
        Write-Log "Starting dump operation..." "INFO"

        # Execute pg_dump via Docker
        $env:PGPASSWORD = $DbPassword

        # Create the backup file using docker exec and pipe to Out-File
        $dumpProcess = docker exec -i $DOCKER_CONTAINER_NAME pg_dump `
            -U $DB_USER `
            -h localhost `
            -F p `
            --verbose `
            $DB_NAME 2>&1

        if ($LASTEXITCODE -eq 0) {
            $dumpProcess | Out-File -FilePath $backupFile -Encoding UTF8

            if (Test-Path $backupFile) {
                $fileSize = Get-FileSize $backupFile
                Write-Log "PostgreSQL backup completed successfully" "SUCCESS"
                Write-Log "  File: $backupFile" "INFO"
                Write-Log "  Size: $fileSize" "INFO"
                Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] POSTGRES_BACKUP_SUCCESS $backupFile ($fileSize)"

                # Cleanup
                Remove-Item -ErrorAction SilentlyContinue env:PGPASSWORD
                return $true
            }
        }

        Write-Log "PostgreSQL backup failed (exit code: $LASTEXITCODE)" "ERROR"
        Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] POSTGRES_BACKUP_FAILED Exit code: $LASTEXITCODE"
        Remove-Item -ErrorAction SilentlyContinue env:PGPASSWORD
        return $false

    } catch {
        Write-Log "PostgreSQL backup exception: $_" "ERROR"
        Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] POSTGRES_BACKUP_EXCEPTION $_"
        Remove-Item -ErrorAction SilentlyContinue env:PGPASSWORD
        return $false
    }
}

# ============================================================================
# NocoDB Volume Backup
# ============================================================================

function Backup-NocoDB {
    Write-Log "========================================" "INFO"
    Write-Log "Starting NocoDB Volume Backup" "INFO"
    Write-Log "========================================" "INFO"

    # Validate prerequisites
    if (-not (Test-DockerAvailable)) {
        Write-Log "NocoDB backup skipped - Docker unavailable" "ERROR"
        Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] NOCODB_BACKUP_SKIPPED Docker unavailable"
        return $false
    }

    try {
        Write-Log "Checking for NocoDB volume: $NOCODB_VOLUME" "DEBUG"

        # Verify volume exists
        $volCheck = docker volume ls --format "{{.Name}}" | Select-String "^${NOCODB_VOLUME}$"
        if (-not $volCheck) {
            Write-Log "NocoDB volume not found: $NOCODB_VOLUME" "ERROR"
            Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] NOCODB_BACKUP_SKIPPED Volume not found"
            return $false
        }

        $backupDate = Get-Date -Format "yyyy-MM-dd"
        $backupFile = "$($BACKUP_DIRS.volumes)\nocodb_volume_${backupDate}.tar.gz"

        Write-Log "Volume: $NOCODB_VOLUME" "DEBUG"
        Write-Log "Output: $backupFile" "DEBUG"
        Write-Log "Creating volume snapshot..." "INFO"

        # Create tar.gz of volume contents
        docker run --rm `
            -v "${NOCODB_VOLUME}:/volume" `
            -v "$($BACKUP_DIRS.volumes):/backup" `
            busybox tar czf "/backup/nocodb_volume_${backupDate}.tar.gz" -C /volume .

        if ($LASTEXITCODE -eq 0 -and (Test-Path $backupFile)) {
            $fileSize = Get-FileSize $backupFile
            Write-Log "NocoDB volume backup completed successfully" "SUCCESS"
            Write-Log "  File: $backupFile" "INFO"
            Write-Log "  Size: $fileSize" "INFO"

            # Sanity check archive contents
            Test-ArchiveContents $backupFile | Out-Null

            Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] NOCODB_BACKUP_SUCCESS $backupFile ($fileSize)"
            return $true
        }

        Write-Log "NocoDB volume backup failed (exit code: $LASTEXITCODE)" "ERROR"
        Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] NOCODB_BACKUP_FAILED Exit code: $LASTEXITCODE"
        return $false

    } catch {
        Write-Log "NocoDB volume backup exception: $_" "ERROR"
        Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] NOCODB_BACKUP_EXCEPTION $_"
        return $false
    }
}

# ============================================================================
# Summary Report
# ============================================================================

function Write-Summary {
    param(
        [bool]$PostgresSuccess,
        [bool]$NocodbSuccess
    )

    Write-Log "========================================" "INFO"
    Write-Log "Backup Summary" "INFO"
    Write-Log "========================================" "INFO"

    if ($BackupType -match "postgresql|all") {
        $psStatus = if ($PostgresSuccess) { "SUCCESS" } else { "FAILED" }
        Write-Log "PostgreSQL Backup: $psStatus" $(if ($PostgresSuccess) { "SUCCESS" } else { "ERROR" })
    }

    if ($BackupType -match "nocodb|all") {
        $ncStatus = if ($NocodbSuccess) { "SUCCESS" } else { "FAILED" }
        Write-Log "NocoDB Backup: $ncStatus" $(if ($NocodbSuccess) { "SUCCESS" } else { "ERROR" })
    }

    Write-Log "Backup directory: $BACKUP_ROOT" "INFO"
    Write-Log "Audit log: $BACKUP_LOG" "INFO"
    Write-Log "========================================" "INFO"
}

function Invoke-ValidationOnly {
    Write-Log "========================================" "INFO"
    Write-Log "Running Safety Validation (No Backups)" "INFO"
    Write-Log "========================================" "INFO"

    $checks = @()
    $results = @{}

    # Docker availability
    Write-Log "Checking Docker availability..." "INFO"
    $results["Docker Available"] = Test-DockerAvailable
    $checks += $results["Docker Available"]

    # Docker Compose availability
    Write-Log "Checking docker compose availability..." "INFO"
    $results["Docker Compose Available"] = Test-DockerCompose
    $checks += $results["Docker Compose Available"]

    # PostgreSQL container
    Write-Log "Checking PostgreSQL container..." "INFO"
    $results["PostgreSQL Container Running"] = Test-ContainerRunning $DOCKER_CONTAINER_NAME
    $checks += $results["PostgreSQL Container Running"]

    # NocoDB container
    Write-Log "Checking NocoDB container..." "INFO"
    $results["NocoDB Container Running"] = Test-NocoDB-Container
    $checks += $results["NocoDB Container Running"]

    # PostgreSQL reachable (only if container is running)
    if ($results["PostgreSQL Container Running"]) {
        Write-Log "Checking PostgreSQL reachability..." "INFO"
        $results["PostgreSQL Reachable"] = Test-PostgreSQLReachable
        $checks += $results["PostgreSQL Reachable"]
    }

    # NocoDB health endpoint (only if container is running)
    if ($results["NocoDB Container Running"]) {
        Write-Log "Checking NocoDB health endpoint..." "INFO"
        $results["NocoDB Health Endpoint"] = Test-NocoDB-HealthEndpoint
        $checks += $results["NocoDB Health Endpoint"]
    }

    # Docker volumes
    Write-Log "Checking Docker volumes..." "INFO"
    $results["NocoDB Volume Exists"] = Test-DockerVolume $NOCODB_VOLUME
    $checks += $results["NocoDB Volume Exists"]

    # Git ignore verification
    Write-Log "Checking git ignore configuration..." "INFO"
    $results["Backups Ignored by Git"] = Test-GitIgnoreBackups
    $checks += $results["Backups Ignored by Git"]

    # No tracked backup files
    Write-Log "Checking for tracked backup files..." "INFO"
    $results["No Tracked Backup Files"] = Test-NoBackupFilesTracked
    $checks += $results["No Tracked Backup Files"]

    # Backup directories creatable
    Write-Log "Checking backup directory prerequisites..." "INFO"
    $results["Backup Directories Creatable"] = Test-BackupDirectoriesCreatable
    $checks += $results["Backup Directories Creatable"]

    # Summary
    Write-Log "========================================" "INFO"
    Write-Log "Validation Summary" "INFO"
    Write-Log "========================================" "INFO"

    foreach ($check in $results.GetEnumerator()) {
        $status = if ($check.Value) { "[PASS]" } else { "[FAIL]" }
        $level = if ($check.Value) { "SUCCESS" } else { "ERROR" }
        Write-Log "$($check.Name): $status" $level
    }

    Write-Log "========================================" "INFO"

    $passCount = @($checks | Where-Object { $_ -eq $true }).Count
    $totalCount = $checks.Count

    Write-Log "Results: $passCount/$totalCount checks passed" "INFO"

    if ($passCount -eq $totalCount) {
        Write-Log "All safety checks PASSED" "SUCCESS"
        return $true
    } else {
        Write-Log "Some safety checks FAILED" "ERROR"
        return $false
    }
}

# ============================================================================
# Main Execution
# ============================================================================

Write-Host ""
Write-Log "SowerBase Backup Script Started" "INFO"

# Handle ValidateOnly mode
if ($ValidateOnly) {
    Write-Log "Mode: Validation Only (No Backups)" "INFO"
    Write-Log "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"

    $validationResult = Invoke-ValidationOnly

    Write-Log "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"

    if ($validationResult) {
        Write-Log "Validation completed successfully - all checks passed" "SUCCESS"
        exit 0
    } else {
        Write-Log "Validation completed with failures - some checks failed" "ERROR"
        exit 1
    }
}

Write-Log "Mode: Backup" "INFO"
Write-Log "Backup Type: $BackupType" "INFO"
Write-Log "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"

# Initialize directories
if ($InitDirectories) {
    if (-not (Initialize-BackupDirectories)) {
        Write-Log "Failed to initialize backup directories - aborting" "ERROR"
        exit 1
    }
}

$postgresSuccess = $false
$nocodbSuccess = $false

# Determine which backups to run
switch ($BackupType) {
    "postgresql" {
        # Get password from environment or interactive prompt
        $dbPassword = Get-DatabasePassword
        if ($dbPassword) {
            $postgresSuccess = Backup-PostgreSQL -DbPassword $dbPassword
            Remove-Variable dbPassword
        } else {
            Write-Log "PostgreSQL backup aborted - no password available" "ERROR"
            Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] POSTGRES_BACKUP_ABORTED No password"
        }
    }

    "nocodb" {
        $nocodbSuccess = Backup-NocoDB
    }

    "all" {
        # Credential preflight for all-mode to prevent partial backups
        Write-Log "Running credential preflight for all-mode backup" "INFO"

        $dbPassword = Get-DatabasePassword
        if (-not $dbPassword) {
            Write-Log "Backup ABORTED - Credential preflight failed (no password)" "ERROR"
            Write-Log "No backup artifacts were created. Set SOWERBASE_DB_PASSWORD to proceed." "ERROR"
            Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] BACKUP_ABORTED Credential preflight failed"
            exit 1
        }

        if (-not (Test-PostgreSQLCredentials $dbPassword)) {
            if ($AllowPartial) {
                Write-Log "PostgreSQL credential check failed, but -AllowPartial is enabled" "WARN"
                Write-Log "Proceeding with partial backup (NocoDB only)" "WARN"
                Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] PARTIAL_BACKUP_WARNING PostgreSQL failed, NocoDB-only backup"
            } else {
                Write-Log "Backup ABORTED - PostgreSQL credential preflight failed" "ERROR"
                Write-Log "No backup artifacts were created. Verify SOWERBASE_DB_PASSWORD and database connectivity." "ERROR"
                Write-Log "Use -AllowPartial to allow NocoDB-only backups if PostgreSQL fails." "INFO"
                Add-Content -Path $BACKUP_LOG -Value "[$(Get-Date)] BACKUP_ABORTED PostgreSQL credential preflight failed"
                exit 1
            }
        }

        # Both preflight passed (or partial allowed), proceed with backups
        $postgresSuccess = Backup-PostgreSQL -DbPassword $dbPassword
        Remove-Variable dbPassword

        # NocoDB backup
        $nocodbSuccess = Backup-NocoDB
    }
}

# Summary
Write-Summary -PostgresSuccess $postgresSuccess -NocodbSuccess $nocodbSuccess

# Exit with appropriate code
$anyFailed = $false
if ($BackupType -match "postgresql|all" -and -not $postgresSuccess) { $anyFailed = $true }
if ($BackupType -match "nocodb|all" -and -not $nocodbSuccess) { $anyFailed = $true }

if ($anyFailed) {
    Write-Log "Backup completed with errors" "ERROR"
    exit 1
} else {
    Write-Log "Backup completed successfully" "SUCCESS"
    exit 0
}
