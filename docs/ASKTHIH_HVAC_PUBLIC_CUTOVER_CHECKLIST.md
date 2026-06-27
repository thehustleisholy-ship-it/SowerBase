# AskTHIH HVAC Public Cutover Deployment Checklist

**Status:** Reference document for deployment team  
**Purpose:** Step-by-step verification before, during, and after public cutover

---

## Phase 1: Documentation & Preparation

### Pre-Deployment Review

- [ ] Read `ASKTHIH_HVAC_PUBLIC_CUTOVER_READINESS.md` completely
- [ ] Understand environment variables (5 required)
- [ ] Understand protection requirements (HTTPS, webhook secret, rate limiting)
- [ ] Review test payload specification
- [ ] Review rollback plan
- [ ] Confirm approval from Michael obtained

### Credential Preparation

- [ ] SOWERBASE_API_TOKEN generated in production NocoDB
- [ ] SOWERBASE_BASE_URL configured (HTTPS only)
- [ ] SOWERBASE_INTAKE_TABLE_ID obtained (Intake Submissions table)
- [ ] ASKTHIH_WEBHOOK_SECRET generated (32+ random bytes)
- [ ] Credentials stored in secure vault (AWS Secrets Manager, HashiCorp Vault, etc.)
- [ ] Credentials NOT committed to git
- [ ] Credentials NOT printed in logs

### Infrastructure Preparation

- [ ] HTTPS certificate installed and valid
- [ ] Reverse proxy configured (nginx, AWS ALB, etc.)
- [ ] TLS version: 1.2+ minimum
- [ ] Cipher suites: Modern only (no RC4, DES, MD5)
- [ ] HSTS header enabled (min-age: 31536000)
- [ ] X-Frame-Options: DENY
- [ ] X-Content-Type-Options: nosniff

---

## Phase 2: Staging Deployment

### Webhook Server Setup

- [ ] Webhook server script deployed to staging
  - File: `scripts/askthih-hvac-local-webhook-server.ps1`
  - Verify: No direct PostgreSQL writes in production path
  - Verify: API token handling via environment variables
  - Verify: Webhook secret validation enabled
- [ ] Webhook server process running
- [ ] Port listening correctly (configured port, typically 8787)
- [ ] Reverse proxy routing to webhook server
- [ ] TLS/HTTPS enforced

### Security Configuration

- [ ] Webhook secret validation code in place
- [ ] Rate limiting configured
  - Limit: 10 requests/second per IP
  - Fallback: 100 requests/minute per source
  - Burst: 20 requests in 5 seconds
- [ ] Request size limits enforced
  - Max payload: 10 KB
  - Max form: 100 KB
- [ ] CORS origins configured
  - Allowed: https://askthih.com, https://*.askthih.com
  - Denied: Everything else

### Logging Configuration

- [ ] Request logging enabled
- [ ] No sensitive data in logs
  - ✅ Log: timestamp, channel, vertical, urgency, status
  - ✅ Log: request_id, response_code, error_type
  - ❌ Do NOT log: email, phone, address
  - ❌ Do NOT log: secrets, tokens, passwords
- [ ] Error logging configured
- [ ] Audit trail setup
- [ ] Log retention policy: 90 days minimum

---

## Phase 3: Pre-Test Validation

### Staging Environment Health

- [ ] SowerBase responsive
  - URL: https://sowerbase-staging.example.com
  - Health check: 200 OK
- [ ] PostgreSQL connected
- [ ] NocoDB operational
- [ ] Intake Submissions table accessible
- [ ] All 5 prior test records intact
  - ID 1: Schema test (schema_test)
  - ID 2: Bridge test (local_bridge_test)
  - ID 3: Webhook test (local_webhook_test)
  - ID 4: Staging test (askthih_hvac_staging)
  - ID 5: API-safe test (askthih_hvac_api_safe_test)

### Webhook Server Validation

- [ ] Webhook endpoint responds to OPTIONS request (CORS preflight)
  - URL: https://staging.askthih.com/hvac
  - Status: 200 OK
- [ ] Webhook endpoint rejects requests without secret
  - Status: 401 Unauthorized
- [ ] Webhook endpoint rejects oversized payloads
  - Payload > 10 KB: 413 Payload Too Large
- [ ] Webhook endpoint rate limit active
  - After 10 req/sec: 429 Too Many Requests

### Backup Validation

- [ ] Backup script operational
- [ ] Run: `./scripts/thih-backup-sowerbase.ps1 -ValidateOnly`
  - Expected: 10/10 checks PASSED
- [ ] Backup artifacts ignored by git
  - Verify: `backups/` in `.gitignore`

---

## Phase 4: Staging Test Execution

### Submit Public Cutover Test Payload

- [ ] Test payload prepared
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

- [ ] Test payload submitted
  - Method: POST
  - URL: https://staging.askthih.com/hvac
  - Headers: Include webhook secret signature
  - Status: 201 Created expected

- [ ] Response validated
  ```json
  {
    "status": "success",
    "message": "HVAC intake received and stored",
    "record_id": 6
  }
  ```

### Record Verification

- [ ] Record ID 6 created in Intake Submissions
- [ ] Fields verified:
  - Submission Title: TEST HVAC Public Cutover - SowerBase ✓
  - Contact Name: Test HVAC Public Lead ✓
  - Channel: askthih_hvac_public_cutover_test ✓
  - Status: New ✓
- [ ] All 5 prior records still exist
- [ ] No Airtable record created
- [ ] No Airtable records modified
- [ ] Timestamp: Recent and correct
- [ ] Source metadata preserved:
  - source_system: askthih_public_cutover_test ✓
  - migration_status: test_only ✓

