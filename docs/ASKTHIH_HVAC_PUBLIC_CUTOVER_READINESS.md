# AskTHIH HVAC Public Cutover Readiness — Tier 0.95

## Executive Summary

**Status:** ✅ **READY FOR CUTOVER** (pending API credentials and approval)

AskTHIH HVAC public intake (askthih.com/hvac) can be cutover to SowerBase after:
1. API credentials are provisioned
2. Staging test passes
3. All readiness checks pass
4. Explicit approval is given

**This document establishes the approval gate and prerequisites.**

---

## PR #16 Merge Status

**Merge Commit:** `d4f7a52523`  
**Date:** 2026-06-27 18:51  
**Status:** ✅ **MERGED to develop**

**What Was Merged:**
- API-safe webhook server (direct PostgreSQL writes removed)
- Secure token handling (environment variables)
- API payload preparation (ready for NocoDB API)
- 5 test records verified (schema, bridge, webhook, staging, api-safe)
- Backup system operational (289.68 KB, all 10 sequences)

---

## Current System State

### Active Components

✅ **SowerBase Running**
- URL: http://localhost:18080
- Status: Responsive
- Database: PostgreSQL operational
- NocoDB: Running and healthy

✅ **Tier 0 Schema (6 Tables)**
1. Vertical Types
2. Contacts
3. Organizations
4. Intake Submissions
5. Source Links
6. Migration Batches

✅ **Intake Submissions Test Records (5 Total)**
| ID | Submission | Channel | System |
|----|-----------|---------|--------|
| 1 | Schema test | schema_test | sowerbase_local_test |
| 2 | Bridge test | local_bridge_test | askthih_local_bridge_test |
| 3 | Webhook test | local_webhook_test | askthih_local_webhook_test |
| 4 | Staging test | askthih_hvac_staging | askthih_staging_route_test |
| 5 | API-safe test | askthih_hvac_api_safe_test | askthih_api_safe_webhook_test |

✅ **Backup System**
- Latest dump: `nocodb_dump_2026-06-27_1851.sql`
- Size: 289.68 KB
- Sequences: 10 total
- Artifacts: Properly ignored by git
- Validation: 10/10 checks PASSED

---

## Required Production/Staging Environment Variables

### Mandatory Variables

```bash
# SowerBase Connection
SOWERBASE_BASE_URL=https://sowerbase.example.com  # HTTPS required
SOWERBASE_API_TOKEN=[REDACTED - keep secure]      # NocoDB API token
SOWERBASE_INTAKE_TABLE_ID=tbl[...]               # Intake Submissions table ID

# Webhook Configuration
ASKTHIH_WEBHOOK_PORT=8787                        # or configured port
ASKTHIH_WEBHOOK_SECRET=[REDACTED - keep secure]  # Webhook signature secret

# Security
ALLOWED_ORIGINS=https://askthih.com,https://*.askthih.com  # CORS origins
```

### Environment Variable Requirements

✅ **Never Hard-Code Secrets**
- Use secure credential storage (AWS Secrets Manager, HashiCorp Vault, etc.)
- Rotate tokens quarterly minimum
- Never commit to git

✅ **Never Print Secrets**
- Token values never logged
- Passwords never exposed
- Only print sanitized status messages

✅ **Session-Only Variables**
- Load at process startup
- Clear after request processing
- Never persist to disk

---

## Protection Requirements

### HTTPS/TLS

✅ **Required for Public/Staging**
```
PUBLIC:   https://askthih.com/hvac (MUST be HTTPS)
STAGING:  https://staging.askthih.com/hvac (MUST be HTTPS)
LOCAL:    http://localhost:8787 (local testing only)
```

### Webhook Authentication

✅ **Webhook Secret Required**
- All webhook requests must include signature
- Signature algorithm: HMAC-SHA256
- Format: `Authorization: Signature <timestamp>.<signature>`
- Timestamp validation: ±300 seconds

