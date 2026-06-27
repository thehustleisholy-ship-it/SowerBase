# SowerBase Disposable Restore Test Plan

## Purpose

Validate that the first successful SowerBase backup can be restored into a separate, disposable environment without risking the active local SowerBase instance. This test confirms:

- PostgreSQL dump restore procedure works correctly
- NocoDB volume snapshot can be recovered
- Restored data is accessible and functional
- Backup integrity is verified
- Restore process is repeatable and documented

**Critical:** This plan uses disposable Docker resources only and never touches the active `sowerbase-local` environment.

---

## Source Backup Artifacts

These artifacts are stored locally and ignored by git:

### PostgreSQL Logical Dump
- **Path:** `backups/postgres-dumps/nocodb_dump_2026-06-27_1350.sql`
- **Size:** 389.13 KB
- **Type:** PostgreSQL pg_dump output
- **Contents:** Complete logical backup of `nocodb` database schema and data
- **Git Status:** Ignored (not tracked in version control)

### NocoDB Volume Snapshot
- **Path:** `backups/volumes/nocodb_volume_2026-06-27.tar.gz`
- **Size:** 86 bytes
- **Type:** Docker volume tar archive
- **Contents:** 1 item (configuration minimal)
- **Git Status:** Ignored (not tracked in version control)
- **Note:** Very small size indicates configuration-only volume; PostgreSQL dump is primary data backup

### Backup Audit Log
- **Path:** `backups/BACKUP_LOG.txt`
- **Size:** 30.28 KB
- **Type:** Timestamped operation log
- **Purpose:** Reference only (not needed for restore)

---

## Disposable Environment Architecture

### Project Isolation
- **Active Local Project:** `sowerbase-local` (production/working)
- **Disposable Test Project:** `sowerbase-restore-test` (ephemeral)
- **Project Separation:** Completely separate Docker Compose project name prevents volume/network conflicts

### Services
```
disposable-sowerbase-restore-test (project name isolation)
├── nocodb (image: nocodb/nocodb:latest)
├── postgres (image: postgres:17.10)
├── redis (image: redis:7)
└── worker (image: nocodb/nocodb:latest)
```

### Network Configuration
- **Separate Docker Network:** `disposable-nocodb-network` (isolated from active)
- **Host Port Mapping:** `18081:8080` (prevents conflict with active 18080)
- **Service Connectivity:** Internal network only (services→services)

### Volume Configuration
All volumes prefixed with `disposable_` to prevent conflicts:

| Volume | Purpose | Active | Disposable |
|--------|---------|--------|-----------|
| PostgreSQL Data | Database files | `postgres_data` | `disposable_postgres_data` |
| NocoDB Data | Configuration | `nocodb_data` | `disposable_nocodb_data` |
| Redis Data | Cache/queue | `redis_data` | `disposable_redis_data` |

---

## Pre-Restore Verification Checklist

**Before executing restore, verify:**

- [ ] Active `sowerbase-local` containers running (health check)
- [ ] Active volumes exist: `sowerbase-local_postgres_data`, `sowerbase-local_nocodb_data`, `sowerbase-local_redis_data`
- [ ] Backup artifacts accessible: `backups/postgres-dumps/nocodb_dump_2026-06-27_1350.sql`
- [ ] Backup artifacts accessible: `backups/volumes/nocodb_volume_2026-06-27.tar.gz`
- [ ] No disposable volumes exist yet (clean state)
- [ ] No disposable containers exist yet (clean state)
- [ ] SowerBase responsive on active port 18080

---

## Restore Procedure

### Phase 1: Disposable Environment Initialization

**1.1 Create Disposable Docker Compose Configuration**

Create `sowerbase-restore-test/docker-compose.yml` with:
- Project name: `sowerbase-restore-test`
- Separate network: `disposable-nocodb-network`
- All volumes prefixed: `disposable_*`
- PostgreSQL port: 5432 (internal, not exposed)
- NocoDB port: 8080 internal, `18081:8080` host mapping
- Credentials: `POSTGRES_USER: nocodb`, `POSTGRES_PASSWORD: [REDACTED]` (same as source)

