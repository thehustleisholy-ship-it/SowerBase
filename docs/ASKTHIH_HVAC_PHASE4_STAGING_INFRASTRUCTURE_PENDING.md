# AskTHIH HVAC Phase 4 — Staging Infrastructure Pending

## Summary

**Phase 4 Status:** ⏸️ **BLOCKED — STAGING INFRASTRUCTURE NOT DEPLOYED**

Phase 4 (Staging Test) cannot be executed in the current environment because the actual protected HTTPS staging route does not yet exist. This is a deliberate hold to avoid false confidence from local simulation.

**Date:** 2026-06-27  
**Blocker:** Actual staging infrastructure (HTTPS reverse proxy, staging domain, API credentials) not deployed  
**Impact:** Record ID 6 test must wait for real staging route  
**Recommendation:** Deploy staging infrastructure, then execute Phase 4 smoke test

---

## What Has Been Completed

### Phase 3 Deliverables (All Ready)

✅ **Deployment Plan:** `docs/ASKTHIH_HVAC_PROTECTED_STAGING_DEPLOYMENT_PLAN.md`
- Webhook code path verified (API-safe)
- Staging route defined: https://askthih.com/hvac-staging
- Reverse proxy requirements documented
- Security requirements specified
- Rate limiting configured (10 req/sec per IP)

✅ **Deploy Check Script:** `scripts/askthih-hvac-staging-deploy-check.ps1`
- Validates environment variables
- Tests webhook endpoint
- Checks SowerBase connectivity
- Ready to run in staging environment

✅ **Smoke Test Script:** `scripts/askthih-hvac-staging-smoke-test.ps1`
- Generates HMAC-SHA256 signed requests
- Sends test payload (Record ID 6)
- Validates successful response
- Ready to run against actual staging route

✅ **Nginx Configuration:** `config/nginx/askthih-hvac-staging.example.conf`
- Complete HTTPS/TLS setup
- Rate limiting rules
- Security headers
- Ready to deploy

✅ **Local Prerequisites:** Phase 2B credentials verified
- Preflight validation passed
- All 5 test records intact
- SowerBase operational

---

## Phase 4 Blocker Analysis

### Why Phase 4 Cannot Execute Now

1. **Staging Route Does Not Exist**
   - https://askthih.com/hvac-staging is documented but not deployed
   - Reverse proxy (nginx/ALB/Cloudflare) not configured
   - HTTPS/TLS certificate not assigned

2. **Staging Environment Not Configured**
   - Production/staging SowerBase API not accessible
   - Staging credentials not provisioned
   - DNS does not route to staging infrastructure

3. **No Live Test Possible**
   - Smoke test expects to POST to actual https://askthih.com/hvac-staging
   - Local simulation would not prove production readiness
   - Would create false confidence without real HTTPS validation

### Why We Avoid Simulation

We intentionally skip local simulation of Phase 4 to:
- **Prevent false confidence:** Local test ≠ production reality
- **Avoid misleading Record ID:** Record ID 6 should come from real staging, not simulation
- **Maintain test isolation:** Keep staging test separate from local development
- **Ensure HTTPS validation:** Real TLS validation required for security proof
- **Preserve audit trail:** Real staging record has proper continuity metadata

---

## Record ID 6 Status

**Submission Title:** TEST HVAC Public Cutover - SowerBase  
**Intended Record ID:** 6 (if prior 5 records unchanged)  
**Current Status:** ⏸️ **AWAITING STAGING DEPLOYMENT**  
**Expected Record:** Will be created when actual staging route is deployed and smoke test executes  

**Payload Specification:**
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

---

## Requirements for Phase 4 Execution

### Prerequisites

1. **Staging Infrastructure Deployed**
   - [ ] HTTPS reverse proxy configured (nginx, AWS ALB, or Cloudflare)
   - [ ] TLS certificate valid and installed
   - [ ] Domain https://askthih.com/hvac-staging resolves correctly
   - [ ] Routes to localhost:8787 webhook server (private)

2. **Staging Credentials Provisioned**
   - [ ] SOWERBASE_BASE_URL set to staging SowerBase
   - [ ] SOWERBASE_API_TOKEN generated and stored securely
   - [ ] SOWERBASE_INTAKE_TABLE_ID discovered
   - [ ] ASKTHIH_WEBHOOK_SECRET generated (32+ bytes)
   - [ ] No credentials committed to git

3. **Webhook Protection Active**
   - [ ] HMAC-SHA256 signature validation enabled
   - [ ] Timestamp validation active (±300 seconds)
   - [ ] Rate limiting configured (10 req/sec per IP)
   - [ ] Request size limits enforced (10 KB)
   - [ ] CORS origins restricted

