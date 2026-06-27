# AskTHIH Cloudflare Tunnel Webhook Guardrail

## Critical Correction

**Correction to Phase 4B.2 Plan:**

Cloudflare Tunnel must expose **ONLY the local API-safe webhook**, NOT the full SowerBase/NocoDB application.

**Why:**
- SowerBase/NocoDB should NOT be publicly exposed
- PostgreSQL must remain private
- NocoDB admin UI must not be accessible externally
- Only the narrow webhook bridge should be exposed
- SowerBase API token should never reach browsers

---

## Corrected Staging Architecture

### Approved Flow ✅

```
Vercel Browser
    ↓
Vercel /api/hvac-staging (Node.js function)
    ↓
Cloudflare Tunnel HTTPS URL (webhook-only)
    ↓
localhost:8787 (API-safe HVAC webhook - private)
    ↓
SowerBase/NocoDB API (localhost:18080 - private)
    ↓
PostgreSQL (localhost:5432 - private)
    ↓
Intake Submissions table
    ↓
Record ID 6 created
```

### Component Access

**Public (via Vercel):**
- ✅ https://www.askthih.com/hvac (form interface)
- ✅ POST /api/hvac-staging (webhook submission endpoint)

**Via Cloudflare Tunnel (webhook-only):**
- ✅ https://[tunnel-host]/askthih/hvac (API-safe webhook)
- ❌ NOT: SoverBase UI at localhost:18080
- ❌ NOT: PostgreSQL at localhost:5432
- ❌ NOT: NocoDB admin panel

**Private/Local (no public exposure):**
- ✅ localhost:18080 (SowerBase/NocoDB API)
- ✅ localhost:5432 (PostgreSQL database)
- ✅ localhost:8787 (webhook server)

---

## Not Approved ❌

**These configurations are NOT allowed:**

### 1. Direct NocoDB/SowerBase Tunnel

❌ **NOT APPROVED:**
```
Cloudflare Tunnel → localhost:18080 (SowerBase/NocoDB)
```

**Problems:**
- Exposes SowerBase UI publicly
- Exposes NocoDB admin panel
- Exposes SowerBase API endpoint
- Risks accidental SOWERBASE_API_TOKEN exposure
- Creates broad attack surface

---

### 2. PostgreSQL Tunnel

❌ **NOT APPROVED:**
```
Cloudflare Tunnel → localhost:5432 (PostgreSQL)
```

**Problems:**
- Database directly exposed to internet
- No application layer protection
- SQL injection attacks possible
- Direct database access without audit trail

---

### 3. Client-Side API Token Usage

❌ **NOT APPROVED:**
```javascript
// In browser JavaScript
const response = await fetch(
  'https://sowerbase.tunnel.cloudflare.com/api/v2/...',
  {
    headers: {
      'Authorization': `Bearer ${SOWERBASE_API_TOKEN}`
    }
  }
);
```

**Problems:**
- Exposes SOWERBASE_API_TOKEN to browser
- Token visible in network inspector
- Token stored in client-side code/environment
- Violates secret management principles

---

### 4. NocoDB Admin UI Access

❌ **NOT APPROVED:**
```
https://[tunnel-host]/nc/... (NocoDB admin panel)
```

**Problems:**
- Exposes NocoDB admin interface
- Allows public access to database UI
- Requires authentication but still publicly discovered
- Schema visible to any scanner

---

## Approved Cloudflare Tunnel Approach

### For Staging: Quick Tunnel (Temporary)

**Setup:**
```bash
# On Michael's machine, running the webhook server:
cloudflare_cli tunnel --hostname sowerbase-staging-[random] http://localhost:8787
```

**Characteristics:**
- ✅ No DNS changes
- ✅ Temporary 7-day URL
- ✅ Auto-generated hostname
- ✅ Perfect for proof of concept
- ✅ No configuration persistence needed
- ⚠️ URL changes after 7 days (requires re-deployment)

**Vercel Environment Variable:**
```bash
ASKTHIH_STAGING_WEBHOOK_URL=https://sowerbase-staging-[random].cloudflareaccess.com
```

**When to Use:**
- Phase 4B.3-4 staging test only
- Record ID 6 proof of concept
- Temporary validation before production

---

### For Durable Staging: Named Tunnel

**Setup:**
```bash
# Create named tunnel (persistent)
cloudflare_cli tunnel create askthih-hvac-staging

# Configure tunnel to expose webhook only
# In tunnel config: localhost:8787/askthih/hvac → routing rule

# Deploy tunnel with access policy
```

