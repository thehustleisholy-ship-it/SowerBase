# SowerBase Level 2B Backup Restore Result

Status: passed_after_gate_2b_fix
Date: 2026-07-06
Scope: local-only SowerBase backup and isolated restore proof

## Objective

Prove that a full SowerBase backup can be restored into the isolated
`sowerbase-restore-test` target and preserve the Level 1 synthetic HVAC
certification records.

## Guardrails Observed

- No production or public systems were touched.
- No DNS, Vercel, Cloudflare, CRM, or Canon systems were touched.
- No restore was attempted against active `sowerbase-local`.
- No secrets were printed.
- No `-AllowPartial` backup was used.
- Restore was attempted only against the isolated `sowerbase-restore-test` stack.
- Disposable restore-test containers and volumes were removed after the proof.

## Backup Validation

Validation command:

```powershell
.\scripts\thih-backup-sowerbase.ps1 -ValidateOnly
```

Result: passed after running with Docker access.

Validation checks passed:

- Docker available
- Docker Compose available
- PostgreSQL container running
- PostgreSQL reachable
- NocoDB container running
- NocoDB health endpoint responding
- NocoDB volume exists
- backups/ ignored by git
- no tracked backup files
- backup directories creatable

## Full Backup

Backup command:

```powershell
.\scripts\thih-backup-sowerbase.ps1 -BackupType all
```

Result: completed successfully.

Artifacts created:

- `backups/postgres-dumps/nocodb_dump_2026-07-05_1902.sql`
- `backups/volumes/nocodb_volume_2026-07-05.tar.gz`
- `backups/BACKUP_LOG.txt`

Notes:

- The PostgreSQL dump completed and validated.
- The NocoDB volume snapshot completed.
- The NocoDB volume archive was very small, which the backup script warned may
  indicate an empty/config-only volume.

## Source Record Baseline

Active source stack:

- `sowerbase-local` remained healthy on `localhost:18080`.

Source Level 1 synthetic HVAC counts before restore:

| Channel | Source rows |
| --- | ---: |
| `cert_level1_hvac-cert-20260705T135556Z` | 25 |
| `cert_level1_hvac-cert-20260705T140747Z` | 100 |
| `cert_level1_hvac-cert-20260705T141644Z` | 100 |
| `cert_level1_hvac-cert-20260705T142036Z` | 500 |
| `cert_level1_hvac-cert-20260705T135556Z-single` | 1 |
| `cert_level1_hvac-cert-20260705T140747Z-single` | 1 |
| `cert_level1_hvac-cert-20260705T141644Z-single` | 1 |
| `cert_level1_hvac-cert-20260705T142036Z-single` | 1 |

The physical source table was identified as:

```text
peoc8ioej5ejtj7."HVAC Intake"
```

## Restore Attempt

Restore target:

```text
sowerbase-restore-test
```

Restore target status:

- `sowerbase-restore-test-db-1` healthy
- `sowerbase-restore-test-redis-1` healthy
- `sowerbase-restore-test-nocodb-1` healthy
- `localhost:18081` reachable

The SQL dump initially stopped because the disposable database already had a
default `public` schema. The disposable `public` schema was dropped and the dump
was replayed successfully against `sowerbase-restore-test-db-1` only.

The NocoDB volume snapshot was restored into:

```text
sowerbase-restore-test_disposable_nocodb_data
```

## Restore Verification Result

Restored metadata tables existed under `public`.

The Level 1 HVAC user-data schema/table did not exist after restore:

```text
peoc8ioej5ejtj7."HVAC Intake"
```

The restored dump did not contain:

- `peoc8ioej5ejtj7`
- `HVAC Intake`
- `cert_level1_hvac`

Observed cause:

```text
scripts/thih-backup-sowerbase.ps1 currently runs pg_dump with --schema=public.
```

That scope backs up NocoDB metadata in `public`, but it excludes the NocoDB
user-data schema where the Level 1 HVAC records live.

## Pass/Fail Against Level 2B Criteria

| Criterion | Result |
| --- | --- |
| backup validation passes | PASS |
| full backup artifacts created | PASS |
| restore-test stack starts on `18081` | PASS |
| active stack remains healthy on `18080` | PASS |
| restored counts match four Level 1 channels | FAIL |
| sample fields survive restore | FAIL |
| Raw Payload survives restore | FAIL |
| `trace_id` survives restore | FAIL |
| `certification_run_id` survives restore | FAIL |
| `marker_prefix` survives restore | FAIL |
| `test_only` survives restore | FAIL |
| rollback/cleanup path documented | PASS |

The failed field-survival checks are caused by the missing restored user-data
schema/table, not by corrupted sample values.

## Cleanup

Disposable restore-test cleanup was executed:

```powershell
docker compose down --volumes
```

Cleanup removed:

- restore-test containers
- restore-test network
- restore-test disposable PostgreSQL volume
- restore-test disposable Redis volume
- restore-test disposable NocoDB volume

Active `sowerbase-local` remained healthy after cleanup.

## Non-Claims

- SowerBase has not passed Level 2 backup/restore certification.
- SowerBase is not certified as the Airtable replacement.
- Public receiver readiness is not proven.
- Airtable parity is not proven.
- CRM is not connected.
- Canon is not connected.
- No production/public deployment behavior is proven by this local restore test.

## Ruling

Level 2B failed: current backup artifacts restore NocoDB metadata but do not
restore the Level 1 HVAC user-data schema/table, so record integrity cannot be
proven.

## Gate 2B-Fix Patch Status

Date: 2026-07-06
Status: backup_scope_patched_restore_proof_pending

Patch applied before rerunning Level 2B:

- Removed the `pg_dump --schema=public` restriction from `scripts/thih-backup-sowerbase.ps1`.
- PostgreSQL backup now dumps the full `nocodb` database with `pg_dump -F p --no-owner`.
- Backup validation now inventories non-system PostgreSQL schemas through `pg_namespace`.
- Backup validation now fails if any non-public NocoDB user-data schema is missing from the SQL dump.
- Sequence validation now checks sequences across all non-system schemas, not only `public`.
- Added `scripts/certification/assert-sowerbase-backup-scope.ps1` as a static guard against reintroducing public-schema-only backups.

Verification performed for this patch only:

```powershell
.\scripts\certification\assert-sowerbase-backup-scope.ps1
```

Result: passed.

Level 2B isolated restore proof was rerun on 2026-07-06 and passed; see rerun section below.
## Gate 2B-Fix Rerun Result

Date: 2026-07-06
Status: passed
Commit under test: `b71a1e1b0c` (`fix: expand SowerBase backup scope for NocoDB user data`)

Execution order completed:

1. `ValidateOnly`
2. full backup
3. isolated restore into `sowerbase-restore-test` only
4. restored HVAC user-data schema/table verification
5. Level 1 sample channel counts verification
6. `Raw_Payload` and trace field survival verification
7. pass/fail documented here

### Rerun Backup Validation

Command:

```powershell
.\scripts\thih-backup-sowerbase.ps1 -ValidateOnly
```

Result: PASS, 10/10 checks passed.

### Rerun Full Backup

Command:

```powershell
.\scripts\thih-backup-sowerbase.ps1 -BackupType all
```

Result: PASS.

Artifacts created:

- `backups/postgres-dumps/nocodb_dump_2026-07-06_1027.sql` (`3,366,823` bytes)
- `backups/volumes/nocodb_volume_2026-07-06.tar.gz` (`86` bytes)
- `backups/BACKUP_LOG.txt`

Backup scope evidence:

- non-system schemas in backup scope: 3 (`peoc8ioej5ejtj7`, `pjnth56hr07kzq1`, `public`)
- non-public NocoDB user-data schemas in dump: 2
- sequences in dump: 6
- dump validation: PASS

### Rerun Isolated Restore

Target: `sowerbase-restore-test` only.

Restore actions:

- removed any existing disposable restore-test containers/volumes with `docker compose down --volumes`
- started disposable `db` and `redis`
- copied `nocodb_dump_2026-07-06_1027.sql` into `sowerbase-restore-test-db-1`
- restored with `psql -v ON_ERROR_STOP=1 -f /tmp/nocodb_restore.sql`
- restored `nocodb_volume_2026-07-06.tar.gz` into `sowerbase-restore-test_disposable_nocodb_data`
- started the full disposable stack

Restore result: PASS.

Disposable stack health during proof:

- `sowerbase-restore-test-db-1`: healthy
- `sowerbase-restore-test-redis-1`: healthy
- `sowerbase-restore-test-nocodb-1`: healthy
- `localhost:18081/api/v1/health`: HTTP 200

Active stack isolation check:

- `localhost:18080/api/v1/health`: HTTP 200 during and after proof
- active `sowerbase-local` containers remained running and healthy
- no restore was attempted against active `sowerbase-local`

### Restored User-Data Schema/Table

Result: PASS.

Restored non-public tables:

| Schema | Table |
| --- | --- |
| `peoc8ioej5ejtj7` | `HVAC Intake` |
| `pjnth56hr07kzq1` | `Features` |

Required HVAC table exists:

```text
peoc8ioej5ejtj7."HVAC Intake"
```

### Restored Level 1 Counts

Result: PASS. Source and restored counts matched exactly.

