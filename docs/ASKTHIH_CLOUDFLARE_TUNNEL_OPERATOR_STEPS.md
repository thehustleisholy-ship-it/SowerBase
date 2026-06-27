# AskTHIH Cloudflare Quick Tunnel Setup — Operator Steps

## Important Before Starting

**Do NOT proceed without approval from Michael.**

This guide sets up a temporary Cloudflare Quick Tunnel to expose ONLY the API-safe webhook on localhost:8787.

**Guardrails:**
- ✅ Tunnel exposes localhost:8787 (webhook) ONLY
- ❌ DO NOT tunnel localhost:18080 (SowerBase)
- ❌ DO NOT tunnel database ports
- ✅ Verify webhook-only exposure before proceeding

---

## Prerequisites

### 1. Confirm cloudflared is installed

**Windows (Chocolatey):**
```powershell
choco install cloudflare-warp
```

**Windows (Direct Download):**
https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/

**Verify installation:**
```powershell
cloudflared --version
```

### 2. Confirm SowerBase is running

**Verify:**
```powershell
curl -I http://localhost:18080
# Expected: HTTP/1.1 200 OK
```

### 3. Confirm API-safe HVAC webhook is ready

**Webhook server location:**
```
scripts/askthih-hvac-local-webhook-server.ps1
```

---

## Setup Steps

### Step 1: Start SowerBase (if not running)

**On Windows:**
```powershell
# If using Docker Compose
cd sowerbase-local
docker-compose up -d

# Verify
curl -I http://localhost:18080
# Expected: HTTP/1.1 200 OK
```

---

### Step 2: Start API-Safe HVAC Webhook Server

**In one terminal/PowerShell window:**

```powershell
cd c:\Users\[username]\SowerBase

# Ensure ASKTHIH_WEBHOOK_PORT is set
$env:ASKTHIH_WEBHOOK_PORT = 8787
$env:ASKTHIH_WEBHOOK_SECRET = "[32-byte-secret-from-Phase-2B]"
$env:SOWERBASE_BASE_URL = "http://localhost:18080"
$env:SOWERBASE_API_TOKEN = "[token-from-Phase-2B]"
$env:SOWERBASE_INTAKE_TABLE_ID = "[table-id-from-Phase-2B]"

# Start webhook server
.\scripts\askthih-hvac-local-webhook-server.ps1
```

**Verify webhook is running:**
```powershell
# In another terminal
curl -I http://localhost:8787/askthih/hvac
# Expected: HTTP/1.1 405 Method Not Allowed (or 200 OK)
```

---

### Step 3: Start Cloudflare Quick Tunnel

**In another terminal/PowerShell window:**

**CRITICAL: Only expose localhost:8787, NOT localhost:18080**

```powershell
# Start Quick Tunnel pointing to WEBHOOK ONLY
cloudflared tunnel --url http://localhost:8787

# Output will show temporary tunnel URL:
# Your quick tunnel is ready! Visit it at (press Ctrl+C to quit):
# https://askthih-staging-abc123.cloudflareaccess.com
```

**⚠️ IMPORTANT:**
- Note the temporary HTTPS URL (e.g., `https://askthih-staging-abc123.cloudflareaccess.com`)
- This URL is temporary (7-day validity)
- This URL is session-only (do NOT commit it to git)
- Keep this terminal running while testing

---

### Step 4: Verify Webhook-Only Exposure

**In yet another terminal, run the verification script:**

```powershell
cd c:\Users\[username]\SowerBase

# Run verification check (READ-ONLY, no records created)
.\scripts\askthih-cloudflare-tunnel-webhook-check.ps1 `
    -TunnelUrl "https://askthih-staging-abc123.cloudflareaccess.com"
