# SowerBase Level 1 Stress Harness Usage

## Purpose

`scripts/certification/sowerbase-write-stress.ps1` is the local-only Level 1 certification harness for SowerBase write stress testing.

It is designed to prove synthetic HVAC webhook behavior before SowerBase can advance beyond Level 0 local mirror proof. It does not certify Airtable replacement by itself.

## Prerequisites

- Local SowerBase/NocoDB is running.
- Local authenticated HVAC webhook receiver is running.
- The target endpoint is local unless a later approval gate explicitly permits otherwise.
- Test data is synthetic only.
- No production or public endpoint should be used without approval.

## Env Names Required

Names only; do not print values.

Required for valid write probes:

- `ASKTHIH_WEBHOOK_SECRET`

Optional for row-count and duplicate readback:

- `SOWERBASE_BASE_URL`
- `SOWERBASE_API_TOKEN`
- `SOWERBASE_INTAKE_TABLE_ID`

## Dry Run Command

Generates reports without sending webhook requests.

```powershell
.\scripts\certification\sowerbase-write-stress.ps1 -DryRun
```

## Auth-Only And Single-Write Command

Runs missing-secret, wrong-secret, and single valid write probes only. This may create one synthetic row if the local receiver is running and auth is configured.

```powershell
.\scripts\certification\sowerbase-write-stress.ps1 -SkipVolume
```

## First 25-Record Command

Default safe first Level 1 run. This may create synthetic certification rows.

```powershell
.\scripts\certification\sowerbase-write-stress.ps1 `
  -RecordCount 25 `
  -Concurrency 1 `
  -Vertical HVAC `
  -MarkerPrefix cert_level1_hvac
```

## Escalation Commands

Run only after the prior level passes and a human reviewer approves escalation.

```powershell
.\scripts\certification\sowerbase-write-stress.ps1 -RecordCount 100 -Concurrency 1 -Vertical HVAC -MarkerPrefix cert_level1_hvac
```

```powershell
.\scripts\certification\sowerbase-write-stress.ps1 -RecordCount 100 -Concurrency 5 -Vertical HVAC -MarkerPrefix cert_level1_hvac
```

```powershell
.\scripts\certification\sowerbase-write-stress.ps1 -RecordCount 500 -Concurrency 10 -Vertical HVAC -MarkerPrefix cert_level1_hvac
```

## Report Output

Reports are written to:

- `outputs/certification/SOWERBASE_LEVEL1_LOCAL_STRESS_REPORT_<TestRunId>.md`
- `outputs/certification/SOWERBASE_LEVEL1_LOCAL_STRESS_REPORT_<TestRunId>.json`

Reports include:

- timestamp
- branch and commit when discoverable
- webhook host and port only
- marker prefix
- test run ID
- record count
- concurrency
- status-code summary
- response-time summary
- auth rejection proof
- single-write proof
- duplicate findings
- candidate pass/fail ruling
- non-claims

## Safety Defaults

Default parameters:

- `RecordCount=25`
- `Concurrency=1`
- `Vertical=HVAC`
- `MarkerPrefix=cert_level1_hvac`
- `WebhookUrl=http://localhost:8787/askthih/hvac`
- `OutputDir=outputs/certification`
- `TimeoutSec=10`

Synthetic data uses values such as:

- `cert-hvac@example.com`
- `555-0100` style phone numbers
- `Certification Test HVAC Proof`
- `Synthetic City, ST`

## Non-Claims

- Airtable has not been replaced.
- SowerBase is not certified as Airtable replacement.
- Public SowerBase receiver is not proven.
- CRM is not connected.
- Canon is not connected.
- Cloudflare is not adopted.
- A local stress report is not production proof.

## Production Warning

Do not run this harness against production or public endpoints without an explicit approval gate.

Do not add Vercel env, change DNS, configure Cloudflare, expose NocoDB/admin surfaces, or use real customer data as part of Level 1 local stress testing.