| Channel | Source rows | Restored rows |
| --- | ---: | ---: |
| `cert_level1_hvac-cert-20260705T135200Z-single` | 1 | 1 |
| `cert_level1_hvac-cert-20260705T135556Z` | 25 | 25 |
| `cert_level1_hvac-cert-20260705T135556Z-single` | 1 | 1 |
| `cert_level1_hvac-cert-20260705T140747Z` | 100 | 100 |
| `cert_level1_hvac-cert-20260705T140747Z-single` | 1 | 1 |
| `cert_level1_hvac-cert-20260705T141644Z` | 100 | 100 |
| `cert_level1_hvac-cert-20260705T141644Z-single` | 1 | 1 |
| `cert_level1_hvac-cert-20260705T142036Z` | 500 | 500 |
| `cert_level1_hvac-cert-20260705T142036Z-single` | 1 | 1 |

Total restored Level 1 rows: 730.

### Raw Payload And Trace Field Survival

Result: PASS.

Restored `Raw_Payload` checks:

| Check | Restored rows |
| --- | ---: |
| Level 1 rows | 730 |
| rows with `Raw_Payload` | 730 |
| rows whose payload contains `trace_id` | 730 |
| rows whose payload contains `certification_run_id` | 730 |
| rows whose payload contains `marker_prefix` | 730 |
| rows whose payload contains `test_only` | 730 |

Source and restored `Raw_Payload` MD5 aggregates matched for every Level 1 channel:

| Channel | Rows | Raw payload MD5 |
| --- | ---: | --- |
| `cert_level1_hvac-cert-20260705T135200Z-single` | 1 | `656495c9dbf7eb3db6302fcd6f7a423d` |
| `cert_level1_hvac-cert-20260705T135556Z` | 25 | `f84324c29972fb47b43e2f4f27f6bc2c` |
| `cert_level1_hvac-cert-20260705T135556Z-single` | 1 | `a753c033d087ae55d4a8b1902e093909` |
| `cert_level1_hvac-cert-20260705T140747Z` | 100 | `95b294a4a3cacee6aabfd888a1ed6fbb` |
| `cert_level1_hvac-cert-20260705T140747Z-single` | 1 | `1a4000f8131825a04bb6df0335ac064f` |
| `cert_level1_hvac-cert-20260705T141644Z` | 100 | `f254a05249199d7722905eb3c5ef04fe` |
| `cert_level1_hvac-cert-20260705T141644Z-single` | 1 | `19c358f98aeacc36edc6b3cf49835d71` |
| `cert_level1_hvac-cert-20260705T142036Z` | 500 | `a1f70159f2d65a41128c0479e6e033d2` |
| `cert_level1_hvac-cert-20260705T142036Z-single` | 1 | `4346db0a036d27265694ed1a9f173846` |

### Rerun Pass/Fail Against Level 2B Criteria

| Criterion | Result |
| --- | --- |
| backup validation passes | PASS |
| full backup artifacts created | PASS |
| backup includes NocoDB user-data schemas | PASS |
| restore-test stack starts on `18081` | PASS |
| active stack remains healthy on `18080` | PASS |
| restored HVAC user-data schema/table exists | PASS |
| restored counts match Level 1 channels | PASS |
| sample fields survive restore | PASS |
| `Raw_Payload` survives restore | PASS |
| `trace_id` survives restore | PASS |
| `certification_run_id` survives restore | PASS |
| `marker_prefix` survives restore | PASS |
| `test_only` survives restore | PASS |
| rollback/cleanup path executed | PASS |

### Rerun Cleanup

Disposable restore-test cleanup was executed after verification:

```powershell
docker compose down --volumes
```

Cleanup removed:

- `sowerbase-restore-test` containers
- `sowerbase-restore-test_disposable-nocodb-network`
- `sowerbase-restore-test_disposable_postgres_data`
- `sowerbase-restore-test_disposable_redis_data`
- `sowerbase-restore-test_disposable_nocodb_data`

Post-cleanup checks:

- active `sowerbase-local` health endpoint returned HTTP 200
- active `sowerbase-local` containers remained running
- no `sowerbase-restore-test` volumes remained

## Final Ruling

Level 2B PASSED on 2026-07-06 after Gate 2B-Fix. The expanded PostgreSQL backup scope includes NocoDB user-data schemas, and the isolated restore proof preserved the Level 1 HVAC table, channel counts, `Raw_Payload`, and trace fields.

## Remaining Non-Claims After Rerun

- Public receiver readiness is not proven by this local restore test.
- Airtable parity is not proven by this local restore test.
- CRM is not connected by this local restore test.
- Canon is not connected by this local restore test.
- No production/public deployment behavior is proven by this local restore test.

## Required Next Gate

Gate 2B-Fix is complete. Proceed to the next certification gate only after reviewing the 2026-07-06 Level 2B pass evidence above.


