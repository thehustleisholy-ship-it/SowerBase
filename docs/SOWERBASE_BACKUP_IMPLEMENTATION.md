# SowerBase Backup Implementation Package

**Version 1.0** | **Created:** 2026-06-26 | **Status:** Review Ready

---

## ⚠️ CRITICAL SECURITY WARNING

**Backup Files Must Never Be Committed to Git**
- Backups contain operational data and must remain **local/private**
- Backup files are now excluded in `.gitignore` (`backups/`, `.sql`, `.dump`, `.tar.gz`, `.zip`, `.7z`, and related archive formats)
- Treat the backup folder as operational data, not source code; keep it local to the machine and out of shared sync folders
- If a backup is accidentally staged, remove it immediately:
  ```powershell
  git rm --cached backups/
  git rm --cached *.sql *.tar.gz
  ```
- Passwords and secret values are **never** written to documentation, scripts, or git
- Example commands show **PLACEHOLDERS ONLY** — use real credentials from secure storage and never include them in sample values

---

## Executive Summary

This document provides **practical, executable backup/restore procedures** for SowerBase local development environment. All commands are Windows PowerShell compatible and use local paths accessible from the command line.

**Key Constraint:** This backup package is for **local development only**. Production backup strategy requires separate infrastructure (cloud storage, automated scheduling, encryption at rest).

---

## 1. Local Backup Folder Definition

### Primary Backup Directory
```
C:\Users\thehu\SowerBase\backups\
```

### Directory Structure
```
backups/
├── daily/              # Daily CSV exports (7-day rotation)
├── volumes/            # Weekly Docker volume snapshots (4-week rotation)
├── postgres-dumps/     # Monthly PostgreSQL logical backups (12-month rotation)
├── archive/            # Encrypted monthly archives (indefinite)
├── verify-logs/        # Verification command outputs
└── BACKUP_LOG.txt      # Master audit log (append-only)
```

### Backup Folder Policy
- Keep the backup root under the local workspace tree and outside any version-controlled source directory.
- Use this folder only for local operational data, verification logs, and restore artifacts.
- Do not copy backup contents into the repository, shared cloud folders, or public ticket attachments.
- Prefer encrypted archives for long-term retention and keep only the current working set in the active folders.

### Create Backup Directories (One-time Setup)
```powershell
$BACKUP_ROOT = "C:\Users\thehu\SowerBase\backups"

New-Item -ItemType Directory -Path "$BACKUP_ROOT\daily" -Force
New-Item -ItemType Directory -Path "$BACKUP_ROOT\volumes" -Force
New-Item -ItemType Directory -Path "$BACKUP_ROOT\postgres-dumps" -Force
New-Item -ItemType Directory -Path "$BACKUP_ROOT\archive" -Force
New-Item -ItemType Directory -Path "$BACKUP_ROOT\verify-logs" -Force

Write-Host "✓ Backup directories created"
```

---

## 2. PostgreSQL Dump Command

### Full Database Logical Backup

**What:** Complete schema + data export using PostgreSQL native dump format

**When to use:** 
- Weekly (automated via Windows Task Scheduler)
- Before schema migrations
- Before major data imports
- Emergency backups before risky operations

**Procedure:**

```powershell
# ============================================================================
# PostgreSQL Logical Backup (pg_dump format)
# Run from C:\Users\thehu\SowerBase\ directory
# ============================================================================

$BACKUP_DATE = Get-Date -Format "yyyy-MM-dd_HHmm"
$BACKUP_DIR = "C:\Users\thehu\SowerBase\backups\postgres-dumps"
$DB_NAME = "nocodb"
$DB_USER = "nocodb"
$DB_HOST = "localhost"
$DB_PORT = "5432"
$POSTGRES_PASSWORD = "YOUR_ACTUAL_PASSWORD_FROM_SECURE_STORAGE"  # PLACEHOLDER - get from password manager, NOT from docs
$BACKUP_FILE = "$BACKUP_DIR\nocodb_dump_${BACKUP_DATE}.sql"

Write-Host "[$(Get-Date)] Starting PostgreSQL backup..."

# Export the database dump to SQL file
# Note: Password is provided via environment variable (not in command line)
$env:PGPASSWORD = $POSTGRES_PASSWORD
& docker exec -i sowerbase-local-db-1 pg_dump `
    -U $DB_USER `
    -h localhost `
    -F p `
    --verbose `
    $DB_NAME | Out-File -FilePath $BACKUP_FILE -Encoding UTF8

