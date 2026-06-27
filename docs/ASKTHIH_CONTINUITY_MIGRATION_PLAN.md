# AskTHIH Continuity Migration Plan

## 1. Executive Summary

AskTHIH is now the **first operational SowerBase schema priority**.

### Why This Matters

AskTHIH currently runs on Airtable and is directly connected to:
- **Public service vertical funnels** (HVAC, plumbing, automotive, real estate, etc.)
- **Social media posts** linking to intake forms
- **Pinterest links** driving traffic to service pages
- **askthih.com intake flows** capturing community requests
- **Real-world intake submissions** from people seeking help

### Risk of Current State

If Airtable service is disrupted or base becomes inaccessible:
- Service vertical intake forms break → people cannot request help
- Leads are lost → community impact ceases
- Past social/Pinterest links return 404 → reputation damage
- Follow-up workflows stop → incomplete service delivery
- Canon operations (if connected) go dark → service disruption

### Migration Goal

**Move AskTHIH from fragile Airtable dependency toward SowerBase ownership** so the system:
- Serves people even if Airtable is inaccessible
- Maintains public funnel continuity
- Preserves intake history and follow-up state
- Enables local control and transparency
- Supports THIHskills integration later

---

## 2. Source Inventory

### Airtable Source Base

| Property | Value |
|----------|-------|
| **Base Name** | askthih |
| **Base ID** | app60wQWdbbgyqTcL |
| **Access Level** | create |
| **Schema Access** | Via Airtable connector |

### All Discovered Tables (24 Total)

#### Service Vertical Intake Tables
Service verticals = community request forms for skilled help

- **PlumberIntake** — Plumbing service requests
- **Barber Intake** — Barber/hair service requests
- **Church Visitors** — Church visitor intake/follow-up
- **Pest Control Intake** — Pest control service requests
- **Funeral Home Intake** — Funeral service requests
- **Auto Repair Intake** — Automotive repair requests
- **HVAC Intake** — HVAC/heating service requests
- **Dental Intake** — Dental service requests
- **Landscaping Intake** — Landscaping/yard service requests
- **Bail Bonds Intake** — Bail bond service inquiries
- **Housekeeping Intake** — Housekeeping service requests

#### Real Estate Lead Tables

- **Seller Leads** — Property seller inquiries
- **Buyer Leads** — Property buyer inquiries
- **Cape Town Leads** — Geographic segment (South Africa)
- **Leads — US** — Geographic segment (United States)

#### Ministry/Prayer Tables

- **Prayer Requests** — Community prayer requests
- **Follow-ups** — Prayer/ministry follow-up tracking

#### Outreach & CRM Tables

- **Outreach** — Outreach events and campaigns
- **Campaigns** — Campaign tracking and metadata
- **Results** — Campaign/outreach results tracking

#### Universal/Meta Tables

- **Universal Vertical Leads** — Cross-vertical lead consolidation
- **Main Site Leads** — Primary website form captures
- **Leads** — Generic/global lead capture
- **Audit Results** — Data audit and compliance tracking

---

## 3. Migration Priority Tiers

### Tier 0: Critical Path (Unlock Core Functionality)

These tables must work first to prove the system is operational:

**Universal/Gateway Tables:**
- **Universal Vertical Leads** — Consolidates all service vertical inquiries; top of funnel
- **Main Site Leads** — Primary intake point; highest volume
- **Prayer Requests** — Ministry core; always operational

**First Test Vertical (Choose One):**
- **HVAC Intake** (Recommended) — Mid-volume, clear intake flow, good test case
  - OR **PlumberIntake** — High-volume, well-structured, immediate public impact
  - OR **Barber Intake** — Low-volume, simple schema, safe test

**Success Criteria for Tier 0:**
- Intake form submission → SowerBase record created
- Record appears in SowerBase UI
- No Airtable dependency for that path
- Backup succeeds after schema creation
- Follow-up flow works (basic outreach)

### Tier 1: Service Verticals & Lead Management (Full Coverage)

Remaining service intake tables and lead management:

**Remaining Service Vertical Intakes:**
- PlumberIntake (if not Tier 0 test)
- Barber Intake (if not Tier 0 test)
- Church Visitors
- Pest Control Intake
- Funeral Home Intake
- Auto Repair Intake
- HVAC Intake (if not Tier 0 test)
- Dental Intake
- Landscaping Intake
- Bail Bonds Intake
- Housekeeping Intake

