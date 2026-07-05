# HVAC Local Webhook Auth and Response Proof

## Status

- Status: local_proven
- Public tunnel/deployment: unverified
- Schema change: none
- Docker compose change: none
- CRM: not connected
- Canon: not connected

## Branch And Commits

Branch:

- feature/askthih-cloudflare-tunnel-webhook-result

Relevant commits:

- a8c5f0d4f2 fix: return response for recovered HVAC webhook writes
- 0908889ecb fix: require auth for HVAC local webhook

Earlier supporting branch commits present:

- bd261cebcb fix: support local loopback webhook prefixes
- f84d4c52cd fix: port parameter defaults to ASKTHIH_WEBHOOK_PORT env var
- f09c176636 fix: repair tunnel verification script encoding issues
- a0352a9860 feat: add comprehensive local webhook preflight validation script
- ce557216b0 fix: improve webhook robustness for safe request handling

## Local Webhook Proof

- Correct auth creates one row
- Missing/wrong auth creates zero rows
- Response returns cleanly instead of hanging after write
- Recovery read-back behavior exists
- GET 405
- wrong content type 415
- invalid JSON 400

## Runtime Proof Records

- Direct auth-success SowerBase record: 19
- AskTHIH runtime mirror SowerBase record: 20
- Runtime trace: operational-mirror-v0-1783146002870-774502cb-c3d6-4b5c-afb2-4fc88b0f4b8d

## Env Names Required

Names only; no values are included here.

- SOWERBASE_BASE_URL
- SOWERBASE_API_TOKEN
- SOWERBASE_INTAKE_TABLE_ID
- ASKTHIH_WEBHOOK_PORT
- ASKTHIH_WEBHOOK_SECRET

## Non-Claims

- Do not claim public tunnel is proven
- Do not claim public migration is complete
- Do not claim Airtable has been replaced
- Do not claim CRM or Canon is connected
- Do not claim production readiness without deployment/source verification
