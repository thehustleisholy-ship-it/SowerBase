# AskTHIH HVAC Phase 3 — Protected Staging Deployment Plan

## Executive Summary

**Phase 3 Goal:** Deploy the API-safe HVAC webhook behind a protected staging route using HTTPS.

**Status:** Planning & Preparation  
**Staging Route:** https://askthih.com/hvac-staging (preferred)  
**Protection Method:** Reverse proxy (nginx, AWS ALB, or equivalent) with HTTPS/TLS  
**Webhook Protection:** HMAC-SHA256 signature validation + timestamp validation  
**Public Route:** NOT changed (askthih.com/hvac remains on Airtable until explicit approval)

---

## Prerequisite Verification

### Phase 2B Status
✅ Local credentials provisioned (session-only)  
✅ Preflight validation passed (exit code 0)  
✅ Webhook server script uses API-safe patterns  
✅ No direct PostgreSQL writes for public/staging  
✅ 5 test records intact (IDs 1-5)  
✅ SowerBase operational at http://localhost:18080  

### Webhook Code Path Analysis

**File:** `scripts/askthih-hvac-local-webhook-server.ps1`

**Verification Findings:**
- ✅ Webhook uses SowerBase/NocoDB API payload preparation
- ✅ Environment variables used for authentication (SOWERBASE_API_TOKEN)
- ✅ Direct PostgreSQL writes removed from main API path
- ✅ Local fallback uses backend layer (not exposed publicly)
- ✅ No direct database access for public/staging mode

**Code Path:**
```
Public HTTPS Request → Reverse Proxy (HTTPS) → localhost:8787 (private)
                                           ↓
                          Webhook Server (API-safe)
                                           ↓
                    SowerBase/NocoDB API or Backend Layer
                                           ↓
                              Database (private)
```

---

## Staging Route Definition

### Preferred Staging Route

**URL:** `https://askthih.com/hvac-staging`

**Requirements:**
- ✅ HTTPS/TLS required (min TLS 1.2)
- ✅ Reverse proxy for local webhook
- ✅ Webhook secret validation enabled
- ✅ Request size limits enforced
- ✅ Rate limiting applied
- ✅ CORS origins restricted

### Alternative Routes

If preferred route not available:
1. `https://staging.askthih.com/hvac` (staging subdomain)
2. Temporary HTTPS tunnel (documented with expiration date)
3. Internal staging URL with documented access method

---

## Reverse Proxy Configuration

### HTTPS / TLS Protection

**Requirements:**
- ✅ HTTPS only (no HTTP fallback for staging/public)
- ✅ TLS 1.2 or higher
- ✅ Modern cipher suites (no RC4, DES, MD5)
- ✅ HSTS header: `Strict-Transport-Security: max-age=31536000`
- ✅ Certificate must be valid and not self-signed

### Security Headers

**Recommended:**
```
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
X-XSS-Protection: 1; mode=block
Referrer-Policy: strict-origin-when-cross-origin
Content-Security-Policy: default-src 'none'; form-action 'none'
```

### Proxy Settings

**Routing:**
- Public HTTPS: `https://askthih.com/hvac-staging` → `http://localhost:8787/askthih/hvac`
- Private webhook: Webhook process listens on localhost only (not internet-facing)
- Direct access to localhost:8787: BLOCKED from public internet

**Timeouts:**
- Connection timeout: 10 seconds
- Read timeout: 30 seconds
- Write timeout: 30 seconds

**Request Body Size Limit:**
- Max payload: 10 KB
- Max form submission: 100 KB
- Response: 413 Payload Too Large if exceeded

**Rate Limiting (Reverse Proxy Level):**
- Primary: 10 requests/second per IP
- Fallback: 100 requests/minute per source
- Burst: 20 requests in 5 seconds
- Response: 429 Too Many Requests if exceeded

---

## Webhook Protection

### Signature Validation (HMAC-SHA256)

**Required:**
- ✅ Every request must include signature header
- ✅ Algorithm: HMAC-SHA256
- ✅ Key: ASKTHIH_WEBHOOK_SECRET (32+ bytes)
- ✅ Format: `Authorization: Signature <timestamp>.<signature>`