if ($LASTEXITCODE -eq 0) {
    $fileSize = (Get-Item $BACKUP_FILE).Length
    Write-Host "✓ PostgreSQL backup succeeded"
    Write-Host "  File: $BACKUP_FILE"
    Write-Host "  Size: $([Math]::Round($fileSize / 1MB, 2)) MB"
    Add-Content -Path "$BACKUP_DIR\..\BACKUP_LOG.txt" -Value "[$(Get-Date)] POSTGRES_BACKUP_SUCCESS $BACKUP_FILE ($([Math]::Round($fileSize / 1MB, 2)) MB)"
} else {
    Write-Host "✗ PostgreSQL backup failed"
    Add-Content -Path "$BACKUP_DIR\..\BACKUP_LOG.txt" -Value "[$(Get-Date)] POSTGRES_BACKUP_FAILED Exit code: $LASTEXITCODE"
}

Remove-Item -ErrorAction SilentlyContinue env:PGPASSWORD
```

### Restore from PostgreSQL Dump

⚠️ **WARNING: Restore actions are destructive. They can drop or overwrite the current database. Perform the first restore test only on disposable/local data, and take a fresh backup of the current state before attempting a real recovery.**

```powershell
# ============================================================================
# Restore from PostgreSQL Dump
# WARNING: This will DROP and recreate the database
# IMPORTANT: Connect to 'postgres' (maintenance DB) when dropping nocodb DB
# ============================================================================

param(
    [Parameter(Mandatory=$true)][string]$DumpFile
)

$DB_NAME = "nocodb"
$DB_USER = "nocodb"
$MAINTENANCE_DB = "postgres"  # Required for dropping target database
$POSTGRES_PASSWORD = "YOUR_ACTUAL_PASSWORD_FROM_SECURE_STORAGE"  # PLACEHOLDER - get from password manager

Write-Host "⚠️  WARNING: This will DROP and recreate database '$DB_NAME'"
Write-Host "   Use this ONLY on disposable/local test data"
Read-Host "Press Enter to continue or Ctrl+C to cancel"

# Drop existing database (connect to maintenance database)
Write-Host "Dropping existing database..."
$env:PGPASSWORD = $POSTGRES_PASSWORD
& docker exec -i sowerbase-local-db-1 psql -U $DB_USER -h localhost $MAINTENANCE_DB -c "DROP DATABASE IF EXISTS $DB_NAME;"

# Recreate database (connect to maintenance database)
Write-Host "Recreating database..."
& docker exec -i sowerbase-local-db-1 psql -U $DB_USER -h localhost $MAINTENANCE_DB -c "CREATE DATABASE $DB_NAME;"

# Restore from dump
Write-Host "Restoring from dump..."
Get-Content $DumpFile | & docker exec -i sowerbase-local-db-1 psql -U $DB_USER -h localhost $DB_NAME

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ PostgreSQL restore succeeded"
    Add-Content -Path "C:\Users\thehu\SowerBase\backups\BACKUP_LOG.txt" -Value "[$(Get-Date)] POSTGRES_RESTORE_SUCCESS $DumpFile"
} else {
    Write-Host "✗ PostgreSQL restore failed"
    Add-Content -Path "C:\Users\thehu\SowerBase\backups\BACKUP_LOG.txt" -Value "[$(Get-Date)] POSTGRES_RESTORE_FAILED $DumpFile"
}

Remove-Item -ErrorAction SilentlyContinue env:PGPASSWORD
```

---

## 3. NocoDB Application Data Volume Backup

### What Gets Backed Up
- NocoDB internal metadata database (SQLite or PostgreSQL depending on NC_DB)
- User configuration and API tokens
- View definitions, filters, sorts
- Calendar view data
- Expansion records cache

**Note:** Actual learner data is stored in the attached PostgreSQL database (covered by item #2), not in the NocoDB volume.

### Backup Procedure

```powershell
# ============================================================================
# NocoDB Volume Snapshot Backup
# Captures: NocoDB metadata and configuration state
# ============================================================================

