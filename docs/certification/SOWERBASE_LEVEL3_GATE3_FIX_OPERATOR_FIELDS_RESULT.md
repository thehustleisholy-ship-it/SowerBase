# SowerBase Level 3 Gate 3-Fix Operator Fields Result

Date: 2026-07-06

Status: PASS

## Question

Can SowerBase promote the required intake parity fields from Raw Payload-only
storage into first-class operator fields while preserving the certified HVAC
intake data path?

## Result

PASS. The certified local SowerBase/NocoDB HVAC intake table now has physical
PostgreSQL columns, NocoDB field metadata, and visible grid columns for the
minimum Gate 3-Fix parity scope.

Target table:

```text
peoc8ioej5ejtj7."HVAC Intake"
```

NocoDB model:

```text
ml69vs2tgn6ng1p / HVAC Intake
```

Operator grid:

```text
vw2o6k70z2ztux46 / Table-1
```

## Scope Split

### Shared/Common Intake Fields

| Operator field | PostgreSQL column | NocoDB type | Result |
| --- | --- | --- | --- |
| Trace ID | `Trace_ID` | `SingleLineText` | PASS |
| Submitted At | `Submitted_At` | `DateTime` | PASS |
| Transcript | `Transcript` | `LongText` | PASS |

### HVAC Parity Fields

| Operator field | PostgreSQL column | NocoDB type | Result |
| --- | --- | --- | --- |
| System Type | `System_Type` | `SingleLineText` | PASS |
| System Age | `System_Age` | `SingleLineText` | PASS |
| Preferred Service Window | `Preferred_Service_Window` | `SingleLineText` | PASS |

### Plumber Parity Fields

| Operator field | PostgreSQL column | NocoDB type | Result |
| --- | --- | --- | --- |
| Preferred Callback Time | `Preferred_Callback_Time` | `SingleLineText` | PASS |

## Evidence

Pre-fix assertion:

```text
FAIL: SowerBase Level 3 first-class operator fields are incomplete.
physical_missing / metadata_missing / grid_hidden_or_missing for all seven required fields
```

Migration command:

```powershell
.\scripts\certification\sowerbase-gate3-promote-intake-fields.ps1
```

Migration result:

```text
ALTER TABLE x7
UPDATE 750
DO
COMMIT
```

Post-fix assertion:

```powershell
.\scripts\certification\assert-sowerbase-level3-fields.ps1
```

Post-fix result:

```text
PASS: SowerBase Level 3 first-class operator fields are present and grid-visible.
Shared/common intake fields: Trace ID, Submitted At, Transcript
HVAC parity fields: System Type, System Age, Preferred Service Window
Plumber parity fields: Preferred Callback Time
```

Level 1 HVAC certification row backfill sample:

```text
rows, trace_ids, submitted_at, system_type, system_age, preferred_window
730, 730, 730, 730, 730, 730
```

NocoDB metadata sample:

```text
Trace ID,Trace_ID,SingleLineText
Submitted At,Submitted_At,DateTime
Transcript,Transcript,LongText
System Type,System_Type,SingleLineText
System Age,System_Age,SingleLineText
Preferred Service Window,Preferred_Service_Window,SingleLineText
Preferred Callback Time,Preferred_Callback_Time,SingleLineText
```

Operator grid visibility sample:

```text
Trace ID,t,180px
Submitted At,t,180px
Transcript,t,260px
System Type,t,180px
System Age,t,140px
Preferred Service Window,t,220px
Preferred Callback Time,t,220px
```

## Files

- `scripts/certification/assert-sowerbase-level3-fields.ps1`
- `scripts/certification/sowerbase-gate3-promote-intake-fields.ps1`
- `scripts/askthih-hvac-local-webhook-server.ps1`

## Certification Note

This fixes the Level 3 gap identified in
`docs/certification/SOWERBASE_LEVEL3_AIRTABLE_PARITY_PROOF.md`: required
operator fields no longer require Raw Payload parsing for the certified HVAC
intake path. Raw Payload remains preserved as the source truth trail.
