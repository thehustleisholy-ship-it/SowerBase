# SowerBase Level 2 Backup Restore Plan

## Purpose

Prove this plainly: if SowerBase breaks, the data can be restored and the restored records can be trusted.

Level 2 is required after Level 1 local stress approval because receiving records is not enough for Airtable replacement readiness. The system must prove recoverability, integrity, and operator verification.

## Current Status

- Level 0 local mirror proof: approved
- Level 1 local stress certification: approved for the HVAC synthetic intake path only
- Production primary: Airtable
- Airtable replacement: not approved
- Public SowerBase receiver: missing
- CRM: not connected
- Canon: not connected

Approved status language:

```text
SowerBase has passed Level 1 local stress certification for the HVAC synthetic intake path. This certifies local stress behavior only. It does not certify public receiver readiness, Airtable parity, backup/restore, CRM connection, Canon connection, or Airtable replacement.
```

## What Gets Backed Up

- PostgreSQL database used by local SowerBase/NocoDB
- NocoDB application metadata required to interpret restored records
- Intake Submissions table data
- Raw Payload field contents
- Channel, Status, Vertical, and trace ID evidence
- Any local volume snapshot required for NocoDB to boot cleanly after restore

Secrets, `.env` files, and API tokens must not be copied into reports or committed.

## Where Backup Is Stored

Backups should be written to local backup storage under the existing SowerBase backup pattern, such as:

- `backups/postgres-dumps/`
- `backups/volumes/`

Backup artifacts should remain local unless a separate approval explicitly decides where encrypted backup artifacts are stored.

## How Restore Is Tested

Restore must be tested against an isolated disposable restore target, not the active local SowerBase instance.

The restore target should:

- use separate Docker containers
- use separate Docker volumes
- use a separate port from active SowerBase
- avoid public exposure
- avoid production data paths
- avoid DNS, Vercel, Cloudflare, CRM, and Canon

Active local SowerBase should remain untouched during restore verification.

## Sample Records To Check

Use synthetic Level 1 certification records only.

Check at least:

- one record from the 25 record concurrency-1 run
- one record from the 100 record concurrency-1 run
- one record from the 100 record concurrency-5 run
- one record from the 500 record concurrency-10 run
- one auth rejection marker channel with zero rows, if represented in backup evidence

For each restored sample record, verify:

- Submission Title
- Vertical
- Channel
- Status
- Raw Payload
- trace_id
- certification_run_id
- marker_prefix
- test_only marker

## Pass Criteria

Level 2 passes only if:

- backup is created successfully
- restore is executed against an isolated disposable target
- restored SowerBase/NocoDB boots cleanly
- restored Intake Submissions table is readable
- record counts match the expected backup source counts
- selected sample records match source values
- trace IDs survive restore
- Raw Payload survives restore
- Status, Channel, and Vertical fields survive restore
- operator can verify restored records through documented commands or UI checks
- rollback path is documented
- no secrets are exposed
- no production, public receiver, DNS, Vercel, Cloudflare, CRM, or Canon changes occur

## Fail Criteria

Level 2 is held if:

- backup fails or is incomplete
- restore fails
- restored NocoDB cannot boot
- restored records are missing or corrupted
- record counts do not match and the difference is not explained
- trace IDs or Raw Payload fields are lost
- operator cannot verify restored records
- active local SowerBase is damaged during restore testing
- secrets are printed or committed
- public or production infrastructure is touched

## Rollback Path To Document

The Level 2 result must document:

- how active local SowerBase was protected before restore testing
- which backup artifact was used
- how the disposable restore target was created
- how to discard the disposable restore target
- how to return to the active local SowerBase instance
- how to confirm active local SowerBase still responds after the restore test

## Must Not Be Claimed

- Airtable has not been replaced.
- Public receiver readiness is not proven.
- Airtable parity is not proven.
- CRM is not connected.
- Canon is not connected.
- Production restore readiness is not proven.
- Cloud or offsite backup policy is not proven.
- Level 2 does not certify SowerBase as the Airtable replacement by itself.
