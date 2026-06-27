# AskTHIH Existing Platform Compatibility Review

## Current Decision

**Option C Selected as Primary Lane:**
- Use existing AskTHIH platform infrastructure if compatible
- Minimize cost, DNS disruption, and operational overhead

**Fallback Lane (If Option C Not Compatible):**
- Cloudflare Tunnel (Option A) — if new infrastructure needed

**Last Resort Lane (If All Else Fails):**
- VPS + Nginx (Option B) — if Cloudflare not acceptable

**Reason:** Avoid unnecessary cost and DNS changes if existing platform can safely host the staging route.

---

## Hosting Discovery — Findings

### SowerBase Repository Context

**This Repository:**
- ✅ NocoDB open-source fork (customized for SowerBase)
- ✅ Local Docker deployment (localhost:18080)
- ✅ Backend API and database for AskTHIH intake data
- ✅ Running on Docker with PostgreSQL

**Deployment Infrastructure (This Repo):**
- CI/CD: GitHub Actions (.github/workflows/)
- Container: Docker Compose configurations
- Helm Charts: Kubernetes deployment support
- Auto-upstall: NocoDB's production deployment script

### AskTHIH Public Platform — Unknown

**Critical Gap:** The current askthih.com public website platform is **not documented in this SowerBase repository**.

**What We Know (from project files):**
- ✅ AskTHIH currently runs on Airtable (source of truth)
- ✅ HVAC intake table exists in Airtable (table: "HVAC Intake")
- ✅ Multiple service verticals in Airtable (plumbing, barber, pest control, real estate, etc.)
- ✅ Forms are exposed on public web (askthih.com/hvac and other routes)
- ✅ Social media links to askthih.com/hvac forms
- ✅ Pinterest links drive traffic to service pages

**What We Don't Know:**
- ❓ Hosting platform for askthih.com (Vercel? AWS? Traditional VPS?)
- ❓ Technology stack (Node.js? Python? PHP? Serverless?)
- ❓ How HVAC form submissions are currently handled
- ❓ Whether route `/hvac-staging` can be added
- ❓ Secret/credential storage capabilities
- ❓ Ability to make outbound API calls to SowerBase
- ❓ Rate limiting / WAF capabilities
- ❓ Rollback procedure if staging fails

---

## Required Platform Capabilities

### For Option C to Work, AskTHIH Platform Must Support:

**1. HTTPS Routes**
- [ ] Can add new HTTPS route: /hvac-staging
- [ ] Route accepts POST requests
- [ ] Route can be isolated from production /hvac

**2. Server-Side API Route or Webhook Handler**
- [ ] Route can execute server-side code
- [ ] Code can call external APIs (SowerBase/NocoDB)
- [ ] NOT client-side JavaScript calling external APIs

**3. Secure Environment Variables / Secrets**
- [ ] Platform supports environment variables
- [ ] Credentials NOT hard-coded in source
- [ ] Secrets NOT exposed in logs or errors
- [ ] Secrets NOT accessible from client-side JavaScript

**4. Outbound HTTP Calls to SowerBase API**
- [ ] Server-side code can make HTTPS calls
- [ ] Can include Bearer token in Authorization header
- [ ] Can handle SowerBase API responses (JSON)
- [ ] SowerBase API URL can be stored in secure environment variable

**5. Request Body Limits**
- [ ] Can enforce maximum request size
- [ ] Can reject payloads > 10 KB
- [ ] Can return 413 Payload Too Large errors

**6. Rate Limiting or Middleware**
- [ ] Platform has rate limiting support
- [ ] OR can implement middleware to rate limit
- [ ] OR can use WAF/reverse proxy for rate limiting

**7. HMAC Signature Validation**
- [ ] Can implement HMAC-SHA256 signature validation
- [ ] Can extract and verify Authorization header
- [ ] Can compare signatures securely

**8. Safe Logging Controls**
- [ ] Logs do NOT include request body
- [ ] Logs do NOT include authorization headers
- [ ] Logs do NOT include secrets
- [ ] Error responses do NOT reveal stack traces

**9. Rollback to Airtable or Previous Route**
- [ ] Can quickly disable /hvac-staging
- [ ] Can re-route /hvac to Airtable if needed
- [ ] Deployment process is reversible
- [ ] No data loss if rollback occurs

---

## Public Route Protection

### Staging Route Isolation

**Requirement:** /hvac-staging can coexist with production /hvac

**Current State:**
- ✅ Production route: https://askthih.com/hvac (→ Airtable)
- ✅ Staging route: https://askthih.com/hvac-staging (→ SowerBase, TBD)

**Must Verify:**
- [ ] /hvac and /hvac-staging don't interfere
- [ ] /hvac remains routed to Airtable during staging test
- [ ] /hvac-staging is completely separate handler
- [ ] No user-facing page is broken by staging route addition

### SowerBase Exposure Risk

**Requirements:**
- ✅ SOWERBASE_BASE_URL NOT exposed in client-side code
- ✅ SOWERBASE_API_TOKEN NOT exposed in client-side code
- ✅ SOWERBASE_API_TOKEN only in server-side environment
- ✅ SowerBase API URL not accessible from public internet (localhost:18080 is private)

**Must Verify:**
- [ ] Platform does NOT expose environment variables to client
- [ ] No secrets in public source code
- [ ] No API calls to SowerBase from client-side JavaScript
- [ ] All SowerBase API calls from server-side only

### PostgreSQL Exposure Risk

**Requirements:**
- ✅ No direct PostgreSQL access from staging route
- ✅ All database access through SowerBase API
- ✅ PostgreSQL port 5432 not publicly exposed
- ✅ Only SowerBase app connects to PostgreSQL