**Characteristics:**
- ✅ Stable hostname (doesn't change)
- ✅ DNS CNAME to tunnel (optional)
- ✅ Access policies (IP restriction, auth)
- ✅ Persistent logging and monitoring
- ✅ Production-ready (if needed for extended staging)
- ⚠️ Requires Cloudflare account and tunnel management

**Vercel Environment Variable:**
```bash
ASKTHIH_STAGING_WEBHOOK_URL=https://askthih-hvac-staging.example.com
```

**When to Use:**
- Extended staging testing
- Multiple team members need access
- Durable proof before production migration
- Transition to production host

---

## Corrected Environment Variables

### For Vercel Staging (Using Webhook Tunnel)

```bash
# Webhook tunnel endpoint (Cloudflare exposes localhost:8787)
ASKTHIH_STAGING_WEBHOOK_URL=https://sowerbase-staging-[random].cloudflareaccess.com

# Webhook secret (same from Phase 2B)
ASKTHIH_WEBHOOK_SECRET=[32-byte-redacted-secret]

# CORS/origin control
ALLOWED_ORIGINS=https://www.askthih.com,https://askthih.com

# Environment identification
NODE_ENV=staging
ASKTHIH_ENV=staging
```

### NOT Used in Vercel (for Webhook Pattern)

```bash
# DO NOT use these for webhook tunnel pattern:
SOWERBASE_BASE_URL          # ❌ Not needed (webhook handles it)
SOWERBASE_API_TOKEN         # ❌ Not needed (secret, stays private)
SOWERBASE_INTAKE_TABLE_ID   # ❌ Not needed (webhook handles it)
```

### When to Use SOWERBASE_* Variables

**Only if Vercel calls SowerBase API DIRECTLY:**
```bash
# Only approve this if:
# 1. SowerBase is on production/managed host
# 2. Vercel function calls SowerBase/NocoDB API directly
# 3. API token is properly encrypted/isolated

SOWERBASE_PRODUCTION_URL=https://sowerbase-prod.askthih.com
SOWERBASE_API_TOKEN=[production-token-redacted]
SOWERBASE_INTAKE_TABLE_ID=[table-id]
```

**This is NOT the staging pattern. This is the production/direct-API pattern.**

---

## Record ID 6 Creation Criteria (Corrected)

**Record ID 6 may be created ONLY when:**

1. ✅ Local API-safe webhook running at localhost:8787
   ```bash
   .\scripts\askthih-hvac-local-webhook-server.ps1
   ```

2. ✅ Cloudflare Quick Tunnel running, exposing localhost:8787
   ```bash
   cloudflare_cli tunnel --hostname askthih-staging http://localhost:8787
   ```

3. ✅ Tunnel HTTPS URL stable and accessible
   - Example: https://askthih-staging-abc123.cloudflareaccess.com

4. ✅ Vercel /api/hvac-staging created
   - Calls tunnel HTTPS URL at `/askthih/hvac`
   - Includes HMAC-SHA256 signature
   - Includes timestamp

5. ✅ ASKTHIH_STAGING_WEBHOOK_URL configured in Vercel
   - Set to tunnel HTTPS URL
   - Verified to be reachable

6. ✅ Deploy check passes
   ```bash
   .\scripts\askthih-hvac-staging-deploy-check.ps1
   ```
   - Verifies Vercel can reach webhook via tunnel
   - Validates SowerBase reachability from webhook

7. ✅ Smoke test sends signed request to Vercel
   ```bash
   .\scripts\askthih-hvac-staging-smoke-test.ps1
   ```
   - Sends test payload to Vercel /api/hvac-staging
   - Vercel forwards to tunnel webhook URL
   - Webhook validates signature and timestamp
   - Webhook calls SowerBase API

8. ✅ SowerBase receives record
   - Record ID 6 appears in Intake Submissions table
   - All fields preserved
   - Timestamp recorded

9. ✅ Backup succeeds after write
   ```bash
   .\scripts\thih-backup-sowerbase.ps1 -BackupType all
   ```
   - Backup includes Record ID 6
   - Exit code 0

**If any step fails:**
- ❌ Stop and diagnose
- ❌ Do NOT retry Record ID 6 creation
- ❌ Fix root cause first

---

## Cloudflare Tunnel Security Requirements

### What Tunnel MUST Do

✅ **Expose only localhost:8787 (webhook)**
- No NocoDB UI
- No SowerBase API
- No PostgreSQL

✅ **HTTPS/TLS encryption**
- All traffic encrypted end-to-end
- Cloudflare provides certificate

✅ **Tunnel security**
- Token stored securely on local machine
- No tunnel token in logs or config files
- Tunnel process isolated

✅ **Logging and monitoring**
- All requests logged
- Access logging available in Cloudflare dashboard
- Unusual activity alerts

### What Tunnel MUST NOT Do

❌ **Expose SowerBase/NocoDB directly**
- No public access to localhost:18080
- No admin panel exposure
- No schema discovery

❌ **Expose PostgreSQL**
- No direct database access
- No SQL queries from public internet

❌ **Store secrets in tunnel URL**
- SOWERBASE_API_TOKEN not in hostname
- API credentials not in tunnel config
- Credentials remain server-side only

❌ **Expose default credentials**
- NocoDB default admin credentials not accessible
- No anonymous access
- No public signup

---

## Temporary vs Durable Tunnel Decision

### Quick Tunnel (Temporary) ✅ Recommended for Phase 4B.3-4

**When to use:**
- Proof of concept (Record ID 6 test)
- Limited time (7-day validity)
- Single test run
- No persistent URL needed

**Setup:** 1 command
```bash
cloudflare_cli tunnel --hostname askthih-staging http://localhost:8787
```

**Cons:**
- URL changes after 7 days
- Not suitable for extended testing
- Requires re-deployment if testing extends past 7 days

---

### Named Tunnel (Durable) ✅ For Extended Staging

**When to use:**
- Extended staging period (>7 days)
- Multiple team members accessing
- Transition period before production
- Stability required for testing

**Setup:** Multiple commands
```bash
cloudflare_cli tunnel create askthih-hvac-staging
cloudflare_cli tunnel route dns askthih-hvac-staging staging.askthih.com
# Configure tunnel config file
# Deploy with access policies
```

**Pros:**
- Stable URL (doesn't change)
- Persistent configuration
- Access policies and logging
- Can be promoted to production if needed

---

## Vercel Route Implementation (Corrected)

### Correct Pattern: Call Webhook via Tunnel

```javascript
// pages/api/hvac-staging.js (Vercel serverless function)

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Call local API-safe webhook via Cloudflare Tunnel
  const tunnelUrl = process.env.ASKTHIH_STAGING_WEBHOOK_URL;
  const webhookSecret = process.env.ASKTHIH_WEBHOOK_SECRET;

  // Generate signature
  const timestamp = Math.floor(Date.now() / 1000);
  const message = `${timestamp}.${JSON.stringify(req.body)}`;
  const signature = crypto
    .createHmac('sha256', webhookSecret)
    .update(message)
    .digest('hex');

  try {
    // Call webhook via tunnel (NOT direct SowerBase API)
    const response = await fetch(`${tunnelUrl}/askthih/hvac`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Signature ${timestamp}.${signature}`
      },
      body: JSON.stringify(req.body)
    });

    const data = await response.json();
    
    if (response.ok) {
      return res.status(201).json({
        status: 'success',
        message: 'Record created in Intake Submissions',
        record_id: data.record_id,
        timestamp: new Date().toISOString()
      });
    } else {
      return res.status(response.status).json({
        status: 'error',
        message: 'Webhook processing failed'
      });
    }
  } catch (error) {
    console.error('Webhook call failed:', error.message);
    return res.status(500).json({
      status: 'error',
      message: 'Failed to process request'
    });
  }
}
```

### Incorrect Pattern ❌

```javascript
// ❌ DO NOT DO THIS:
// Calling SowerBase API directly via Vercel with exposed token

