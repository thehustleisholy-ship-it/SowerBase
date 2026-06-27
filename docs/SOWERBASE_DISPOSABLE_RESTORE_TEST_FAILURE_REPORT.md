# SowerBase Disposable Restore Test — Failure Report

## Executive Summary

The disposable restore test revealed a **critical backup creation defect**: the PostgreSQL dump is missing the `nc_store_id_seq` sequence, which is required by the NocoDB application.

**Status:** Restore test failed at Phase 4 (NocoDB startup)  
**Severity:** Critical — Backup is incomplete  
**Affected Component:** PostgreSQL backup script  
**Active SowerBase:** Still healthy and operational

---

## Failure Timeline

### First Attempt (2026-06-27 15:05:31)

**Phases 1-3:** ✅ Succeeded
- Disposable PostgreSQL initialized
- PostgreSQL dump restored (118 tables, exit code 0)
- NocoDB volume snapshot extracted

**Phase 4:** ❌ Failed
- NocoDB startup error: `null value in column "id" of relation "nc_store" violates not-null constraint`
- Initially diagnosed as schema version mismatch
- Root cause: Missing sequence definition

### Investigation Phase

Checked sequence definitions in both databases:

**Active Database Sequences (4 total):**
```
public | nc_api_tokens_id_seq                | sequence | nocodb
public | nc_store_id_seq                     | sequence | nocodb
public | xc_knex_migrationsv0_id_seq         | sequence | nocodb
public | xc_knex_migrationsv0_lock_index_seq | sequence | nocodb
```

**Restored Database Sequences (3 total, MISSING 1):**
```
public | nc_api_tokens_id_seq                | sequence | nocodb
                                              [MISSING: nc_store_id_seq]
public | xc_knex_migrationsv0_id_seq         | sequence | nocodb
public | xc_knex_migrationsv0_lock_index_seq | sequence | nocodb
```

### Retry Attempt (2026-06-27 17:03:54)

**Strategy:** Match disposable environment to active environment with:
- Same NocoDB image: `nocodb/nocodb:latest` (SHA256: e5a6ac9cfa59f78b...)
- Additional env vars: `NC_DOCKER=0.6`, `NC_TOOL_DIR=/usr/app/data/`
- PostgreSQL 17.10 (same version)
- Redis 7 (same version)

**Phase 1:** ✅ Disposable environment initialized
**Phase 2:** ✅ PostgreSQL dump restored (118 tables, exit code 0)
**Discovery Phase:** ❌ Sequence verification failed
- nc_store_id_seq not found in restored database
- Only 3 of 4 required sequences present
- Confirmed: Backup dump is incomplete

---

## Root Cause Analysis

### The Problem

The PostgreSQL dump file (`nocodb_dump_2026-06-27_1350.sql`) was created with `pg_dump` but does not include the `nc_store_id_seq` sequence definition.

### The Mechanism

1. **nc_store Table Definition (Active):**
   ```
   Column | id | integer | NOT NULL | DEFAULT nextval('nc_store_id_seq'::regclass)
   ```

