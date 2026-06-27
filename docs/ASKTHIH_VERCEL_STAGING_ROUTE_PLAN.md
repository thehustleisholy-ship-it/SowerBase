# AskTHIH Vercel Staging Route Implementation Plan

## Current Finding

✅ **askthih.com is hosted on Vercel**
- Confirmed via HTTP headers: `Server: Vercel`
- Confirmed via DNS: `ns1.vercel-dns.com`, `ns2.vercel-dns.com`
- Confirmed via framework: Next.js App Router detected

✅ **Option C is compatible**
- Vercel supports all required capabilities
- No DNS changes needed
- Same platform for both public and staging
- Native environment variable support

✅ **Public askthih.com/hvac remains unchanged**
- Production route untouched
- New staging route: `/api/hvac-staging`
- No public-facing changes

---

## Critical Reachability Blocker

### The Problem

**Vercel serverless functions cannot call Michael's local Windows machine at http://localhost:18080.**

**Why:**
- Michael's machine is local/private (no public IP)
- Vercel functions run in Vercel's infrastructure (US/EU data centers)
- No network tunnel from Vercel to Michael's machine exists
- `localhost` is meaningless from a Vercel function (refers to Vercel's container, not Michael's machine)

**Therefore:**
- ❌ `SOWERBASE_BASE_URL=http://localhost:18080` will NOT work in Vercel
- ✅ Must use an HTTPS endpoint reachable from Vercel's infrastructure
- ✅ SowerBase must be accessible through a public/reachable path

### Current State

**Local Testing (Phase 2B, Phase 3):** ✅ Works
- Preflight script on local machine
- Local credentials provisioned
- Local SowerBase at http://localhost:18080
- Local webhook at localhost:8787

**Vercel Deployment (Phase 4B.2+):** ❌ Does NOT work
- Vercel cannot call Michael's localhost
- Need reachable HTTPS endpoint
- Need SowerBase accessible from Vercel's infrastructure

---

## Approved SowerBase Reachability Options

### Option 1: Deploy SowerBase to Production Host

**Concept:**
Deploy SowerBase (NocoDB + PostgreSQL) to a managed or self-hosted production environment accessible via HTTPS.

**Examples:**
- Railway.app (managed platform)
- Render.com (managed platform)
- AWS RDS + NocoDB (hybrid)
- DigitalOcean (self-hosted)
- Hetzner (self-hosted)