### System Health After Test

- [ ] SowerBase still responsive
- [ ] No error logs for test request
- [ ] Webhook server still running
- [ ] No rate limit exceeded errors
- [ ] Response time < 500ms

### Backup After Test

- [ ] Run: `./scripts/thih-backup-sowerbase.ps1 -ValidateOnly`
  - Expected: 10/10 checks PASSED
- [ ] Run: `./scripts/thih-backup-sowerbase.ps1 -BackupType all`
  - Expected: Exit code 0
  - Filename: `nocodb_dump_2026-06-27_[timestamp].sql`
  - Size: ~290 KB
  - Sequences: 10 total
- [ ] Backup contains record ID 6
- [ ] All 6 test records included in backup

---

## Phase 5: Production Readiness Final Check

### No Unauthorized Changes

- [ ] Airtable remains untouched
  - No new bases created
  - No tables modified
  - No records imported
  - No schema changes
- [ ] Canon integration: No changes
- [ ] THIHskills: No modifications
- [ ] Other verticals: Not affected

### Documentation Review

- [ ] Environment variables documented
- [ ] Protection requirements confirmed
- [ ] Rollback plan reviewed
- [ ] Success criteria understood

### Approval Confirmation

- [ ] Michael approval obtained for production cutover
- [ ] Approval documented (date, time, confirmation)
- [ ] Deployment team briefed
- [ ] Rollback team on standby

---

## Phase 6: Production Cutover

### Pre-Cutover (30 minutes before)

- [ ] Airtable intake still working (last test at T-30min)
- [ ] SowerBase staging test passed (all checks green)
- [ ] Monitoring and alerting configured
- [ ] Runbook reviewed by operations team
- [ ] Slack notification sent to team

### Cutover Execution

- [ ] Update DNS or routing to point askthih.com/hvac to SowerBase webhook
  - Old: askthih.com/hvac → Airtable form
  - New: askthih.com/hvac → SowerBase webhook (via reverse proxy)
- [ ] Deployment completed
- [ ] Verify public askthih.com/hvac redirects to SowerBase webhook

### Post-Cutover Validation (Immediate)

- [ ] Public askthih.com/hvac accessible via HTTPS
- [ ] Webhook endpoint responds
- [ ] Reverse proxy routing working
- [ ] SowerBase Intake Submissions table healthy
- [ ] No error spikes in logs
- [ ] Response time < 500ms

### 5-Minute Check

- [ ] Submit manual test submission to public askthih.com/hvac
- [ ] Verify record created in SowerBase (ID 7+)
- [ ] Verify no Airtable record created
- [ ] All SowerBase metrics normal

### 1-Hour Monitoring

- [ ] Error rate: < 1%
- [ ] Webhook secret validation: 100% passed
- [ ] Rate limiting: No false positives
- [ ] Response time: < 500ms average
- [ ] Backup system: Operational
- [ ] Database health: OK

### 24-Hour Monitoring

- [ ] Continuous operation without incidents
- [ ] 10+ production submissions received
- [ ] All submissions in SowerBase
- [ ] Zero data loss
- [ ] Zero security incidents
- [ ] Airtable intake still working (for rollback if needed)

---

## Phase 7: Rollback (If Needed)

### Trigger Conditions

Rollback if:
- [ ] Response time consistently > 2 seconds
- [ ] Error rate > 5%
- [ ] Webhook secret validation failures > 1%
- [ ] Data loss detected
- [ ] Security incident
- [ ] SowerBase database failure

### Rollback Procedure

- [ ] Stop accepting submissions to SowerBase webhook
- [ ] Revert DNS/routing: askthih.com/hvac → Airtable form
- [ ] Verify Airtable intake working again
- [ ] Investigate issue in staging environment
- [ ] Document issue and fix
- [ ] Retry cutover after fix validated

### Data Recovery

- [ ] SowerBase test records (IDs 1-7+): Preserved
- [ ] Airtable intake: Resumed from rollback point
- [ ] No data loss
- [ ] Audit log: Documents rollback and reason

---

## Post-Cutover Success Criteria

### First Day

- [ ] Public askthih.com/hvac fully operational
- [ ] Multiple submissions received
- [ ] All submissions in SowerBase
- [ ] Zero errors for end users
- [ ] Zero data loss

### First Week

- [ ] 50+ production submissions
- [ ] All submissions queryable in SowerBase
- [ ] Airtable intake optional (maintained for archive)
- [ ] No performance issues
- [ ] Zero security incidents

### First Month

- [ ] 500+ production submissions
- [ ] Full migration confidence
- [ ] Airtable archive decision made (continue or retire)
- [ ] Cutover preparation for other verticals underway

---

## Sign-Off

| Role | Name | Date | Time | Notes |
|------|------|------|------|-------|
| Project Owner | Michael | | | |
| Deployment Lead | | | | |
| Operations | | | | |
| Security Review | | | | |

---

## Contact Information

**On-Call for Cutover Issues:**
- Email: [deployment team email]
- Slack: #askthih-cutover
- Phone: [emergency number]

**Escalation Path:**
1. Deployment Lead
2. Operations Manager
3. CTO
4. Michael (Project Owner)

**Timeline:**
- Cutover window: 2-hour maintenance window
- Rollback capability: 24 hours
- Monitoring: 48+ hours continuous

---

**Last Updated:** 2026-06-27  
**Version:** 1.0 (Pre-Deployment)  
**Status:** Ready for staging & production deployment
