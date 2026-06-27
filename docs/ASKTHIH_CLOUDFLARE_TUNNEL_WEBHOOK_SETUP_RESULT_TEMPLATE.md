# AskTHIH Cloudflare Tunnel Webhook Setup — Result Template

**Complete this document AFTER running the tunnel setup and verification.**

---

## Setup Information

**PR #25 Merge Commit:**
```
[REPLACE WITH ACTUAL COMMIT HASH]
```

**Latest Develop Commit:**
```
[REPLACE WITH ACTUAL COMMIT HASH]
```

**Branch:**
```
feature/askthih-cloudflare-tunnel-webhook-helper
```

**Date:**
```
[REPLACE WITH DATE: 2026-MM-DD HH:MM]
```

---

## Prerequisites Verification

**SowerBase at localhost:18080:**
- [ ] ✅ Responsive and accessible
- [ ] ❌ Not running

**API-Safe HVAC Webhook:**
- [ ] ✅ Running at localhost:8787
- [ ] ❌ Not running

**Intake Submissions Table:**
- [ ] ✅ Contains 5 test records (IDs 1-5)
- [ ] ⚠️ Record count: [REPLACE WITH ACTUAL COUNT]

**Record ID 6:**
- [ ] ✅ Does NOT exist (reserved for Vercel)
- [ ] ❌ Exists (STOP - do not proceed)

**Public askthih.com/hvac:**
- [ ] ✅ Unchanged (still on Airtable)
- [ ] ❌ Changed (STOP - investigate)

**Airtable:**
- [ ] ✅ Unchanged
- [ ] ❌ Modified (STOP - investigate)

---

## Cloudflare Quick Tunnel Setup

**cloudflared Installed:**
- [ ] ✅ Yes, version: [REPLACE WITH VERSION]
- [ ] ❌ No (run: choco install cloudflare-warp)

**Webhook Server Running:**
- [ ] ✅ Yes, listening on localhost:8787
- [ ] ⚠️ Partial (running but may have errors - check logs)
- [ ] ❌ No (run: .\scripts\askthih-hvac-local-webhook-server.ps1)

**Tunnel Started:**
- [ ] ✅ Yes
- [ ] ❌ No

**Tunnel Target:**
- [ ] ✅ localhost:8787 (webhook only)
- [ ] ❌ localhost:18080 (SowerBase - WRONG)
- [ ] ❌ Other: [REPLACE WITH ACTUAL]

**Temporary Tunnel URL:**
```
[MARK AS SESSION-ONLY OR REDACTED]
Example: https://askthih-staging-abc123.cloudflareaccess.com
Do NOT commit this URL to git.
```

---

## Verification Results

### Helper Script: askthih-cloudflare-tunnel-webhook-check.ps1

**Script Run:**
- [ ] ✅ Yes
- [ ] ❌ No

**Script Exit Code:**
- [ ] ✅ 0 (success)
- [ ] ❌ Non-zero (failure - see below)

**Verification Output:**
```
[COPY OUTPUT FROM HELPER SCRIPT HERE]
```

---

### Security Checks

**Webhook-Only Exposure:**
- [ ] ✅ Verified (tunnel points to localhost:8787 only)
- [ ] ❌ Failed (tunnel also exposes other services)

**SowerBase/NocoDB UI Exposed:**
- [ ] ✅ NO (good - not exposed)
- [ ] ⚠️ Partial (some paths respond but no login required)
- [ ] ❌ YES (CRITICAL - STOP, do not proceed)

**Admin Panel Exposed:**
- [ ] ✅ NO (good - not accessible)
- [ ] ❌ YES (CRITICAL - STOP)

**PostgreSQL Exposed:**
- [ ] ✅ NO (good - database not tunneled)
- [ ] ❌ YES (CRITICAL - STOP)

**Credentials/Tokens Exposed:**
- [ ] ✅ NO (good - no secrets in responses)
- [ ] ❌ YES (CRITICAL - STOP, contact admin)

---

## Test Results

### Basic Connectivity