**Real Estate & Sales Leads:**
- Seller Leads
- Buyer Leads

**Outreach & Follow-Up:**
- Outreach
- Campaigns
- Results

**Success Criteria for Tier 1:**
- All service verticals operational in SowerBase
- Leads capture working for all channels
- Follow-up workflows complete
- Multi-vertical queries possible (e.g., "all leads this month")
- Historical data accessible

### Tier 2: Segmentation & Historical (Complete Archive)

Specialized geographic and historical tables:

- Cape Town Leads — Geographic segment archival
- Leads — US — Geographic segment archival
- Audit Results — Compliance/audit trail
- Any derived or reporting tables

**Success Criteria for Tier 2:**
- Historical data preserved and queryable
- Geographic filtering available
- Audit trail complete
- Full replacement of Airtable possible

---

## 4. SowerBase Schema Design Approach

### Principle: Normalize, Don't Clone

**DO NOT** simply create 24 SowerBase tables that mirror Airtable exactly.

**INSTEAD** create one unified operating model:
- Deduplicate intake concepts
- Create normalized tables
- Preserve Airtable source metadata
- Enable cross-vertical queries
- Support future features

### Recommended Core Table Structure

#### 1. **Contacts**
Unified contact record for any person submitting an intake.

**Fields:**
- contact_id (PK, auto)
- first_name
- last_name
- email
- phone
- address
- city / state / postal_code
- country
- created_at
- updated_at
- source_system (always "askthih")
- source_base_id (app60wQWdbbgyqTcL)

#### 2. **Organizations**
Business/entity serving a vertical (e.g., "Joe's Plumbing").

**Fields:**
- org_id (PK, auto)
- org_name
- vertical_type_id (FK)
- email
- phone
- address
- website
- created_at
- updated_at

#### 3. **Vertical Types**
Service categories (HVAC, plumbing, real estate, prayer, etc.).

**Fields:**
- vertical_id (PK, auto)
- vertical_name (e.g., "HVAC", "Real Estate Sales")
- vertical_slug (e.g., "hvac", "real-estate-sales")
- description
- active (bool)

#### 4. **Intake Submissions**
Unified intake record for any service request or lead.

**Fields:**
- intake_id (PK, auto)
- contact_id (FK)
- vertical_id (FK)
- intake_type (enum: "request", "lead", "prayer-request", "visitor")
- submission_date
- submission_source (enum: "web-form", "social", "direct", "imported")
- description / message / details
- status (enum: "new", "contacted", "in-progress", "completed", "archived")
- priority (enum: "low", "normal", "high", "urgent")
- created_at
- updated_at
- **Source Metadata (see section 5)**

#### 5. **Campaigns**
Outreach campaigns and media placements.

**Fields:**
- campaign_id (PK, auto)
- campaign_name
- campaign_type (enum: "social-post", "pinterest", "email", "offline", "partnership")
- vertical_id (FK, nullable — can be cross-vertical)
- launch_date
- end_date
- status (enum: "planned", "active", "paused", "completed")
- notes
- created_at

#### 6. **Source Links**
Mapping of where intakes originated (social posts, landing pages, etc.).

**Fields:**
- link_id (PK, auto)
- campaign_id (FK)
- intake_id (FK, nullable)
- source_url
- link_text
- platform (enum: "instagram", "pinterest", "facebook", "askthih-com", "other")
- click_count
- conversion_count
- created_at

#### 7. **Outreach Events**
Follow-up actions and outreach attempts.

**Fields:**
- outreach_id (PK, auto)
- intake_id (FK)
- outreach_type (enum: "phone-call", "email", "sms", "in-person", "referral")
- outreach_date
- notes
- result (enum: "reached", "voicemail", "no-answer", "declined", "completed")
- next_followup_date
- created_at
- created_by (contact name or system)

#### 8. **Follow-ups**
Structured follow-up tracking for intake states.

**Fields:**
- followup_id (PK, auto)
- intake_id (FK)
- followup_date
- followup_type (enum: "intake-received", "contact-made", "service-offered", "referral-given", "completed")
- notes
- status (enum: "pending", "completed", "skipped")
- assigned_to (contact name, optional)
- created_at

