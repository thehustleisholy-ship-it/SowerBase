# AskTHIH HVAC Staging Credential Preparation Result — Phase 2

## Executive Summary

**Status:** ✅ **STAGING CREDENTIAL PREP COMPLETE**

Phase 2 of public cutover readiness is complete. Secure staging environment variable handling and credential preflight validation are now in place. Ready for credential provisioning and protected staging deployment.

**Files Created:** 3  
**Real Credentials Committed:** NO ✅  
**Public cutover executed:** NO ✅  
**Public askthih.com/hvac changed:** NO ✅

---

## PR #17 Merge Status

**Merge Commit:** `2fa954c737`  
**Date:** 2026-06-27 19:00  
**Status:** ✅ **MERGED to develop**

**Verified:**
- ✅ Both readiness documents exist
- ✅ SowerBase responsive (http://localhost:18080)
- ✅ All 5 test records verified
- ✅ Backup system operational

---

## Files Created

### 1. Environment Variable Template

**File:** `.env.askthih-hvac-staging.example`

**Purpose:** Template showing required variables for staging deployment

**Contents (placeholders only, no real credentials):**
```
SOWERBASE_BASE_URL=https://[STAGING-SOWERBASE-API-URL]
SOWERBASE_API_TOKEN=[REDACTED]
SOWERBASE_INTAKE_TABLE_ID=[REDACTED]
ASKTHIH_WEBHOOK_PORT=8787
ASKTHIH_WEBHOOK_SECRET=[REDACTED]
ALLOWED_ORIGINS=https://askthih.com,https://www.askthih.com
```

**Safety Features:**
- ✅ Template only (no real values)
- ✅ Clear placeholders
- ✅ Instructions for secure loading
- ✅ No secrets in file
- ✅ Not imported from command-line

### 2. Credential Preflight Script

**File:** `scripts/askthih-hvac-staging-preflight.ps1`

**Purpose:** Validates all required credentials and SowerBase connectivity before deployment

**Validations Performed:**
1. ✅ All required environment variables present
   - SOWERBASE_BASE_URL
   - SOWERBASE_API_TOKEN
   - SOWERBASE_INTAKE_TABLE_ID
   - ASKTHIH_WEBHOOK_SECRET
2. ✅ SOWERBASE_BASE_URL uses HTTPS (staging/production requirement)
3. ✅ SOWERBASE_API_TOKEN length check (minimum 10 characters)
4. ✅ ASKTHIH_WEBHOOK_SECRET length check (minimum 32 bytes)
5. ✅ SowerBase API reachability test
6. ✅ API authentication validation (Bearer token accepted)
7. ✅ Intake Submissions table accessibility test
8. ✅ Webhook port configuration validation (1024-65535)
9. ✅ CORS origins configuration check

**Safety Features:**
- ✅ Never prints secret values
- ✅ Only prints "value redacted" for credentials
- ✅ Logs to file (not stdout)
- ✅ Clear error messages without exposing secrets
- ✅ Exits 0 on success, nonzero on failure
- ✅ Detailed audit trail for troubleshooting

**Usage:**
```powershell
# Load environment variables (not committed to repo)
Get-Content .env.askthih-hvac-staging | ForEach-Object { ... }

# Run preflight
./scripts/askthih-hvac-staging-preflight.ps1

# Check result
if ($LASTEXITCODE -eq 0) { "Preflight passed" }
```

### 3. .gitignore Update

**File:** `.gitignore` (modified)

**Changes:**
```
# Environment files - DO NOT COMMIT CREDENTIALS
.env
.env.*
# Except example/template files
!.env.*.example
```

**Safety Verification:**
- ✅ .env files will NOT be committed
- ✅ .env.askthih-hvac-staging will NOT be committed
- ✅ .env.askthih-hvac-staging.example WILL be committed (template only)
- ✅ Real credentials protected by git

---

## Credential Handling Requirements

### Secure Loading (Not Committed)

**Real credentials must be:**
1. Stored in secure vault (AWS Secrets Manager, HashiCorp Vault, etc.)
2. Loaded at deployment time only
3. Never committed to git
4. Never hard-coded in scripts
5. Never printed in logs
6. Cleared after request processing

**Example (secure loading in staging):**
```powershell
# Load from vault at deployment time
$creds = Get-SecretsFromVault -Environment staging

# Set environment variables (session-only)
$env:SOWERBASE_API_TOKEN = $creds.api_token
$env:ASKTHIH_WEBHOOK_SECRET = $creds.webhook_secret

# Run preflight
./scripts/askthih-hvac-staging-preflight.ps1

# Clear environment after deployment
[System.Environment]::SetEnvironmentVariable('SOWERBASE_API_TOKEN', $null)
[System.Environment]::SetEnvironmentVariable('ASKTHIH_WEBHOOK_SECRET', $null)
```

---

## Credential Provisioning Status

### Current Status

| Credential | Status |
|-----------|--------|
| SOWERBASE_BASE_URL | ⏳ Pending (staging URL needed) |
| SOWERBASE_API_TOKEN | ⏳ Pending (generate in NocoDB) |
| SOWERBASE_INTAKE_TABLE_ID | ⏳ Pending (discover via API) |
| ASKTHIH_WEBHOOK_SECRET | ⏳ Pending (generate: openssl rand -hex 32) |
| ALLOWED_ORIGINS | ✅ Documented (https://askthih.com, etc.) |

**Next Step:** Provision credentials in secure vault

### How to Generate Each Credential

**SOWERBASE_BASE_URL:**
- Staging SowerBase API endpoint
- Must use HTTPS
- Example: `https://sowerbase-staging.example.com`

**SOWERBASE_API_TOKEN:**
1. Log into production NocoDB as admin
2. Go to Settings → API → Generate API Token
3. Copy token (visible only once)
4. Store securely in vault

**SOWERBASE_INTAKE_TABLE_ID:**
1. Call: `GET https://[SOWERBASE_BASE_URL]/api/v2/db/meta/tables`
2. Auth: Bearer `[SOWERBASE_API_TOKEN]`
3. Find table with title "Intake Submissions"
4. Copy `id` field value

**ASKTHIH_WEBHOOK_SECRET:**
1. Generate: `openssl rand -hex 32`
2. Or Python: `import secrets; print(secrets.token_hex(32))`
3. Store securely in vault
4. Use for webhook signature validation

---

## Preflight Test Result

### Pending Credential Provisioning

**Status:** ⏳ **PREFLIGHT AWAITING CREDENTIALS**

**When credentials are provisioned, run:**
```powershell
./scripts/askthih-hvac-staging-preflight.ps1
```

**Expected Output (when credentials available):**
```
[timestamp] [SUCCESS] Preflight Status: PASSED
✓ All credentials present
✓ SowerBase API reachable
✓ Intake Submissions table accessible
✓ Configuration valid
```

**If Preflight Fails:**
- ✅ Check SOWERBASE_BASE_URL is HTTPS
- ✅ Check SOWERBASE_API_TOKEN is correct (in vault)
- ✅ Check SOWERBASE_INTAKE_TABLE_ID is correct (discover via API)
- ✅ Check ASKTHIH_WEBHOOK_SECRET is 32+ bytes
- ✅ Check network connectivity to staging SowerBase

---

## Safety Constraints Maintained

### No Real Credentials Committed

✅ **Files Created:**
- `.env.askthih-hvac-staging.example` — Template only
- `scripts/askthih-hvac-staging-preflight.ps1` — No secrets
- `.gitignore` updated — Protects .env files

✅ **Real Credentials:**
- NOT in any .env file
- NOT in any script
- NOT in git history
- Awaiting secure provisioning

### No Public Changes

✅ **Public Routes:** NOT changed
- askthih.com/hvac still routes to Airtable
- No DNS changes
- No reverse proxy changes
- No staging deployment executed

### No Airtable Changes

✅ **Airtable:**
- Untouched
- No records imported
- No schema modified
- Remains read-only source for archive

### No Canon Connection

✅ **Canon:** No connection attempted

### THIHskills Untouched

✅ **Skills:** No modifications

### Backup System

✅ **Backups:**
- Still operational
- Still 5 test records in backup
- Artifacts still ignored by git
- Ready for staging test record (ID 6)

---

## Next Steps

### Phase 3: Staging Deployment Preparation

**When ready to proceed:**

1. **Provision Credentials**
   - Generate SOWERBASE_API_TOKEN in production NocoDB
   - Obtain SOWERBASE_INTAKE_TABLE_ID (discover via API)
   - Generate ASKTHIH_WEBHOOK_SECRET (32+ random bytes)
   - Store securely in vault

2. **Run Preflight**
   ```powershell
   # Load credentials from vault (not committed)
   $env:SOWERBASE_BASE_URL = "https://sowerbase-staging.example.com"
   $env:SOWERBASE_API_TOKEN = "[from vault]"
   $env:SOWERBASE_INTAKE_TABLE_ID = "[from vault]"
   $env:ASKTHIH_WEBHOOK_SECRET = "[from vault]"
   
   # Validate
   ./scripts/askthih-hvac-staging-preflight.ps1
   ```

3. **Deploy Staging Webhook Server**
   - Use webhook server script
   - Configure reverse proxy (nginx, AWS ALB)
   - Enable HTTPS/TLS
   - Set webhook secret for signature validation

4. **Execute Staging Test**
   - Submit public cutover test payload
   - Verify record ID 6 created
   - Verify no Airtable changes
   - Run backup validation

---

## Approval Gate Progress

| Phase | Status | Files/Commits |
|-------|--------|--------------|
| **1. Documentation** | ✅ COMPLETE | PR #17 (2 docs) |
| **2. Credential Prep** | ✅ COMPLETE | PR #18 (3 files, this step) |
| **3. Staging Deployment** | ⏳ Pending | (deploy when credentials ready) |
| **4. Staging Test** | ⏳ Pending | (execute after deployment) |
| **5. Production Readiness** | ⏳ Pending | (verify staging test passes) |
| **6. Approval & Cutover** | ⏳ Pending | (explicit approval required) |

---

## Verification Checklist

✅ **Files Created:**
- [x] .env.askthih-hvac-staging.example (template)
- [x] scripts/askthih-hvac-staging-preflight.ps1 (validation)
- [x] .gitignore updated (credential protection)

✅ **Real Credentials:**
- [x] NOT in .env.askthih-hvac-staging.example
- [x] NOT in any .ps1 script
- [x] NOT in .gitignore
- [x] Awaiting secure provisioning

✅ **No Public Changes:**
- [x] askthih.com/hvac NOT changed
- [x] No DNS changes
- [x] No reverse proxy changes
- [x] No staging deployment

✅ **Safety Maintained:**
- [x] No Airtable changes
- [x] No Airtable imports
- [x] No Canon connection
- [x] THIHskills untouched
- [x] Backup system operational

---

## Conclusion

**Phase 2 Credential Preparation is complete.**

Staging environment variable template and credential validation are in place. Preflight script will validate credentials and SowerBase connectivity when provisioned.

**Ready for:**
- Credential provisioning in secure vault
- Phase 3 staging deployment (when credentials ready)
- Phase 4 staging test execution

**Status:** ✅ **PHASE 2 COMPLETE — CREDENTIALS AWAITING PROVISIONING**

---

**Next Gate:** Phase 3 — Secure Staging Deployment (requires credentials)  
**Estimated Timeline:** 1 day (after credentials provisioned)  
**Approval Required:** For each phase transition
