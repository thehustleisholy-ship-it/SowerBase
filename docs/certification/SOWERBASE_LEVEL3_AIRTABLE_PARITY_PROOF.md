# SowerBase Level 3 Airtable Parity Proof

Status: pass
Date: 2026-07-06
Scope: AskTHIH intake path parity, focused on Airtable `PlumberIntake` and `HVAC Intake` versus local SowerBase/NocoDB `HVAC Intake` operator storage after Gate 3-Fix field promotion.

## Plain Question

Does SowerBase pass Airtable parity after first-class field promotion and backfill?

## Short Answer

Yes, for Level 3 operational-truth parity.

After Gate 3-Fix, SowerBase preserves the operational truth Airtable currently preserves for the intake path: required intake fields are first-class operator fields, vertical-specific HVAC and plumber parity fields exist, HVAC certification rows were backfilled from Raw Payload, trace IDs survive where source payloads contained them, source timestamps are first-class, Raw Payload remains preserved, records are filterable/searchable, and rows are exportable.

Airtable remains production primary. This proof certifies local SowerBase parity readiness for the inspected intake path; it does not switch production ownership.

## Evidence Sources

- Airtable schema, read-only via Airtable connector:
  - base: `app60wQWdbbgyqTcL`
  - table: `tblGWD4CNzRKtYHPf` / `PlumberIntake`
  - table: `tblumYhjvYRztRZ4q` / `HVAC Intake`
- SowerBase local PostgreSQL:
  - container: `sowerbase-local-db-1`
  - database: `nocodb`
  - table: `peoc8ioej5ejtj7."HVAC Intake"`
  - NocoDB model: `ml69vs2tgn6ng1p`
  - operator grid: `vw2o6k70z2ztux46` / `Table-1`
- Gate 3-Fix evidence:
  - `docs/certification/SOWERBASE_LEVEL3_GATE3_FIX_OPERATOR_FIELDS_RESULT.md`
  - `scripts/certification/assert-sowerbase-level3-fields.ps1`
  - `scripts/certification/sowerbase-gate3-promote-intake-fields.ps1`

No Airtable records were read or modified for this proof. Only Airtable schema metadata was inspected.

## Airtable Source Schema

### PlumberIntake

| Field | Airtable type | Required parity status |
| --- | --- | --- |
| Name | singleLineText | mapped to SowerBase `Contact Name` |
| Phone | phoneNumber | first-class |
| Service Address | singleLineText | first-class |
| Problem Description | multilineText | first-class text |
| Urgency | singleSelect | value-preserving text |
| Preferred Callback Time | singleLineText | first-class after Gate 3-Fix |
| Status | singleSelect | value-preserving text |
| Channel | singleLineText | first-class |
| Submitted At | date | first-class after Gate 3-Fix |
| Transcript | multilineText | first-class after Gate 3-Fix |

Plumber select choices inspected:

- Urgency: `Emergency`, `High`, `Normal`, `Low`, `Urgent`
- Status: `New`, `Contacted`, `Booked`, `Closed`

### HVAC Intake

| Field | Airtable type | Required parity status |
| --- | --- | --- |
| Name | singleLineText | mapped to SowerBase `Contact Name` |
| Phone | phoneNumber | first-class |
| Service Address | singleLineText | first-class |
| System Type | singleLineText | first-class after Gate 3-Fix |
| System Age | singleLineText | first-class after Gate 3-Fix |
| Problem Description | multilineText | first-class text |
| Urgency | singleSelect | value-preserving text |
| Preferred Service Window | singleLineText | first-class after Gate 3-Fix |
| Status | singleSelect | value-preserving text |
| Channel | singleLineText | first-class |
| Submitted At | dateTime | first-class after Gate 3-Fix |
| Transcript | multilineText | first-class after Gate 3-Fix |

HVAC select choices inspected:

- Urgency: `Emergency`, `High`, `Normal`, `Low`
- Status: `New`, `Contacted`, `Scheduled`, `Closed`

## SowerBase Post-Fix Operator Schema

The following SowerBase fields are physical PostgreSQL columns, NocoDB metadata fields, and visible operator-grid columns:

| Operator field | PostgreSQL column | NocoDB type | PostgreSQL type | Grid visible |
| --- | --- | --- | --- | --- |
| Submission Title | `Submission_Title` | SingleLineText | text | yes |
| Vertical | `Vertical` | SingleLineText | text | yes |
| Contact Name | `Contact_Name` | SingleLineText | text | yes |
| Phone | `Phone` | SingleLineText | text | yes |
| Email | `Email` | SingleLineText | text | yes |
| Service Address | `Service_Address` | SingleLineText | text | yes |
| Problem Description | `Problem_Description` | SingleLineText | text | yes |
| Urgency | `Urgency` | SingleLineText | text | yes |
| Channel | `Channel` | SingleLineText | text | yes |
| Status | `Status` | SingleLineText | text | yes |
| Trace ID | `Trace_ID` | SingleLineText | text | yes |
| Submitted At | `Submitted_At` | DateTime | timestamp without time zone | yes |
| Transcript | `Transcript` | LongText | text | yes |
| System Type | `System_Type` | SingleLineText | text | yes |
| System Age | `System_Age` | SingleLineText | text | yes |
| Preferred Service Window | `Preferred_Service_Window` | SingleLineText | text | yes |
| Preferred Callback Time | `Preferred_Callback_Time` | SingleLineText | text | yes |
| Raw Payload | `Raw_Payload` | SingleLineText | text | yes |
| Source System | `Source_System` | SingleLineText | text | yes |
| Source Base ID | `Source_Base_ID` | SingleLineText | text | yes |
| Source Table Name | `Source_Table_Name` | SingleLineText | text | yes |
| Migration Status | `Migration_Status` | SingleLineText | text | yes |

## Vertical Scope

### Shared/Common Intake Fields

PASS.

- `Trace ID`
- `Submitted At`
- `Transcript`
- `Contact Name`
- `Phone`
- `Service Address`
- `Problem Description`
- `Urgency`
- `Status`
- `Channel`
- `Raw Payload`

### HVAC Parity Fields

PASS.

- `System Type`
- `System Age`
- `Preferred Service Window`

Backfill evidence for Level 1 HVAC certification rows:

```text
rows, trace_ids, submitted_at, system_type, system_age, preferred_window
730, 730, 730, 730, 730, 730
```

### Plumber Parity Fields

PASS for first-class schema parity.

- `Preferred Callback Time`

The current local certification dataset contains HVAC rows only, so no plumber callback values were available to backfill. The field is present as a physical column, NocoDB field, and visible operator-grid column for plumber-route intake records.

## Status, Channel, Source, And Routing Values

Observed local SowerBase data:

```text
vertical: HVAC = 750
status: New = 749; new = 1
source_system: sowerbase_certification_harness = 730; askthih.com = 7; askthih_webhook_api = 2; other local proof sources = 11
channels: certification, webhook, direct API, local bridge, and operational mirror proof channels preserved
```

Result: PASS. SowerBase preserves the current values and exposes them as first-class filterable operator fields. Select-choice enforcement is not identical to Airtable; for Level 3 this is accepted as a non-blocking implementation difference because the operational truth values are preserved, searchable, and exportable.

## Raw Payload, Trace IDs, And Timestamps

Whole-table survival sample:

```text
rows, raw_payload_rows, trace_id_rows, distinct_trace_ids, submitted_at_rows, transcript_rows, system_type_rows, system_age_rows, preferred_service_window_rows, preferred_callback_time_rows
750, 750, 732, 732, 750, 0, 730, 730, 730, 0
```

Interpretation:

- Raw Payload survives for every local SowerBase intake row.
- Submitted At is first-class for every local SowerBase intake row.
- Trace IDs survive for all rows whose source payload contained trace IDs, including all Level 1 certification rows.
- Transcript and Preferred Callback Time are first-class but blank in the existing local HVAC-only dataset because no source values were present to backfill.

## Search, Filter, And Export Usability

Search/filter proof:

```text
filter_system_type,730
filter_status_new,750
search_trace_id,500
search_raw_payload_marker,501
```

Export proof using `COPY ... TO STDOUT WITH CSV HEADER` returned promoted operator fields and Raw Payload together, including:

```text
Trace_ID,Submitted_At,Vertical,Status,Channel,System_Type,System_Age,Preferred_Service_Window,Preferred_Callback_Time,Raw_Payload
single-cert-20260705T135200Z-1-b118a4b0-fab9-4d53-8636-d4afdc4ff79a,2026-07-05 13:52:01,HVAC,New,cert_level1_hvac-cert-20260705T135200Z-single,Central AC,7,Certification window only,,{...}
```

Result: PASS.

## Operator Review Workflow

PASS. Operators can review the intake truth in the NocoDB grid without parsing Raw Payload for the required Gate 3 fields:

- common intake fields are visible in `Table-1`
- HVAC parity fields are visible in `Table-1`
- plumber callback field is visible in `Table-1`
- status/channel/source fields remain visible
- Raw Payload remains visible for audit/debug context

## Accepted Differences

These differences do not block Level 3 operational-truth parity:

- SowerBase uses a unified intake table with `Vertical` routing rather than separate Airtable tables per vertical.
- Airtable `Name` maps to SowerBase `Contact Name`.
- Airtable `phoneNumber`, `email`, `singleSelect`, and `multilineText` controls are currently represented mostly as text fields in SowerBase/NocoDB, except promoted `Transcript` as `LongText` and `Submitted At` as `DateTime`.
- SowerBase preserves select values as text but does not yet enforce Airtable choice lists in the UI.

## Verdict

PASS.

SowerBase passes Level 3 Airtable parity after first-class field promotion and backfill for the inspected AskTHIH intake path. Airtable remains production primary until a separate cutover decision is made.