#### 9. **Results / Outcomes**
Outcome tracking for completed intakes.

**Fields:**
- result_id (PK, auto)
- intake_id (FK)
- campaign_id (FK, nullable)
- outcome_type (enum: "service-provided", "referral-made", "prayer-answered", "no-contact", "archived")
- outcome_date
- notes
- impact_level (enum: "low", "medium", "high", "transformational")
- created_at

### Data Relationships

```
Contacts ←→ Intake Submissions ←→ Follow-ups
            ↓
        Vertical Types
            ↓
        Organizations

Campaigns ←→ Source Links ←→ Intake Submissions
            ↓
        Outreach Events

Intake Submissions ←→ Results / Outcomes
```

---

## 5. Continuity Fields

**Every migrated record** (in every table) must preserve Airtable source metadata:

### Standard Source Fields (All Tables)

```
- source_system: "askthih" (always)
- source_base_id: "app60wQWdbbgyqTcL" (always)
- source_table_id: Airtable table ID
- source_table_name: Name of Airtable source table (e.g., "PlumberIntake")
- source_record_id: Airtable record ID for this row
- source_url: URL to record in Airtable (if available)
```

### Migration Tracking Fields (All Tables)

```
- submitted_at: Original submission timestamp (from Airtable created_at)
- migration_batch_id: Unique ID for migration run (e.g., "batch-20260627-hvac-tier0")
- migration_status: Enum ["new", "migrated", "verified", "archived"]
- migration_notes: Free text for any migration issues/decisions
```

### Example Intake Record (After Migration)

```json
{
  "intake_id": 1,
  "contact_id": 42,
  "vertical_id": 3,
  "intake_type": "request",
  "submission_date": "2026-06-20",
  "status": "new",
  "created_at": "2026-06-20T14:30:00Z",
  
  "source_system": "askthih",
  "source_base_id": "app60wQWdbbgyqTcL",
  "source_table_id": "tblXXXXXXXXXXXXXX",
  "source_table_name": "HVACIntake",
  "source_record_id": "recYYYYYYYYYYYYYY",
  "source_url": "https://airtable.com/app60wQWdbbgyqTcL/tblXXXXXXXXXXXXXX/recYYYYYYYYYYYYYY",
  "submitted_at": "2026-06-20T14:30:00Z",
  "migration_batch_id": "batch-20260627-hvac-tier0",
  "migration_status": "migrated",
  "migration_notes": "Imported from Airtable HVAC Intake table during Tier 0 test"
}
```

---

## 6. AskTHIH Test Path (Tier 0 Validation)

### End-to-End Test Flow

**Goal:** Prove one vertical works in SowerBase without Airtable dependency.

**Test Case: HVAC Intake (Recommended)**

**Step 1: Schema Creation**
- Create `Vertical Types` table → add "HVAC" entry
- Create `Contacts` table
- Create `Intake Submissions` table
- Create `Outreach Events` table
- Create `Follow-ups` table
- Backup SowerBase after schema creation

**Step 2: Test Submission**
- Generate test intake: "I need HVAC maintenance"
- Submit to SowerBase via API or UI form
- Verify:
  - Record appears in SowerBase
  - All source metadata fields populated
  - No Airtable call required
  - Backup completes without error

**Step 3: Follow-Up Flow**
- Add outreach event: "Called homeowner"
- Add follow-up: "Service scheduled"
- Update result: "Service provided"
- Verify:
  - Workflow state machine works
  - Query returns intake → outreach → follow-up → result chain
  - No Airtable query required

**Step 4: Validation**
- Stop Airtable access (simulated)
- Verify test intake still loads from SowerBase
- Verify follow-up workflow still works
- Verify backup can be restored (backup recovery test)

**Success Criteria:**
- ✅ Test intake appears in SowerBase
- ✅ All source metadata preserved
- ✅ Follow-up workflow complete
- ✅ No Airtable dependency for this vertical
- ✅ Backup after schema creation succeeds
- ✅ Restore from backup works (verify with next backup cycle)

---

## 7. Risk Controls

### Read-Only Airtable During Migration

**Rule:** Airtable remains the read-only source of truth during migration.
- **No deletes** in Airtable
- **No structure changes** in Airtable
- **No data modifications** in Airtable
- **Read-only API access only** for schema discovery and data export
- **Audit every read** (log what data was pulled and when)

