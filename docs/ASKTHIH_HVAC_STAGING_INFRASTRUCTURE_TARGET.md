# AskTHIH HVAC — Staging Infrastructure Target Selection

## Executive Summary

**Phase 4A Goal:** Select the staging infrastructure lane for the real protected HTTPS route before attempting Phase 4 execution.

**Status:** ⏸️ **AWAITING INFRASTRUCTURE SELECTION**

**Decision Needed:** Which staging infrastructure option best fits AskTHIH's current setup and deployment model?

---

## Current Blocker

**Phase 4 Cannot Execute Because:**
- ❌ No protected HTTPS route exists for `/hvac-staging`
- ❌ https://askthih.com/hvac-staging is documented but not deployed
- ❌ Reverse proxy or API bridge not configured
- ❌ Staging credentials not provisioned to any infrastructure

**What Exists:**
- ✅ API-safe webhook server (localhost:8787)
- ✅ SowerBase/NocoDB database (http://localhost:18080)
- ✅ Phase 3 deployment documentation and scripts
- ✅ Deploy check script (validates environment)
- ✅ Smoke test script (sends Record ID 6 test)
- ✅ Nginx configuration template (example)

**What's Needed:**
- 🚀 Real staging route with HTTPS protection
- 🔒 Reverse proxy or API bridge
- 🔑 Secure credential provisioning
- 📊 Public access control (rate limiting, CORS)
- 🔐 Private webhook protection

---

## Staging Route Objective

**Goal:** Create a protected HTTPS route that receives HVAC staging submissions and forwards them to the private API-safe webhook.

**Flow:**
```
Public HTTPS Request
    ↓
https://askthih.com/hvac-staging (staging route)
    ↓
Reverse Proxy / API Bridge
    - HTTPS/TLS validation
    - Rate limiting (10 req/sec)
    - CORS origin checks
    - Security headers
    ↓
localhost:8787 (private webhook)
    - Signature validation (HMAC-SHA256)
    - Timestamp validation
    - Payload validation
    ↓
SowerBase/NocoDB API
    ↓
Intake Submissions (Record ID 6 expected)
```

**Requirements:**
- ✅ HTTPS/TLS only (min TLS 1.2)
- ✅ Webhook secret validation (HMAC-SHA256)
- ✅ Timestamp validation (±300 seconds)
- ✅ Rate limiting (10 req/sec per IP)
- ✅ CORS origin restrictions (askthih.com only)
- ✅ Request size limits (10 KB)
- ✅ localhost:8787 remains private (not internet-facing)
- ✅ SowerBase remains private (not internet-facing)

---

## Option A: Cloudflare Tunnel

### Overview
Use Cloudflare's tunnel service to create a protected HTTPS route without exposing local webhook server or SowerBase to public internet.

### Requirements
- Cloudflare account (free or paid)
- Cloudflare nameserver pointing at askthih.com (or DNS delegation)
- Cloudflare Tunnel client running locally
- Domain: askthih.com (existing)
- Route: https://askthih.com/hvac-staging

### Architecture
```
Public HTTPS Request (https://askthih.com/hvac-staging)
    ↓
Cloudflare Edge (DDoS protection, rate limiting, WAF)
    ↓
Cloudflare Tunnel (encrypted to local client)
    ↓
Local Tunnel Client
    ↓
localhost:8787 (private webhook)
    ↓
SowerBase/NocoDB API (localhost:18080, private)
    ↓
Database
```

### Benefits
✅ **No server management** — Cloudflare handles infrastructure
✅ **Zero trust tunneling** — Webhook stays completely private
✅ **Built-in DDoS protection** — Cloudflare edge handles attacks
✅ **Built-in WAF** — Web application firewall included
✅ **Rate limiting** — Native Cloudflare rate limiting rules
✅ **No DNS record pointing to webhook** — Complete privacy
✅ **SSL/TLS included** — Automatic certificate renewal
✅ **Global CDN** — Fast response from edge servers
✅ **Fast setup** — ~15 minutes configuration
✅ **No firewall changes needed** — Outbound connection only

### Risks & Concerns
⚠️ **Cloudflare dependency** — If Cloudflare is down, staging route fails
⚠️ **Cost** — Free tier has limits; paid tiers $20+/month
⚠️ **DNS changes** — Requires pointing askthih.com nameservers to Cloudflare
⚠️ **Configuration complexity** — Tunnel authentication, firewall rules
⚠️ **Rate limiting per IP not per endpoint** — May need WAF rules
⚠️ **Vendor lock-in** — Difficult to migrate away later
⚠️ **Free tier limitations** — 30-day log retention, limited analytics

### DNS Changes Required
**Yes** — Significant: Cloudflare must be nameserver for askthih.com

**Process:**
1. Point askthih.com nameservers to Cloudflare (ns1.cloudflare.com, ns2.cloudflare.com)
2. Or use CNAME delegation for specific subdomains
3. Takes 24-48 hours for DNS propagation

**Impact:**
- ⚠️ **Risk:** If Cloudflare nameservers are misconfigured, entire askthih.com fails
- ✅ **Benefit:** Can manage all DNS through Cloudflare dashboard

### SowerBase Privacy
**Status:** ✅ **PRIVATE**

SowerBase remains accessible only from local network. Cloudflare Tunnel does NOT expose SowerBase to public internet. Only webhook server is tunneled.

### Setup Complexity
**Estimated Time:** 15-30 minutes

**Steps:**
1. Create Cloudflare account (if needed)
2. Add askthih.com domain to Cloudflare
3. Update nameservers at domain registrar (24-48 hour wait)
4. Install Cloudflare Tunnel client locally
5. Create tunnel configuration (routes localhost:8787 → askthih.com/hvac-staging)
6. Configure Cloudflare WAF rules for rate limiting
7. Test with deploy check and smoke test

### Estimated Cost
- **Free tier:** $0/month (with limitations)
  - 1 tunnel allowed
  - 30-day log retention
  - Limited analytics
  - Adequate for staging test

- **Pro tier:** $20/month
  - Unlimited tunnels
  - Better analytics
  - Advanced WAF rules
  - Recommended for long-term use

- **Business tier:** $200/month
  - Enterprise features
  - Priority support
  - Probably overkill for staging

### Recommended For
✅ Fast staging deployment without infrastructure
✅ Maximum security (no exposed IPs)
✅ Budget-conscious approach (free tier works)
✅ Low operational overhead

### Not Recommended For
❌ Requires existing Cloudflare setup (DNS changes risky)
❌ Organizations that disallow third-party CDN
❌ Scenarios requiring isolated infrastructure control

---

## Option B: VPS + Nginx Reverse Proxy

### Overview
Deploy a reverse proxy server (nginx) on a VPS to protect the local webhook server behind HTTPS.

### Requirements
- VPS provider (DigitalOcean, AWS EC2, Linode, etc.)
- Domain: askthih.com with DNS A record
- TLS certificate (Let's Encrypt free, or paid)
- Nginx reverse proxy configuration
- Firewall rules (allow 443, restrict 8787)
- SSH access for management
- Estimated cost: $5-50/month depending on traffic

### Architecture
```
Public HTTPS Request (https://askthih.com/hvac-staging)
    ↓
VPS IP (1.2.3.4)
    ↓
Nginx Reverse Proxy (HTTPS termination)
    - Rate limiting (10 req/sec)
    - Security headers
    - CORS validation
    ↓
Local Network Tunnel or SSH Port Forward
    ↓
localhost:8787 (private webhook)
    ↓
SowerBase/NocoDB API (localhost:18080, private)
    ↓
Database
```

### Benefits
✅ **Full control** — Complete infrastructure ownership
✅ **Cost effective** — $5-50/month depending on provider
✅ **Standard tooling** — Nginx is well-documented, proven
✅ **Configuration template provided** — Phase 3 nginx example ready
✅ **No third-party dependency** — Managed by you
✅ **Scalable** — Can add more routes/services easily
✅ **Portable** — Can migrate between providers easily
✅ **Debugging transparency** — Full access to logs and configs

### Risks & Concerns
⚠️ **Server management** — You handle security patches, updates
⚠️ **Certificate renewal** — Must automate Let's Encrypt renewal
⚠️ **DDoS protection** — Must implement yourself or use WAF
⚠️ **Network tunnel complexity** — Need SSH port forward or private link
⚠️ **Public IP exposure** — Reverse proxy IP must be public (no anonymity)
⚠️ **Firewall management** — Must configure and maintain firewall rules
⚠️ **Server hardening** — SSH keys, security groups, fail2ban
⚠️ **Operational overhead** — You manage uptime, patches, monitoring

### DNS Changes Required
**Minimal** — Add/update A record for askthih.com or subdomain

**Process:**
1. Create DNS A record pointing askthih.com/hvac-staging → VPS IP (1.2.3.4)
2. Wait 5 minutes for DNS propagation
3. No nameserver changes needed

**Impact:**
- ✅ **Benefit:** Minimal DNS risk
- ✅ **Benefit:** Fast propagation
- ⚠️ **Risk:** Must keep VPS IP stable (no IP changes)

### SowerBase Privacy
**Status:** ✅ **PRIVATE**

SowerBase remains on local network. Reverse proxy uses SSH tunnel or private network to communicate with localhost:8787. SowerBase is NOT accessible from public internet.

### Setup Complexity
**Estimated Time:** 45-90 minutes

**Steps:**
1. Provision VPS instance (5 minutes)
2. SSH into VPS
3. Install nginx
4. Generate TLS certificate (Let's Encrypt)
5. Copy nginx configuration from template
6. Configure private tunnel to localhost:8787 (SSH or VPN)
7. Set up certificate auto-renewal (certbot)
8. Configure firewall (allow 443, restrict 8787)
9. Start nginx
10. Test with deploy check and smoke test
11. Monitor for issues

### Estimated Cost
- **DigitalOcean:** $5-40/month (depending on droplet size)
  - $5: Basic staging (low traffic)
  - $6-40: Higher traffic/performance

- **AWS EC2:** $5-50/month
  - t3.micro free tier for 12 months
  - t3.small ~$8/month after free tier

- **Linode:** $5-20/month
  - Nanode 1GB $5/month
  - Good balance of price and reliability

- **TLS Certificate:** $0 (Let's Encrypt free)

### Recommended For
✅ Full infrastructure control needed
✅ Existing ops team familiar with Linux/nginx
✅ Long-term deployment with growth expected
✅ Organizations that disallow cloud CDN
✅ Regulatory requirements (data residency)

### Not Recommended For
❌ Minimal ops experience
❌ No existing VPS infrastructure
❌ Highly availability-critical (single point of failure)
❌ Teams without server management expertise

---

## Option C: Existing AskTHIH Host/API Route

### Overview
Use existing askthih.com infrastructure to host the staging route via serverless function, API endpoint, or existing application framework.

### Requirements
**Depends on current infrastructure:**

**If askthih.com uses serverless (AWS Lambda, Vercel, etc.):**
- Create new Lambda function or serverless route
- Store credentials in Secrets Manager or environment variables
- Route: POST /hvac-staging
- Configure CORS and rate limiting in API Gateway

**If askthih.com uses traditional server (Node/Python/PHP):**
- Add new route handler to existing application
- Store SowerBase credentials in secure vault or environment
- Route: POST /hvac-staging
- Implement rate limiting middleware
- Implement CORS middleware

**If askthih.com uses managed platform (Heroku, Railway, etc.):**
- Deploy new function or route
- Store credentials as environment variables
- Route: POST /hvac-staging
- Platform handles HTTPS/TLS

### Current AskTHIH Setup
**Unknown from this environment** — Project files don't reveal current hosting setup.

**Likely candidates:**
- Vercel or similar serverless (if modern JS/Next.js app)
- AWS Lambda (if enterprise/scaling focus)
- Traditional VPS with Node/Python app
- Managed platform (Heroku, Railway)

**To determine current setup:**
1. Check project root for deployment config files:
   - `vercel.json` → Vercel deployment
   - `serverless.yml` → AWS Serverless Framework
   - `.heroku/` → Heroku deployment
   - `Dockerfile` → Container deployment (Docker/ECS/K8s)
   - `package.json` scripts → Check build/deploy commands
   - Git deployment hooks (`.github/workflows/`) → CI/CD pipeline

2. Check DNS records:
   - Who hosts DNS for askthih.com?
   - What IPs does it point to?
   - Are there CNAME records indicating platform?

3. Ask Michael:
   - Current hosting platform
   - API/serverless support
   - Environment variable support
   - Deployment frequency and process

### Benefits (If Applicable)
✅ **Reuse existing infrastructure** — No new servers to manage
✅ **Familiar deployment process** — Use existing CI/CD pipeline
✅ **Integrated secrets management** — Use existing vault
✅ **Single platform billing** — No multi-vendor costs
✅ **Easier monitoring** — Existing observability tools
✅ **Better logging** — Integrated with existing logs
✅ **No DNS changes** — Uses existing domain

### Risks & Concerns
⚠️ **Unknown setup** — Current infrastructure not documented
⚠️ **Compatibility** — May not support simple reverse proxy needs
⚠️ **Secrets exposure risk** — Poor env var handling could expose creds
⚠️ **Architectural complexity** — May require significant refactoring
⚠️ **Scaling impact** — Staging traffic could impact production service
⚠️ **Deployment risk** — Pushing to production platform for test

### DNS Changes Required
**None** — Uses existing askthih.com domain and infrastructure

### SowerBase Privacy
**Status:** ⚠️ **NEEDS VERIFICATION**

**Question:** Can existing askthih.com host call SowerBase API securely?
- If yes: Server-side API call (safe, credentials hidden)
- If no: Client-side call (exposes credentials, security risk)

**Must ensure:**
- ✅ SowerBase API credentials stored securely (Secrets Manager)
- ✅ No credentials in client-side JavaScript
- ✅ No SowerBase URL exposed to public
- ✅ API calls server-side only

### Setup Complexity
**Estimated Time:** Highly variable (30 min - 4 hours)

**Depends on:**
- Current platform capabilities
- Availability of secrets management
- Existing deployment pipeline
- Code organization and modularity

**Steps (Generic):**
1. Research current askthih.com infrastructure
2. Ask Michael for deployment details
3. Determine if route/function can be added
4. Write route handler code
5. Configure environment variables for secrets
6. Implement rate limiting
7. Implement CORS
8. Deploy to staging environment
9. Test with deploy check and smoke test
10. Verify no production impact

### Estimated Cost
**$0** — Uses existing infrastructure

**Caveat:** May reduce budget for other services

### Recommended For
✅ AskTHIH already has robust, secure infrastructure
✅ Team knows existing platform well
✅ Minimal new infrastructure wanted
✅ Existing secrets management in place
✅ Cost efficiency critical

### Not Recommended For
❌ Current infrastructure unknown or undocumented
❌ Production platform and staging must be completely isolated
❌ Poor secrets management in existing platform
❌ Regulatory separation required (prod/staging)

---

## Decision Checklist

**For Michael to approve one recommended lane:**

### Cloudflare Tunnel Option
- [ ] Acceptable to change askthih.com nameservers to Cloudflare?
- [ ] Free tier ($0/month) sufficient for staging test?
- [ ] OK to depend on Cloudflare availability?
- [ ] Comfortable with Cloudflare account/onboarding?

### VPS + Nginx Option
- [ ] Team has Linux/server management experience?
- [ ] Budget allows $5-50/month for VPS?
- [ ] Can commit to security patch maintenance?
- [ ] OK with managing TLS certificates?
- [ ] Have stable VPS provider in mind?

### Existing askthih.com Platform Option
- [ ] Current askthih.com hosting documented/known?
- [ ] Platform supports new routes/functions?
- [ ] Secrets management available?
- [ ] Can isolate staging from production traffic?

---

## Recommended Staging Lane

### **Primary Recommendation: Option C (Existing AskTHIH Host)**

**If current infrastructure is known and compatible** — use existing platform.

**Rationale:**
- ✅ Reuses existing deployment pipeline
- ✅ Integrates with existing secrets management
- ✅ Minimal new infrastructure
- ✅ Cost-effective
- ✅ Familiar to team

**Fallback if Option C not viable:**

### **Secondary Recommendation: Option A (Cloudflare Tunnel)**

**If new infrastructure needed and DNS changes acceptable** — use Cloudflare Tunnel.

**Rationale:**
- ✅ Fastest setup (15-30 minutes)
- ✅ Maximum security (webhook stays private)
- ✅ No server management
- ✅ Adequate free tier for staging test
- ✅ Can upgrade to paid tier if needed

**Alternative if both above not viable:**

### **Tertiary Recommendation: Option B (VPS + Nginx)**

**If existing platform unusable and Cloudflare DNS changes problematic** — use VPS.

**Rationale:**
- ✅ Full control and portability
- ✅ Minimal DNS changes
- ✅ Standard tooling (nginx proven)
- ✅ Cost-effective long-term
- ✅ Configuration template ready

---

## Cutover Guardrails

**These constraints apply regardless of selected lane:**

✅ **Public askthih.com/hvac remains unchanged until Phase 5 passes**
- Staging route: https://askthih.com/hvac-staging (testing only)
- Production route: https://askthih.com/hvac (remains Airtable intake until explicit approval)

✅ **Airtable remains fallback/archive until public cutover succeeds**
- Minimum retention: 30 days after public cutover
- Can be extended indefinitely
- Never deleted without approval

✅ **No public direct database writes**
- All submissions go through SowerBase/NocoDB API
- No direct PostgreSQL writes
- Backend layer provides protection

✅ **No public SowerBase exposure**
- SowerBase API URL not accessible from internet
- Credentials not exposed in any public route
- Private network only

✅ **No public PostgreSQL exposure**
- Database not accessible from internet
- Firewall rules block all external access
- Only SowerBase/NocoDB app connects

---

## Next Steps

### 1. Approve Infrastructure Lane
Michael selects one option:
- [ ] Option A: Cloudflare Tunnel
- [ ] Option B: VPS + Nginx
- [ ] Option C: Existing askthih.com platform
- [ ] Other (document choice and rationale)

### 2. Provide Infrastructure Details (if needed)
- For Option C: Current hosting platform, API support, secrets management
- For Option A: Cloudflare account status, nameserver authority
- For Option B: VPS provider preference, existing Linux expertise

### 3. Deploy Infrastructure
Selected lane is deployed with:
- HTTPS/TLS enabled
- Webhook secret validation active
- Rate limiting configured (10 req/sec per IP)
- CORS origins restricted to askthih.com
- Security headers configured

### 4. Execute Phase 4
Once infrastructure deployed:
1. Run deploy check (validates environment)
2. Run smoke test (creates Record ID 6)
3. Verify record in SowerBase
4. Run backup validation
5. Proceed to Phase 5

---

## Decision Authorization

**Michael (Owner) must approve:**
1. Which staging infrastructure lane (A, B, C, or other)
2. Cost authorization (if applicable)
3. DNS changes (if applicable)
4. Timeline and deployment resource allocation

**This document is ready for approval.**

---

**Status:** ⏸️ **AWAITING INFRASTRUCTURE TARGET SELECTION**  
**Phase 4A Blocker:** Infrastructure lane not chosen  
**Next Action:** Michael approves one recommended lane  
**Target Date:** TBD (pending approval)

