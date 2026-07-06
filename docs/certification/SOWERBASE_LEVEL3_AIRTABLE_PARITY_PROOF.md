# SowerBase Level 3 Airtable Parity Proof

Status: failed_certification_candidate
Date: 2026-07-06
Scope: AskTHIH intake path parity, focused on Airtable `PlumberIntake` and `HVAC Intake` versus local SowerBase HVAC intake storage

## Plain Question

Can SowerBase preserve the same operational truth Airtable currently preserves
for the intake path?

## Short Answer

Partially.

SowerBase currently preserves the HVAC intake truth needed for local mirror and
backup/restore proof: common intake fields, source metadata, raw payload,
trace IDs, timestamps, channel/source values, and exportable rows.

SowerBase does not yet pass Airtable replacement parity because several
required Airtable fields are not first-class SowerBase fields. They survive in
`Raw_Payload`, but operators cannot reliably filter, search, review, or export
them as first-class operational fields without parsing raw JSON/text.

## Evidence Sources

- Airtable schema, read-only via Airtable connector:
  - base: `app60wQWdbbgyqTcL`
  - table: `PlumberIntake`
  - table: `HVAC Intake`
- SowerBase local PostgreSQL:
  - container: `sowerbase-local-db-1`
  - database: `nocodb`
  - restored/proven user-data table: `peoc8ioej5ejtj7."HVAC Intake"`
- SowerBase Level 1/2 evidence:
  - `docs/certification/SOWERBASE_LEVEL1_LOCAL_STRESS_CERTIFICATION_REVIEW.md`
  - `docs/certification/SOWERBASE_LEVEL2B_BACKUP_RESTORE_RESULT.md`
  - `docs/certification/SOWERBASE_AIRTABLE_PARITY_MAP.md`

No Airtable records were read or modified for this proof. Only Airtable schema
metadata was inspected.

## Airtable Source Schema

### PlumberIntake

| Field | Airtable type | Notes |
| --- | --- | --- |
| `Name` | `singleLineText` | customer name |
| `Phone` | `phoneNumber` | customer phone |
| `Service Address` | `singleLineText` | service location |
| `Problem Description` | `multilineText` | intake details |
| `Urgency` | `singleSelect` | `Emergency`, `High`, `Normal`, `Low`, `Urgent` |
| `Preferred Callback Time` | `singleLineText` | required in parity map |
| `Status` | `singleSelect` | `New`, `Contacted`, `Booked`, `Closed` |
| `Channel` | `singleLineText` | described as web/sms/voice |
| `Submitted At` | `date` | source timestamp |
| `Transcript` | `multilineText` | conversation history |

### HVAC Intake

| Field | Airtable type | Notes |
| --- | --- | --- |
| `Name` | `singleLineText` | customer name |
| `Phone` | `phoneNumber` | customer phone |
| `Service Address` | `singleLineText` | service location |
| `System Type` | `singleLineText` | required HVAC field |
| `System Age` | `singleLineText` | required HVAC field |
| `Problem Description` | `multilineText` | intake details |
| `Urgency` | `singleSelect` | `Emergency`, `High`, `Normal`, `Low` |
| `Preferred Service Window` | `singleLineText` | required HVAC field |
| `Status` | `singleSelect` | `New`, `Contacted`, `Scheduled`, `Closed` |
| `Channel` | `singleLineText` | source channel |
| `Submitted At` | `dateTime` | source timestamp |
| `Transcript` | `multilineText` | conversation history |

## SowerBase Current HVAC Schema

Physical table:

```text
peoc8ioej5ejtj7."HVAC Intake"
```

First-class SowerBase columns:

| Column | PostgreSQL type | NocoDB type |
| --- | --- | --- |
| `id` | `integer` | `ID` |
| `created_at` | `timestamp without time zone` | `CreatedTime` |
| `updated_at` | `timestamp without time zone` | `LastModifiedTime` |
| `Submission_Title` | `text` | `SingleLineText` |
| `Vertical` | `text` | `SingleLineText` |
| `Contact_Name` | `text` | `SingleLineText` |
| `Phone` | `text` | `SingleLineText` |
| `Email` | `text` | `SingleLineText` |
| `Service_Address` | `text` | `SingleLineText` |
| `Problem_Description` | `text` | `SingleLineText` |
| `Urgency` | `text` | `SingleLineText` |
| `Channel` | `text` | `SingleLineText` |
| `Status` | `text` | `SingleLineText` |
| `Source_System` | `text` | `SingleLineText` |
| `Source_Base_ID` | `text` | `SingleLineText` |
| `Source_Table_Name` | `text` | `SingleLineText` |
| `Migration_Status` | `text` | `SingleLineText` |
| `Raw_Payload` | `text` | `SingleLineText` |

Not present as first-class columns:

- `Submitted At`
- `Transcript`
- `trace_id`
- `certification_run_id`
- `marker_prefix`
- `test_only`
- `System Type`
- `System Age`
- `Preferred Service Window`
- plumber `Preferred Callback Time`

## Required Field Parity

### HVAC