### No Destructive Actions

- No dropping SowerBase tables mid-migration
- No truncating intake history
- No deleting unverified records
- No mass deletes without manual review
- Git branch for every schema version (rollback safe)

### No Public DNS Changes Until Verified

- Airtable forms remain public facing during migration
- SowerBase is internal only until Tier 0 test passes
- askthih.com continues routing to Airtable
- No social link redirects until local flow works
- Staged go-live: Tier 0 → Tier 1 → Tier 2 → Public switch (estimated 2-3 weeks)

### No Canon Connection

- Never import Canon data during askthih migration
- Never write Canon references in intake records
- Keep askthih separate until explicitly approved
- If Canon eventually connects, it will be a separate integration step

### No THIHskills Changes

- THIHskills remains untouched during schema work
- If askthih eventually connects to THIHskills, that's a separate effort
- This phase: capture intakes, not service delivery workflows

---

## 8. Deliverables

### Immediate (This Document)

- ✅ **Migration Plan Document** — This file (ASKTHIH_CONTINUITY_MIGRATION_PLAN.md)
- ✅ **Table Mapping Matrix** (below)
- ✅ **First Test Vertical Recommendation** — HVAC Intake
- ✅ **Implementation Checklist** (below)
- ✅ **Rollback Plan** (below)

### Table Mapping Matrix

| Airtable Table | Tier | Maps To | Purpose |
|---|---|---|---|
| Universal Vertical Leads | 0 | Intake Submissions + Vertical Types | Cross-vertical lead consolidation |
| Main Site Leads | 0 | Intake Submissions + Source Links | Primary intake funnel |
| Prayer Requests | 0 | Intake Submissions (intake_type="prayer-request") | Ministry core |
| HVAC Intake | 0 | Intake Submissions + Contacts (vertical="HVAC") | First test vertical |
| PlumberIntake | 1 | Intake Submissions + Contacts (vertical="Plumbing") | Service vertical |
| Barber Intake | 1 | Intake Submissions + Contacts (vertical="Barber") | Service vertical |
| Church Visitors | 1 | Intake Submissions (intake_type="visitor") | Ministry funnel |
| Pest Control Intake | 1 | Intake Submissions + Contacts (vertical="Pest Control") | Service vertical |
| Funeral Home Intake | 1 | Intake Submissions + Contacts (vertical="Funeral Services") | Service vertical |
| Auto Repair Intake | 1 | Intake Submissions + Contacts (vertical="Auto Repair") | Service vertical |
| Dental Intake | 1 | Intake Submissions + Contacts (vertical="Dental") | Service vertical |
| Landscaping Intake | 1 | Intake Submissions + Contacts (vertical="Landscaping") | Service vertical |
| Bail Bonds Intake | 1 | Intake Submissions + Contacts (vertical="Bail Bonds") | Service vertical |
| Housekeeping Intake | 1 | Intake Submissions + Contacts (vertical="Housekeeping") | Service vertical |
| Seller Leads | 1 | Intake Submissions + Contacts (vertical="Real Estate - Seller") | Real estate funnel |
| Buyer Leads | 1 | Intake Submissions + Contacts (vertical="Real Estate - Buyer") | Real estate funnel |
| Outreach | 1 | Outreach Events | Outreach tracking |
| Campaigns | 1 | Campaigns + Source Links | Campaign/media tracking |
| Follow-ups | 1 | Follow-ups | Follow-up workflow |
| Results | 1 | Results / Outcomes | Outcome tracking |
| Cape Town Leads | 2 | Intake Submissions (geographic segment) | Archive/historical |
| Leads — US | 2 | Intake Submissions (geographic segment) | Archive/historical |
| Leads | 2 | Intake Submissions (fallback/global) | Catch-all/archive |
| Audit Results | 2 | Results / Outcomes (audit trail) | Compliance/audit |

### Implementation Checklist

**Phase 1: Schema Design & Test Setup**
- [ ] Create SowerBase AskTHIH schema v1 (Vertical Types, Contacts, Intake Submissions, etc.)
- [ ] Add source metadata fields to all tables
- [ ] Design Tier 0 tables (Universal Vertical Leads, Main Site Leads, Prayer Requests, HVAC Intake)
- [ ] Create backup immediately after schema creation
- [ ] Document table relationships and field mappings