```

**Expected output:**
```
✓ Tunnel URL format valid (HTTPS, no localhost)
✓ Webhook endpoint responds with 405 Method Not Allowed
✓ Path / appears safe
✓ SowerBase/NocoDB does not appear to be exposed
✓ Tunnel appears to be webhook-only
```

**If verification FAILS:**
- ❌ Stop. Do NOT proceed to Vercel integration
- Diagnose issue:
  - Verify webhook is running at localhost:8787
  - Verify tunnel is pointing to localhost:8787 ONLY
  - Verify SowerBase is NOT exposed
  - Check firewall/network restrictions

---

### Step 5: Document Tunnel URL (Session-Only)

**Copy the temporary tunnel URL:**
```
https://askthih-staging-abc123.cloudflareaccess.com
```

**Usage:**
- Use in `ASKTHIH_STAGING_WEBHOOK_URL` environment variable
- Do NOT commit to git
- Do NOT share in logs
- Mark as "session-only" / "temporary"
- Will be invalid after 7 days

---

### Step 6: Prepare for Vercel Configuration

**Once verification passes:**

Create or update `.env.askthih-vercel-staging.example`:
```bash
# Vercel staging environment variables (for manual entry in Vercel dashboard)
# Do NOT commit actual URLs or secrets

ASKTHIH_STAGING_WEBHOOK_URL=[temporary-tunnel-url-from-step-5]
ASKTHIH_WEBHOOK_SECRET=[secret-from-Phase-2B-redacted]
ALLOWED_ORIGINS=https://www.askthih.com,https://askthih.com
NODE_ENV=staging
```

---

## Troubleshooting

### Webhook Not Responding

**Check webhook is running:**
```powershell
curl -I http://localhost:8787/askthih/hvac
```

**Check environment variables are set:**
```powershell
$env:ASKTHIH_WEBHOOK_PORT
$env:ASKTHIH_WEBHOOK_SECRET
# (others should be redacted, but verify they're set)
```

**Check logs for errors:**
- Review terminal output from webhook server
- Look for "listening on localhost:8787" message

---

### Tunnel Not Starting

**Verify cloudflared installation:**
```powershell
cloudflared --version
```

**Check if port 8787 is in use:**
```powershell
netstat -ano | findstr :8787
```

**Try tunnel again:**
```powershell
cloudflared tunnel --url http://localhost:8787
```

---

### SowerBase Appears Exposed

**⚠️ CRITICAL: Stop immediately if SowerBase is exposed through tunnel**

**Verification should have caught this. If it didn't:**
1. ❌ Stop webhook server
2. ❌ Stop tunnel
3. ❌ Kill any lingering processes
4. Review tunnel configuration
5. Verify tunnel points to localhost:8787 ONLY

---

## After Tunnel Verification Passes

### Next Steps

1. ✅ Tunnel verified as webhook-only
2. ✅ SowerBase not exposed
3. ✅ PostgreSQL not exposed
4. 📝 Document results in: `docs/ASKTHIH_CLOUDFLARE_TUNNEL_WEBHOOK_SETUP_RESULT.md`
5. 🚀 Ready for Phase 4B.4: Vercel /api/hvac-staging route implementation

### When to Stop Tunnel

- Tunnel can run for the duration of testing (7-day quick tunnel validity)
- Keep webhook server running on localhost:8787 while testing
- When done with Phase 4B.3-4 testing, stop tunnel and webhook:
  ```powershell
  # In tunnel terminal: Ctrl+C
  # In webhook terminal: Ctrl+C
  ```

---

## Safety Checklist

Before running tunnel, verify:

- [ ] cloudflared is installed
- [ ] SowerBase is running at http://localhost:18080
- [ ] Webhook server can run at http://localhost:8787
- [ ] Tunnel is configured for localhost:8787 ONLY
- [ ] Verification script exists: `scripts/askthih-cloudflare-tunnel-webhook-check.ps1`
- [ ] Result template exists: `docs/ASKTHIH_CLOUDFLARE_TUNNEL_WEBHOOK_SETUP_RESULT_TEMPLATE.md`
- [ ] Record ID 6 does NOT exist (verification)
- [ ] Public askthih.com/hvac is UNCHANGED (verification)

---

## Critical Guardrails

**MUST DO:**
✅ Start SowerBase first  
✅ Start webhook server second  
✅ Start tunnel pointing to localhost:8787 ONLY  
✅ Verify webhook-only exposure before Vercel integration  
✅ Keep tunnel URL session-only (do NOT commit)  

**MUST NOT:**
❌ Tunnel localhost:18080  
❌ Tunnel database ports  
❌ Expose SowerBase UI  
❌ Expose PostgreSQL  
❌ Create Record ID 6 (reserved for Vercel smoke test)  
❌ Change public askthih.com/hvac  
❌ Commit tunnel URL to git  

---

**This setup is for Phase 4B.3 only. For production, use Option 1 (managed host) from Phase 5.**