| Airtable field | SowerBase destination | Result | Notes |
| --- | --- | --- | --- |
| `Name` | `Contact_Name` | PASS | first-class |
| `Phone` | `Phone` | PASS | first-class text; Airtable type is `phoneNumber` |
| `Service Address` | `Service_Address` | PASS | first-class |
| `System Type` | `Raw_Payload.system_type` | PARTIAL | preserved but not first-class |
| `System Age` | `Raw_Payload.system_age_years` | PARTIAL | preserved but not first-class |
| `Problem Description` | `Problem_Description` | PASS | first-class |
| `Urgency` | `Urgency` | PARTIAL | first-class text, not constrained select |
| `Preferred Service Window` | `Raw_Payload.preferred_service_window` | PARTIAL | preserved but not first-class |
| `Status` | `Status` | PARTIAL | first-class text, not constrained select |
| `Channel` | `Channel` | PASS | first-class |
| `Submitted At` | `created_at` | PARTIAL | SowerBase creation time exists, but source submitted-at is not first-class |
| `Transcript` | none observed | FAIL | no first-class transcript column in current HVAC table |

### Plumber

| Airtable field | SowerBase destination | Result | Notes |
| --- | --- | --- | --- |
| `Name` | `Contact_Name` | PASS | target exists |
| `Phone` | `Phone` | PASS | target exists as text |
| `Service Address` | `Service_Address` | PASS | target exists |
| `Problem Description` | `Problem_Description` | PASS | target exists |
| `Urgency` | `Urgency` | PARTIAL | target exists as text, not constrained select |
| `Preferred Callback Time` | `Raw_Payload` only per parity map | FAIL | no first-class target in current SowerBase table |
| `Status` | `Status` | PARTIAL | target exists as text; plumber `Booked` differs from HVAC `Scheduled` |
| `Channel` | `Channel` | PASS | target exists |
| `Submitted At` | `created_at` or raw payload | PARTIAL | source submitted-at not first-class |
| `Transcript` | none observed | FAIL | no first-class transcript column in current HVAC table |

## Field Names

Result: PARTIAL.

SowerBase uses NocoDB/PostgreSQL-safe field names such as `Contact_Name` and
`Service_Address`, while NocoDB displays human labels such as `Contact Name`
and `Service Address`.

This is acceptable for internal storage if the mapping is documented, but
replacement certification needs the mapping enforced in a script or schema
contract so future fields do not drift.

## Field Types

Result: PARTIAL.

SowerBase stores most operator-visible fields as text:

- `Phone` is text, while Airtable uses `phoneNumber`.
- `Urgency` is text, while Airtable uses `singleSelect`.
- `Status` is text, while Airtable uses `singleSelect`.
- `Raw_Payload` is text, while the operational content inside it is structured JSON.

The text approach preserves values, but it does not preserve Airtable's select
constraints or phone semantics.

## Vertical Routing

Result: PASS for HVAC local proof.

Observed local SowerBase rows:

| Vertical | Rows |
| --- | ---: |
| `HVAC` | 750 |

SowerBase can route and preserve HVAC vertical identity for the current proof
scope. Plumber vertical routing is mapped in documentation but was not proven
with live SowerBase plumber rows in this Level 3 run.

## Status Values

Result: PARTIAL.

Airtable source values:

- plumber: `New`, `Contacted`, `Booked`, `Closed`
- HVAC: `New`, `Contacted`, `Scheduled`, `Closed`

Observed SowerBase values:

| Status | Rows |
| --- | ---: |
| `New` | 749 |
| `new` | 1 |

SowerBase preserves status text, but it does not currently enforce canonical
case or the per-vertical lifecycle vocabulary.

## Channel And Source Values

Result: PASS for preservation, PARTIAL for governance.

Observed SowerBase source values include:

| Source system | Source base | Source table | Migration status | Rows |
| --- | --- | --- | --- | ---: |
| `sowerbase_certification_harness` | `app60wQWdbbgyqTcL` | `HVAC Intake` | `test_only` | 730 |
| `askthih.com` | `app60wQWdbbgyqTcL` | `HVAC Intake` | `forwarded_from_askthih` | 6 |
| `askthih_operational_mirror_v0` | `app60wQWdbbgyqTcL` | `Operational Mirror v0` | `mirror` | 2 |
| `askthih_webhook_api` | `app60wQWdbbgyqTcL` | `HVAC Intake` | `webhook` | 2 |

SowerBase preserves channel/source/migration metadata, but channel values are
not yet governed by a documented controlled vocabulary.

## Raw Payload

Result: PASS for preservation.

For Level 1 certification rows:

| Check | Rows |
| --- | ---: |
| Level 1 rows | 730 |
| rows with `Raw_Payload` | 730 |
| rows with `system_type` in `Raw_Payload` | 730 |
| rows with `system_age_years` in `Raw_Payload` | 730 |
| rows with `preferred_service_window` in `Raw_Payload` | 730 |
| rows with `test_only` in `Raw_Payload` | 730 |

Raw Payload is sufficient to preserve truth, but not sufficient by itself for
operator-grade parity where filtering/reporting on those fields is required.