### Request Protection

✅ **Rate Limiting**
- Recommended: 10 requests/second per IP
- Fallback: 100 requests/minute per source
- Burst allowance: 20 requests in 5 seconds

✅ **Request Size Limits**
- Max payload: 10 KB
- Max form submission: 100 KB
- Protects against memory exhaustion

✅ **No Direct Database Access**
- Public routes: ONLY through SowerBase/NocoDB API
- No `docker exec psql` for public intake
- No direct PostgreSQL connections from public internet

### No Public API Exposure

✅ **SowerBase Not Internet-Facing**
- Webhook server protected by reverse proxy (nginx, AWS ALB, etc.)
- SowerBase database: Private network only
- Public webhook server: Single entry point with authentication

---

## Data Protection

### Logging Requirements

✅ **Avoid Logging Sensitive Data**
- Do not log email addresses
- Do not log phone numbers (log last 4 digits only)
- Do not log full addresses
- Log: timestamp, channel, vertical, urgency, status
- Log: request ID, response code, error type (not error message)

✅ **Audit Trail**
- All intake submissions logged
- Timestamp of submission
- Source channel recorded
- Migration status tracked
- Airtable ID preserved (if applicable)

### Backup Security

✅ **Backup Encryption**
- Backups stored on encrypted volumes
- Database dumps: AES-256 encryption recommended
- Backup artifacts: Keep encrypted when at rest

---

## Public Cutover Test Payload

### Synthetic Test Record

**Purpose:** Verify end-to-end flow before production cutover

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
- Record ID 6 created in Intake Submissions
- Status: New
- Channel: askthih_hvac_public_cutover_test
- Source system: askthih_public_cutover_test
- No Airtable record created
- All 6 test records remain intact

---

## Approval Gate

### Prerequisites for Public Cutover

**Phase 1: Documentation (Current)**
- ✅ Readiness document created (this file)
- ✅ Environment variables documented
- ✅ Protection requirements defined
- ✅ Test payload specified

**Phase 2: Credentials Provisioning**
- ⏳ SOWERBASE_API_TOKEN provisioned
- ⏳ SOWERBASE_INTAKE_TABLE_ID obtained
- ⏳ ASKTHIH_WEBHOOK_SECRET configured
- ⏳ Credentials securely stored

**Phase 3: Staging Deployment**
- ⏳ Webhook server deployed behind HTTPS reverse proxy
- ⏳ Webhook secret validation enabled
- ⏳ Rate limiting configured
- ⏳ Request size limits enforced
- ⏳ Logging configured (no sensitive data)

**Phase 4: Staging Test**
- ⏳ Public cutover test payload submitted
- ⏳ Record ID 6 created successfully
- ⏳ All 6 prior test records remain intact
- ⏳ SowerBase health check passes
- ⏳ Backup validation passes (10/10 checks)
- ⏳ Full backup succeeds

**Phase 5: Production Readiness**
- ⏳ No Airtable changes detected
- ⏳ No Airtable data imported
- ⏳ No Canon data connected
- ⏳ THIHskills untouched
- ⏳ All safety constraints maintained

**Phase 6: Approval & Cutover**
- ⏳ Explicit user approval obtained
- ⏳ Public askthih.com/hvac routed to SowerBase
- ⏳ Airtable maintained as read-only archive (30-day minimum)
- ⏳ Monitoring activated

---

## Deployment Checklist

See: `docs/ASKTHIH_HVAC_PUBLIC_CUTOVER_CHECKLIST.md`

---

## Cutover Rollback Plan

### If Issues Detected

**Immediate Actions:**
1. Revert public askthih.com/hvac to Airtable intake
2. Investigate issue in staging/local environment
3. Do NOT modify Airtable records
4. Do NOT delete any SowerBase records
5. Document issue and fix