**Must Verify:**
- [ ] Staging route uses SowerBase API, not direct SQL
- [ ] No SQL queries in public route handler
- [ ] No database connection strings in public code

---

## Compatibility Ruling

### Current Assessment: UNKNOWN — Requires Manual Confirmation

**Reason:** AskTHIH platform is not documented in this SowerBase repository.

### To Determine Compatibility, Michael Must Answer:

**Platform Questions:**

1. **What platform hosts askthih.com?**
   - Example: Vercel, AWS Lambda, Heroku, traditional VPS, etc.

2. **What technology stack?**
   - Example: Node.js, Python, PHP, Go, etc.

3. **How are form submissions currently handled?**
   - Example: Direct to Airtable API, backend route, webhook, etc.

4. **Where are secrets stored?**
   - Example: .env files, AWS Secrets Manager, platform secrets, etc.

5. **Can the platform add new HTTPS routes?**
   - Example: Yes/No, and if yes, what's the process?

6. **Does the platform support outbound API calls?**
   - Example: Yes/No, any restrictions?

7. **What's the deployment/rollback process?**
   - Example: Git push, CI/CD pipeline, manual, etc.

### Dashboard Items to Inspect:

**If hosting on Vercel:**
- Check Vercel project settings
- Verify environment variables support
- Check deployment logs for outbound calls

**If hosting on AWS:**
- Check Lambda environment variable support
- Check API Gateway configuration
- Verify IAM roles allow outbound HTTPS

**If hosting on Heroku:**
- Check Procfile and app.json
- Verify environment variable security
- Check dyno type (web dyno required)

**If traditional VPS:**
- Check current application code
- Verify web server configuration (nginx/Apache)
- Check firewall rules for outbound HTTPS

---

## Compatibility Classification

### Pending Manual Confirmation

**Current Status:** ⏳ **UNKNOWN**

**Reason:** AskTHIH platform architecture not documented in SowerBase repository.

**To Proceed:**
1. Michael identifies current askthih.com hosting platform
2. Michael verifies required capabilities (list above)
3. Michael confirms option C feasibility
4. Then: Proceed to Option C deployment plan

**If Incompatible:**
1. Fall back to Option A: Cloudflare Tunnel
2. Cloudflare DNS configuration (24-48 hour wait)
3. Deploy staging route via Cloudflare

**If Last Resort:**
1. Fall back to Option B: VPS + Nginx
2. Provision VPS instance
3. Deploy nginx reverse proxy

---

## Recommended Next Move

### **IMMEDIATE ACTION: Michael Confirmation Required**

**Michael must answer the platform questions above** (or check deployment dashboard if in control).

### **THEN: One of Three Paths**

**Path 1 (If Option C Compatible):**
1. Create "Option C Staging Deployment Plan" document
2. Implement staging route on existing platform
3. Deploy SOWERBASE_API_TOKEN securely
4. Configure /hvac-staging handler
5. Test with deploy check and smoke test
6. Proceed to Phase 4 with existing platform

**Path 2 (If Option C Incompatible, Use Option A Cloudflare):**
1. Create "Cloudflare Tunnel Setup Plan" document
2. Point askthih.com nameservers to Cloudflare
3. Create tunnel configuration
4. Deploy staging route via tunnel
5. Wait 24-48 hours for DNS propagation
6. Test with deploy check and smoke test
7. Proceed to Phase 4 with Cloudflare

**Path 3 (If Both Above Infeasible, Use Option B VPS):**
1. Create "VPS + Nginx Deployment Plan" document
2. Provision VPS instance
3. Install nginx and configure reverse proxy
4. Generate TLS certificate (Let's Encrypt)
5. Deploy staging route via VPS
6. Test with deploy check and smoke test
7. Proceed to Phase 4 with VPS

---

## Safety Confirmations

✅ **No Public askthih.com/hvac Changes**
- Production route unchanged during compatibility review
- Still routes to Airtable

✅ **No DNS Changes**
- No nameserver modifications
- No DNS record updates
- DNS remains under current control

✅ **No Airtable Changes**
- Airtable base untouched
- No records imported or modified
- No schema changes

✅ **No Airtable Imports**
- Zero migration during review phase
- Airtable remains source of truth

✅ **No Canon Connection**
- Canon data integration untouched

✅ **THIHskills Untouched**
- Skills data/configuration unchanged

✅ **No Credentials Committed**
- No secrets in git
- No .env files committed
- Only documentation committed

✅ **Record ID 6 Not Created**
- Staging test not executed yet
- Waiting for infrastructure selection

---

## Approval Requirements

**Michael Must Confirm:**
1. **Platform Identified** — Know what hosts askthih.com
2. **Capabilities Verified** — Platform can support staging route
3. **Safety Confirmed** — Production route protected during test
4. **Rollback Plan Clear** — Can revert if staging fails

**Then Proceed With Selected Infrastructure Lane:**
- [ ] Path 1: Option C (existing platform)
- [ ] Path 2: Option A (Cloudflare Tunnel)
- [ ] Path 3: Option B (VPS + Nginx)

---

## Conclusion

**Phase 4B Status:** ⏸️ **AWAITING MICHAEL'S PLATFORM CONFIRMATION**

**Next Action:** Michael answers platform questions or inspects deployment dashboard

**Timeline:** Once platform confirmed, deployment can proceed same day

**Risk:** Minimal (compatibility review only, no infrastructure changes)

**Safety:** All constraints maintained (no public changes, no Airtable changes, no credentials committed)

---

**Prepared:** 2026-06-27  
**Latest Develop Commit:** 4265e6162a  
**Phase 3 Complete:** YES  
**Phase 4A Complete:** YES  
**Phase 4B Status:** Awaiting platform confirmation  
**Ready for Phase 4 Deployment:** Pending infrastructure selection confirmation

