# SowerBase Level 4 Public Receiver Readiness Proof

Status: pass
Date: 2026-07-06
Scope: Local loopback proof of the API-safe AskTHIH HVAC receiver as the public-facing intake boundary. No production route, DNS, Cloudflare tunnel, Airtable write, CRM connection, or Canon connection was changed.

## Plain Question

Can SowerBase safely receive intake records from a public endpoint without exposing secrets, accepting bad requests, or breaking Airtable-primary production?

## Short Answer

Yes, for local public receiver readiness.

SowerBase can safely receive intake records through the narrow AskTHIH webhook receiver when the receiver is run under `pwsh`. The proof did not connect production. Airtable remains production primary.

## Evidence Sources

- Receiver script: `scripts/askthih-hvac-local-webhook-server.ps1`
- Level 4 assertion script: `scripts/certification/assert-sowerbase-level4-public-receiver.ps1`
- Passing run artifact: `outputs/certification/SOWERBASE_LEVEL4_PUBLIC_RECEIVER_level4-20260706T090348Z.md`
- Passing run JSON: `outputs/certification/SOWERBASE_LEVEL4_PUBLIC_RECEIVER_level4-20260706T090348Z.json`
- Passing run log: `outputs/certification/SOWERBASE_LEVEL4_PUBLIC_RECEIVER_level4-20260706T090348Z.log`

## Runtime Boundary

The receiver was started locally on loopback only:

```text
http://localhost:18787/askthih/hvac
http://127.0.0.1:18787/askthih/hvac
```

The proof did not start Cloudflare, expose a tunnel, touch DNS, modify Vercel routing, or change `askthih.com/hvac` production behavior.

The Level 4 harness now starts the receiver with `pwsh.exe` when available. This matters because two earlier harness runs under Windows PowerShell wrote the valid synthetic row but did not return `201` to the caller within the readiness timeout. Those failed runs were treated as failed evidence and not certified.

## Probe Results

Passing run: `level4-20260706T090348Z`

| Probe | Expected | Actual | Result |
| --- | ---: | ---: | --- |
| HEAD blocked | 405 | 405 | PASS |
| GET blocked | 405 | 405 | PASS |
| Unknown path blocked before write | 404 | 404 | PASS |
| Wrong content type blocked | 415 | 415 | PASS |
| Missing auth blocked | 401 | 401 | PASS |
| Wrong auth blocked | 401 | 401 | PASS |
| Invalid JSON blocked | 400 | 400 | PASS |
| Missing required fields blocked | 400 | 400 | PASS |
| Valid synthetic intake accepted | 201 | 201 | PASS |

## Write Safety

The proof used a unique synthetic channel:

```text
cert_level4_public_receiver_level4-20260706T090348Z
```

Write counts:

```text
Before: 0
After bad requests: 0
After valid request: 1
Accepted row verified with promoted metadata: True
```

Result: PASS. Bad requests did not create SowerBase rows. The valid synthetic request created exactly one row and returned a `201` response.

## Secret Hygiene

The receiver log was scanned for secret and token exposure.

```text
Secret value leaked to log: False
Token value leaked to log: False
Bearer header leaked to log: False
```

Result: PASS. The receiver logs redacted the SowerBase API endpoint and did not print the webhook secret, API token, or bearer header.

A `.gitignore` hardening patch was also added so local `.env` files remain untracked:

```text
.env
.env.*
!.env.example
!.env.*.example
```

## Airtable-Primary Safety

Result: PASS.

- Airtable records were not read or modified.
- No Airtable connector write was performed.
- No production route was changed.
- Cloudflare was not started.
- Public DNS was not touched.
- SowerBase received only synthetic local test data.

## Accepted Limitations

Level 4 certifies local public receiver readiness only. It does not certify:

- public tunnel readiness
- public webhook HMAC/timestamp signing
- production SowerBase routing
- SowerBase-primary pilot operation
- CRM connection
- Canon connection
- multi-vertical production cutover
- Airtable decommissioning

The current receiver uses the `X-AskTHIH-Webhook-Secret` shared-secret header for local readiness proof. A stronger HMAC/timestamp signature layer should be proven before any persistent public tunnel or production receiver approval.

## Verdict

PASS.

SowerBase passes Level 4 local public receiver readiness proof for the inspected HVAC intake receiver. This confirms the narrow receiver can reject bad requests, avoid secret exposure in logs, accept one valid synthetic request, write exactly one SowerBase record, preserve promoted metadata, and avoid breaking Airtable-primary production.

Airtable remains production primary until SowerBase-primary pilot proof is completed and explicitly approved.