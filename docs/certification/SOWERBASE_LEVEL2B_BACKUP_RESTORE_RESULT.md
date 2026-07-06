# SowerBase Level 2B Backup Restore Result

Status: failed_certification_candidate
Date: 2026-07-05
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

Level 2B isolated restore proof has not been rerun yet.
## Required Next Gate

Gate 2B-Fix: expand and validate SowerBase backup scope so PostgreSQL backup
includes NocoDB user-data schemas, then rerun isolated restore proof.