2. **nc_store Table in Restored Database:**
   - Table exists: ✓ (118 tables restored)
   - Column `id` exists: ✓
   - Sequence `nc_store_id_seq` exists: ✗ (NOT in backup dump)
   - Default behavior for new rows: ✗ (sequence doesn't exist)

3. **NocoDB Initialization:**
   - Connects to restored PostgreSQL
   - Tries to initialize internal state by inserting into nc_store
   - Attempts to use sequence default: `DEFAULT nextval('nc_store_id_seq'::regclass)`
   - Sequence doesn't exist: PostgreSQL constraint violation
   - Application fails to start

### Why This Happened

The backup script uses:
```powershell
docker exec pg_dump -U $DB_USER -d $DB_NAME | out_to_file
```

This approach captures:
- ✅ Table schemas
- ✅ Table data
- ✅ Most sequences (nc_api_tokens_id_seq, xc_knex_migrationsv0_id_seq, etc.)
- ❌ MISSING: nc_store_id_seq sequence

The `nc_store_id_seq` sequence exists but was not included in the dump, likely because:
- It's owned by or related to the nc_store table
- It may be a recent addition to the schema
- pg_dump may skip certain sequences under specific conditions

---

## Verification Results

| Aspect | Status | Details |
|--------|--------|---------|
| **Active Image** | ✅ | nocodb/nocodb:latest (SHA256: e5a6ac9cfa...) |
| **Disposable Image** | ✅ | nocodb/nocodb:latest (same as active) |
| **Environment Variables** | ✅ | Matched active (NC_DOCKER, NC_TOOL_DIR added) |
| **PostgreSQL Restore** | ✅ | 118 tables, exit code 0 |
| **PostgreSQL Sequences** | ❌ | 3 of 4 sequences (nc_store_id_seq MISSING) |
| **NocoDB Startup** | ❌ | Failed: sequence constraint violation |
| **Disposable Port 18081** | ❌ | Not responding (NocoDB failed to start) |
| **Active Port 18080** | ✅ | Responsive, healthy, unaffected |
| **Active Volumes** | ✅ | Untouched and intact |
| **Backup Artifacts** | ✅ | Ignored and untracked |

---

## Impact Assessment

**Backup Status:** 🔴 **CRITICAL ISSUE**
- PostgreSQL dump is **incomplete**
- Cannot be used for full system restore
- NocoDB requires the missing sequence to function

**Data Loss Risk:** ⚠️ **MEDIUM**
- PostgreSQL data is intact (118 tables restored successfully)
- If sequence were added manually, data would be accessible
- But automated restore fails without manual intervention

**Active System:** ✅ **UNAFFECTED**
- Active SowerBase continued operating during entire test
- No volumes were modified
- No containers were affected
- Service remains healthy

---

## Recommended Repairs

### Immediate: Fix the Backup Script

The PostgreSQL backup step in `scripts/thih-backup-sowerbase.ps1` should be updated to ensure all sequences are captured:

**Option A: Use pg_dump with explicit sequence inclusion**
```bash
pg_dump --schema-only --include-sequences U $DB_USER -d $DB_NAME
```

**Option B: Use pg_dump with standard options that include sequences**
```bash
pg_dump -U $DB_USER -d $DB_NAME  # sequences are included by default
```

**Option C: Explicit dump of sequences before tables**
```bash
# First: dump sequence definitions
pg_dump --schema-only -t nc_store_id_seq U $DB_USER -d $DB_NAME

# Then: dump full schema and data
pg_dump -U $DB_USER -d $DB_NAME
```

### Testing: Verify Complete Dump

After fixing the backup script:
1. Create a new backup with the fixed script
2. Verify all 4 sequences are present in the dump file
3. Retry disposable restore test
4. Confirm NocoDB starts successfully

### Documentation: Update Backup Plan

Update `docs/SOWERBASE_DISPOSABLE_RESTORE_TEST_PLAN.md` to include:
- Sequence verification step
- Post-restore validation checklist
- Backup completeness requirements

---

## Technical Details

### Active Environment Configuration

**NocoDB Image:**
```
Image: nocodb/nocodb:latest
ImageID: sha256:e5a6ac9cfa59f78b333b491efde4b6cd60bb866b49c76daf92295ef359ef710e
Created: 2026-06-26T20:16:35.527299718Z
```

**Environment Variables:**
```
NC_DB: pg://db:5432?u=nocodb&p=[REDACTED]&d=nocodb
NC_REDIS_URL: redis://redis:6379
NC_SITE_URL: http://localhost:8080
NC_DISABLE_MUX: true
NC_DOCKER: 0.6
NC_TOOL_DIR: /usr/app/data/
```

**Database:**
```
User: nocodb
Database: nocodb
Engine: PostgreSQL 17.10
```

### Disposable Environment Configuration (Attempted)

**Matching Configuration:**
```
Image: nocodb/nocodb:latest (same as active)
NC_DB: pg://db:5432?u=nocodb&p=[REDACTED]&d=nocodb
NC_REDIS_URL: redis://redis:6379
NC_SITE_URL: http://localhost:18081
NC_DISABLE_MUX: true
NC_DOCKER: 0.6
NC_TOOL_DIR: /usr/app/data/
Port: 18081 -> 8080
Database: PostgreSQL 17.10
```

### Backup Artifact Inspection

**PostgreSQL Dump File:**
- Path: `backups/postgres-dumps/nocodb_dump_2026-06-27_1350.sql`
- Size: 389.13 KB
- Created: 2026-06-27 13:50:16
- Status: Incomplete (missing nc_store_id_seq)

**NocoDB Volume Snapshot:**
- Path: `backups/volumes/nocodb_volume_2026-06-27.tar.gz`
- Size: 86 bytes
- Status: Valid (minimal configuration)

---

## Safety Compliance

✅ **No production tables created**
✅ **No Canon data connected**
✅ **THIHskills untouched**
✅ **Active SowerBase remained operational**
✅ **Active volumes remain intact**
✅ **Backup artifacts ignored by git**
✅ **Disposable resources fully cleaned up**
✅ **No manual schema modifications**

---

## Conclusion

The disposable restore test successfully identified a **critical backup defect**: the PostgreSQL dump is incomplete and cannot be used for full system recovery without manual sequence recreation.

**This is a backup creation issue, not a restore/application issue.**

The backup script must be fixed to ensure the `nc_store_id_seq` sequence (and all other sequences) are included in future PostgreSQL dumps. Once fixed, the restore test should be retried to validate the corrected backup procedure.

---

## Next Steps

1. **Fix Backup Script:** Update PostgreSQL dump command to include all sequences
2. **Retest Backup:** Execute corrected backup script and verify sequence inclusion
3. **Retry Restore:** Run disposable restore test with corrected backup
4. **Update Documentation:** Document backup completeness requirements
5. **Establish Validation:** Add sequence verification to backup validation checklist

---

## Appendix: Sequence Details

### nc_store_id_seq (MISSING FROM BACKUP)

**Definition in Active Database:**
```sql
CREATE SEQUENCE nc_store_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE nc_store_id_seq OWNER TO nocodb;
```

**Usage:**
```sql
-- In nc_store table:
id integer NOT NULL DEFAULT nextval('nc_store_id_seq'::regclass)
```

**Impact of Missing Sequence:**
- Any INSERT into nc_store without explicit `id` value will fail
- NocoDB initialization requires inserting into nc_store
- Application cannot start without sequence

---

**Status:** Test Stopped - Backup Defect Confirmed  
**Timestamp:** 2026-06-27 17:03:54 UTC  
**Active SowerBase:** Healthy and operational at http://localhost:18080