Configuration details:
```yaml
version: '3.8'
services:
  nocodb:
    image: nocodb/nocodb:latest
    environment:
      NC_DB: 'pg://db:5432?u=nocodb&p=[REDACTED]&d=nocodb'
      NC_REDIS_URL: 'redis://redis:6379'
      NC_SITE_URL: 'http://localhost:18081'
      NC_DISABLE_MUX: 'true'
    ports:
      - '18081:8080'
    networks:
      - disposable-nocodb-network
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck: [standard NocoDB health check]

  worker:
    image: nocodb/nocodb:latest
    environment: [same as nocodb]
    networks:
      - disposable-nocodb-network
    depends_on:
      nocodb:
        condition: service_healthy

  db:
    image: postgres:17.10
    environment:
      POSTGRES_USER: nocodb
      POSTGRES_PASSWORD: [REDACTED]
      POSTGRES_DB: nocodb
    volumes:
      - disposable_postgres_data:/var/lib/postgresql/data
    networks:
      - disposable-nocodb-network
    healthcheck: [standard PostgreSQL health check]

  redis:
    image: redis:7
    volumes:
      - disposable_redis_data:/data
    networks:
      - disposable-nocodb-network
    healthcheck: [standard Redis health check]

networks:
  disposable-nocodb-network:
    driver: bridge

volumes:
  disposable_postgres_data:
  disposable_nocodb_data:
  disposable_redis_data:
```

**1.2 Start Disposable PostgreSQL Only**

```powershell
cd sowerbase-restore-test
docker-compose up -d db redis
docker-compose logs -f db  # wait for healthy
```

**Verification:**
- [ ] Container `sowerbase-restore-test-db-1` running
- [ ] Container `sowerbase-restore-test-redis-1` running
- [ ] Volume `sowerbase-restore-test_disposable_postgres_data` created
- [ ] Volume `sowerbase-restore-test_disposable_redis_data` created
- [ ] PostgreSQL reporting healthy status

---

### Phase 2: PostgreSQL Restore

**2.1 Restore PostgreSQL Dump**

```powershell
$env:PGPASSWORD = "[REDACTED]"
cat backups/postgres-dumps/nocodb_dump_2026-06-27_1350.sql | `
  docker exec -i sowerbase-restore-test-db-1 psql -U nocodb -d nocodb
Remove-Item Env:PGPASSWORD
```

**Expected output:** No errors, data inserted successfully

**Verification:**
- [ ] PostgreSQL dump restored without errors
- [ ] Exit code: 0
- [ ] No `ERROR` messages in output

**2.2 Verify PostgreSQL Restore**

```powershell
$env:PGPASSWORD = "[REDACTED]"
docker exec sowerbase-restore-test-db-1 psql -U nocodb -d nocodb -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';"
Remove-Item Env:PGPASSWORD
```

**Expected:** Non-zero table count (schema restored)

**Verification:**
- [ ] Table count > 0
- [ ] Exit code: 0
- [ ] Data visible in database

---

### Phase 3: NocoDB Volume Restore

**3.1 Prepare Disposable NocoDB Volume**

```powershell
# Start NocoDB container to create volume
docker-compose up -d nocodb
docker-compose logs -f nocodb  # wait for healthy
```

**3.2 Restore NocoDB Volume Snapshot**

```powershell
# Extract snapshot into volume
docker run --rm -v sowerbase-restore-test_disposable_nocodb_data:/data `
  -v "$(pwd)/backups/volumes:/backups" `
  busybox tar -xzf /backups/nocodb_volume_2026-06-27.tar.gz -C /data