const response = await fetch(
  `${process.env.SOWERBASE_TUNNEL_URL}/api/v2/tables/...`,
  {
    headers: {
      'Authorization': `Bearer ${process.env.SOWERBASE_API_TOKEN}`
    }
  }
);
```

**Problems:**
- Exposes SowerBase API to Vercel function
- Token visible in function execution
- Multiple layers of exposure
- Complexity without benefit

---

## Safety Confirmations

✅ **No public askthih.com/hvac change**
- Production route untouched
- No user-facing impact

✅ **No DNS change**
- Cloudflare Tunnel doesn't modify DNS
- No nameserver changes
- Existing records intact

✅ **No Airtable change**
- Airtable untouched
- Source of truth unchanged

✅ **No Airtable import**
- Zero migration
- Record ID 6 is test-only

✅ **No Canon connection**
- Canon integration untouched

✅ **THIHskills untouched**
- Skills data unchanged

✅ **No credentials committed**
- Environment vars in Vercel only
- No secrets in git
- Tunnel URLs may be temporary (not secrets)

✅ **Record ID 6 not created yet**
- Awaiting tunnel and Vercel setup
- Created only after prerequisites met

✅ **SowerBase/NocoDB not publicly exposed**
- Only webhook exposed via tunnel
- Tunnel points to localhost:8787 (webhook)
- NOT pointing to localhost:18080 (SowerBase)
- PostgreSQL completely private

---

## Summary

### Corrected Tunnel Approach

| Component | Public? | How Exposed |
|-----------|---------|------------|
| **Vercel /api/hvac-staging** | ✅ | Direct (DNS A record) |
| **Webhook via tunnel** | ✅ | Cloudflare Tunnel HTTPS |
| **SowerBase/NocoDB** | ❌ | Private (no tunnel) |
| **PostgreSQL** | ❌ | Private (no tunnel) |
| **NocoDB Admin UI** | ❌ | Private (no tunnel) |

### Next Step: Phase 4B.3 Setup

When setting up Cloudflare Tunnel:
1. ✅ Expose ONLY localhost:8787 (webhook)
2. ❌ DO NOT expose localhost:18080 (SowerBase)
3. ✅ Verify tunnel HTTPS URL works: `curl https://[tunnel-url]/askthih/hvac`
4. ✅ Use Quick Tunnel for staging (temporary)
5. ✅ Use Named Tunnel only if extended testing needed

---

**Date:** 2026-06-27  
**Latest Develop Commit:** 7f51ea4d21  
**PR #24 Merged:** YES  
**Guardrail Status:** APPROVED  
**SowerBase Exposure:** ❌ NOT exposed  
**Record ID 6:** Not created (awaiting prerequisites)