4. **Network Security**
   - [ ] Staging route accessible via HTTPS only
   - [ ] localhost:8787 not exposed publicly
   - [ ] SowerBase not internet-facing
   - [ ] Reverse proxy handles authentication/validation

### Execution Steps

1. Run deploy check:
   ```powershell
   .\scripts\askthih-hvac-staging-deploy-check.ps1
   ```
   Must pass all checks (exit code 0)

2. Run smoke test:
   ```powershell
   .\scripts\askthih-hvac-staging-smoke-test.ps1 -StagingUrl "https://askthih.com/hvac-staging"
   ```
   Must receive 201 Created response

3. Verify record creation:
   - Query Intake Submissions table
   - Confirm Record ID 6 (or next available ID)
   - Verify all fields present and correct

4. Run backup validation:
   ```powershell
   .\scripts\thih-backup-sowerbase.ps1 -ValidateOnly
   .\scripts\thih-backup-sowerbase.ps1 -BackupType all
   ```
   Must pass (exit code 0)

---

## Safety Constraints Maintained

✅ **Public askthih.com/hvac:** NOT changed  
✅ **Airtable:** NOT altered  
✅ **Airtable imports:** NONE  
✅ **Canon connection:** NONE  
✅ **THIHskills:** UNTOUCHED  
✅ **Credentials:** NOT committed  
✅ **Secrets:** NOT printed  
✅ **Direct PostgreSQL writes:** DISABLED for public/staging  

---

## Approval Gate Status

| Phase | Status | Files | Next Action |
|-------|--------|-------|------------|
| **1. Documentation** | ✅ COMPLETE | PR #17 | — |
| **2. Credential Prep** | ✅ COMPLETE | PR #18 | — |
| **2B. Preflight** | ✅ PASSED | Local test | — |
| **3. Deployment Planning** | ✅ COMPLETE | PR #19 | Deploy infrastructure |
| **4. Staging Test** | ⏸️ BLOCKED | Pending | Infrastructure required |
| **5. Production Readiness** | ⏳ PENDING | — | After Phase 4 |
| **6. Public Cutover** | ⏳ PENDING | — | After Phase 5 |

---

## What Happens When Infrastructure is Ready

Once staging infrastructure is deployed:

1. Create new branch: `feature/askthih-hvac-phase4-staging-test-execution`
2. Run deploy check against staging environment
3. Run smoke test against staging route (https://askthih.com/hvac-staging)
4. Verify Record ID 6 created in production SowerBase
5. Run backup validation
6. Document results in: `docs/ASKTHIH_HVAC_PHASE4_STAGING_TEST_RESULT.md`
7. Open PR with Record ID 6 proof
8. Proceed to Phase 5 (production readiness review)

---

## Deployment Readiness Checklist

**Before executing Phase 4, ensure:**

- [ ] PR #19 merged (deployment planning complete)
- [ ] Staging reverse proxy configured (nginx/ALB/Cloudflare)
- [ ] HTTPS certificate valid for askthih.com/hvac-staging
- [ ] Staging SowerBase API accessible
- [ ] Staging credentials provisioned securely
- [ ] Rate limiting configured (10 req/sec per IP)
- [ ] Webhook secret validation active (HMAC-SHA256)
- [ ] Timestamp validation active (±300 seconds)
- [ ] Request size limits enforced (10 KB)
- [ ] CORS origins restricted to askthih.com
- [ ] localhost:8787 not exposed to public internet
- [ ] SowerBase not directly accessible from public internet
- [ ] All security headers configured (HSTS, CSP, X-Frame-Options, etc.)
- [ ] All 5 prior test records still intact
- [ ] Public askthih.com/hvac unchanged
- [ ] Airtable untouched
- [ ] No credentials committed to git
- [ ] Backup system operational

Once all prerequisites are confirmed, execute Phase 4 staging test.

---

## Conclusion

**Phase 4 is deliberately blocked until staging infrastructure is deployed.**

This is not a technical blocker but an environmental one: we have the scripts, credentials, and plan ready, but the actual staging route does not exist yet.

**When staging infrastructure is ready:**
1. Run deploy check (validates environment)
2. Run smoke test (creates Record ID 6)
3. Verify record in production SowerBase
4. Run backup
5. Proceed to Phase 5

**Status:** ⏸️ **AWAITING STAGING INFRASTRUCTURE DEPLOYMENT**  
**Block Duration:** Until reverse proxy, HTTPS, and credentials are configured  
**Risk:** None (Phase 3 is complete, Phase 4 waits for real infrastructure)  
**Next Action:** Deploy staging infrastructure, then execute Phase 4

---

**Prepared:** 2026-06-27  
**Latest Develop Commit:** 1cd138500f  
**Phase 3 Complete:** YES  
**Phase 4 Ready (docs/scripts):** YES  
**Phase 4 Executable (infrastructure):** NO — Awaiting deployment