```

**Expected:** Archive extracted without errors

**Note:** Volume may appear empty due to small archive size (86 bytes). Configuration is minimal; verify by checking NocoDB UI rather than filesystem.

**Verification:**
- [ ] Extract command exits 0
- [ ] No `ERROR` or `permission denied` messages
- [ ] Volume contains extracted archive contents (may be minimal)

---

### Phase 4: Disposable SowerBase Startup

**4.1 Start Complete Disposable Stack**

```powershell
cd sowerbase-restore-test
docker-compose up -d
docker-compose ps
```

**Expected:** All services healthy within 60 seconds

**Verification:**
- [ ] `db` container: UP, healthy
- [ ] `redis` container: UP, healthy
- [ ] `nocodb` container: UP, healthy
- [ ] `worker` container: UP

**4.2 Wait for NocoDB Health**

```powershell
# Poll health endpoint
$attempts = 0
while ($attempts -lt 30) {
    $response = curl -s http://localhost:18081/api/v1/health
    if ($response -match '"status":"ok"') {
        Write-Host "Disposable NocoDB healthy"
        break
    }
    Start-Sleep -Seconds 2
    $attempts++
}
```

**Verification:**
- [ ] Health endpoint responds within 60 seconds
- [ ] HTTP 200 response
- [ ] `"status":"ok"` in JSON

---

## Verification Checklist

### Resource Isolation

**Active Local Resources (Must Be Untouched):**
- [ ] `sowerbase-local` containers still running
- [ ] `sowerbase-local_postgres_data` volume unchanged
- [ ] `sowerbase-local_nocodb_data` volume unchanged
- [ ] `sowerbase-local_redis_data` volume unchanged
- [ ] Port 18080 still serving active SowerBase

**Disposable Test Resources (New):**
- [ ] `sowerbase-restore-test` containers created
- [ ] `disposable_postgres_data` volume created (new)
- [ ] `disposable_nocodb_data` volume created (new)
- [ ] `disposable_redis_data` volume created (new)
- [ ] Port 18081 serving disposable SowerBase

### PostgreSQL Restore Verification

- [ ] PostgreSQL dump imported: `nocodb_dump_2026-06-27_1350.sql`
- [ ] Database `nocodb` exists and contains tables
- [ ] No restore errors in logs
- [ ] `docker exec` commands return exit code 0

### NocoDB Volume Restore Verification

- [ ] NocoDB volume snapshot extracted: `nocodb_volume_2026-06-27.tar.gz`
- [ ] Archive extracted without permission errors
- [ ] Volume mounted to disposable NocoDB container

### Service Health Verification

- [ ] Disposable PostgreSQL healthy (pg_isready returns 0)
- [ ] Disposable Redis healthy (redis-cli ping returns PONG)
- [ ] Disposable NocoDB healthy (health endpoint responds)
- [ ] Disposable NocoDB UI loads on http://localhost:18081

### Data Accessibility Verification

- [ ] SowerBase UI loads at `http://localhost:18081`
- [ ] NocoDB markup present in HTML response
- [ ] No 404, 500, or service unavailable errors
- [ ] UI responds to user interactions (click, navigate)

### Restored State Validation

- [ ] Database schema present (tables exist)
- [ ] Data visible in NocoDB if UI shows records
- [ ] Reasonable state compared to backup time
- [ ] No obvious corruption or missing data

### Safety Constraint Verification

- [ ] ✅ No Canon data connected
- [ ] ✅ No production tables created
- [ ] ✅ THIHskills untouched
- [ ] ✅ Active local SowerBase unaffected
- [ ] ✅ Active volumes unmodified
- [ ] ✅ Backup artifacts not committed to git

---

## Post-Test Procedures

### If Restore Succeeds

**Cleanup (Unless Michael Approves Retention):**

```powershell
cd sowerbase-restore-test

# Shut down disposable stack
docker-compose down --volumes

# Verify cleanup
docker volume ls | grep disposable  # should be empty
docker ps --filter "name=sowerbase-restore-test" | wc -l  # should be 0
```

**Verification:**
- [ ] All disposable containers stopped
- [ ] All disposable volumes removed
- [ ] Original `sowerbase-local` containers still running
- [ ] Original `sowerbase-local` volumes still present
- [ ] Original SowerBase still healthy on port 18080

**Documentation:**
- [ ] Record all verification results
- [ ] Document any data differences from backup time
- [ ] Document restore time and resource usage
- [ ] Update main backup strategy if needed

### If Restore Fails

**Diagnosis:**
1. Collect logs from all disposable containers
2. Check error messages in restore commands
3. Verify PostgreSQL dump integrity
4. Verify NocoDB volume snapshot integrity
5. Check disk space and permissions

**Rollback:**
```powershell
cd sowerbase-restore-test
docker-compose down --volumes  # remove all disposable resources
```