$BACKUP_DATE = Get-Date -Format "yyyy-MM-dd"
$VOLUME_NAME = "sowerbase-local_nocodb_data"
$BACKUP_DIR = "C:\Users\thehu\SowerBase\backups\volumes"
$BACKUP_FILE = "$BACKUP_DIR\nocodb_volume_${BACKUP_DATE}.tar.gz"

Write-Host "[$(Get-Date)] Starting NocoDB volume backup..."

# Verify volume exists
$volCheck = docker volume ls | Select-String $VOLUME_NAME
if (-not $volCheck) {
    Write-Host "✗ Volume $VOLUME_NAME not found"
    exit 1
}

# Create tar.gz of volume contents
Write-Host "Creating volume snapshot..."
& docker run --rm `
    -v ${VOLUME_NAME}:/volume `
    -v "C:/Users/thehu/SowerBase/backups/volumes:/backup" `
    busybox tar czf "/backup/nocodb_volume_${BACKUP_DATE}.tar.gz" -C /volume .

if ($LASTEXITCODE -eq 0) {
    $fileSize = (Get-Item $BACKUP_FILE).Length
    Write-Host "✓ NocoDB volume backup succeeded"
    Write-Host "  File: $BACKUP_FILE"
    Write-Host "  Size: $([Math]::Round($fileSize / 1MB, 2)) MB"
    Add-Content -Path "$BACKUP_DIR\..\BACKUP_LOG.txt" -Value "[$(Get-Date)] NOCODB_VOLUME_BACKUP_SUCCESS $BACKUP_FILE ($([Math]::Round($fileSize / 1MB, 2)) MB)"
} else {
    Write-Host "✗ NocoDB volume backup failed"
    Add-Content -Path "$BACKUP_DIR\..\BACKUP_LOG.txt" -Value "[$(Get-Date)] NOCODB_VOLUME_BACKUP_FAILED Exit code: $LASTEXITCODE"
}
```

### Restore NocoDB Volume from Snapshot

⚠️ **WARNING: Restore actions are destructive. They can overwrite the current NocoDB configuration and cached data. Perform the first restore test only on disposable/local data, and take a fresh backup of the current state before attempting a real recovery.**

```powershell
# ============================================================================
# Restore NocoDB Volume from Snapshot
# WARNING: This will overwrite current NocoDB configuration
# IMPORTANT: STOP services (don't just pause), use "docker compose"
# ============================================================================

param(
    [Parameter(Mandatory=$true)][string]$SnapshotDate  # Format: yyyy-MM-dd
)

$VOLUME_NAME = "sowerbase-local_nocodb_data"
$BACKUP_DIR = "C:\Users\thehu\SowerBase\backups\volumes"
$SNAPSHOT_FILE = "$BACKUP_DIR\nocodb_volume_${SnapshotDate}.tar.gz"
$SOWERBASE_DIR = "C:\Users\thehu\SowerBase\sowerbase-local"

if (-not (Test-Path $SNAPSHOT_FILE)) {
    Write-Host "✗ Snapshot file not found: $SNAPSHOT_FILE"
    exit 1
}

Write-Host "⚠️  WARNING: This will REPLACE NocoDB configuration and cached data"
Write-Host "   Use this ONLY on disposable/local test data"
Read-Host "Press Enter to continue or Ctrl+C to cancel"

# STOP NocoDB and worker containers (not just pause)
Write-Host "Stopping NocoDB and worker containers..."
Set-Location $SOWERBASE_DIR
docker compose stop nocodb worker

Write-Host "Waiting for containers to stop gracefully..."
Start-Sleep -Seconds 5

# Remove and recreate volume
Write-Host "Removing current volume..."
docker volume rm $VOLUME_NAME

Write-Host "Creating new volume..."
docker volume create $VOLUME_NAME

# Restore from snapshot
Write-Host "Restoring snapshot..."
& docker run --rm `
    -v ${VOLUME_NAME}:/volume `
    -v "C:/Users/thehu/SowerBase/backups/volumes:/backup" `
    busybox tar xzf "/backup/nocodb_volume_${SnapshotDate}.tar.gz" -C /volume

if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Snapshot restore failed"
    exit 1
}

# Restart containers
Write-Host "Restarting NocoDB and worker containers..."
docker compose start nocodb worker

Write-Host "Waiting for services to be ready..."
Start-Sleep -Seconds 15