**Tunnel root (/) test:**
- [ ] ✅ Not directly accessible (safe)
- [ ] ⚠️ Accessible with error response (safe)
- [ ] ❌ Accessible with NocoDB UI (UNSAFE)

**Webhook endpoint (/askthih/hvac) test:**
- [ ] ✅ Returns 405 Method Not Allowed (safe)
- [ ] ✅ Returns 200 OK (safe)
- [ ] ❌ Returns error (investigate)

**Safe paths test:**
- [ ] ✅ All return 404 or error (expected, safe)
- [ ] ⚠️ Some paths respond (check content)
- [ ] ❌ Any path shows admin interface (UNSAFE)

---

## Record Creation Verification

**Record ID 6:**
- [ ] ✅ Does NOT exist (correct)
- [ ] ❌ Exists (PROBLEM - should not create until Vercel)

**Intake Submissions Count:**
- [ ] ✅ Still 5 records
- [ ] ⚠️ Count: [REPLACE WITH NUMBER]

**No Unauthorized Changes:**
- [ ] ✅ Verified (no extra records)
- [ ] ⚠️ Possible extra records created (investigate)

---

## Safety Constraints Verification

**Public askthih.com/hvac Changed:**
- [ ] ✅ NO (unchanged)
- [ ] ❌ YES (STOP)

**Airtable Changed:**
- [ ] ✅ NO (unchanged)
- [ ] ❌ YES (STOP)

**Airtable Imports:**
- [ ] ✅ NO (none performed)
- [ ] ❌ YES (STOP)

**Canon Connection:**
- [ ] ✅ NO (not connected)
- [ ] ❌ YES (STOP)

**THIHskills Touched:**
- [ ] ✅ NO (untouched)
- [ ] ❌ YES (STOP)

**Credentials Committed:**
- [ ] ✅ NO (no commits with secrets)
- [ ] ❌ YES (STOP - review git history)

**Temporary Tunnel URL Committed:**
- [ ] ✅ NO (session-only, not in git)
- [ ] ❌ YES (should remove from git)

---

## Issues Found (if any)

### Issue 1:
```
[DESCRIPTION]
Status: [RESOLVED / PENDING / BLOCKING]
Action: [WHAT WAS DONE OR NEEDS TO BE DONE]
```

### Issue 2:
```
[DESCRIPTION]
Status: [RESOLVED / PENDING / BLOCKING]
Action: [WHAT WAS DONE OR NEEDS TO BE DONE]
```

---

## Readiness for Next Phase

### Phase 4B.4: Vercel /api/hvac-staging Route Implementation

**Ready to Proceed:**
- [ ] ✅ YES - all checks passed
- [ ] ❌ NO - blocking issues exist (see above)

**Blockers (if any):**
```
[LIST ANY BLOCKING ISSUES HERE]
```

**Next Step:**
1. Merge this result document
2. Proceed to Phase 4B.4: Create /api/hvac-staging route in Vercel
3. Configure ASKTHIH_STAGING_WEBHOOK_URL in Vercel project settings
4. Deploy to preview environment
5. Run deploy check script
6. Run smoke test (creates Record ID 6)

---

## Tunnel Maintenance

**Tunnel Running:**
- [ ] Keep running (testing in progress)
- [ ] Can stop (testing complete)

**Tunnel Expiration:**
- [ ] Valid for 7 days (Quick Tunnel expiration)
- [ ] Expires: [CALCULATE FROM START DATE]

**Webhook Server:**
- [ ] Keep running (Phase 4B.4 testing)
- [ ] Can stop (Phase 4B.3 complete)

---

## Sign-Off

**Completed by:**
```
[NAME OR IDENTIFIER]
```

**Date/Time Completed:**
```
[REPLACE WITH DATE/TIME]
```

**Status:**
```
[✅ PASSED / ⚠️ PASSED WITH WARNINGS / ❌ FAILED]
```

---

**Next Document:** Phase 4B.4 — Vercel /api/hvac-staging Route Implementation Result