**Do NOT modify active sowerbase-local.**

---

## Approval Gate

⚠️ **This is a plan document only. No restore will be executed until Michael approves.**

**To proceed with restore execution:**
1. Michael reviews this plan
2. Michael approves execution in writing
3. Follow "Restore Procedure" section exactly
4. Document results in new document
5. Report completion with verification results

---

## Rollback/Cleanup Plan

### Safe Cleanup (Disposable Only)

**Step 1: Stop Disposable Stack**
```powershell
cd sowerbase-restore-test
docker-compose down
```

**Step 2: Remove Disposable Volumes**
```powershell
docker volume rm sowerbase-restore-test_disposable_postgres_data
docker volume rm sowerbase-restore-test_disposable_nocodb_data
docker volume rm sowerbase-restore-test_disposable_redis_data
```

**Step 3: Verify Active Resources Untouched**
```powershell
docker volume ls | grep sowerbase-local  # should list 3 volumes
docker ps | grep sowerbase-local         # should list 4 containers
curl http://localhost:18080              # should respond
```

### If Accidental Modification

**DO NOT DELETE ANYTHING WITHOUT CONFIRMATION**

If active `sowerbase-local` volumes are accidentally modified:
1. STOP all operations immediately
2. Do NOT restart `sowerbase-local`
3. Contact team for recovery assistance
4. Restore from backup if available
5. Review and update safety procedures

---

## Resource Requirements

- **Disk Space:** ~500 MB (PostgreSQL dump + NocoDB + Redis volumes)
- **Memory:** ~2 GB for disposable stack
- **CPU:** Minimal (restore is I/O bound)
- **Network:** Internal Docker network only
- **Duration:** ~2-5 minutes for complete restore and verification
- **Port:** 18081 must be available (not in use)

---

## Environment Variables and Credentials

**PostgreSQL Credentials (Same as Source):**
- Username: `nocodb`
- Password: `[REDACTED]` (never hardcode in logs)
- Database: `nocodb`
- Host: `db` (internal service name)
- Port: `5432` (internal, not exposed)

**NocoDB Configuration:**
- Site URL: `http://localhost:18081` (external)
- Database URL: `pg://db:5432?u=nocodb&p=[REDACTED]&d=nocodb` (internal)
- Redis URL: `redis://redis:6379` (internal)

**Security:**
- Never log real passwords
- Use `[REDACTED]` in documentation
- Remove environment variables after commands
- Do not commit credentials to git

---

## Success Criteria

Restore test is considered successful if ALL of the following are true:

1. ✅ Disposable environment created without affecting active local SowerBase
2. ✅ PostgreSQL dump restored without errors
3. ✅ NocoDB volume restored without errors
4. ✅ Disposable SowerBase starts and becomes healthy
5. ✅ Disposable UI loads on http://localhost:18081
6. ✅ Restored data is accessible and reasonable
7. ✅ Active local SowerBase remains healthy on http://localhost:18080
8. ✅ Active volumes untouched and unmodified
9. ✅ No Canon data connected at any point
10. ✅ No production tables created
11. ✅ THIHskills untouched
12. ✅ Disposable resources cleaned up after test

---

## Next Steps After Successful Restore

1. **Document Results** - Create restore result document
2. **Backup Frequency** - Establish automated backup schedule
3. **Retention Policy** - Define backup retention (weekly, monthly archives)
4. **Disaster Recovery Runbook** - Document full recovery procedures
5. **Regular Testing** - Schedule periodic restore tests (monthly recommended)
6. **Monitoring** - Add backup success/failure alerts

---

## Notes

- This plan is designed for local development environment testing
- Procedures can be adapted for production if needed
- Restore time and data volume may vary based on backup size
- Archive size (86 bytes) is expected for configuration-only NocoDB volumes
- PostgreSQL dump is the primary backup (389 KB contains all critical data)

---

## Conclusion

This disposable restore test validates the backup system without risk to the active local SowerBase environment. By using separate Docker project names, volumes, and ports, complete isolation is maintained. Test execution requires explicit approval before proceeding.

**Status:** Plan complete. Awaiting Michael approval for execution.