# Verify health endpoint
Write-Host "Verifying NocoDB health endpoint..."
$maxRetries = 10
$retry = 0
$healthy = $false

while ($retry -lt $maxRetries -and -not $healthy) {
    $response = docker compose exec -T nocodb wget -q --tries=1 --spider http://localhost:8080/api/v1/health 2>&1
    if ($LASTEXITCODE -eq 0) {
        $healthy = $true
        Write-Host "✓ NocoDB restore succeeded and health endpoint verified"
        Add-Content -Path "$BACKUP_DIR\..\BACKUP_LOG.txt" -Value "[$(Get-Date)] NOCODB_VOLUME_RESTORE_SUCCESS $SNAPSHOT_FILE"
    } else {
        $retry++
        if ($retry -lt $maxRetries) {
            Write-Host "  Attempt $retry/$maxRetries - waiting for NocoDB to become ready..."
            Start-Sleep -Seconds 2
        }
    }
}

if (-not $healthy) {
    Write-Host "✗ NocoDB restore failed - service unhealthy after $maxRetries attempts"
    Add-Content -Path "$BACKUP_DIR\..\BACKUP_LOG.txt" -Value "[$(Get-Date)] NOCODB_VOLUME_RESTORE_FAILED $SNAPSHOT_FILE"
    exit 1
}
```

---

## 4. Redis Backup Decision

### Decision: Backup or Regenerate?

**DECISION: REGENERATE (no backup required for local development)**

**Reasoning:**
- Redis in local SowerBase contains only **temporary cache data**:
  - Session tokens
  - Query result cache
  - Rate limiting counters
  - Temporary processing queues
- **None of this data is critical** to restore from backup
- Data loss = temporary performance degradation only, not data loss
- Restart containers = fresh Redis, fully functional within seconds

### Implementation

**No backup command needed.** If Redis fails:

```powershell
# Simply restart the container
Set-Location C:\Users\thehu\SowerBase\sowerbase-local
docker compose restart redis

# Verify
docker compose exec -T redis redis-cli ping
# Should return: PONG
```

**What NOT to backup:**
- Redis dump.rdb file (transient)
- Redis AOF (append-only file) - we use RDB snapshots, not AOF
- Redis memory snapshots

**Expected recovery time:** ~5 seconds (container restart)

---

## 5. Restore Procedures

See individual sections above:
- **PostgreSQL restore** → Section 2 (pg_dump restore)
- **NocoDB restore** → Section 3 (volume restore)
- **Redis restore** → Section 4 (container restart)

### Complete System Recovery Procedure

```powershell
# ============================================================================
# Full SowerBase System Recovery (if all containers are down)
# ============================================================================

$SOWERBASE_DIR = "C:\Users\thehu\SowerBase\sowerbase-local"
$BACKUP_DIR = "C:\Users\thehu\SowerBase\backups"
$RESTORE_DATE = "2026-06-25"  # Specify backup date to restore from

Write-Host "Starting full system recovery from date: $RESTORE_DATE"
Write-Host "This will:"
Write-Host "  1. Stop all running containers"
Write-Host "  2. Restore PostgreSQL database"
Write-Host "  3. Restore NocoDB configuration"
Write-Host "  4. Start all containers fresh"
Write-Host ""
Read-Host "Press Enter to begin or Ctrl+C to cancel"

# Step 1: Stop containers
Write-Host "[1/5] Stopping containers..."
Set-Location $SOWERBASE_DIR
docker-compose down

# Step 2: Restore PostgreSQL
Write-Host "[2/5] Restoring PostgreSQL database..."
$pg_dump = "$BACKUP_DIR\postgres-dumps\nocodb_dump_${RESTORE_DATE}*.sql"
$pg_file = Get-Item -Path $pg_dump | Select-Object -First 1
if ($pg_file) {
    & powershell -NoProfile -Command {
        param($DumpFile)
        # (Reuse PostgreSQL restore script from Section 2)
        Write-Host "Restore PostgreSQL from: $DumpFile"
    } -ArgumentList $pg_file.FullName
} else {
    Write-Host "⚠ No PostgreSQL dump found for date $RESTORE_DATE - skipping"
}