**Signature Generation:**
```
message = timestamp + "." + request_body
signature = HMAC-SHA256(message, webhook_secret)
header = "Signature " + timestamp + "." + hex(signature)
```

### Timestamp Validation

**Requirements:**
- ✅ Request must include timestamp in header
- ✅ Validate timestamp within ±300 seconds (5 minutes)
- ✅ Reject stale requests (older than window)
- ✅ Prevent replay attacks

### Request Method Validation

**Requirements:**
- ✅ Only POST allowed
- ✅ Reject GET, PUT, DELETE, HEAD, OPTIONS
- ✅ Return 405 Method Not Allowed for non-POST

### Payload Validation

**Requirements:**
- ✅ Content-Type: application/json required
- ✅ Validate JSON structure before processing
- ✅ Required fields:
  - submission_title
  - vertical
  - contact_name
  - phone
  - email
  - service_address
  - problem_description
  - urgency
  - channel
  - status
- ✅ Reject with 400 Bad Request if fields missing

### Error Response Security

**Requirements:**
- ✅ No stack traces in responses
- ✅ No SQL errors in responses
- ✅ No database details in responses
- ✅ No file paths in responses
- ✅ Generic error messages only

**Error Response Example:**
```json
{
  "status": "error",
  "message": "Request validation failed"
}
```

---

## CORS / Origin Controls

### Allowed Origins

**Staging:**
- `https://askthih.com`
- `https://www.askthih.com`
- Staging origin if different (if applicable)

**Configuration:**
```
ALLOWED_ORIGINS=https://askthih.com,https://www.askthih.com
```

### CORS Headers (if applicable)

**Response headers:**
```
Access-Control-Allow-Origin: [matching origin only]
Access-Control-Allow-Methods: POST
Access-Control-Allow-Headers: Content-Type, Authorization
Access-Control-Max-Age: 86400
```

**Preflight (OPTIONS) Handling:**
- ✅ Return 200 OK for valid origin
- ✅ Return 403 Forbidden for invalid origin
- ✅ Never list all origins in response

---

## Rate Limiting Configuration

### Recommended Limits

**Primary:**
- 10 requests per second per IP
- Fallback: 100 requests per minute per source
- Burst: 20 requests in 5 seconds

### Abuse Response

**When limit exceeded:**
- Return 429 Too Many Requests
- Include `Retry-After` header
- Log offending IP and timestamp
- Consider temporary blocking (15-60 minute cooldown)

### Implementation Options

1. **Reverse Proxy Level** (nginx, AWS ALB)
   - Most efficient
   - Can block before webhook process
   - Configured in proxy rules

2. **Webhook Server Level** (PowerShell)
   - Secondary defense
   - In-memory rate limit tracking
   - Per-IP counters with TTL

3. **WAF/DDoS Service** (Cloudflare, AWS Shield)
   - Enterprise-level protection
   - Auto-scaling, global edge
   - Advanced threat detection

---

## Staging Environment Variables

### Required Variables

```bash
# SowerBase Connection
SOWERBASE_BASE_URL=http://localhost:18080  # Local for staging, HTTPS for remote
SOWERBASE_API_TOKEN=[REDACTED]
SOWERBASE_INTAKE_TABLE_ID=[REDACTED]

# Webhook Configuration
ASKTHIH_WEBHOOK_PORT=8787
ASKTHIH_WEBHOOK_SECRET=[REDACTED]
ALLOWED_ORIGINS=https://askthih.com,https://www.askthih.com

# Optional: Advanced Configuration
# ASKTHIH_WEBHOOK_RATE_LIMIT=10
# ASKTHIH_WEBHOOK_MAX_SIZE=10240
# ASKTHIH_WEBHOOK_TIMESTAMP_WINDOW=300
```

### Credential Requirements

**For Local Staging (Recommended):**
- SOWERBASE_BASE_URL: `http://localhost:18080` (private network)
- SowerBase remains local-only, not internet-facing

**For Remote SowerBase:**
- SOWERBASE_BASE_URL: `https://[remote-sowerbase-url]` (HTTPS required)
- Must be properly secured, not publicly exposed

---

## Deployment Verification

### Deploy Check Script

**Purpose:** Verify all staging deployment prerequisites before testing