**Requirements:**
- HTTPS endpoint (e.g., https://sowerbase.askthih.com)
- Database persistence (PostgreSQL)
- Backup strategy
- Authentication/authorization
- Monitoring and logging

**Timeline:** 2-4 days
**Cost:** $15-100+/month depending on scale
**Best For:** Long-term, production-ready deployment
**Risk Level:** Medium (new infrastructure, requires maintenance)

**Advantages:**
- ✅ Durable, production-grade
- ✅ Vercel can reliably connect
- ✅ Backup/restore independent
- ✅ Scalable for future growth
- ✅ No local machine dependency

**Disadvantages:**
- ⚠️ Higher setup effort
- ⚠️ Ongoing maintenance required
- ⚠️ Additional monthly cost
- ⚠️ New operational complexity

---

### Option 2: Cloudflare Tunnel to Local SowerBase (RECOMMENDED for Staging)

**Concept:**
Use Cloudflare Tunnel to expose local SowerBase endpoint securely from Michael's machine to Vercel.

**Flow:**
```
Vercel /api/hvac-staging
    ↓
https://sowerbase-staging.your-tunnel.cloudflare.com (public tunnel endpoint)
    ↓
Cloudflare Tunnel client (on Michael's machine)
    ↓
localhost:18080 (local SowerBase)
```

**Requirements:**
- Cloudflare account (free or paid)
- Cloudflare Tunnel client running on Michael's machine
- Tunnel subdomain
- Keep local SowerBase running

**Timeline:** 30 minutes
**Cost:** $0-20/month (free tier adequate)
**Best For:** Fast staging test, temporary bridge
**Risk Level:** Low (Cloudflare handles security)

**Advantages:**
- ✅ Fastest setup (~30 minutes)
- ✅ No infrastructure deployment needed
- ✅ Cloudflare handles HTTPS/security
- ✅ Local machine remains control point
- ✅ Easy to test and iterate
- ✅ No new server to maintain
- ✅ Works with existing Cloudflare setup (if any)

**Disadvantages:**
- ⚠️ Requires local machine to stay on/tunnel running
- ⚠️ Temporary (not production-ready)
- ⚠️ Tunnel security depends on Cloudflare
- ⚠️ Not suitable for 24/7 uptime
- ⚠️ Local machine becomes hard dependency

---

### Option 3: VPS-Hosted SowerBase/API Bridge

**Concept:**
Deploy SowerBase or an API bridge to a VPS (Virtual Private Server).

**Examples:**
- DigitalOcean Droplet ($5-50/month)
- Linode ($5-20/month)
- AWS EC2 ($10-100/month)
- Vultr ($5-50/month)

**Requirements:**
- VPS provisioning
- Docker + NocoDB deployment
- PostgreSQL database
- Nginx reverse proxy
- TLS certificate (Let's Encrypt free)
- SSH key management
- Firewall configuration

**Timeline:** 2-3 hours
**Cost:** $5-50/month
**Best For:** Medium-term, owned infrastructure
**Risk Level:** Medium (requires server management)

**Advantages:**
- ✅ Full control of infrastructure
- ✅ Durable and reliable
- ✅ Moderate cost
- ✅ Portable (can migrate between VPS providers)
- ✅ Independent from Cloudflare/other vendors

**Disadvantages:**
- ⚠️ Requires server management skills
- ⚠️ Security patch maintenance needed
- ⚠️ Operational overhead
- ⚠️ TLS certificate renewal automation required

---

### Option 4: Vercel Route Writes to Temporary Queue/Storage

**Concept:**
Vercel route writes to a temporary storage (Redis, S3, etc.) that later syncs to SowerBase.

**Not Approved** because:
- ❌ Doesn't satisfy "Record ID 6 in SowerBase immediately" requirement
- ❌ Adds complexity and latency
- ❌ Only acceptable as emergency fallback
- ❌ Smoke test requires immediate SowerBase confirmation

---

## Recommended Reachability Lane

### For Phase 4B.2 (Immediate Staging Test):

### **RECOMMENDED: Option 2 — Cloudflare Tunnel**

**Why:**
1. ✅ **Fastest deployment** (30 minutes vs. 2-4 hours or 2-4 days)
2. ✅ **No infrastructure setup** needed
3. ✅ **No monthly cost** (free tier adequate)
4. ✅ **Vercel can reach SowerBase** immediately
5. ✅ **Staging test can run today**
6. ✅ **Easy to remove** when no longer needed

**Implementation:**
```
Michael's Machine (Windows):
  └─ SowerBase at localhost:18080
  └─ Cloudflare Tunnel client running
     (exposes to sowerbase-staging.your-tunnel.cloudflare.com)

Vercel Function (/api/hvac-staging):
  ├─ Receives form submission from browser
  ├─ Calls SowerBase via tunnel HTTPS endpoint
  └─ Returns Record ID 6 confirmation

Record ID 6 Created:
  └─ In SowerBase Intake Submissions table
```

### For Phase 5+ (Production Readiness):

### **RECOMMENDED FOR PRODUCTION: Option 1 — Managed/Production Host**

**Why:**
1. ✅ **Production-grade** (not temporary)
2. ✅ **Always-on** (not dependent on Michael's machine)
3. ✅ **Independently backed up**
4. ✅ **Scalable** for growing traffic
5. ✅ **Maintainable** long-term

**Timeline:**
- Evaluate managed platforms (Railway, Render)
- Deploy SowerBase to production host
- Migrate data from local to production
- Update Vercel environment variables
- Test full production flow
- Execute public cutover

---

## Vercel Route Design: /api/hvac-staging

### Route Specification

**Endpoint:**
```
POST /api/hvac-staging
```

**Authorization:**
```
Header: Authorization: Signature <timestamp>.<hmac-sha256>
```

**Request Payload:**
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

**Response (201 Created):**
```json
{
  "status": "success",
  "message": "Record created in Intake Submissions",
  "record_id": 6,
  "timestamp": "2026-06-27T17:11:15Z"
}
```

**Response (400 Bad Request):**
```json
{
  "status": "error",
  "message": "Request validation failed"
}
```

**Response (401 Unauthorized):**
```json
{
  "status": "error",
  "message": "Authentication required"
}
```

---

### Route Implementation Pseudocode

```javascript
// pages/api/hvac-staging.js (Next.js API route)

export default async function handler(req, res) {
  // 1. Method validation
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // 2. Content-type validation
  if (req.headers['content-type'] !== 'application/json') {
    return res.status(400).json({ error: 'JSON required' });
  }

  // 3. Signature validation
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Signature ')) {
    return res.status(401).json({ error: 'Signature required' });
  }

  const [timestamp, signature] = authHeader.slice(10).split('.');
  const message = `${timestamp}.${JSON.stringify(req.body)}`;
  const expected = crypto
    .createHmac('sha256', process.env.ASKTHIH_WEBHOOK_SECRET)
    .update(message)
    .digest('hex');

  if (signature !== expected) {
    return res.status(401).json({ error: 'Invalid signature' });
  }

  // 4. Timestamp validation (±300 seconds)
  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - parseInt(timestamp)) > 300) {
    return res.status(401).json({ error: 'Request too old' });
  }

  // 5. Payload validation
  const required = [
    'submission_title', 'vertical', 'contact_name', 'phone',
    'email', 'service_address', 'problem_description'
  ];
  for (const field of required) {
    if (!req.body[field]) {
      return res.status(400).json({ error: `Missing: ${field}` });
    }
  }

  // 6. Call SowerBase API
  try {
    const sowerbaseUrl = process.env.SOWERBASE_TUNNEL_URL; // Cloudflare tunnel endpoint
    const response = await fetch(`${sowerbaseUrl}/api/v2/tables/...`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.SOWERBASE_API_TOKEN}`
      },
      body: JSON.stringify({
        // Map form fields to SowerBase table columns
        ...req.body
      })
    });

    const data = await response.json();
    if (!response.ok) throw new Error(data.message);

    // 7. Return success with record ID
    return res.status(201).json({
      status: 'success',
      message: 'Record created in Intake Submissions',
      record_id: data.id,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    // 8. Safe error response (no stack traces)
    console.error('SowerBase API error:', error.message);
    return res.status(500).json({
      status: 'error',
      message: 'Failed to create record'
    });
  }
}
```

---

## Required Vercel Environment Variables

### Staging Environment (Preview/Testing)

```bash
# SowerBase Connection
SOWERBASE_TUNNEL_URL=https://sowerbase-staging.your-tunnel.cloudflare.com
SOWERBASE_API_TOKEN=[staging-api-token]
SOWERBASE_INTAKE_TABLE_ID=[table-id-from-sowerbase]

