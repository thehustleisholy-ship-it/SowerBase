# AskTHIH HVAC Controlled Live Submission Result

Status: blocked before SowerBase write
Date: 2026-07-06
Branch: feature/askthih-hvac-sowerbase-primary

## Goal

Run one controlled AskTHIH HVAC form/chat submission and verify:

- the submission reaches SowerBase
- `routing_mode = sowerbase_primary`
- `fallback_status` is `not_needed` or an expected fallback result
- Airtable fallback/shadow remains intact
- operator can see the record in SowerBase
- `Follow-up Status` is present
- rollback switch is documented and still available

## Attempted Live Routes

### `https://askthih.com/hvac-staging`

Result: failed before write.

Observed response: Next.js `404`.

Meaning: the non-www documented staging path is not the deployed live intake endpoint.

### `https://www.askthih.com/api/hvac-staging`

Result: endpoint exists, but failed before write.

First form-shaped validation response:

```text
Validation failed: name, service, and message are required.
```

Second controlled form/chat-shaped submission included `name`, `service`, `message`, HVAC metadata, channel, trace ID, and follow-up status.

Observed response:

```text
Server configuration error
```

Meaning: the public AskTHIH API route is deployed and validating requests, but the runtime is not configured to complete the SowerBase write.

## SowerBase Verification

Local SowerBase check:

```text
SELECT COUNT(*)
FROM "peoc8ioej5ejtj7"."HVAC Intake"
WHERE "Channel" LIKE 'askthih_hvac_live_controlled_%';

Result: 0
```

No controlled live-test row was created in SowerBase.

## Vercel Runtime Check

Project inspected:

```text
askthih-core
```

Observed deployed route:

```text
https://www.askthih.com/api/hvac-staging
```

Observed environment variable list includes Airtable variables, including:

```text
AIRTABLE_API_KEY
AIRTABLE_BASE_ID
AIRTABLE_HVAC_TABLE_NAME
```

Observed missing SowerBase runtime variables:

```text
SOWERBASE_TUNNEL_URL
SOWERBASE_PRODUCTION_URL
SOWERBASE_BASE_URL
SOWERBASE_API_TOKEN
SOWERBASE_INTAKE_TABLE_ID
ASKTHIH_WEBHOOK_SECRET
ASKTHIH_HVAC_INTAKE_PRIMARY
ASKTHIH_HVAC_AIRTABLE_MODE
```

Local `.env.askthih-hvac-staging` contains SowerBase credentials, but its SowerBase base URL is:

```text
http://localhost:18080
```

That URL is reachable from the local machine only. Vercel cannot use it as a live SowerBase target.

Cloudflare tunnel check:

```text
cloudflared tunnel list
```

Result: failed because no origin certificate is configured in this environment.

## Seven Checks

| Check | Result |
| --- | --- |
| Submission reaches SowerBase | FAIL |
| `routing_mode = sowerbase_primary` | FAIL, route failed before SowerBase response |
| `fallback_status` is expected | FAIL, route failed before routing response |
| Airtable fallback/shadow remains intact | PARTIAL, Airtable env exists in Vercel; SowerBase fallback/shadow mode is not deployed/configured |
| Operator can see the record in SowerBase | FAIL, no row was created |
| `Follow-up Status` is present | PASS in SowerBase schema/operator field from prior implementation; FAIL for live row because no row was created |
| Rollback switch documented and available | PASS in branch/env template; FAIL in live Vercel env because switch is not configured |

## Blocker

The live nerve is blocked at public SowerBase reachability and Vercel runtime configuration.

The next single operational fix is to give `askthih-core` a reachable SowerBase URL and the required SowerBase env vars, then redeploy the route and rerun the same one controlled submission.

## Non-Actions

No CRM connection was added.

No Canon connection was added.

No multi-vertical expansion was attempted.

No controlled live-test row was written to SowerBase.