**Phase 2: Tier 0 Test Execution**
- [ ] Set up test intake form (HVAC Intake)
- [ ] Submit test intake via SowerBase
- [ ] Verify record appears with all source metadata
- [ ] Create outreach event (follow-up)
- [ ] Complete follow-up workflow
- [ ] Verify no Airtable dependency for this path
- [ ] Backup SowerBase after test data
- [ ] Document test results

**Phase 3: Tier 1 Migration**
- [ ] Create remaining service vertical tables
- [ ] Migrate real estate leads
- [ ] Set up outreach and campaign tracking
- [ ] Batch import Airtable Tier 1 data
- [ ] Verify all workflows (intake → outreach → follow-up → result)
- [ ] Backup after each batch import

**Phase 4: Tier 2 Archive & Historical**
- [ ] Migrate geographic segments
- [ ] Migrate audit/compliance tables
- [ ] Archive historical data
- [ ] Backup complete askthih schema

**Phase 5: Staged Go-Live**
- [ ] Test all public funnels against SowerBase (internal only)
- [ ] Verify intake form submissions work
- [ ] Run full backup pre-switchover
- [ ] Update DNS/routing to SowerBase (if approved)
- [ ] Monitor for 24h post-switch
- [ ] Fallback plan if needed (revert to Airtable routing)

### Rollback Plan

**If Tier 0 test fails:**
1. Restore SowerBase from backup (pre-schema backup)
2. Investigate failure mode
3. Update schema design if needed
4. Retry with fresh data

**If Tier 1 migration has issues:**
1. Stop import process
2. Restore SowerBase to Tier 0-only state (from backup before Tier 1)
3. Investigate data issues
3. Retry Tier 1 with data cleansing

**If public switch fails (post-go-live):**
1. Revert DNS/routing back to Airtable immediately
2. Preserve SowerBase backup at time of failure
3. Investigate what broke
4. Plan retry window

---

## 9. Next Gate: Approval & Execution

### What This Document Established

✅ **Migration strategy** — Phased approach, risk-controlled  
✅ **Schema design** — Normalized vs. cloned  
✅ **Tier priorities** — Tier 0 (critical), Tier 1 (full coverage), Tier 2 (archive)  
✅ **Test path** — HVAC Intake end-to-end test  
✅ **Rollback plan** — Safe recovery at each stage  
✅ **Continuity fields** — Source metadata for full traceability  
✅ **Risk controls** — Airtable read-only, no destructive actions, no Canon connection  

### What This Document Did NOT Do (Intentionally)

❌ Create any SowerBase tables  
❌ Import any Airtable data  
❌ Modify Airtable base, tables, or fields  
❌ Connect Canon data  
❌ Modify askthih.com integrations  
❌ Change public routing  

### Next Step (After Plan Approval)

1. **Local Schema Creation**
   - Create SowerBase AskTHIH tables based on this design
   - Run full backup immediately after schema creation
   - Commit schema code to git

2. **Tier 0 Test Execution**
   - Create HVAC Intake test form
   - Submit test intake
   - Verify workflow end-to-end
   - Confirm no Airtable dependency

3. **Document Results**
   - Create test execution report
   - Verify Tier 0 ready for Tier 1

**Estimated Timeline for Full Migration:**
- Tier 0: 1-2 days (schema + test)
- Tier 1: 3-5 days (remaining verticals + leads)
- Tier 2: 2-3 days (archive/historical)
- Staged go-live: 2-3 days (testing + switch)
- **Total: ~2 weeks** (Tier 0 test → public production)

---

## Appendix: AskTHIH Airtable Base Reference

**Base ID:** app60wQWdbbgyqTcL  
**Base Name:** askthih  
**Access:** Create permission via Airtable connector  
**Read Status:** Active (source of truth during migration)  
**Modification Status:** READ-ONLY (no changes permitted during this phase)  

**Last Audited:** 2026-06-27  
**Tables Discovered:** 24  
**Migration Planning:** Complete  
**Schema Ready:** Awaiting approval to implement  

---

**Status:** ✅ **PLAN COMPLETE — READY FOR APPROVAL**  
**Next Action:** Review and approve migration plan; then proceed with local schema creation and Tier 0 test.