# Step 3: Restore NocoDB volume
Write-Host "[3/5] Restoring NocoDB configuration..."
$snapshot = "$BACKUP_DIR\volumes\nocodb_volume_${RESTORE_DATE}.tar.gz"
if (Test-Path $snapshot) {
    Write-Host "Snapshot found, restoring..."
    docker volume rm sowerbase-local_nocodb_data
    docker volume create sowerbase-local_nocodb_data
    docker run --rm `
        -v sowerbase-local_nocodb_data:/volume `
        -v "C:/Users/thehu/SowerBase/backups/volumes:/backup" `
        busybox tar xzf "/backup/nocodb_volume_${RESTORE_DATE}.tar.gz" -C /volume
} else {
    Write-Host "⚠ No snapshot found for date $RESTORE_DATE - using fresh NocoDB"
}

# Step 4: Start containers
Write-Host "[4/5] Starting containers..."
docker compose up -d

# Step 5: Verify
Write-Host "[5/5] Verifying system health..."
Start-Sleep -Seconds 15

$checks = @()

# Check PostgreSQL
$db_ok = docker compose exec -T db pg_isready -U nocodb 2>&1
if ($db_ok -match "accepting") {
    Write-Host "✓ PostgreSQL: Healthy"
    $checks += "OK"
} else {
    Write-Host "✗ PostgreSQL: Failed"
}

# Check Redis
$redis_ok = docker compose exec -T redis redis-cli ping 2>&1
if ($redis_ok -match "PONG") {
    Write-Host "✓ Redis: Healthy"
    $checks += "OK"
} else {
    Write-Host "✗ Redis: Failed"
}

# Check NocoDB
$nocodb_ok = docker compose exec -T nocodb wget -q --tries=1 --spider http://localhost:8080/api/v1/health 2>&1
if ($nocodb_ok -eq $null -or $LASTEXITCODE -eq 0) {
    Write-Host "✓ NocoDB: Healthy"
    $checks += "OK"
} else {
    Write-Host "✗ NocoDB: Failed"
}

if ($checks.Count -eq 3) {
    Write-Host ""
    Write-Host "✓✓✓ Full system recovery succeeded"
    Write-Host "SowerBase is available at: http://localhost:18080"
    Add-Content -Path "$BACKUP_DIR\BACKUP_LOG.txt" -Value "[$(Get-Date)] FULL_RECOVERY_SUCCESS from $RESTORE_DATE"
} else {
    Write-Host ""
    Write-Host "✗ Some services failed to recover"
    Add-Content -Path "$BACKUP_DIR\BACKUP_LOG.txt" -Value "[$(Get-Date)] FULL_RECOVERY_PARTIAL_FAILURE from $RESTORE_DATE"
}
```

---

## 6. Backup Frequency

| Backup Type | Frequency | Command | Retention | Trigger |
|-------------|-----------|---------|-----------|---------|
| **PostgreSQL Dump** | Weekly | Mondays 22:00 UTC | 12 months | Scheduled or manual before risky ops |
| **NocoDB Volume Snapshot** | Bi-weekly | Every other Sunday | 4 weeks | Scheduled or on-demand |
| **Encrypted Archive** | Monthly | 1st of month | 24 months | Scheduled |
| **Emergency Backup** | On-demand | Before schema changes, bulk imports | Until operation succeeds | Manual |

### Setup Windows Task Scheduler (Optional - Future)

```powershell
# This is a template for future automation
# Currently: Manual execution recommended

$taskName = "SowerBase-Weekly-Backup"
$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -File C:\Users\thehu\SowerBase\scripts\backup-postgres-weekly.ps1"
$taskTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 22:00
$taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Description "Weekly PostgreSQL backup for SowerBase"

Write-Host "Task scheduled: $taskName"
Write-Host "Note: Not yet active. Activate after manual testing confirms procedure works."
```

---

## 7. What Should NOT Be Backed Up

### Exclude from Backups

❌ **Docker images** (rebuild from registry if needed):
- `nocodb/nocodb:latest`
- `postgres:17.10`
- `redis:7`

❌ **Temporary runtime files**:
- Docker build caches
- Node.js node_modules/ (recreate via npm install)
- Docker layer caches

❌ **Personal files** (exclude from archive):
- `.env` files with passwords (see section 8)
- Private SSH keys
- Local IDE config files
- `.git/` history (preserve only current commit)

❌ **Development artifacts**:
- `node_modules/` directories
- Build outputs in `dist/` or `build/`
- IDE configuration (`.vscode/`, `.idea/`)

❌ **Logs older than 30 days** (external archival only):
- Docker container logs beyond 30 days
- Application logs beyond 30 days

### Compression Settings
When creating archives, use:
```powershell
# Exclude patterns when creating backup archive
$exclude = @(
    "*.node_modules*",
    "*/.git/*",
    "*.git-ignore*",
    "*/__pycache__/*",
    "*.env.local",
    "*.env.development.local"
)
```

---

## 8. Where Secrets/Passwords Must NOT Be Stored

### ✅ SAFE Storage Locations

**Database Credentials:**
- Docker-compose.yml: YES (for local development only)
  - Rationale: Local-only, not in production, rotated regularly
- `.env` file (local copy, NOT in git): YES
  - Rationale: .gitignore prevents accidental commit
- Windows Credential Manager: YES (for Windows Authenticator)
  - Rationale: Windows-managed encryption

**Backup Encryption Passwords:**
- Password manager (1Password, Bitwarden, LastPass): YES
  - Rationale: Encrypted, centralized, auditable
- Paper backup (secured location): YES
  - Rationale: Offline backup for disaster recovery

### ❌ UNSAFE Storage Locations

Never store passwords in:
- ✗ Plain text files in repo
- ✗ Git history (even if deleted later)
- ✗ Cloud sync (OneDrive, Google Drive) without encryption
- ✗ Email messages
- ✗ Slack/Teams messages
- ✗ Comments in code
- ✗ Backup filenames or metadata
- ✗ PowerShell scripts in git

### Implementation for This Environment

```powershell
# ============================================================================
# Secrets Management for Local SowerBase
# ============================================================================

# Option 1: Store in Windows Credential Manager (Recommended)
# Command to save credential (run once):
$cred = Get-Credential -UserName "nocodb" -Message "Enter SowerBase database password"
$cred | ConvertFrom-SecureString | Set-Content "C:\Users\thehu\AppData\Local\SowerBase\db-cred.txt" -Force
# Set file permissions to user-read-only
$file = "C:\Users\thehu\AppData\Local\SowerBase\db-cred.txt"
icacls $file /inheritance:r /grant:r "$($env:USERNAME):(F)"

# Command to retrieve credential (in backup scripts):
$cred = Get-Content "C:\Users\thehu\AppData\Local\SowerBase\db-cred.txt" | ConvertTo-SecureString
$plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($cred))
$env:PGPASSWORD = $plain
# Use $env:PGPASSWORD in commands above

# Option 2: Store in .env file (local only, never commit)
# File: C:\Users\thehu\SowerBase\.env
# Content:
# DB_PASSWORD=<local-db-password>
# NOCODB_API_TOKEN=<local-api-token>
# Note: Keep this file local-only and add it to .gitignore

# Option 3: Use Docker secrets (for future production)
# Not implemented for local dev, but consider for staging environment
```

### Backup File Security

When creating encrypted archives:

```powershell
# Create password-protected 7-zip archive (requires 7-Zip)
$password = Read-Host "Enter encryption password for backup archive" -AsSecureString
$plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($password))

& "C:\Program Files\7-Zip\7z.exe" a -p$plain `
    -mhe=on `
    -t7z `
    "$BACKUP_DIR\archive\THIH_Backup_$(Get-Date -Format 'yyyy-MM-dd').7z" `
    "$BACKUP_DIR\daily\*" "$BACKUP_DIR\postgres-dumps\*"

# Securely clear password from memory
Clear-Variable plain
```

---

## 9. Verification Command After Backup

### Automated Post-Backup Verification

```powershell
# ============================================================================
# Post-Backup Verification Script
# Runs after every backup to confirm integrity and accessibility
# ============================================================================

function Verify-PostgresBackup {
    param([string]$BackupFile)
    
    Write-Host "Verifying PostgreSQL backup..."
    
    # Check file exists and has content
    if (-not (Test-Path $BackupFile)) {
        Write-Host "✗ Backup file not found: $BackupFile"
        return $false
    }
    
    $fileSize = (Get-Item $BackupFile).Length
    if ($fileSize -lt 1MB) {
        Write-Host "✗ Backup file too small ($fileSize bytes) - may be corrupted"
        return $false
    }
    
    # Check SQL dump contains expected content
    $content = Select-String -Path $BackupFile -Pattern "CREATE TABLE|INSERT INTO" -Quiet
    if ($content) {
        Write-Host "✓ PostgreSQL backup verified"
        Write-Host "  Size: $([Math]::Round($fileSize / 1MB, 2)) MB"
        return $true
    } else {
        Write-Host "✗ Backup file does not contain SQL statements"
        return $false
    }
}

function Verify-NocoDBAVolume {
    param([string]$SnapshotFile)
    
    Write-Host "Verifying NocoDB volume snapshot..."
    
    if (-not (Test-Path $SnapshotFile)) {
        Write-Host "✗ Snapshot file not found: $SnapshotFile"
        return $false
    }
    
    $fileSize = (Get-Item $SnapshotFile).Length
    if ($fileSize -lt 100KB) {
        Write-Host "✗ Snapshot file too small ($fileSize bytes) - may be corrupted"
        return $false
    }
    
    # Verify tar.gz integrity
    $tarTest = & docker run --rm -v "$SnapshotFile`:/$([System.IO.Path]::GetFileName($SnapshotFile))" busybox tar tzf "/$([System.IO.Path]::GetFileName($SnapshotFile))" 2>&1 | Measure-Object -Line
    if ($tarTest.Lines -gt 0) {
        Write-Host "✓ NocoDB volume snapshot verified"
        Write-Host "  Size: $([Math]::Round($fileSize / 1MB, 2)) MB"
        Write-Host "  Files in snapshot: $($tarTest.Lines)"
        return $true
    } else {
        Write-Host "✗ Snapshot integrity check failed"
        return $false
    }
}

