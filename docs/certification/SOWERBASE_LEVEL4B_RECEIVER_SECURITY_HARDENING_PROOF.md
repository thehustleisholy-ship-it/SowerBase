# SowerBase Level 4B Receiver Security Hardening Proof

Status: pass
Date: 2026-07-06
Scope: Local loopback proof of HMAC/timestamp/replay hardening for the AskTHIH HVAC receiver. No production route, DNS, Cloudflare tunnel, Airtable write, CRM connection, or Canon connection was changed.

## Plain Question

Can SowerBase receive public-intake-shaped requests through a hardened receiver that requires HMAC/timestamp signing, rejects stale or replayed requests, keeps logs redacted, and still writes exactly one valid synthetic intake row?

## Short Answer

Yes, locally.

Level 4B proves the receiver security hardening required before any public tunnel or production routing step. Airtable remains production primary.

## Implementation

Receiver: `scripts/askthih-hvac-local-webhook-server.ps1`

New hardening behavior:

- default auth mode is `signature`
- signed requests use `Authorization: Signature <unix_timestamp>.<hmac_sha256>`
- HMAC payload is `<unix_timestamp>.<raw_request_body>`
- default timestamp tolerance is 300 seconds
- stale timestamps are rejected with `401`
- missing, malformed, and wrong signatures are rejected with `401`
- accepted signatures are stored in an in-memory replay cache
- replayed signatures are rejected with `409`
- bearer/token/signature values are not written to receiver logs

Compatibility behavior:

- `ASKTHIH_WEBHOOK_AUTH_MODE=shared-secret` keeps the older local Level 4 harness working explicitly
- hardened/default mode remains `signature`

## Evidence Sources

- Level 4B assertion script: `scripts/certification/assert-sowerbase-level4b-receiver-security.ps1`
- Passing run artifact: `outputs/certification/SOWERBASE_LEVEL4B_RECEIVER_SECURITY_level4b-20260706T092935Z.md`
- Passing run JSON: `outputs/certification/SOWERBASE_LEVEL4B_RECEIVER_SECURITY_level4b-20260706T092935Z.json`
- Passing run log: `outputs/certification/SOWERBASE_LEVEL4B_RECEIVER_SECURITY_level4b-20260706T092935Z.log`

A prior red run, `level4b-20260706T092406Z`, failed as expected before implementation because valid HMAC requests still returned `401`. A later intermediate run, `level4b-20260706T092710Z`, proved valid/replay behavior but failed missing-signature handling with `500`; that was fixed before this pass was recorded.

## Probe Results

Passing run: `level4b-20260706T092935Z`

| Probe | Expected | Actual | Result |
| --- | ---: | ---: | --- |
| Missing signature rejected | 401 | 401 | PASS |
| Wrong signature rejected | 401 | 401 | PASS |
| Stale timestamp rejected | 401 | 401 | PASS |
| Valid signed synthetic intake accepted | 201 | 201 | PASS |
| Replay signature rejected | 409 | 409 | PASS |

## Write Safety

Synthetic channel:

```text
cert_level4b_receiver_security_level4b-20260706T092935Z
```

Write counts:

```text
Before: 0
After invalid signed requests: 0
After valid signed request: 1
After replay attempt: 1
Accepted row verified with promoted metadata: True
```

Result: PASS. Invalid signed requests wrote zero rows. The valid signed synthetic request wrote exactly one row. The replay attempt wrote zero additional rows.

## Secret Hygiene

Receiver log scan:

```text
Secret value leaked to log: False
Token value leaked to log: False
Bearer header leaked to log: False
Signature header leaked to log: False
```

Result: PASS.

## Level 4 Compatibility Check

The older Level 4 local readiness harness was rerun after hardening with explicit `ASKTHIH_WEBHOOK_AUTH_MODE=shared-secret` and passed:

```text
Run ID: level4-20260706T092935Z
Status: pass
```

This preserves the Level 4 local readiness proof while making the receiver's default mode hardened for Level 4B and later public-facing work.

## Non-Claims

Level 4B does not certify:

- production SowerBase routing
- public Cloudflare tunnel readiness
- SowerBase-primary pilot operation
- CRM connection
- Canon connection
- multi-vertical production cutover
- Airtable decommissioning

## Verdict

PASS.

SowerBase passes Level 4B receiver security hardening proof locally. The receiver now supports HMAC/timestamp signing, rejects missing/wrong/stale/replayed signatures, keeps bearer/secret/signature logs redacted, writes exactly one valid signed synthetic intake row, and leaves Airtable-primary production untouched.

Airtable remains production primary until SowerBase-primary pilot proof is completed and explicitly approved.