**Locations:**
- Local: `scripts/askthih-hvac-staging-deploy-check.ps1`
- Staging: Deploy check runs against staging environment

**Checks Performed:**
1. All required environment variables present
2. Webhook process/endpoint reachable
3. Staging HTTPS route accessible
4. SowerBase API reachable
5. Intake Submissions table accessible
6. Webhook signature validation working
7. Rate limiting active
8. CORS headers correct

**Exit Code:**
- `0`: All checks passed, ready for smoke test
- Non-zero: Deployment issue detected, fix before proceeding

### Smoke Test Script

**Purpose:** Safe synthetic test request before production use

**Locations:**
- Local: `scripts/askthih-hvac-staging-smoke-test.ps1`
- Staging: Smoke test sends request to staging URL

**Procedure:**
1. Generate signed request with valid timestamp
2. Send to staging HTTPS route
3. Validate successful response
4. Verify no new production records created
5. Check SowerBase health after test
6. Confirm all 5 prior test records still exist

**Record Expectation:**
- Test payload: TEST HVAC Public Cutover - SowerBase
- Expected record ID: 6 (first test via protected staging)
- Channel: askthih_hvac_public_cutover_test
- Status: New
- Migration Status: test_only

---

## Staging Test Payload

### Record ID 6 - Public Cutover Test

**Payload:**
```json
{
  "submission_title": "TEST HVAC Public Cutover - SowerBase",
  "vertical": "HVAC",
  "contact_name": "Test HVAC Public Lead",
  "phone": "555-0155",
  "email": "public-cutover-test@example.com",
  "service_address": "987 Public Cutover Way",
  "problem_description": "HVAC compressor starts then shuts down after one minute.",
  "urgency": "Same Day",
  "channel": "askthih_hvac_public_cutover_test",
  "status": "New",
  "source_system": "askthih_public_cutover_test",
  "source_base_id": "app60wQWdbbgyqTcL",
  "source_table_name": "HVAC Intake",
  "migration_status": "test_only"
}
```

**Expected Result:**
- Record created in Intake Submissions table
- Record ID: 6 (if prior 5 records unchanged)
- All fields preserved
- No Airtable record created
- Backup includes new record

---

## Backup Requirement

### Before Phase 4 Staging Test

**Step 1: Validation**
```powershell
.\scripts\thih-backup-sowerbase.ps1 -ValidateOnly
```
Expected: 10/10 checks passed

**Step 2: Full Backup**
```powershell
.\scripts\thih-backup-sowerbase.ps1 -BackupType all
```
Expected: Backup file created, exit code 0

**Backup Should Include:**
- All 5 prior test records (IDs 1-5)
- All Tier 0 schema tables
- All sequences and metadata

---

## Phase 3 Completion Gates

### Deploy Check

✅ All environment variables configured  
✅ Webhook process operational  
✅ Staging route accessible via HTTPS  
✅ SowerBase API reachable  
✅ Intake Submissions table accessible  

### Smoke Test (Optional at this stage)

✅ Signed request accepted by staging  
✅ Response code 201 Created  
✅ Record ID 6 created (if run)  
✅ All 5 prior records unchanged  

### Backup Verification

✅ ValidateOnly: 10/10 checks passed  
✅ Full backup successful (exit code 0)  
✅ Backup file created and size reasonable  

---

## Security Checklist

✅ Webhook secret validation enabled  
✅ Timestamp validation enabled  
✅ HTTPS/TLS required for public/staging  
✅ localhost:8787 not exposed publicly  
✅ SowerBase not exposed publicly  
✅ Rate limiting configured or documented  
✅ No direct PostgreSQL writes for public route  
✅ Error responses don't expose secrets  
✅ CORS origins restricted  
✅ Request size limits enforced  

---

## Next Phase Gate

**Phase 4:** Staging Test Execution (Record ID 6)

**Prerequisites for Phase 4:**
- ✅ Phase 3 deployment complete
- ✅ Deploy check passes
- ✅ Smoke test succeeds (if run)
- ✅ Backup validation passes
- ✅ No public askthih.com/hvac changes
- ✅ No Airtable changes
- ✅ All 5 prior records intact

---

**Phase 3 Status:** PLANNING  
**Next Action:** Deploy reverse proxy and webhook to staging environment