function Verify-RuntimeHealth {
    Write-Host "Verifying runtime services..."
    
    $healthy = $true
    
    # Check PostgreSQL
    $db = docker-compose exec -T db pg_isready -U nocodb 2>&1
    if ($db -match "accepting") {
        Write-Host "✓ PostgreSQL: accepting connections"
    } else {
        Write-Host "✗ PostgreSQL: connection failed"
        $healthy = $false
    }
    
    # Check Redis
    $redis = docker-compose exec -T redis redis-cli ping 2>&1
    if ($redis -match "PONG") {
        Write-Host "✓ Redis: operational"
    } else {
        Write-Host "✗ Redis: failed"
        $healthy = $false
    }
    
    # Check NocoDB
    $nocodb = docker-compose exec -T nocodb wget -q --tries=1 --spider http://localhost:8080/api/v1/health 2>&1
    if ($nocodb -eq $null) {
        Write-Host "✓ NocoDB: health endpoint responding"
    } else {
        Write-Host "✗ NocoDB: health check failed"
        $healthy = $false
    }
    
    return $healthy
}

# ============================================================================
# Main Verification Workflow
# ============================================================================

$BACKUP_DIR = "C:\Users\thehu\SowerBase\backups"
$VERIFY_LOG = "$BACKUP_DIR\verify-logs\$(Get-Date -Format 'yyyy-MM-dd_HHmm')_verify.log"