## Trace IDs

Result: PASS for preservation, FAIL for first-class operator workflow.

For Level 1 certification rows:

| Check | Rows |
| --- | ---: |
| rows with `trace_id` in `Raw_Payload` | 730 |
| rows with `certification_run_id` in `Raw_Payload` | 730 |
| rows with `marker_prefix` in `Raw_Payload` | 730 |

Trace IDs survive, but they are not first-class columns. Operators cannot use a
plain field filter for `trace_id` without searching/parsing `Raw_Payload`.

## Created Timestamps

Result: PARTIAL.

SowerBase has `created_at` and `updated_at` NocoDB system timestamps, and all
750 local HVAC rows have `created_at`.

This proves SowerBase creation-time tracking. It does not prove preservation of
Airtable's original `Submitted At` value as a first-class migrated field.

## Search And Filter Usability

Result: PARTIAL.

Operator-style filters that work directly:

| Filter | Observed rows |
| --- | ---: |
| `Vertical = HVAC AND Status = New` | 749 |
| `Channel LIKE cert_level1_hvac%` | 730 |
| `Raw_Payload contains trace_id` | 732 |
| `created_at IS NOT NULL` | 750 |

PostgreSQL full-text search across title, problem description, and raw payload
found all 730 Level 1 certification rows for `certification trace_id`.

Direct filters work for first-class fields. Filters for `trace_id`, system
type, system age, preferred service window, test-only marker, and
certification run require Raw Payload search/parsing rather than ordinary
field filtering.

## Exportability

Result: PASS for current proof data.

CSV export was proven from SowerBase PostgreSQL over synthetic-only HVAC rows
with these fields:

- `id`
- `created_at`
- `Submission_Title`
- `Vertical`
- `Contact_Name`
- `Phone`
- `Email`
- `Service_Address`
- `Problem_Description`
- `Urgency`
- `Channel`
- `Status`
- `Source_System`
- `Source_Base_ID`
- `Source_Table_Name`
- `Migration_Status`
- `Raw_Payload` preview

The export is usable for operational review. It still inherits the first-class
field gaps noted above.

## Operator Review Workflow

Result: PARTIAL.

NocoDB metadata shows one current grid view for the HVAC table:

| Model | View | Type |
| --- | --- | --- |
| `HVAC Intake` | `Table-1` | grid |

Operators can review rows in a basic table/grid and can use first-class fields
such as vertical, status, channel, migration status, source system, and created
timestamp.

Operator review is not yet Airtable-equivalent because important review fields
remain Raw Payload-only:

- `trace_id`
- `test_only`
- `certification_run_id`
- `System Type`
- `System Age`
- `Preferred Service Window`
- plumber `Preferred Callback Time`
- source `Submitted At`
- `Transcript`

## Pass/Fail Matrix

| Requirement | Result |
| --- | --- |
| required fields | PARTIAL |
| field names | PARTIAL |
| field types | PARTIAL |
| vertical routing | PASS for HVAC; NOT PROVEN for plumber |
| status values | PARTIAL |
| channel/source values | PASS preservation; PARTIAL governance |
| raw payload | PASS |
| trace IDs | PASS preservation; FAIL first-class workflow |
| created timestamps | PARTIAL |
| search/filter usability | PARTIAL |
| exportability | PASS |
| operator review workflow | PARTIAL |

## Ruling

Level 3 is a failed certification candidate.

SowerBase can preserve the operational truth of the HVAC intake path in the
sense that the data survives in first-class common fields plus `Raw_Payload`.
It cannot yet replace Airtable as an operator-equivalent system of record for
the intake path because required fields and traceability fields are not fully
first-class, typed, filterable, and governed.

## Required Fixes Before Level 3 Can Pass

1. Add first-class SowerBase fields for:
   - `trace_id`
   - `test_only`
   - `certification_run_id`
   - `marker_prefix`
   - `System Type`
   - `System Age`
   - `Preferred Service Window`
   - plumber `Preferred Callback Time`
   - source `Submitted At`
   - `Transcript`
2. Normalize and document status vocabularies:
   - shared statuses
   - HVAC-specific `Scheduled`
   - plumber-specific `Booked`
3. Normalize and document urgency vocabularies:
   - HVAC: `Emergency`, `High`, `Normal`, `Low`
   - plumber: includes `Urgent`
4. Promote operator-critical Raw Payload keys to first-class fields or create
   generated/extracted columns.
5. Add saved NocoDB views for operator review:
   - new HVAC intakes
   - certification/test-only records
   - source/migration review
   - trace lookup
6. Prove plumber parity with live SowerBase plumber rows or a plumber-specific
   synthetic certification dataset.
7. Add an automated parity check script that compares Airtable schema metadata
   to SowerBase schema targets and emits machine-readable pass/fail results.

## Non-Claims

- Airtable has not been replaced.
- SowerBase is not certified as the Airtable replacement.
- Public receiver readiness is not proven by Level 3.
- CRM is not connected.
- Canon is not connected.
- No production/public deployment behavior is proven by this local parity proof.