**Recovery:**
- SowerBase test records preserved (IDs 1-6+)
- Airtable intake continues normally
- No data loss
- Retry cutover after fix validated

---

## Estimated Timeline

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Documentation | ✅ Complete | None |
| Phase 2: Credential Provisioning | 1-2 days | Security team approval |
| Phase 3: Staging Deployment | 1 day | Credentials ready |
| Phase 4: Staging Test | 1 day | Staging deployed |
| Phase 5: Production Readiness | 1 day | Staging test passed |
| Phase 6: Approval & Cutover | Same-day | All phases complete, approval given |

**Total Estimated Time:** 4-6 days from credential provisioning

---

## Approval Sign-Off

### Prerequisites for Cutover Approval

- [ ] PR #16 merged (API-safe webhook)
- [ ] API credentials provisioned (SOWERBASE_API_TOKEN, etc.)
- [ ] Staging test created record ID 6 successfully
- [ ] All 6 prior test records remain intact
- [ ] SowerBase health check passes
- [ ] Backup validation passes (10/10 checks)
- [ ] Full backup succeeds
- [ ] No Airtable changes detected
- [ ] No Airtable data imported
- [ ] No Canon data connected
- [ ] THIHskills untouched
- [ ] Webhook secret validation enabled
- [ ] HTTPS enforced for public/staging
- [ ] Rate limiting configured
- [ ] Logging configured (no sensitive data)
- [ ] Explicit user approval obtained

### Approval Required From

- [ ] Michael (Project Owner / AskTHIH Lead)

---

## Success Criteria

### Public Cutover is Successful When

✅ **Immediate (First 24 Hours)**
- askthih.com/hvac accepts submissions
- Submissions appear in SowerBase Intake Submissions table
- Response time < 500ms
- No 5xx errors
- Webhook secret validation succeeds

✅ **Short Term (First Week)**
- 10+ test submissions received
- All submissions visible in SowerBase
- Airtable intake still works (for archive/rollback)
- No data loss
- Zero security incidents

✅ **Medium Term (First Month)**
- 100+ production submissions received
- Migration data preserved
- No performance degradation
- Airtable maintained as archive (30-day retention minimum)
- Cutover validated for other service verticals

---

## Next Steps

### If Approved for Staging/Production

1. **Credential Provisioning**
   - Generate SOWERBASE_API_TOKEN in production NocoDB
   - Obtain SOWERBASE_INTAKE_TABLE_ID (discover via API)
   - Generate ASKTHIH_WEBHOOK_SECRET (32+ random bytes)
   - Store securely in production secrets manager

2. **Staging Deployment**
   - Deploy webhook server to staging environment
   - Configure reverse proxy (nginx, AWS ALB, etc.)
   - Enable TLS/HTTPS
   - Configure webhook secret validation
   - Enable rate limiting (10 req/sec)
   - Test webhook endpoint with `curl` before cutover

3. **Staging Test**
   - Submit public cutover test payload
   - Verify record ID 6 created
   - Verify no Airtable changes
   - Run backup validation and full backup
   - Monitor error logs for 24 hours

4. **Production Cutover**
   - Route public askthih.com/hvac to SowerBase webhook
   - Maintain Airtable as read-only archive (30+ days)
   - Monitor: response times, error rates, webhook secret validation
   - Set up alerting for errors or rate limit exceeded

---

## References

- **PR #14:** Webhook bridge proof
- **PR #15:** Staging route proof
- **PR #16:** API-safe webhook refactor
- **Schema:** 6 Tier 0 tables (Vertical Types, Contacts, Organizations, Intake Submissions, Source Links, Migration Batches)
- **Continuity Metadata:** source_system, source_base_id, source_record_id, source_table_name, migration_batch_id, migration_status

---

**Status:** ✅ **TIER 0.95 READINESS DOCUMENTATION COMPLETE**  
**Next:** Provision credentials and execute staging test  
**Final Approval Required:** For public cutover transition