# Webhook Authentication
ASKTHIH_WEBHOOK_SECRET=[32-byte-secret-redacted]

# CORS/Origin Control
ALLOWED_ORIGINS=https://www.askthih.com,https://askthih.com

# Environment Identification
NODE_ENV=staging
ASKTHIH_ENV=staging
```

### Production Environment (After Cutover Approval)

```bash
# SowerBase Connection (upgraded from tunnel to production host)
SOWERBASE_PRODUCTION_URL=https://sowerbase-prod.askthih.com
SOWERBASE_API_TOKEN=[production-api-token]
SOWERBASE_INTAKE_TABLE_ID=[table-id-from-sowerbase]

# Webhook Authentication (same for both environments)
ASKTHIH_WEBHOOK_SECRET=[same-32-byte-secret]

# CORS/Origin Control
ALLOWED_ORIGINS=https://www.askthih.com,https://askthih.com

# Environment Identification
NODE_ENV=production
ASKTHIH_ENV=production
```

### Secret Placement Strategy

1. **Add to Vercel Project Settings (not in code)**
   - Go to Vercel dashboard
   - Project → Settings → Environment Variables
   - Add each secret separately
   - Mark as "Preview" environment first

2. **Test in Preview/Staging Environment**
   - Deploy to preview branch first
   - Run deploy check script
   - Run smoke test (Record ID 6)
   - Verify SowerBase record created

3. **Promote to Production Environment**
   - Only after Phase 5 approval
   - Update production URL
   - Deploy to production branch
   - Execute public cutover

4. **Never:**
   - ❌ Commit to `.env` file
   - ❌ Include in git repository
   - ❌ Print in logs or responses
   - ❌ Expose in client-side code

---

## Record ID 6 Creation Criteria

**Record ID 6 may be created only after ALL of the following:**

1. ✅ Vercel `/api/hvac-staging` route exists and deployed
2. ✅ SowerBase is reachable from Vercel (Cloudflare Tunnel OR production host)
3. ✅ `SOWERBASE_TUNNEL_URL` or `SOWERBASE_PRODUCTION_URL` configured in Vercel
4. ✅ `SOWERBASE_API_TOKEN` and `SOWERBASE_INTAKE_TABLE_ID` configured
5. ✅ `ASKTHIH_WEBHOOK_SECRET` configured (same 32-byte secret from Phase 2B)
6. ✅ Deploy check script passes (validates all environment variables)
7. ✅ Smoke test sends signed payload to Vercel `/api/hvac-staging`
8. ✅ Vercel route forwards to SowerBase successfully
9. ✅ SowerBase Intake Submissions table receives the record
10. ✅ Record ID 6 appears in SowerBase with all fields intact
11. ✅ Backup succeeds after record write

**If any prerequisite fails:**
- ❌ Record ID 6 NOT created
- ❌ Stop and diagnose
- ❌ Fix issue before retrying

---

## Safety Confirmations

✅ **No public askthih.com/hvac change**
- Production route unchanged
- No user-facing impact
- Staging route isolated to /api/hvac-staging

✅ **No DNS change**
- Cloudflare Tunnel doesn't modify DNS
- Vercel DNS unchanged
- Existing records intact

✅ **No Airtable change**
- Airtable remains source of truth
- No data imported
- No schema modified

✅ **No Airtable import**
- Migration only for staging test
- No bulk import
- Record ID 6 is test-only

✅ **No Canon connection**
- Canon integration untouched
- No Canon data accessed

✅ **THIHskills untouched**
- Skills data/configuration unchanged

✅ **No credentials committed**
- Environment variables in Vercel only
- No secrets in git
- No .env files committed

✅ **Record ID 6 not created yet**
- Awaiting Vercel implementation
- Awaiting SowerBase reachability decision
- Created only after all prerequisites met

---

## Implementation Roadmap

### Phase 4B.2 (This Phase): Planning ✅
- [x] Identify askthih.com platform (Vercel)
- [x] Identify reachability blocker (localhost unreachable)
- [x] Evaluate reachability options (4 options analyzed)
- [x] Recommend staging path (Cloudflare Tunnel)
- [x] Recommend production path (Managed host)
- [x] Design /api/hvac-staging route
- [ ] Create this implementation plan document

### Phase 4B.3 (Next): Setup SowerBase Reachability ⏳
- [ ] Michael sets up Cloudflare Tunnel (staging)
- [ ] Tunnel exposes SowerBase to https://sowerbase-staging.tunnel.cloudflare.com
- [ ] Tunnel runs on Michael's machine continuously

### Phase 4B.4 (After Setup): Vercel Route Deployment ⏳
- [ ] Michael accesses Vercel project
- [ ] Creates /api/hvac-staging route (copy /api/hvac, modify for SowerBase)
- [ ] Adds environment variables to Vercel project settings
- [ ] Tests in preview environment first

### Phase 4B.5 (Final): Execute Phase 4 Test ⏳
- [ ] Run deploy check script (validates Vercel can reach SowerBase)
- [ ] Run smoke test script (creates Record ID 6)
- [ ] Verify Record ID 6 in SowerBase Intake Submissions
- [ ] Run backup validation
- [ ] Report Phase 4 completion

### Phase 5 (Production): Upgrade SowerBase ⏳
- [ ] Deploy SowerBase to production host (Railway, Render, etc.)
- [ ] Migrate data from local to production
- [ ] Update Vercel production environment variables
- [ ] Update /api/hvac route to use production SowerBase
- [ ] Execute production cutover

---

## Conclusion

**Option C is viable and ready for implementation.**

**Next Steps:**
1. ✅ Approve Cloudflare Tunnel for staging (Phase 4B.3)
2. ✅ Approve managed platform for production (Phase 5)
3. ⏳ Michael sets up Cloudflare Tunnel
4. ⏳ Michael creates /api/hvac-staging in Vercel
5. ⏳ Michael deploys environment variables
6. ⏳ Execute Phase 4 staging test (Record ID 6)
7. ⏳ Proceed to Phase 5 production readiness

---

**PR #23 Merge Commit:** c5cdc70dc6  
**Latest Develop Commit:** c5cdc70dc6  
**Phase 4B.1 Status:** ✅ COMPLETE  
**Phase 4B.2 Status:** ⏳ PLANNING  
**Recommended SowerBase Reachability:** Cloudflare Tunnel (staging), Managed Host (production)  
**Record ID 6:** Not created yet (awaiting prerequisites)  
**Public askthih.com/hvac:** ✅ Unchanged