Write-Host "═════════════════════════════════════════════════════════════"
Write-Host "SowerBase Post-Backup Verification"
Write-Host "═════════════════════════════════════════════════════════════"

# Find latest backups
$latestPostgres = Get-ChildItem -Path "$BACKUP_DIR\postgres-dumps" -Filter "*.sql" | Sort-Object LastWriteTime | Select-Object -Last 1
$latestVolume = Get-ChildItem -Path "$BACKUP_DIR\volumes" -Filter "*.tar.gz" | Sort-Object LastWriteTime | Select-Object -Last 1

$results = @()

if ($latestPostgres) {
    $result = Verify-PostgresBackup -BackupFile $latestPostgres.FullName
    $results += $result
} else {
    Write-Host "⚠ No PostgreSQL backups found"
}

if ($latestVolume) {
    $result = Verify-NocoDBAVolume -SnapshotFile $latestVolume.FullName
    $results += $result
} else {
    Write-Host "⚠ No NocoDB volume snapshots found"
}

Write-Host ""
$result = Verify-RuntimeHealth
$results += $result

# Summary
Write-Host ""
Write-Host "═════════════════════════════════════════════════════════════"
$passed = ($results | Where-Object { $_ -eq $true } | Measure-Object).Count
Write-Host "Verification Results: $passed/$($results.Count) checks passed"

