# SowerBase Level 1 Local Stress Certification Review

## Purpose

This review consolidates the SowerBase Level 1 local stress evidence for the HVAC synthetic intake path.

Level 1 evaluates local stress behavior only. It does not certify public receiver readiness, Airtable parity, backup/restore, CRM connection, Canon connection, or Airtable replacement.

## Current Status

- Level 0 local mirror proof: passed
- Smallest Level 1 preflight: passed
- Level 1 ladder candidate runs: passed
- Production primary: Airtable
- Public SowerBase receiver: missing
- Public receiver involved in these tests: no
- Test data class: synthetic HVAC certification data only
- Real customer records used: no

## Evidence Sources

| Run | Report |
| --- | --- |
| Smallest preflight | `outputs/certification/SOWERBASE_LEVEL1_LOCAL_STRESS_REPORT_cert-20260705T135200Z.md` |
| 25 records, concurrency 1 | `outputs/certification/SOWERBASE_LEVEL1_LOCAL_STRESS_REPORT_cert-20260705T135556Z.md` |
| 100 records, concurrency 1 | `outputs/certification/SOWERBASE_LEVEL1_LOCAL_STRESS_REPORT_cert-20260705T140747Z.md` |
| 100 records, concurrency 5 | `outputs/certification/SOWERBASE_LEVEL1_LOCAL_STRESS_REPORT_cert-20260705T141644Z.md` |
| 500 records, concurrency 10 | `outputs/certification/SOWERBASE_LEVEL1_LOCAL_STRESS_REPORT_cert-20260705T142036Z.md` |

An earlier report, `outputs/certification/SOWERBASE_LEVEL1_LOCAL_STRESS_REPORT_cert-20260705T133754Z.md`, recorded a failed precondition state before the local webhook and process environment were ready. It is not treated as a SowerBase write-path failure.

## Run Summary

| Run | Candidate ruling | Requested | Sent | Successes | Failures | Matching rows | Duplicate trace IDs | Avg ms | Max ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Preflight auth and single write | `PARTIAL_PASS_CANDIDATE` | 0 | 0 | 0 | 0 | 0 | 0 | 537.52 | 1382.71 |
| 25 records, concurrency 1 | `PASS_CANDIDATE` | 25 | 25 | 25 | 0 | 25 | 0 | 196.77 | 334.86 |
| 100 records, concurrency 1 | `PASS_CANDIDATE` | 100 | 100 | 100 | 0 | 100 | 0 | 188.48 | 680.58 |
| 100 records, concurrency 5 | `PASS_CANDIDATE` | 100 | 100 | 100 | 0 | 100 | 0 | 252.48 | 412.96 |
| 500 records, concurrency 10 | `PASS_CANDIDATE` | 500 | 500 | 500 | 0 | 500 | 0 | 749.14 | 1023.92 |

## Auth Rejection Review

| Run | Missing-secret status | Missing-secret rows | Wrong-secret status | Wrong-secret rows | Single valid status | Single valid rows |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Preflight auth and single write | 401 | 0 | 401 | 0 | 201 | 1 |
| 25 records, concurrency 1 | 401 | 0 | 401 | 0 | 201 | 1 |
| 100 records, concurrency 1 | 401 | 0 | 401 | 0 | 201 | 1 |
| 100 records, concurrency 5 | 401 | 0 | 401 | 0 | 201 | 1 |
| 500 records, concurrency 10 | 401 | 0 | 401 | 0 | 201 | 1 |

Auth rejection consistently protected the write path. Missing and wrong secrets returned `401` and created zero rows in every reviewed run. Valid synthetic single-write probes returned `201` and created exactly one row in every reviewed run.

## Review Questions

| Question | Answer | Evidence |
| --- | --- | --- |
| Did every candidate run pass? | Yes | All ladder runs returned `PASS_CANDIDATE`; preflight returned `PARTIAL_PASS_CANDIDATE` with volume intentionally skipped. |
| Were all records synthetic? | Yes | Harness payloads used synthetic HVAC certification markers, synthetic contact values, and `test_only` metadata. |
| Were all failures zero or understood? | Yes | Reviewed candidate runs recorded zero harness failures. The earlier failed report was a local precondition failure, not a write-path failure. |
| Did auth rejection consistently protect the write path? | Yes | Missing and wrong secret probes returned `401` with zero rows in every reviewed run. |
| Did duplicate trace IDs remain zero? | Yes | Duplicate trace ID count was zero in every reviewed run. |
| Did response times stay within the acceptable local threshold? | Yes | The largest reviewed average response time was 749.14 ms on the 500-record concurrency-10 run. |
| Were public, production, DNS, Vercel, Cloudflare, and customer records avoided? | Yes | All reviewed runs targeted `localhost:8787`, used local SowerBase, and used synthetic data only. |

## Non-Claims

- This does not certify public receiver readiness.
- This does not certify Airtable parity.
- This does not certify backup or restore behavior.
- This does not certify CRM connection.
- This does not certify Canon connection.
- This does not certify SowerBase as the Airtable replacement.
- This does not prove production behavior.
- This does not prove Vercel mirror readiness.
- This does not adopt Cloudflare.
- This does not involve public DNS or public webhook exposure.

## Certification Scope

SowerBase has passed Level 1 local stress certification for the HVAC synthetic intake path. This certifies local stress behavior only.

Level 1 approved
