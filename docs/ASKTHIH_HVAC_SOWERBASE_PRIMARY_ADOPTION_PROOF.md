# AskTHIH HVAC SowerBase-Primary Adoption Proof

Status: implementation ready for controlled live HVAC submission
Date: 2026-07-06
Branch: feature/askthih-hvac-sowerbase-primary

## Goal

Route controlled AskTHIH HVAC submissions to SowerBase first, keep Airtable available as fallback or shadow, and make rollback one environment switch.

This is not another certification level. This is the operational adoption step for one vertical.

## What Changed

Receiver: `scripts/askthih-hvac-local-webhook-server.ps1`

The HVAC receiver now supports:

- SowerBase primary write path by default
- Airtable fallback path when SowerBase primary fails
- Airtable shadow mode when dual-write observation is desired
- Airtable-primary rollback path by one env switch
- response metadata showing `routing_mode`, `fallback_status`, and `airtable_status`
- first-class `Follow-up Status` operator field in the SowerBase write payload

## Operational Switches

Default controlled live mode:

```text
ASKTHIH_HVAC_INTAKE_PRIMARY=sowerbase
ASKTHIH_HVAC_AIRTABLE_MODE=fallback
```

Shadow mode, if operators want Airtable to receive a copy while SowerBase remains primary:

```text
ASKTHIH_HVAC_INTAKE_PRIMARY=sowerbase
ASKTHIH_HVAC_AIRTABLE_MODE=shadow
```

One-switch rollback:

```text
ASKTHIH_HVAC_ROLLBACK_PRIMARY=airtable
```

Airtable fallback/shadow requires:

```text
AIRTABLE_BASE_ID=app60wQWdbbgyqTcL
AIRTABLE_HVAC_TABLE_NAME=HVAC Intake
AIRTABLE_API_TOKEN=[REDACTED]
```

## Proof Run

Implementation assertion:

```text
scripts/certification/assert-askthih-hvac-sowerbase-primary-routing.ps1
Result: PASS
```

SowerBase-first receiver proof after the routing patch:

```text
scripts/certification/assert-sowerbase-level5-hvac-primary-pilot.ps1
Run ID: level5-hvac-20260706T143037Z
Result: PASS
```

Observed response metadata from the signed valid HVAC submission included:

```text
routing_mode: sowerbase_primary
fallback_status: not_needed
method: sowerbase-api
record_id: 762
```

The same run verified:

- unsigned request wrote zero rows
- valid signed HVAC submission wrote exactly one SowerBase row
- operator-visible fields remained workable
- backup scope guard passed
- backup ValidateOnly passed
- temporary restore contained the pilot row
- receiver log scan stayed clean

## Live Success Criteria Remaining

The next action is one controlled real AskTHIH HVAC form/chat submission through the live route, not more local ladder work.

That live submission must show:

- the HVAC record lands in SowerBase first
- operator can see the record in SowerBase
- `Follow-up Status` is available for operator workflow
- Airtable fallback or shadow is not broken
- failure behavior is clear from response metadata and logs
- rollback works by setting `ASKTHIH_HVAC_ROLLBACK_PRIMARY=airtable`

## Failure Behavior

SowerBase primary success:

```text
HTTP 201
routing_mode=sowerbase_primary
fallback_status=not_needed
```

SowerBase primary failure with Airtable fallback enabled:

```text
HTTP 202 if Airtable accepts fallback
routing_mode=sowerbase_primary
fallback_status=fallback_created
```

SowerBase primary failure with fallback unavailable or disabled:

```text
HTTP 500
routing_mode=sowerbase_primary
fallback_status=fallback_failed, unconfigured, or disabled
```

Rollback mode:

```text
ASKTHIH_HVAC_ROLLBACK_PRIMARY=airtable
routing_mode=airtable_primary
```

## Non-Goals

This branch does not add:

- Cloudflare tunnel changes
- CRM connection
- Canon connection
- multi-vertical expansion
- Airtable decommissioning
- new certification ladder levels

## Verdict

The HVAC receiver is now wired for operational adoption: SowerBase primary by default, Airtable fallback/shadow available, and rollback controlled by one env switch.

The next proof is one controlled real AskTHIH HVAC submission through the live path.