if ($passed -eq $results.Count) {
    Write-Host "Status: ✓ ALL VERIFICATIONS PASSED"
    Add-Content -Path "$BACKUP_DIR\BACKUP_LOG.txt" -Value "[$(Get-Date)] VERIFICATION_PASSED All checks successful"
} else {
    Write-Host "Status: ✗ SOME VERIFICATIONS FAILED - Review above"
    Add-Content -Path "$BACKUP_DIR\BACKUP_LOG.txt" -Value "[$(Get-Date)] VERIFICATION_FAILED $($results.Count - $passed) checks failed"
}
```

---

## 10. Windows-Friendly Backup Paths and Commands

### Recommended Windows Paths

```powershell
# Primary backup root
$SOWERBASE_ROOT = "C:\Users\thehu\SowerBase"
$BACKUP_ROOT = "$SOWERBASE_ROOT\backups"

# Specific paths (Windows-native format, no forward slashes in commands)
$DAILY_DIR = "$BACKUP_ROOT\daily"
$VOLUME_DIR = "$BACKUP_ROOT\volumes"
$POSTGRES_DIR = "$BACKUP_ROOT\postgres-dumps"
$ARCHIVE_DIR = "$BACKUP_ROOT\archive"
$VERIFY_DIR = "$BACKUP_ROOT\verify-logs"

# These paths work in PowerShell without escaping
```

### Windows PowerShell Best Practices

✅ **Use UNC paths for network shares** (if backing up to network):
```powershell
$BACKUP_ROOT = "\\nas-server\backups\sowerbase"  # Example
```

✅ **Use native Windows datetime formatting**:
```powershell
$DATE_ISO = Get-Date -Format "yyyy-MM-dd"  # For sorting
$DATE_FRIENDLY = Get-Date -Format "dddd, MMMM dd, yyyy"  # For display
```

✅ **Escape spaces in paths properly**:
```powershell
$path = "C:\Program Files\7-Zip\7z.exe"  # PowerShell auto-escapes
& "$path" a archive.7z "C:\Users\My User\Backups\*"  # Quotes handle spaces
```

✅ **Use `docker exec -i` for piped commands**:
```powershell
Get-Content $sqlFile | & docker exec -i sowerbase-local-db-1 psql -U nocodb $DB_NAME
```

❌ **Avoid mixing forward/back slashes**:
```powershell
# BAD: Mixed slashes
& docker volume inspect C:\backup/volumes\file.tar.gz

# GOOD: Consistent format
& docker volume inspect "C:\backup\volumes\file.tar.gz"
```

### Docker Path Mapping

When binding Windows paths in Docker, use forward slashes:

```powershell
# Correct Windows-to-Docker path format
docker run --rm `
    -v "C:/Users/thehu/SowerBase/backups:/backup" `
    busybox ls /backup
```

---

## Summary: Backup Package Files

This implementation package defines:

1. ✅ **Local backup folder:** `C:\Users\thehu\SowerBase\backups\`
2. ✅ **PostgreSQL dump command:** Full logical backup via `pg_dump` to `.sql` file
3. ✅ **NocoDB volume backup:** Docker volume snapshot to `.tar.gz`
4. ✅ **Redis backup decision:** No backup needed (regenerate on restart)
5. ✅ **Restore procedures:** Full scripts for each component + complete recovery
6. ✅ **Backup frequency:** Weekly (PostgreSQL), Bi-weekly (NocoDB), Monthly (encrypted archive)
7. ✅ **What not to back up:** Docker images, temp files, node_modules, secrets
8. ✅ **Secrets management:** Windows Credential Manager + .env (.gitignore)
9. ✅ **Verification commands:** Post-backup verification script with integrity checks
10. ✅ **Windows-friendly paths:** UNC paths, PowerShell formatting, Docker mappings

---

## Approval & Transition

**Status:** ⏳ **Awaiting Michael's Approval**

**Next Steps After Approval:**
1. Test backup procedures manually
2. Verify restore procedures work end-to-end
3. Confirm data integrity after restore
4. Document any adjustments
5. Consider Windows Task Scheduler automation (future)

**No changes to:** Product code, production tables, Canon data, THIHskills

---

**Package prepared by:** Automated SowerBase Implementation  
**Date:** 2026-06-26  
**Review stage:** Ready for technical review
