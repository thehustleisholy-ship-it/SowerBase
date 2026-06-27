# AskTHIH HVAC Phase 3 — Protected Staging Deployment Result

## Executive Summary

**Phase 3 Status:** ✅ **DEPLOYMENT PLANNING & SCRIPTS COMPLETE**

Comprehensive documentation and verification scripts for deploying the API-safe HVAC webhook behind a protected HTTPS staging route have been created. Ready to deploy to staging environment.

**Date:** 2026-06-27  
**Branch:** feature/askthih-hvac-protected-staging-deployment  
**Commits:** TBD (after PR merge)

---

## Prerequisites Verification

### Phase 2B Completion

✅ Local credentials provisioned (session-only)  
✅ Preflight validation passed (exit code 0)  
✅ 5 test records intact (IDs 1-5)  
✅ SowerBase operational (http://localhost:18080)  
✅ Latest develop: `9fab3ad2f7`  
✅ Preflight script updated for local HTTP support  

---

## Phase 3 Deliverables

### 1. Deployment Plan Document

**File:** `docs/ASKTHIH_HVAC_PROTECTED_STAGING_DEPLOYMENT_PLAN.md`

**Contents:**
- ✅ Webhook code path verification (API-safe, no direct PostgreSQL writes)
- ✅ Staging route definition (https://askthih.com/hvac-staging preferred)
- ✅ Reverse proxy configuration requirements (HTTPS/TLS, security headers)
- ✅ Webhook protection specifications (HMAC-SHA256, timestamp validation)
- ✅ CORS/origin control requirements
- ✅ Rate limiting configuration (10 req/sec per IP)
- ✅ Environment variables specification
- ✅ Deployment verification requirements
- ✅ Security checklist
- ✅ Phase 3 completion gates

### 2. Deploy Check Script

**File:** `scripts/askthih-hvac-staging-deploy-check.ps1`

**Purpose:** Verify all staging deployment prerequisites before testing

**Checks Performed:**
1. All required environment variables present
2. Webhook process/endpoint reachable (localhost:8787)
3. Staging HTTPS route accessible
4. SowerBase API reachable
5. Intake Submissions table configured
6. Configuration validation (port range, secret length)

**Exit Codes:**
- 0: All checks passed, ready for smoke test
- Non-zero: Deployment issue detected

**Execution:**
```powershell
./scripts/askthih-hvac-staging-deploy-check.ps1
```

### 3. Smoke Test Script

**File:** `scripts/askthih-hvac-staging-smoke-test.ps1`

**Purpose:** Safe synthetic test request to protected staging webhook

**Procedure:**
1. Generate signed request with valid timestamp
2. Send to staging HTTPS route
3. Validate successful response
4. Verify no production records created
5. Check SowerBase health

**Test Payload:**
- Submission: TEST HVAC Public Cutover - SowerBase
- Contact: Test HVAC Public Lead (555-0155)
- Channel: askthih_hvac_public_cutover_test
- Expected Record ID: 6
- Status: test_only

**Execution:**
```powershell
./scripts/askthih-hvac-staging-smoke-test.ps1 -StagingUrl "https://askthih.com/hvac-staging"
```

### 4. Reverse Proxy Configuration Example

**File:** `config/nginx/askthih-hvac-staging.example.conf`

**Purpose:** Example nginx configuration for protecting webhook with HTTPS

**Features:**
- ✅ HTTPS/TLS 1.2+ required
- ✅ HTTP → HTTPS redirect
- ✅ Rate limiting (10 req/sec per IP)
- ✅ Request size limits (10 KB payload)
- ✅ Security headers (HSTS, X-Frame-Options, CSP, etc.)
- ✅ Only POST method allowed
- ✅ No directory listing
- ✅ Upstream configuration for localhost:8787
- ✅ Logging and monitoring

**Deployment Options:**
- Nginx (standalone)
- AWS ALB (Application Load Balancer)
- Cloudflare (reverse proxy)
- Docker / Kubernetes (sidecar)

**Notes:**
- Example only (customize for your environment)
- Update domain, certificate paths, upstream server
- Test with `nginx -t` before deploying
- Monitor logs during initial deployment

---

## Deployment Architecture

### Request Flow

```
Public HTTPS Request
    ↓
https://askthih.com/hvac-staging
    ↓
Reverse Proxy (nginx/ALB/Cloudflare)
    - HTTPS/TLS validation
    - Rate limiting (10 req/sec)
    - Security headers
    - Request size validation
    ↓
localhost:8787 (private network)
    ↓
Webhook Server (local, private)
    - Signature validation (HMAC-SHA256)
    - Timestamp validation (±300s)
    - JSON payload validation
    - Required field validation
    ↓
SowerBase/NocoDB API or Backend Layer
    ↓
Database (private)
    ↓
Response (201 Created)
    - record_id
    - status
    - message
```

### Security Layers

1. **HTTPS/TLS** - Public network encryption
2. **Reverse Proxy** - Access control, rate limiting
3. **Webhook Secret** - HMAC-SHA256 signature validation
4. **Timestamp Validation** - Replay attack prevention
5. **Request Validation** - JSON schema, required fields
6. **Error Handling** - No secrets in error responses
7. **SowerBase API** - Application-layer access control

---

## Webhook Code Path Verification

### API-Safe Pattern

✅ **Webhook Server Uses:**
- Environment variables for authentication
- SowerBase/NocoDB API payload preparation
- Secure credential handling (never printed)
- Safe error responses (no stack traces)

✅ **Direct PostgreSQL Writes:**
- NOT used for public/staging mode
- Backend layer provides protection
- Fallback approach only for local testing

✅ **Public Route Protection:**
- HTTPS required
- Webhook secret validation
- Reverse proxy access control
- Rate limiting enforced

---

## Staging Route Details

### Primary Route

**URL:** `https://askthih.com/hvac-staging`

**Features:**
- HTTPS/TLS required (no HTTP fallback)
- Reverse proxy protection
- Rate limiting (10 req/sec per IP)
- Webhook secret validation
- CORS origin restrictions
- Request size limits (10 KB)

### Public Route Status

**URL:** `https://askthih.com/hvac`

**Status:** ❌ **NOT CHANGED**
- Still routes to Airtable
- Remains unchanged until explicit approval
- Protected staging test (ID 6) via /hvac-staging only

---

## Environment Variables Required

**For Staging Deployment:**

```bash
# SowerBase Connection
SOWERBASE_BASE_URL=http://localhost:18080  # Local for this staging
SOWERBASE_API_TOKEN=[REDACTED]
SOWERBASE_INTAKE_TABLE_ID=[REDACTED]

# Webhook Configuration
ASKTHIH_WEBHOOK_PORT=8787
ASKTHIH_WEBHOOK_SECRET=[REDACTED]
ALLOWED_ORIGINS=https://askthih.com,https://www.askthih.com

# Optional: Advanced
# ASKTHIH_WEBHOOK_RATE_LIMIT=10
# ASKTHIH_WEBHOOK_MAX_SIZE=10240
# ASKTHIH_WEBHOOK_TIMESTAMP_WINDOW=300
```

---

## Phase 3 Completion Checklist

### Deployment Plan

✅ Webhook code path verified (API-safe, no direct PostgreSQL)  
✅ Staging route defined (https://askthih.com/hvac-staging)  
✅ Reverse proxy requirements documented  
✅ Webhook protection requirements specified  
✅ CORS/origin controls defined  
✅ Rate limiting configuration documented  
✅ Environment variables documented  

### Verification Scripts

✅ Deploy check script created (pre-deployment validation)  
✅ Smoke test script created (synthetic test request)  
✅ Both scripts avoid printing secrets  
✅ Both scripts exit with appropriate codes  

### Configuration Examples

✅ Nginx reverse proxy example provided  
✅ AWS ALB configuration notes included  
✅ Cloudflare configuration notes included  
✅ Docker/Kubernetes notes included  

### Security

✅ HTTPS/TLS required  
✅ Webhook secret validation enabled  
✅ Timestamp validation required  
✅ Request size limits enforced  
✅ Rate limiting configured  
✅ Error responses secure (no secrets)  
✅ CORS origins restricted  

---

## Status Summary

**Phase 3 Deliverables:**
- ✅ Deployment plan
- ✅ Deploy check script
- ✅ Smoke test script
- ✅ Reverse proxy examples
- ✅ Result documentation

**Verification:**
- ✅ No direct PostgreSQL writes for public/staging
- ✅ HTTPS protection specified
- ✅ Webhook secret validation required
- ✅ Rate limiting configured
- ✅ SowerBase not exposed publicly
- ✅ Public askthih.com/hvac NOT changed

**Safety Constraints:**
- ✅ No public cutover executed
- ✅ No askthih.com/hvac changes
- ✅ No Airtable changes
- ✅ No Airtable imports
- ✅ No Canon connection
- ✅ THIHskills untouched

---

## Next Phase Gate

**Phase 4:** Staging Test Execution (Record ID 6)

### Prerequisites for Phase 4

1. **Deploy Check Passes**
   ```powershell
   ./scripts/askthih-hvac-staging-deploy-check.ps1
   ```
   Expected: Exit code 0

2. **Optional: Smoke Test**
   ```powershell
   ./scripts/askthih-hvac-staging-smoke-test.ps1 -StagingUrl "https://askthih.com/hvac-staging"
   ```
   Expected: Test request accepted, signature validation working

3. **Backup Validation**
   ```powershell
   ./scripts/thih-backup-sowerbase.ps1 -ValidateOnly
   ./scripts/thih-backup-sowerbase.ps1 -BackupType all
   ```
   Expected: 10/10 checks passed, backup file created

### Phase 4 Test Payload

**Submission:** TEST HVAC Public Cutover - SowerBase  
**Contact:** Test HVAC Public Lead (555-0155)  
**Channel:** askthih_hvac_public_cutover_test  
**Expected Record ID:** 6  

### Phase 4 Verification

- ✅ Record ID 6 created in Intake Submissions
- ✅ All 5 prior records unchanged
- ✅ No Airtable record created
- ✅ Backup includes record ID 6
- ✅ SowerBase health normal
- ✅ No public askthih.com/hvac changes

---

## Conclusion

**Phase 3 Status:** ✅ **COMPLETE**

Comprehensive deployment documentation and verification scripts are ready. The protected staging deployment approach:

1. ✅ Maintains API-safe webhook implementation
2. ✅ Protects webhook with HTTPS/TLS
3. ✅ Enforces webhook secret validation
4. ✅ Applies rate limiting and request limits
5. ✅ Restricts CORS origins
6. ✅ Keeps localhost webhook private
7. ✅ Keeps SowerBase not internet-facing
8. ✅ Does not change public askthih.com/hvac
9. ✅ Keeps all Airtable data intact

**Ready for:** Deploying to staging environment and executing Phase 4 staging test

---

**Phase 3 Status:** ✅ **DEPLOYMENT PLANNING COMPLETE**  
**Next Phase:** Phase 4 — Staging Test Execution (Record ID 6)  
**Public Cutover:** ❌ **NOT APPROVED** (awaiting Phase 4-6 completion)  
**Public askthih.com/hvac Changed:** ❌ **NO**
