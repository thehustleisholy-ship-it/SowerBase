# SowerBase Level 5 HVAC Primary Pilot Proof

Status: pass
Date: 2026-07-06
Scope: Local controlled HVAC-only SowerBase-primary pilot. No production route, DNS, Cloudflare tunnel, public receiver endpoint, CRM connection, Canon connection, multi-vertical cutover, or Airtable decommissioning was changed.

## Plain Question

Can SowerBase act as the primary intake store for one controlled HVAC pilot path without making a full production cutover?

## Short Answer

Yes, locally for the controlled HVAC pilot path.

Level 5 proves one synthetic HVAC intake can be accepted by the hardened receiver, written first to SowerBase, worked from SowerBase operator fields, and recovered through backup/restore evidence. Airtable remains production primary outside this pilot proof.

## Pilot Mode

Pilot vertical: HVAC

Pilot mode: SowerBase primary, Airtable disabled for this pilot path.

Reason: the existing local receiver writes directly to SowerBase and does not perform Airtable writes. Disabling Airtable for this synthetic pilot path gives a clean SowerBase-first proof without touching production Airtable routing.

Controls:

- one vertical only: HVAC
- synthetic submission only
- local loopback receiver only
- no Cloudflare tunnel
- no production DNS or routing
- no real customer data
- Airtable not touched

## Evidence Sources

- Level 5 assertion script: `scripts/certification/assert-sowerbase-level5-hvac-primary-pilot.ps1`
- Passing run artifact: `outputs/certification/SOWERBASE_LEVEL5_HVAC_PRIMARY_PILOT_level5-hvac-20260706T133044Z.md`
- Passing run JSON: `outputs/certification/SOWERBASE_LEVEL5_HVAC_PRIMARY_PILOT_level5-hvac-20260706T133044Z.json`
- Passing run log: `outputs/certification/SOWERBASE_LEVEL5_HVAC_PRIMARY_PILOT_level5-hvac-20260706T133044Z.log`

## Run Summary

Passing run: `level5-hvac-20260706T133044Z`

Pilot channel:

```text
cert_level5_hvac_primary_pilot_level5-hvac-20260706T133044Z
```

Trace ID:

```text
trace-level5-hvac-20260706T133044Z
```

## Receiver And Write Results

| Check | Expected | Actual | Result |
| --- | ---: | ---: | --- |
| Unsigned synthetic request rejected | 401 | 401 | PASS |
| Rows after unsigned request | 0 | 0 | PASS |
| Valid signed synthetic request accepted | 201 | 201 | PASS |
| Rows after valid signed request | 1 | 1 | PASS |

Result: PASS. The invalid request wrote zero rows. The valid signed HVAC pilot request wrote exactly one SowerBase row.

## SowerBase-Primary Evidence

The pilot row was verified in SowerBase with:

- `Vertical = HVAC`
- matching pilot `Channel`
- matching `Trace_ID`
- `System_Type = Central AC`
- `Preferred_Service_Window = Certification window only`
- `Migration_Status = sowerbase_primary_pilot_test_only`
- raw payload containing `sowerbase_primary_airtable_disabled`

Result: PASS.

## Operator Workflow

The HVAC operator grid exposes the required promoted fields needed to identify, filter, review, and work the pilot record:

- Trace ID
- Submitted At
- Status
- Channel
- System Type
- System Age
- Preferred Service Window
- Raw Payload

Visible required fields found: 8

Result: PASS.

## Backup And Restore After Pilot Data

Post-pilot backup checks:

```text
Backup scope guard: PASS
Backup ValidateOnly: PASS
Temporary restored pilot rows: 1
```

The proof performed a logical PostgreSQL dump from the active SowerBase database, restored it into a temporary PostgreSQL database, and verified the pilot channel existed in the restored database.

Result: PASS.

## Failure Behavior

Observed failure behavior:

- unsigned request returned `401`
- unsigned request wrote zero rows
- no bearer token, shared secret, or HMAC credential was found in the receiver log

Expected operational failure behavior for this pilot path:

- reject unauthenticated or malformed requests
- write zero rows for rejected requests
- keep Airtable-primary production path untouched
- keep pilot rows identifiable by the synthetic channel and trace ID

Result: PASS.

## Rollback Path

Rollback path:

```text
disable pilot route and return HVAC intake to Airtable-primary path
```

Pilot rows are identifiable by channel:

```text
cert_level5_hvac_primary_pilot_level5-hvac-20260706T133044Z
```

Because this proof did not change production routing or public DNS, rollback is limited to leaving the local pilot route disabled and continuing Airtable-primary operation.

## Non-Claims

Level 5 does not certify:

- full production cutover
- public production routing
- multi-vertical production routing
- CRM connection
- Canon connection
- Airtable decommissioning
- SowerBase as the sole production system of record

## Verdict

PASS.

SowerBase passes Level 5 for a controlled, synthetic, HVAC-only SowerBase-primary pilot. The proof confirms SowerBase can write first for the pilot path, reject bad unsigned traffic, expose the pilot record for operator work, preserve pilot metadata, and retain the pilot row through backup/restore evidence.

Airtable remains production primary until the next approved certification step explicitly expands routing beyond this controlled HVAC pilot proof.
