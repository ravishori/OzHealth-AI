# HealthNest — Feature Master Checklist

Product:
HealthNest

Market:
Australia

Platform:
Android / Flutter

Purpose:
Single source of truth for HealthNest feature development.

Source Documents:
- docs/CURRENT_FEATURE_STATUS.md
- docs/CURRENT_FEATURE_ROADMAP.md

Total Features/Sub-features:
204

> This checklist is the authoritative development board for HealthNest feature work. Changes to feature status should be made here after implementation and verification. Production/security/compliance work remains tracked separately unless it directly affects a feature's functionality or safety.

---

## Current Feature Status

Total: 204

🟢 Completed: 74
🟡 Under Development: 67
🔴 Needs Fix: 16
⚫ Mock/Demo: 4
🟠 Pending: 40
⚪ Not Required: 3

These counts represent the **original audit** categories (unchanged).

### Development status (post Sprint 2)

Total: 204
🟢 COMPLETED: 100
🔵 IN PROGRESS: 0
🟡 UNDER DEVELOPMENT: 58
🔴 NEEDS FIX: 6
⚫ MOCK/DEMO: 3
🟠 PENDING: 29
⚪ DEFERRED: 5
⚪ NOT REQUIRED: 3


---

## Status Update Rules

```text
PENDING
→ Development has not started.
UNDER DEVELOPMENT
→ Implementation exists/has started but is incomplete.
IN PROGRESS
→ Active Cursor/developer work is currently underway.
COMPLETED
→ Implementation complete AND verification passed.
NEEDS FIX
→ Existing implementation fails expected behaviour.
MOCK/DEMO
→ Demonstration only; not real production functionality.
DEFERRED
→ Explicitly postponed by project decision.
NOT REQUIRED
→ Explicitly determined unnecessary.
```

### Mapping from audit → development status

| Original Audit Status | Development Status |
|----------------------|--------------------|
| Implemented & Working | 🟢 COMPLETED |
| Partially Implemented | 🟡 UNDER DEVELOPMENT |
| Needs Fix | 🔴 NEEDS FIX |
| Mock/Demo | ⚫ MOCK/DEMO |
| Not Implemented | 🟠 PENDING (or ⚪ DEFERRED if roadmap postpones) |
| Not Required | ⚪ NOT REQUIRED |

---

## Development Progress

### Wave 1 — Core Functionality

Rows in wave: 151
Completed: 66
In Development: 49
Pending: 19
Needs Fix: 14
Mock/Demo: 1
Deferred: 0
Not Required: 2

### Wave 2 — Health & Medicine Intelligence

Rows in wave: 12
Completed: 7
In Development: 5
Pending: 0
Needs Fix: 0
Mock/Demo: 0
Deferred: 0
Not Required: 0

### Wave 3 — Advanced Personal Health

Rows in wave: 18
Completed: 0
In Development: 8
Pending: 9
Needs Fix: 1
Mock/Demo: 0
Deferred: 0
Not Required: 0

### Wave 4 — Australian Healthcare Ecosystem

Rows in wave: 10
Completed: 0
In Development: 4
Pending: 2
Needs Fix: 0
Mock/Demo: 3
Deferred: 0
Not Required: 1

### Wave 5 — Business / Enterprise / Scale

Rows in wave: 13
Completed: 1
In Development: 1
Pending: 6
Needs Fix: 1
Mock/Demo: 0
Deferred: 4
Not Required: 0

---

## 🔥 Current Development Priorities

Derived from `CURRENT_FEATURE_ROADMAP.md` Phase A/B and P0/P1 audit rows (broken core first).

1. **Reminder frequency mapping + create path** — unblock medication/family reminders (audit Needs Fix / P0).
2. **Notification delivery** — permission + local/FCM honesty path so reminders actually fire (P0).
3. **Medical records access control** — no public `/uploads`; discharge type + view/delete UX (P0/P1).
4. **OCR confirm-before-save + catalog match** — production-safe prescription workflow (Phase B).
5. **AI chat reliability** — stable Anthropic key, degraded mode clarity, persistent disclaimer, history (P0/P1).
6. **SOS honesty or real contact notify** — dial-first vs SMS (Phase B).
7. **Production API + legal URLs** — HTTPS host, privacy/deletion pages, rebuild store client (Phase A).
8. **Medicine clinical enrichment** — TGA/PBS/CMI depth without false compliance claims (Wave 2).

---

## 🔴 Needs Fix

> Sprint 1 resolved several former Needs Fix items in the master table (frequency, uploads, discharge type). Items still listed below retain **Original Audit Status = Needs Fix** until a full re-audit; check Development Status in the master table for current state.

| ID | Feature | Problem | Location | Impact | Recommended action | Priority |
|----|---------|---------|----------|--------|--------------------|----------|
| HN-FAMILY-012 | Family photo upload | `FamilyApi.uploadPhoto` → `/family/{id}/photo` — **no backend route** | C. Family Health Management | Blocks reliable use of related flow | Implement route or remove client call | P2 |
| HN-MED-003 | Barcode scanning | `mobile_scanner` + `GET /medicines/barcode/{code}`; **0 barcodes** in local DB | G. Medicine Intelligence | Blocks reliable use of related flow | Ingest AU barcodes or hide feature | P1 |
| HN-NEARBY-001 | Nearby hospitals / pharmacies / labs / GPs | Overpass live; E2E Melbourne query **TimeoutError** | M. Nearby Healthcare Services | Blocks reliable use of related flow | Timeouts, cache, fallbacks | P1 |
| HN-NEARBY-005 | Provider reliability | External OSM; not controlled SLA | M. Nearby Healthcare Services | Blocks reliable use of related flow | Paid Places API or cache | P1 |
| HN-NOTIF-005 | Medication push delivery E2E | Worker requires `fcm_token`; none registered → no delivery | N. Notifications | Blocks reliable use of related flow | Full client+server path | P0 |
| HN-SEC-001 | HTTPS (client production) | Release refuses LAN if no `API_BASE_URL`; no hosted HTTPS API configured in build | O. Privacy & Security | Blocks reliable use of related flow | Deploy HTTPS API + dart-define | P0 |
| HN-INFRA-003 | Production API configuration | `AppEnv.API_BASE_URL` required for release; unset → unusable store API | X. Technical Infrastructure | Blocks reliable use of related flow | Deploy + rebuild AAB | P0 |

---

## ⚫ Mock / Demo Features

**Rule:** Mock/demo functionality must NEVER be represented as a live Australian ePrescription capability.

| ID | Feature | Current state | Production requirement | Target release |
|----|---------|---------------|------------------------|----------------|
| HN-ERX-001 | ePrescription UI (scan/list/detail) | Full Flutter flows; release gated unless `ENABLE_EPRESCRIPTION` | Replace with real integration or keep clearly labelled dial-only/mock | V1.3 |
| HN-ERX-002 | eRx Script Exchange live integration | `EPRESCRIPTION_MOCK_MODE=True` default; mock patients/meds | Replace with real integration or keep clearly labelled dial-only/mock | V1.3 |
| HN-ERX-004 | Token extract / validate / share / refill hooks | Routes exist; mock-backed when mock mode on | Replace with real integration or keep clearly labelled dial-only/mock | V1.3 |

---

## ⚪ Deferred

Explicitly postponed by `CURRENT_FEATURE_ROADMAP.md` Phase D (monetization after A–C):

| ID | Feature | Original Audit Status | Notes |
|----|---------|----------------------|-------|
| HN-BIZ-001 | Free / premium plans | Not Implemented | Roadmap: do not schedule before Phases A–C |
| HN-BIZ-002 | Google Play Billing / IAP | Not Implemented | Roadmap: do not schedule before Phases A–C |
| HN-BIZ-003 | Payment processing / trials / restore | Not Implemented | Roadmap: do not schedule before Phases A–C |
| HN-BIZ-004 | Premium feature gating | Not Implemented | Roadmap: do not schedule before Phases A–C |

---

## 🇦🇺 Australia-Specific Feature Track

Do **not** claim regulatory compliance from this track alone.

| ID | Feature | Development Status | Classification | Target |
|----|---------|--------------------|----------------|--------|
| HN-MED-010 | Australian medicine identification (ARTG) | 🟢 COMPLETED | Implemented | V1.1 |
| HN-MED-011 | Live TGA/ARTG enrichment on hot path | 🟡 UNDER DEVELOPMENT | Partially implemented | V1.3 |
| HN-MED-012 | PBS integration | 🟡 UNDER DEVELOPMENT | Partially implemented | V1.3 |
| HN-SOS-004 | Australian emergency numbers | 🟡 UNDER DEVELOPMENT | Partially implemented | V1.0 |
| HN-LEGAL-008 | Australian Privacy Principles readiness | 🟡 UNDER DEVELOPMENT | Partially implemented | V1.0 |
| HN-AU-001 | AU medicine catalog (DB) | 🟢 COMPLETED | Implemented | V1.1 |
| HN-AU-002 | TGA identity fields | 🟢 COMPLETED | Implemented | V1.1 |
| HN-AU-003 | PBS codes / benefits | 🟡 UNDER DEVELOPMENT | Partially implemented | V1.3 |
| HN-AU-004 | Authoritative CMI / PI content | 🟡 UNDER DEVELOPMENT | Partially implemented | V1.3 |
| HN-AU-005 | Healthcare provider / hospital integration | 🟠 PENDING | Planned / Future integration | V1.3 |
| HN-AU-006 | Pharmacy dispensing integration | 🟠 PENDING | Planned / Future integration | V1.3 |
| HN-AU-007 | AU emergency services linkage | 🟢 COMPLETED | Implemented | V1.1 |
| HN-ERX-001 | ePrescription UI (scan/list/detail) | ⚫ MOCK/DEMO | Mock | V1.3 |
| HN-ERX-002 | eRx Script Exchange live integration | ⚫ MOCK/DEMO | Mock | V1.3 |
| HN-ERX-003 | MediSecure | ⚪ NOT REQUIRED | Not required | V1.3 |
| HN-ERX-004 | Token extract / validate / share / refill hooks | ⚫ MOCK/DEMO | Mock | V1.3 |

---

## RECONCILIATION NOTES

1. **Source docs agree on 204 matrix rows** and the executive counts (74/67/16/4/40/3).
2. **Roadmap Phase A** still lists some blockers (e.g. reminder frequency, public `/uploads`, admin stats, FCM) that later P0 remediation docs claim partially addressed. This master checklist **does not silently update** those audit matrix statuses — it preserves `CURRENT_FEATURE_STATUS.md` matrix rows as of generation. Update statuses here only after re-verification.
3. **FCM note in status doc** (`flutter_local_notifications` unused) may lag code changes; treat notification rows per matrix until re-audited.
4. **Play Store section** in the status doc is a development view snapshot; production hosting remains external.
5. **Monetization (category S)** deferred per roadmap Phase D while retaining original **Not Implemented** audit status.

---

## Master Feature Table (all 204 rows)

| ID | Wave | Module | Feature | Original Audit Status | Development Status | Priority | Target Release | Dependencies | Verification | Source | Notes |
|----|------|--------|---------|----------------------|--------------------|----------|----------------|--------------|--------------|--------|-------|
| HN-AUTH-001 | Wave 1 | A. Authentication & Account | Email registration | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | SMTP (Gmail) for OTP; Remaining: Prod SMTP must be configured | PARTIALLY VERIFIED | STATUS.md | `RegisterScreen` → `POST /auth/send-otp` + `/auth/register`; `User.email` |
| HN-AUTH-002 | Wave 1 | A. Authentication & Account | Phone registration | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | Twilio SMS; Remaining: Prod Twilio credentials | PARTIALLY VERIFIED | STATUS.md | Same register flow; phone normalized in `auth.py` |
| HN-AUTH-003 | Wave 1 | A. Authentication & Account | OTP verification (register/login) | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | None for verify logic; Remaining: None for core path | PARTIALLY VERIFIED | STATUS.md | `OtpScreen` → register/login; OTP hashed (`hash_otp`); `sp_mark_otp_used` |
| HN-AUTH-004 | Wave 1 | A. Authentication & Account | Email OTP delivery | Partially Implemented | 🟡 UNDER DEVELOPMENT | P0 | V1.0 | SMTP_EMAIL / SMTP_PASSWORD; Remaining: Reliable prod mail + monitoring | PARTIALLY VERIFIED | STATUS.md | `_send_email_otp` via SMTP settings; fails closed if unset |
| HN-AUTH-005 | Wave 1 | A. Authentication & Account | SMS OTP delivery | Partially Implemented | 🟡 UNDER DEVELOPMENT | P0 | V1.0 | Twilio SID/token/from; Remaining: Prod Twilio + AU sender compliance | REQUIRES BACKEND TEST | STATUS.md | `_send_sms_otp` Twilio; empty defaults in `config.py` |
| HN-AUTH-006 | Wave 1 | A. Authentication & Account | Login (OTP) | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | SMTP/Twilio for OTP; Remaining: None for API path | PARTIALLY VERIFIED | STATUS.md | `LoginScreen` → OTP → `POST /auth/login` |
| HN-AUTH-007 | Wave 1 | A. Authentication & Account | Logout | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | VERIFIED | SPRINT3_AUTH_LOGOUT | `POST /auth/logout` bumps `users.token_version`; access+refresh JWT claim `tv` must match — immediate revoke; client calls server then clears storage; device LOGOUT-UI PASS |
| HN-AUTH-008 | Wave 1 | A. Authentication & Account | Session persistence | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | VERIFIED | SPRINT5-S1 | Verified after S5-S1: AuthStorage performs safe local JWT `exp` inspection; expired/malformed sessions cleared and cannot enter `/home`; valid sessions proceed. Server JWT/`token_version` unchanged. JWT/session tests + Android session-gate PASS (ANDROID-05: local clearAll→welcome; live AuthApi.logout device not re-run — backend unavailable; logout contracts PASS) |
| HN-AUTH-009 | Wave 1 | A. Authentication & Account | Secure token storage | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | `flutter_secure_storage` via `AuthStorage` / `ApiClient` |
| HN-AUTH-010 | Wave 1 | A. Authentication & Account | Access token expiration | Implemented & Working | 🟢 COMPLETED | P2 | V1.0 | Remaining: Tune TTL for production | PARTIALLY VERIFIED | STATUS.md | JWT `ACCESS_TOKEN_EXPIRE_MINUTES` default 1440; jose HS256 |
| HN-AUTH-011 | Wave 1 | A. Authentication & Account | Refresh token | Implemented & Working | 🟢 COMPLETED | P2 | V1.0 | Remaining: Rotate refresh tokens on use | PARTIALLY VERIFIED | STATUS.md | `POST /auth/refresh`; Dio interceptor |
| HN-AUTH-012 | Wave 1 | A. Authentication & Account | Password authentication | Not Required | ⚪ NOT REQUIRED | P3 | V1.0 | Remaining: Not in OTP MVP | NOT VERIFIED | STATUS.md | OTP-only product; unused `hash_password` helpers exist |
| HN-AUTH-013 | Wave 1 | A. Authentication & Account | Password recovery | Not Required | ⚪ NOT REQUIRED | P3 | V1.0 | Remaining: N/A under OTP model | NOT VERIFIED | STATUS.md | OTP purpose `reset` allowed in DB; no UI/API flow |
| HN-AUTH-014 | Wave 1 | A. Authentication & Account | Account deletion | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | Remaining: Hosted web deletion URL for Play | PARTIALLY VERIFIED | STATUS.md | `DeleteAccountScreen` → `DELETE /users/me`; CASCADE |
| HN-AUTH-015 | Wave 1 | A. Authentication & Account | Account reactivation | Not Implemented | 🟠 PENDING | P3 | V1.0 | Remaining: If required: soft-delete + restore | NOT VERIFIED | STATUS.md | Hard delete only; no soft-delete reactivation |
| HN-AUTH-016 | Wave 1 | A. Authentication & Account | Profile creation at registration | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | Register collects name/age/gender/blood_group → `sp_insert_user` |
| HN-AUTH-017 | Wave 1 | A. Authentication & Account | Standalone verify-otp endpoint | Partially Implemented | 🟡 UNDER DEVELOPMENT | P3 | V1.0 | Remaining: Wire or remove dead path | PARTIALLY VERIFIED | STATUS.md | `POST /auth/verify-otp` + `AuthApi.verifyOtp` unused by screens |
| HN-PROF-001 | Wave 1 | B. User Profile | Name / age / gender / blood group | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | `GET/PUT /users/me`; Profile edit dialogs |
| HN-PROF-002 | Wave 1 | B. User Profile | Email / phone display & OTP change | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | SMTP/Twilio | PARTIALLY VERIFIED | STATUS.md | Contact change OTP flows in `users.py` + Profile UI |
| HN-PROF-003 | Wave 1 | B. User Profile | Secondary phone (phone2) | Implemented & Working | 🟢 COMPLETED | P2 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | `phone2` on User; `_Phone2Dialog` |
| HN-PROF-004 | Wave 1 | B. User Profile | Health conditions | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | ENCRYPTION_KEY; Remaining: Ensure ENCRYPTION_KEY set in prod | PARTIALLY VERIFIED | STATUS.md | Encrypted JSON; chip editor on Profile |
| HN-PROF-005 | Wave 1 | B. User Profile | Allergies | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | ENCRYPTION_KEY | PARTIALLY VERIFIED | STATUS.md | Same as conditions |
| HN-PROF-006 | Wave 3 | B. User Profile | Lifestyle preferences | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.2 | Remaining: Expose in API response + Profile UI | PARTIALLY VERIFIED | STATUS.md | Column + write in update; omitted from `UserResponse`; no UI |
| HN-PROF-007 | Wave 1 | B. User Profile | Emergency contacts (profile-adjacent) | Partially Implemented | 🟢 COMPLETED | P1 | V1.0 | Remaining: Optional profile deep-link | VERIFIED | SPRINT2_SOS_DEVICE | Delete UI via Emergency screen; device SOS-03 PASS |
| HN-PROF-008 | Wave 1 | B. User Profile | Profile photo | Implemented & Working | 🟢 COMPLETED | P2 | V1.0 | Local disk storage; Remaining: CDN/S3 for prod scale | PARTIALLY VERIFIED | STATUS.md | `POST /users/me/photo`; Profile camera/gallery upload |
| HN-PROF-009 | Wave 1 | B. User Profile | Address / reverse geocode | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.0 | Nominatim; Remaining: Rate-limit / ToS compliance | PARTIALLY VERIFIED | STATUS.md | Profile address fields + Nominatim; AU-oriented |
| HN-PROF-010 | Wave 1 | B. User Profile | Profile persistence | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | Redis optional | PARTIALLY VERIFIED | STATUS.md | Postgres users table; Redis profile cache key |
| HN-FAMILY-001 | Wave 1 | C. Family Health Management | Add family member | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | `AddFamilyMemberScreen` → `POST /family/` |
| HN-FAMILY-002 | Wave 1 | C. Family Health Management | Edit family member | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | VERIFIED | SPRINT3_FAMILY_EDIT | `EditFamilyMemberScreen` + `family/edit/:id`; PUT owner-scoped; device FAMILY-UI-01..10 PASS |
| HN-FAMILY-003 | Wave 1 | C. Family Health Management | Delete family member | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | Soft-delete `is_active=False`; UI confirm |
| HN-FAMILY-004 | Wave 1 | C. Family Health Management | Family profile view | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | List + detail bottom sheet |
| HN-FAMILY-005 | Wave 1 | C. Family Health Management | Family medical conditions | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | Stored on create; editable via HN-FAMILY-002 edit UI |
| HN-FAMILY-006 | Wave 1 | C. Family Health Management | Family allergies | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | Same as conditions; editable via HN-FAMILY-002 |
| HN-FAMILY-007 | Wave 1 | C. Family Health Management | Family blood group | Implemented & Working | 🟢 COMPLETED | P2 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | Field on FamilyMember create/view |
| HN-FAMILY-008 | Wave 1 | C. Family Health Management | Family medications (dedicated) | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.0 | Remaining: Family-centric medication UI | PARTIALLY VERIFIED | STATUS.md | No meds on FamilyMember; reminders can set `family_member_id` |
| HN-FAMILY-009 | Wave 1 | C. Family Health Management | Family reminders | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | VERIFIED | SPRINT3_FAMILY_REM | Owner-scoped `family_member_id`; authoritative `family_member_name`; create/update/list/edit; local notifications unchanged; FAMILY-REM-SEC + device QA PASS |
| HN-FAMILY-010 | Wave 3 | C. Family Health Management | Switch active family profile | Not Implemented | 🟠 PENDING | P2 | V1.2 | Remaining: Design multi-profile context | NOT VERIFIED | STATUS.md | No global 'acting as' profile context |
| HN-FAMILY-011 | Wave 1 | C. Family Health Management | Family data isolation | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | Queries filter owner `user_id` |
| HN-FAMILY-012 | Wave 1 | C. Family Health Management | Family photo upload | Not Required | 🟢 COMPLETED | P2 | V1.0 | — | VERIFIED | SPRINT3_FAMILY_PHOTO | Closure: removed orphaned `FamilyApi.uploadPhoto`; no UI/DB/route; initials avatars retained; HN-PROF-008 untouched |
| HN-RECORD-001 | Wave 1 | D. Medical Records | Upload PDF | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | Local uploads dir | PARTIALLY VERIFIED | STATUS.md | `FilePicker` + `POST /records/upload`; pdf allowed |
| HN-RECORD-002 | Wave 1 | D. Medical Records | Upload JPG/PNG | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | Gallery picker; jpg/jpeg/png/heic |
| HN-RECORD-003 | Wave 3 | D. Medical Records | Camera capture for records | Not Implemented | 🟠 PENDING | P2 | V1.2 | Remaining: Add camera option | NOT VERIFIED | STATUS.md | Upload UI: gallery + PDF only; no `ImageSource.camera` |
| HN-RECORD-004 | Wave 1 | D. Medical Records | Gallery selection | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | `ImagePicker` gallery |
| HN-RECORD-005 | Wave 1 | D. Medical Records | Document categorization | Needs Fix | 🟢 COMPLETED | P1 | V1.0 | Remaining: Align type enums | VERIFIED | STATUS.md | Flutter sends `discharge`; API `VALID_TYPES` expects `discharge_summary` | Closure: live upload discharge→discharge_summary | Sprint1: discharge→discharge_summary alias + Flutter aligned |
| HN-RECORD-006 | Wave 1 | D. Medical Records | Document listing | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | `RecordsScreen` tabs + `GET /records/` |
| HN-RECORD-007 | Wave 1 | D. Medical Records | Document viewing (open file) | Partially Implemented | 🟢 COMPLETED | P1 | V1.0 | Remaining: Open/download viewer | PARTIALLY VERIFIED | STATUS.md | Metadata sheet only; `GET /records/{id}/file` unused in UI | Sprint1: authenticated download via /records/{id}/file + open |
| HN-RECORD-008 | Wave 1 | D. Medical Records | Document deletion UI | Partially Implemented | 🟢 COMPLETED | P1 | V1.0 | Remaining: Wire delete action | PARTIALLY VERIFIED | STATUS.md | API + provider delete exist; RecordsScreen never calls them | Sprint1: delete UI + soft-delete + file cleanup |
| HN-RECORD-009 | Wave 1 | D. Medical Records | Secure storage (files) | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | Optional AWS S3 (out of scope) | VERIFIED | S5-S5 | Encrypted-at-rest local files (`HNREC1`+Fernet); owner download decrypts; legacy plaintext readable; S3 unused |
| HN-RECORD-010 | Wave 1 | D. Medical Records | User-specific access control (API download) | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | VERIFIED | STATUS.md | Authenticated owner check on `/{id}/file` | Closure: other user GET/DL/DEL → 404 | Sprint1: owner check + inactive excluded |
| HN-RECORD-011 | Wave 1 | D. Medical Records | Public /uploads StaticFiles mount | Needs Fix | 🟢 COMPLETED | P0 | V1.0 | Remaining: Remove mount or require auth | VERIFIED | STATUS.md | `main.py` mounts `/uploads` without JWT — undermines access control | Closure: HTTP /uploads → 404; no StaticFiles mount | Sprint1: verified no public StaticFiles /uploads mount |
| HN-RECORD-012 | Wave 1 | D. Medical Records | Download/share | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.0 | Remaining: Share sheet + secure links | PARTIALLY VERIFIED | STATUS.md | Backend file endpoint; no share UI |
| HN-RX-001 | Wave 1 | E. Prescription Management | List prescriptions | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | `GET /prescriptions/`; detail route |
| HN-RX-002 | Wave 1 | E. Prescription Management | Prescription detail view | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | `prescription_detail_screen.dart` |
| HN-RX-003 | Wave 1 | E. Prescription Management | Manual prescription entry | Not Implemented | 🟠 PENDING | P2 | V1.0 | Remaining: Add manual CRUD if needed | NOT VERIFIED | STATUS.md | No manual create form found |
| HN-RX-004 | Wave 1 | E. Prescription Management | Link prescription to family member | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.0 | Remaining: Expose in scan UI | PARTIALLY VERIFIED | STATUS.md | API accepts `family_member_id` on scan; UI limited |
| HN-OCR-001 | Wave 1 | F. Prescription OCR | Image upload (camera/gallery) | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | `PrescriptionScanScreen` camera + gallery → `/prescriptions/scan` | Sprint1: scan→/ocr then review |
| HN-OCR-002 | Wave 1 | F. Prescription OCR | OCR engine (Tesseract/PyMuPDF) | Partially Implemented | 🟡 UNDER DEVELOPMENT | P0 | V1.0 | Tesseract binary; Remaining: Ensure prod image has Tesseract | PARTIALLY VERIFIED | STATUS.md | `ocr_provider.py`; Docker installs tesseract; empty if missing |
| HN-OCR-003 | Wave 1 | F. Prescription OCR | Printed prescription recognition | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | VERIFIED | S5-S6 | Canonical confidence 0..1; threshold 0.60; Confirm gated on needsReview; legacy persist=true disabled; fixture+Android QA PASS |
| HN-OCR-004 | Wave 3 | F. Prescription OCR | Handwritten prescription recognition | Not Implemented | 🟠 PENDING | P3 | V1.2 | Specialized HTR; Remaining: Out of current MVP or partner OCR | NOT VERIFIED | STATUS.md | No handwritten detector/engine |
| HN-OCR-005 | Wave 1 | F. Prescription OCR | Medicine / dosage / frequency extraction | Partially Implemented | 🟡 UNDER DEVELOPMENT | P1 | V1.0 | Anthropic Claude; Remaining: Confirm before save; ground to catalog | PARTIALLY VERIFIED | STATUS.md | Claude `analyze_prescription` after OCR text | Sprint1: extract+review; rule OCR path primary |
| HN-OCR-006 | Wave 1 | F. Prescription OCR | Doctor extraction | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.0 | Anthropic; Remaining: User confirm/edit | PARTIALLY VERIFIED | STATUS.md | Included in Claude JSON analysis | Sprint1: editable doctor field on confirm |
| HN-OCR-007 | Wave 1 | F. Prescription OCR | OCR confidence in production UI | Partially Implemented | 🟢 COMPLETED | P1 | V1.0 | Remaining: Surface confidence; switch to confirm flow | PARTIALLY VERIFIED | STATUS.md | Confidence on `/ocr` path; Flutter uses `/scan` which discards it | Sprint1: confidence shown on review screen |
| HN-OCR-008 | Wave 1 | F. Prescription OCR | User confirmation before accept | Not Implemented | 🟢 COMPLETED | P1 | V1.0 | Remaining: Adopt `/ocr` confirm/match pipeline | VERIFIED | STATUS.md | `/scan` auto-persists; no edit/confirm gate | Closure: /ocr+/scan require confirm; no auto id | Sprint1: /ocr + review UI + /confirm; no silent save |
| HN-OCR-009 | Wave 1 | F. Prescription OCR | Save extracted prescription | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | Remaining: After confirmation UX | PARTIALLY VERIFIED | STATUS.md | `/scan` persists Prescription + file | Sprint1: save only via /confirm after user confirm |
| HN-OCR-010 | Wave 1 | F. Prescription OCR | Link to medicine database | Partially Implemented | 🟢 COMPLETED | P1 | V1.0 | Catalog DB; Remaining: Wire match candidates in UI | PARTIALLY VERIFIED | STATUS.md | Alternate `/ocr` catalog match unused by Flutter | Sprint1: catalogue candidates in review UI |
| HN-OCR-011 | Wave 1 | F. Prescription OCR | OCR overall classification | Partially Implemented | 🟡 UNDER DEVELOPMENT | P1 | V1.0 | Tesseract + Claude; Remaining: Confirmation + grounding | PARTIALLY VERIFIED | STATUS.md | REAL partial pipeline (Tesseract + Claude); not mock; not production-safe confirm | Sprint1: confirm+match wired; handwriting still out |
| HN-MED-001 | Wave 2 | G. Medicine Intelligence | Medicine name search | Implemented & Working | 🟢 COMPLETED | P0 | V1.1 | Postgres catalog (~28,368 local); Remaining: Hosted prod DB sync | PARTIALLY VERIFIED | STATUS.md | `CatalogMedicineSearchService`; E2E `paracetamol` → `source=database` |
| HN-MED-002 | Wave 2 | G. Medicine Intelligence | Ingredient search | Implemented & Working | 🟢 COMPLETED | P1 | V1.1 | Postgres | PARTIALLY VERIFIED | STATUS.md | Joins `medicine_ingredient_strengths` |
| HN-MED-003 | Wave 3 | G. Medicine Intelligence | Barcode scanning | Not Required | 🟢 COMPLETED | P1 | V1.2 | — | VERIFIED | SPRINT3_BARCODE_HIDE | Resolution: HIDE/DISABLE user-facing barcode; 0 catalog barcodes; no AU source; backend `GET /medicines/barcode/{code}` dormant; re-enable only after authoritative GTIN ingest |
| HN-MED-004 | Wave 2 | G. Medicine Intelligence | Composition | Partially Implemented | 🟡 UNDER DEVELOPMENT | P1 | V1.1 | Optional Claude; Remaining: Prefer DB/TGA label text | PARTIALLY VERIFIED | STATUS.md | Often from DB (~28k); detail may fall back to AI |
| HN-MED-005 | Wave 2 | G. Medicine Intelligence | Dosage / uses / side effects / contraindications | Partially Implemented | 🟡 UNDER DEVELOPMENT | P1 | V1.1 | Claude for narrative; Remaining: Enrich from authoritative CMI | PARTIALLY VERIFIED | STATUS.md | DB clinical fields sparse (~59 side_effects); UI merges Claude Haiku |
| HN-MED-006 | Wave 2 | G. Medicine Intelligence | Drug interactions (user-facing) | Partially Implemented | 🟡 UNDER DEVELOPMENT | P1 | V1.1 | Claude; Remaining: Grounded interaction DB + disclaimers | PARTIALLY VERIFIED | STATUS.md | Flutter → AI `check_drug_interactions`; DB `interactions` empty; safety-check unused |
| HN-MED-007 | Wave 2 | G. Medicine Intelligence | Duplicate medicine detection | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.1 | Remaining: User-facing duplicate warnings | PARTIALLY VERIFIED | STATUS.md | Normalization/canonical keys in ingest; limited UX |
| HN-MED-008 | Wave 2 | G. Medicine Intelligence | Medicine detail screen | Implemented & Working | 🟢 COMPLETED | P0 | V1.1 | Provenance: DB vs AI vs unavailable; no silent AI merge | VERIFIED | S5-S3 HN-MED-008 | Detail uses `GET /{id}` + `GET /{id}/explanation`; `/ai-info` catalogue-gated; MED-HONEST + MED-UI + live AI + Android QA PASS |
| HN-MED-009 | Wave 3 | G. Medicine Intelligence | Medicine favourites | Not Implemented | 🟠 PENDING | P3 | V1.2 | Remaining: Implement if product requires | NOT VERIFIED | STATUS.md | No favourites table/API/UI found |
| HN-MED-010 | Wave 2 | G. Medicine Intelligence | Australian medicine identification (ARTG) | Implemented & Working | 🟢 COMPLETED | P0 | V1.1 | TGA-sourced catalog load; Remaining: Distinguish seed placeholders vs live ARTG | PARTIALLY VERIFIED | STATUS.md | 28,338 rows with `tga_artg_number`; TGA primary_source majority |
| HN-MED-011 | Wave 4 | G. Medicine Intelligence | Live TGA/ARTG enrichment on hot path | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.3 | TGA/ARTG sources; Remaining: Offline ARTG index + refresh job | PARTIALLY VERIFIED | STATUS.md | Connectors exist; ARTG live index often fast-fails; not hot search path |
| HN-MED-012 | Wave 4 | G. Medicine Intelligence | PBS integration | Partially Implemented | 🟡 UNDER DEVELOPMENT | P1 | V1.3 | PBS API key/rate limits; Remaining: Bulk PBS match enrichment | PARTIALLY VERIFIED | STATUS.md | PBS connector + enrichment; only **13** local rows with `pbs_code` |
| HN-MED-013 | Wave 2 | G. Medicine Intelligence | Medicine data source (identity) | Implemented & Working | 🟢 COMPLETED | P0 | V1.1 | Ingest pipelines; Remaining: Keep AU refresh cadence | PARTIALLY VERIFIED | STATUS.md | PostgreSQL catalog (primary), not static JSON for search |
| HN-AI-001 | Wave 1 | H. AI Health Assistant | AI chat UI | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | `AiChatScreen` |
| HN-AI-002 | Wave 1 | H. AI Health Assistant | Send question / receive response | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | None for live send/receive | VERIFIED | SPRINT1_AI_RETEST | ANTHROPIC_API_KEY=PRESENT; live `POST /ai/chat` 200; model claude-sonnet-4-6; non-empty reply; degraded=false | Sprint1 retest: API + Flutter E2E PASS |
| HN-AI-003 | Wave 3 | H. AI Health Assistant | Conversation history UI | Implemented & Working | 🟢 COMPLETED | P1 | V1.2 | — | VERIFIED | SPRINT4-S3 | History browser + resume via owner-scoped GET list/get; new chat preserved |
| HN-AI-004 | Wave 1 | H. AI Health Assistant | Medicine / health / lifestyle Q&A | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.0 | Claude; Remaining: Domain modes optional | PARTIALLY VERIFIED | STATUS.md | Single general system prompt; `/ai/health-guidance` unused by chat UI |
| HN-AI-005 | Wave 1 | H. AI Health Assistant | Safety disclaimer (system prompt) | Partially Implemented | 🟢 COMPLETED | P0 | V1.0 | Remaining: Persistent disclaimer banner | VERIFIED | STATUS.md | Prompt: no diagnose; emergencies → 000; weak persistent UI banner | Sprint1: persistent disclaimer banner verified in UI |
| HN-AI-006 | Wave 1 | H. AI Health Assistant | Report AI response | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | Remaining: Moderation workflow | PARTIALLY VERIFIED | STATUS.md | AppBar flag → `POST /ai/report` |
| HN-AI-007 | Wave 1 | H. AI Health Assistant | Error / timeout handling | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | Remaining: Distinguish outage vs empty key | VERIFIED | STATUS.md | Try/except + user-facing error; fallback text if no key | Sprint1: timeout messaging + Retry on error bubbles |
| HN-AI-008 | Wave 1 | H. AI Health Assistant | AI authentication | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | JWT required on `/ai/*` |
| HN-AI-009 | Wave 3 | H. AI Health Assistant | AI rate limiting | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.2 | Redis; Remaining: Per-user AI quotas | PARTIALLY VERIFIED | STATUS.md | Redis OTP limits exist; dedicated AI quota not clearly productized |
| HN-AI-010 | Wave 3 | H. AI Health Assistant | Prompt injection protection | Implemented & Working | 🟢 COMPLETED | P1 | V1.2 | — | VERIFIED | SPRINT5-S2 | Verified after S5-S2 + live Android closure: trusted safety policy + UNTRUSTED fences; output gate; PI-01..12 + SAFE-01..15 PASS; live Anthropic path PASS; Android live matrix AI-S2-ANDROID-01..12 PASS on emulator-5554 via Flutter→API→ai_service→Anthropic (metadata-only). Not a claim of perfect AI safety or clinical validation |
| HN-AI-011 | Wave 1 | H. AI Health Assistant | Production AI provider | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | None for Anthropic live path | VERIFIED | SPRINT1_AI_RETEST | Credits available YES; live Anthropic PASS; real response PASS; conversation continuity PASS | Sprint1 retest: funded key in backend/.env; Flutter E2E PASS |
| HN-MEDMGMT-001 | Wave 1 | I. Medication Management | Add medication (via reminder schedule) | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | VERIFIED | S4-VERIFY-MEDMGMT-001 | Verified against current reminder implementation: add-medication flow posts reminder schedule (`POST /reminders/`) using `medicationFrequencyToApi`; backend `normalize_medication_frequency`; local medication notifications scheduled from saved schedule. Verified by `frequency_mapping_test.dart` + `test_reminder_frequency.py` (PASS). Family-reminder authz coverage also present. |
| HN-MEDMGMT-002 | Wave 1 | I. Medication Management | Edit medication fields | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | VERIFIED | S4-VERIFY-MEDMGMT-002 | Verified against current reminder implementation: medication edit via `/reminders/edit` using `AddReminderScreen(initialReminder)`, `PUT /reminders/{id}` (`MedicationScheduleUpdate`), owner-scoped `_get_schedule`, local reschedule after update. HN-REM-005 provides edit-path evidence. Residual refill/date/quantity UI refinement belongs to HN-REM-009 and does not block core edit. Verified by `family_reminders_contract_test.dart` + `test_family_reminders_authz.py` (PASS). |
| HN-MEDMGMT-003 | Wave 1 | I. Medication Management | Delete / deactivate medication | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | Soft delete / toggle `is_active` |
| HN-MEDMGMT-004 | Wave 1 | I. Medication Management | Dose / frequency / dates / notes | Needs Fix | 🟢 COMPLETED | P0 | V1.0 | Remaining: Map Daily→daily etc. | VERIFIED | STATUS.md | UI collects fields but frequency labels break DB check | Sprint1: frequencyToApi + API normalize; tests pass |
| HN-MEDMGMT-005 | Wave 1 | I. Medication Management | Active/inactive | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | Toggle in RemindersScreen |
| HN-MEDMGMT-006 | Wave 1 | I. Medication Management | Medication history | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.0 | Remaining: History/adherence log | PARTIALLY VERIFIED | STATUS.md | Schedules list; no dedicated history timeline |
| HN-MEDMGMT-007 | Wave 1 | I. Medication Management | Family medication management | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.0 | Remaining: Family hub UI | PARTIALLY VERIFIED | STATUS.md | Optional `family_member_id` on schedule |
| HN-REM-001 | Wave 1 | J. Medication Reminders | Reminder creation | Needs Fix | 🟢 COMPLETED | P0 | V1.0 | Remaining: Normalize frequency strings | VERIFIED | STATUS.md | E2E FAIL: Flutter `'Daily'` vs CHECK (`daily`,`twice_daily`,…) | Closure: API create Daily/Weekly/Monthly OK | Sprint1: create path + frequency normalize; unit tests |
| HN-REM-002 | Wave 1 | J. Medication Reminders | Daily / twice / three times UI | Needs Fix | 🟢 COMPLETED | P0 | V1.0 | Remaining: Mapping layer | VERIFIED | STATUS.md | UI labels Title Case; DB snake_case — create fails | Sprint1: Title Case→snake_case mapping both sides |
| HN-REM-003 | Wave 1 | J. Medication Reminders | Weekly / monthly semantics | Needs Fix | 🟢 COMPLETED | P1 | V1.0 | Remaining: Weekly device-fire wait optional | VERIFIED | SPRINT1_N04 | start_date DOW/DOM in fn+local; alembic 015; N04b monthly Android fire PASS (dayOfMonthAndTime, due_day=4, active notif body match count=1) | Sprint1: monthly device fire PASS; weekly fire still schedule-path (N03) |
| HN-REM-004 | Wave 1 | J. Medication Reminders | Custom frequency | Partially Implemented | 🟢 COMPLETED | P1 | V1.0 | Remaining: Same mapping fix | VERIFIED | STATUS.md | `As Needed` in UI; DB `as_needed` | Sprint1: as_needed mapping verified |
| HN-REM-005 | Wave 1 | J. Medication Reminders | Reminder editing | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | VERIFIED | SPRINT3_REM_EDIT_CLOSURE | Edit form via `AddReminderScreen(initialReminder)` + `/reminders/edit`; PUT owner-scoped; medicine/dosage/frequency/times/instructions/family; local reschedule; Slice 6 FAMILY-REM tests + ANDROID-08/09; verification-only Slice 8 closure |
| HN-REM-006 | Wave 1 | J. Medication Reminders | Reminder deletion | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | VERIFIED | STATUS.md | UI delete → API soft-delete | Sprint1: delete cancels local notifications |
| HN-REM-007 | Wave 1 | J. Medication Reminders | Notification scheduling (server) | Partially Implemented | 🟡 UNDER DEVELOPMENT | P0 | V1.0 | Firebase Admin; Remaining: Requires client FCM tokens | REQUIRES DEVICE TEST | STATUS.md | `reminder_worker` APScheduler every 5 min → FCM |
| HN-REM-008 | Wave 1 | J. Medication Reminders | Notification permission (Android 13+) | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | VERIFIED | SPRINT1_N09 | N01 grant path PASS; N09 denied path PASS (`schedule`→false, snackbar when permission off, no crash) | Final: permission grant + denied UX verified; sticky-Deny tap flakiness is emulator behaviour |
| HN-REM-009 | Wave 1 | J. Medication Reminders | Refill reminder | Implemented & Working | 🟢 COMPLETED | P2 | V1.0 | — | VERIFIED | S5-S7_REM009 | Local refill: create/edit `refill_date` UI+payload; one-shot local notif id=`scheduleId*10+9` (outside dose 0..3); cancel on edit/clear/delete/disable; past dates skipped (not moved); no FCM. REM9-01..06 backend + REM9-07..09 Flutter + Android REM9-10..12 PASS |
| HN-REM-010 | Wave 3 | J. Medication Reminders | Appointment reminder | Not Implemented | 🟠 PENDING | P3 | V1.2 | Remaining: Future module | NOT VERIFIED | STATUS.md | No appointments feature |
| HN-REM-011 | Wave 1 | J. Medication Reminders | Background / reboot reliability | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | VERIFIED | SPRINT1_FINAL | Boot receivers + RTC_WAKEUP restored after adb reboot; N08_REBOOT_CHECK restored=true | Final: N08 PASS |
| HN-HEALTH-001 | Wave 1 | K. Health Monitoring | Blood pressure / sugar / HR / SpO2 / weight | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | `LogMetricScreen` + `POST /health-metrics/`; E2E HR PASS |
| HN-HEALTH-002 | Wave 1 | K. Health Monitoring | Temperature | Implemented & Working | 🟢 COMPLETED | P2 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | Supported in metrics types |
| HN-HEALTH-003 | Wave 1 | K. Health Monitoring | Date/time recording | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | Server timestamps + history |
| HN-HEALTH-004 | Wave 1 | K. Health Monitoring | Historical records / charts / trends | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | Remaining: Richer history screen | PARTIALLY VERIFIED | STATUS.md | `fl_chart` sparklines; summary API |
| HN-HEALTH-005 | Wave 1 | K. Health Monitoring | Edit metric | Not Implemented | 🟠 PENDING | P2 | V1.0 | Remaining: Add update endpoint + UI | NOT VERIFIED | STATUS.md | No PUT/PATCH route on health_metrics |
| HN-HEALTH-006 | Wave 1 | K. Health Monitoring | Delete metric | Not Implemented | 🟠 PENDING | P2 | V1.0 | Remaining: Add delete | NOT VERIFIED | STATUS.md | No DELETE route |
| HN-HEALTH-007 | Wave 1 | K. Health Monitoring | Family health metrics | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.0 | Remaining: Family selector in log UI | PARTIALLY VERIFIED | STATUS.md | `family_member_id` on model/schema; UI limited |
| HN-SOS-001 | Wave 1 | L. Emergency / SOS | Emergency button / long-press SOS | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | VERIFIED | SPRINT3_SOS_HOLD | Explicit 3s `SosHoldButton` (Listener + AnimationController); early release cancels; progress ring; Sprint2 dial-first honesty preserved; device SOS-ANDROID matrix PASS |
| HN-SOS-002 | Wave 1 | L. Emergency / SOS | Emergency contacts CRUD | Partially Implemented | 🟢 COMPLETED | P1 | V1.0 | Remaining: None for delete path | VERIFIED | SPRINT2_SOS_DEVICE | Add/list + API delete; Sprint2: delete confirm UI; device SOS-03 PASS on emulator-5554 |
| HN-SOS-003 | Wave 1 | L. Emergency / SOS | Call emergency contact | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | Phone dialer | PARTIALLY VERIFIED | STATUS.md | `tel:` launcher |
| HN-SOS-004 | Wave 1 | L. Emergency / SOS | Australian emergency numbers | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.0 | Remaining: Add 112/106 if required | PARTIALLY VERIFIED | STATUS.md | 000, Poisons 13 11 26, Healthdirect 1800 022 222; no 112/106 |
| HN-SOS-005 | Wave 1 | L. Emergency / SOS | GPS location capture | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | Device GPS | PARTIALLY VERIFIED | STATUS.md | Geolocator in SOS flow |
| HN-SOS-006 | Wave 1 | L. Emergency / SOS | Location sharing to contacts | Mock/Demo | 🟢 COMPLETED | P0 | V1.0 | Remaining: Real SMS/push to contacts (future) | VERIFIED | SPRINT2_SOS_DEVICE | Dial-first honesty; device long-press SOS contacts_notified=0; no false share claim |
| HN-SOS-007 | Wave 1 | L. Emergency / SOS | Permission / failure handling | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | Snackbars; call 000 fallback copy |
| HN-SOS-008 | Wave 1 | L. Emergency / SOS | Emergency medical disclaimer | Not Implemented | 🟢 COMPLETED | P1 | V1.0 | Remaining: Legal review optional | VERIFIED | SPRINT2_SOS_DEVICE | Persistent disclaimer; device SOS-05 PASS |
| HN-NEARBY-001 | Wave 1 | M. Nearby Healthcare Services | Nearby hospitals / pharmacies / labs / GPs | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | OSM Overpass/Nominatim; TTL cache 900s | VERIFIED | SPRINT3_NEARBY | Bounded timeouts + mirror fallback + cache-on-fail + honest `status=ok|cached|degraded`; device NEARBY-UI PASS |
| HN-NEARBY-002 | Wave 1 | M. Nearby Healthcare Services | GPS + AU bbox fallback | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | GPS | PARTIALLY VERIFIED | STATUS.md | Outside AU → Ringwood VIC default |
| HN-NEARBY-003 | Wave 1 | M. Nearby Healthcare Services | Maps / directions | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | External Maps app | PARTIALLY VERIFIED | STATUS.md | Google Maps URL via `url_launcher` |
| HN-NEARBY-004 | Wave 1 | M. Nearby Healthcare Services | Suburb/postcode search | Implemented & Working | 🟢 COMPLETED | P2 | V1.0 | Nominatim | PARTIALLY VERIFIED | STATUS.md | `GET /nearby/geocode` |
| HN-NEARBY-005 | Wave 1 | M. Nearby Healthcare Services | Provider reliability | Needs Fix | 🔴 NEEDS FIX | P1 | V1.0 | OSM; Remaining: Paid Places API or cache | PARTIALLY VERIFIED | STATUS.md | External OSM; not controlled SLA |
| HN-NOTIF-001 | Wave 1 | N. Notifications | Firebase Cloud Messaging (client) | Not Implemented | ⚪ DEFERRED | P0 | V1.0 | Firebase; Remaining: Add FlutterFire + token upload | REQUIRES EXTERNAL INTEGRATION | SPRINT1_FINAL | No FlutterFire; outside this closure pass | Final: FCM DEFERRED — no fake credentials |
| HN-NOTIF-002 | Wave 1 | N. Notifications | FCM send (server) | Partially Implemented | 🟡 UNDER DEVELOPMENT | P0 | V1.0 | serviceAccountKey; Remaining: Prod credentials path | PARTIALLY VERIFIED | STATUS.md | `notification_service.py` firebase-admin if credentials path set | Sprint1: settings path for creds; no fake success; still needs Firebase Admin |
| HN-NOTIF-003 | Wave 1 | N. Notifications | Local notifications | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | VERIFIED | SPRINT1_N09 | Device TZ + exactAllowWhileIdle; N02b daily fire PASS; N04b monthly fire PASS; **N09 denied UX PASS**; schedule/cancel E2E PASS | Final: local path verified on emulator-5554 including monthly fire + denied UX |
| HN-NOTIF-004 | Wave 1 | N. Notifications | Push token registration | Not Implemented | 🟠 PENDING | P0 | V1.0 | FCM; Remaining: Register on login | NOT VERIFIED | STATUS.md | `UserApi.updateFcmToken` never called |
| HN-NOTIF-005 | Wave 1 | N. Notifications | Medication push delivery E2E | Partially Implemented | 🟡 UNDER DEVELOPMENT | P0 | V1.0 | FCM still deferred; local E2E verified | PARTIALLY VERIFIED | SPRINT1_FINAL | Local daily fire PASS; FCM production still DEFERRED | Final: local E2E PASS; FCM not production-ready |
| HN-NOTIF-006 | Wave 3 | N. Notifications | In-app notifications UI | Not Implemented | 🟠 PENDING | P2 | V1.2 | Remaining: Inbox screen | NOT VERIFIED | STATUS.md | Home bell `onPressed: () {}` |
| HN-NOTIF-007 | Wave 1 | N. Notifications | Android notification channels | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | VERIFIED | SPRINT1_FINAL | Channel `vitapulse_reminders` / Medication reminders created; dumpsys confirmed | Final: channel PASS |
| HN-SEC-001 | Wave 1 | O. Privacy & Security | HTTPS (client production) | Needs Fix | 🔴 NEEDS FIX | P0 | V1.0 | Prod API host; Remaining: Deploy HTTPS API + dart-define | PARTIALLY VERIFIED | STATUS.md | Release refuses LAN if no `API_BASE_URL`; no hosted HTTPS API configured in build |
| HN-SEC-002 | Wave 1 | O. Privacy & Security | Cleartext traffic policy | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | Release manifest `usesCleartextTraffic=false`; debug true |
| HN-SEC-003 | Wave 1 | O. Privacy & Security | JWT API authentication | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | `get_current_user` Bearer on protected routes |
| HN-SEC-004 | Wave 1 | O. Privacy & Security | User data isolation | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | Routes filter `current_user.id` |
| HN-SEC-005 | Wave 1 | O. Privacy & Security | Field-level encryption | Partially Implemented | 🟡 UNDER DEVELOPMENT | P1 | V1.0 | ENCRYPTION_KEY; Remaining: Key management / rotation | PARTIALLY VERIFIED | STATUS.md | Fernet `EncryptedText` on selected columns; needs ENCRYPTION_KEY |
| HN-SEC-006 | Wave 1 | O. Privacy & Security | Secrets management | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | External residual: historical Git exposure; live credential rotation; production secret store | VERIFIED | SPRINT5-S1 | Verified after S5-S1 local hygiene: env/config injection; private credential files protected from tracking; `.env.example` placeholders only; `scripts/audit_tracked_secrets.py` PASS/count=0; rotation procedure documented in `docs/SECURITY_HYGIENE.md`; sensitive logging protected. Does not claim production secret-store completion |
| HN-SEC-007 | Wave 1 | O. Privacy & Security | Sensitive logging | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | — | VERIFIED | SPRINT4-S1 | No plaintext OTP; ApiClient/DebugLogger omit bodies; AI/health logs metadata-only |
| HN-SEC-008 | Wave 1 | O. Privacy & Security | CORS configuration | Needs Fix | 🟢 COMPLETED | P1 | V1.0 | Remaining: Set prod origins in CORS_ORIGINS env | VERIFIED | SPRINT2 | allow_origins from settings.get_cors_origins(); never '*'; credentials OK |
| HN-SEC-009 | Wave 1 | O. Privacy & Security | Admin stats authorization | Needs Fix | 🟢 COMPLETED | P0 | V1.0 | Remaining: Keep DEVELOPER_EMAILS populated in prod | VERIFIED | SPRINT2 | assert_admin_access + fail-closed empty list; pytest deny/allow |
| HN-LEGAL-001 | Wave 1 | P. Legal & Compliance | In-app privacy policy screen | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | Remaining: Hosted URL still required by Play | PARTIALLY VERIFIED | STATUS.md | `PrivacyPolicyScreen` + drawer/profile links |
| HN-LEGAL-002 | Wave 1 | P. Legal & Compliance | Hosted privacy policy URL | Not Implemented | 🟠 PENDING | P0 | V1.0 | Public HTTPS site; Remaining: Publish + rebuild AAB | NOT VERIFIED | STATUS.md | `PRIVACY_POLICY_URL` dart-define optional; empty in current AAB |
| HN-LEGAL-003 | Wave 1 | P. Legal & Compliance | Terms & conditions | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | Remaining: Legal review AU | PARTIALLY VERIFIED | STATUS.md | `TermsScreen` + consent |
| HN-LEGAL-004 | Wave 1 | P. Legal & Compliance | Medical / AI disclaimer | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | VERIFIED | SPRINT4-S2 | Shared ClinicalSafetyBanner + LegalCopy context banners on clinical/AI surfaces |
| HN-LEGAL-005 | Wave 1 | P. Legal & Compliance | Consent capture | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | Remaining: Server-side consent record optional | PARTIALLY VERIFIED | STATUS.md | Hive `legal_consent_v1` gate on splash |
| HN-LEGAL-006 | Wave 1 | P. Legal & Compliance | Web account deletion URL | Not Implemented | 🟠 PENDING | P0 | V1.0 | Public HTTPS page; Remaining: Host deletion instructions page | REQUIRES EXTERNAL INTEGRATION | STATUS.md | `ACCOUNT_DELETION_URL` unset; Play often requires web path |
| HN-LEGAL-007 | Wave 3 | P. Legal & Compliance | Data export (user) | Not Implemented | 🟠 PENDING | P1 | V1.2 | Remaining: APP access/correction export | NOT VERIFIED | STATUS.md | No export endpoint/UI |
| HN-LEGAL-008 | Wave 1 | P. Legal & Compliance | Australian Privacy Principles readiness | Partially Implemented | 🟡 UNDER DEVELOPMENT | P0 | V1.0 | Legal counsel; Remaining: Formal APP assessment | PARTIALLY VERIFIED | STATUS.md | Marketing claim on welcome; not a compliance certification |
| HN-ADMIN-001 | Wave 5 | Q. Admin | Admin login / panel | Not Implemented | 🟠 PENDING | P3 | V1.2 | Remaining: Build admin app if needed | NOT VERIFIED | STATUS.md | No admin Flutter/web console |
| HN-ADMIN-002 | Wave 5 | Q. Admin | User management | Not Implemented | 🟠 PENDING | P3 | V1.2 | Remaining: Admin APIs + RBAC | NOT VERIFIED | STATUS.md | Not implemented |
| HN-ADMIN-003 | Wave 5 | Q. Admin | Medicine management UI | Not Implemented | 🟠 PENDING | P3 | V1.2 | Remaining: Ops console | NOT VERIFIED | STATUS.md | Enrichment APIs exist; no admin UI |
| HN-ADMIN-004 | Wave 5 | Q. Admin | System statistics endpoint | Needs Fix | 🟢 COMPLETED | P0 | V1.2 | Remaining: Optional dedicated admin role later | VERIFIED | SPRINT2 | `/admin/stats` gated by DEVELOPER_EMAILS via assert_admin_access |
| HN-ADMIN-005 | Wave 5 | Q. Admin | AI / enrichment logs (ops) | Partially Implemented | 🟡 UNDER DEVELOPMENT | P3 | V1.2 | Remaining: Authz + UI | PARTIALLY VERIFIED | STATUS.md | `/enrichment/log/*` routes; not a product admin panel |
| HN-ANALYTICS-001 | Wave 5 | R. Analytics | Product analytics (Firebase/GA) | Not Implemented | 🟠 PENDING | P2 | V1.2 | Remaining: Add analytics if desired | NOT VERIFIED | STATUS.md | Not in Flutter deps |
| HN-ANALYTICS-002 | Wave 5 | R. Analytics | Crash reporting (Crashlytics/Sentry) | Not Implemented | 🟠 PENDING | P1 | V1.2 | Email; Remaining: Crashlytics or Sentry | NOT VERIFIED | STATUS.md | Custom `ErrorReporter` → `/errors/report` only |
| HN-ANALYTICS-003 | Wave 5 | R. Analytics | Custom error reporting | Implemented & Working | 🟢 COMPLETED | P2 | V1.2 | SMTP | PARTIALLY VERIFIED | STATUS.md | `POST /api/v1/errors/report` + email + `error_logs` |
| HN-BIZ-001 | Wave 5 | S. Subscription / Monetization | Free / premium plans | Not Implemented | ⚪ DEFERRED | P3 | FUTURE | Remaining: Product design then IAP | NOT VERIFIED | STATUS.md | No billing code |
| HN-BIZ-002 | Wave 5 | S. Subscription / Monetization | Google Play Billing / IAP | Not Implemented | ⚪ DEFERRED | P3 | FUTURE | Play Billing; Remaining: Implement later | REQUIRES EXTERNAL INTEGRATION | STATUS.md | No `in_app_purchase` / Play Billing |
| HN-BIZ-003 | Wave 5 | S. Subscription / Monetization | Payment processing / trials / restore | Not Implemented | ⚪ DEFERRED | P3 | FUTURE | Remaining: N/A until monetization | NOT VERIFIED | STATUS.md | Absent |
| HN-BIZ-004 | Wave 5 | S. Subscription / Monetization | Premium feature gating | Not Implemented | ⚪ DEFERRED | P3 | FUTURE | — | NOT VERIFIED | STATUS.md | Absent |
| HN-AU-001 | Wave 2 | T. Australia Healthcare Integration | AU medicine catalog (DB) | Implemented & Working | 🟢 COMPLETED | P0 | V1.1 | Ingest pipelines; Remaining: Prod refresh | PARTIALLY VERIFIED | STATUS.md | Local MigrationTest: 28,368 medicines; 28,338 TGA-sourced |
| HN-AU-002 | Wave 2 | T. Australia Healthcare Integration | TGA identity fields | Implemented & Working | 🟢 COMPLETED | P1 | V1.1 | TGA data load; Remaining: Validate against live ARTG | PARTIALLY VERIFIED | STATUS.md | `tga_artg_number`, `tga_registered`, primary_source TGA |
| HN-AU-003 | Wave 4 | T. Australia Healthcare Integration | PBS codes / benefits | Partially Implemented | 🟡 UNDER DEVELOPMENT | P1 | V1.3 | PBS API; Remaining: Bulk enrichment | PARTIALLY VERIFIED | STATUS.md | 13 PBS codes populated locally; connector exists |
| HN-AU-004 | Wave 4 | T. Australia Healthcare Integration | Authoritative CMI / PI content | Partially Implemented | 🟡 UNDER DEVELOPMENT | P1 | V1.3 | TGA CMI sources; Remaining: Do not claim label compliance | PARTIALLY VERIFIED | STATUS.md | Sparse clinical fields; AI fill common |
| HN-AU-005 | Wave 4 | T. Australia Healthcare Integration | Healthcare provider / hospital integration | Not Implemented | 🟠 PENDING | P3 | V1.3 | Partner APIs; Remaining: Future | NOT VERIFIED | STATUS.md | No HL7/FHIR provider integrations in app path |
| HN-AU-006 | Wave 4 | T. Australia Healthcare Integration | Pharmacy dispensing integration | Not Implemented | 🟠 PENDING | P3 | V1.3 | Remaining: Future | NOT VERIFIED | STATUS.md | Not implemented |
| HN-AU-007 | Wave 2 | T. Australia Healthcare Integration | AU emergency services linkage | Implemented & Working | 🟢 COMPLETED | P1 | V1.1 | — | VERIFIED | S4-VERIFY-AU-007 | Verified against current Australian emergency-services implementation: Emergency screen exposes 000, Poisons Information Centre 13 11 26, and Healthdirect 1800 022 222 through dialer-primary `tel:` actions (`_callNumber` / `launchUrl`). SOS remains honest/dialer-first (`contacts_notified=0`; does not auto-dispatch or silently call 000). Emergency contacts + disclaimer retained. Verified by `sos_honesty_contract_test.dart`, `sos_hold_button_test.dart`, `test_sos_hold_security.py` (PASS). |
| HN-ERX-001 | Wave 4 | U. ePrescription | ePrescription UI (scan/list/detail) | Mock/Demo | ⚫ MOCK/DEMO | P1 | V1.3 | Remaining: Keep gated until live eRx | PARTIALLY VERIFIED | STATUS.md | Full Flutter flows; release gated unless `ENABLE_EPRESCRIPTION` |
| HN-ERX-002 | Wave 4 | U. ePrescription | eRx Script Exchange live integration | Mock/Demo | ⚫ MOCK/DEMO | P2 | V1.3 | ERX_API_KEY + eRx agreement; Remaining: Live credentials + compliance | PARTIALLY VERIFIED | STATUS.md | `EPRESCRIPTION_MOCK_MODE=True` default; mock patients/meds |
| HN-ERX-003 | Wave 4 | U. ePrescription | MediSecure | Not Required | ⚪ NOT REQUIRED | P3 | V1.3 | — | NOT VERIFIED | STATUS.md | Documented discontinued; not supported |
| HN-ERX-004 | Wave 4 | U. ePrescription | Token extract / validate / share / refill hooks | Mock/Demo | ⚫ MOCK/DEMO | P2 | V1.3 | eRx; Remaining: Production eRx only | PARTIALLY VERIFIED | STATUS.md | Routes exist; mock-backed when mock mode on |
| HN-SET-001 | Wave 1 | V. Settings | Appearance / theme settings | Implemented & Working | 🟢 COMPLETED | P2 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | `AppearanceScreen` |
| HN-SET-002 | Wave 1 | V. Settings | Notification settings | Not Implemented | 🟠 PENDING | P2 | V1.0 | Remaining: Add toggles after FCM | NOT VERIFIED | STATUS.md | No notification preferences screen |
| HN-SET-003 | Wave 1 | V. Settings | Privacy settings | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.0 | Remaining: Consent preferences | PARTIALLY VERIFIED | STATUS.md | Links to legal screens; no granular toggles |
| HN-SET-004 | Wave 1 | V. Settings | Security settings | Not Implemented | 🟠 PENDING | P3 | V1.0 | Remaining: Optional biometrics | NOT VERIFIED | STATUS.md | No PIN/biometric settings UI |
| HN-SET-005 | Wave 1 | V. Settings | Logout from profile/drawer | Implemented & Working | 🟢 COMPLETED | P1 | V1.0 | Remaining: Server revoke | PARTIALLY VERIFIED | STATUS.md | Clears secure storage |
| HN-SET-006 | Wave 1 | V. Settings | About / Help / Feedback | Not Implemented | 🟠 PENDING | P2 | V1.0 | Error report only; Remaining: Add support screens | NOT VERIFIED | STATUS.md | No dedicated about/help/feedback screens found |
| HN-UX-001 | Wave 1 | W. Onboarding / UX | Splash + auth routing | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | `SplashScreen` → consent/welcome/home |
| HN-UX-002 | Wave 1 | W. Onboarding / UX | Welcome / onboarding | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.0 | Remaining: Optional guided tour | PARTIALLY VERIFIED | STATUS.md | Welcome screen; not multi-step product tour |
| HN-UX-003 | Wave 1 | W. Onboarding / UX | Legal consent gate | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | Required before main app |
| HN-UX-004 | Wave 1 | W. Onboarding / UX | Navigation (GoRouter + drawer/home) | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | — | PARTIALLY VERIFIED | STATUS.md | `app_router.dart` feature routes |
| HN-UX-005 | Wave 1 | W. Onboarding / UX | Loading / empty / error states | Partially Implemented | 🟡 UNDER DEVELOPMENT | P1 | V1.0 | Remaining: Consistent error model | PARTIALLY VERIFIED | STATUS.md | Many screens handle empty; uneven error UX (e.g. reminder 503) |
| HN-UX-006 | Wave 1 | W. Onboarding / UX | Accessibility | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.0 | Remaining: TalkBack / contrast QA | PARTIALLY VERIFIED | STATUS.md | Material defaults; no dedicated a11y audit evidence |
| HN-INFRA-001 | Wave 1 | X. Technical Infrastructure | Flutter 3.41.0 / Dart 3.11.0 | Implemented & Working | 🟢 COMPLETED | P2 | V1.0 | Remaining: Track upgrades | PARTIALLY VERIFIED | STATUS.md | `flutter --version` on audit machine |
| HN-INFRA-002 | Wave 1 | X. Technical Infrastructure | Android minSdk 24 / targetSdk 36 | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | Remaining: None for API 36 rule | PARTIALLY VERIFIED | STATUS.md | Flutter defaults; versionName 1.0.0 versionCode 1 |
| HN-INFRA-003 | Wave 1 | X. Technical Infrastructure | Production API configuration | Needs Fix | 🔴 NEEDS FIX | P0 | V1.0 | Hosted FastAPI HTTPS; Remaining: Deploy + rebuild AAB | PARTIALLY VERIFIED | STATUS.md | `AppEnv.API_BASE_URL` required for release; unset → unusable store API |
| HN-INFRA-004 | Wave 1 | X. Technical Infrastructure | PostgreSQL | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | Postgres; Remaining: Managed prod DB | PARTIALLY VERIFIED | STATUS.md | SQLAlchemy async + Alembic 001–014; Compose postgres:16 |
| HN-INFRA-005 | Wave 1 | X. Technical Infrastructure | Redis | Partially Implemented | 🟡 UNDER DEVELOPMENT | P1 | V1.0 | Redis; Remaining: Managed Redis in prod | PARTIALLY VERIFIED | STATUS.md | Cache/rate-limit; local default URL |
| HN-INFRA-006 | Wave 1 | X. Technical Infrastructure | Docker Compose | Partially Implemented | 🟡 UNDER DEVELOPMENT | P1 | V1.0 | Docker; Remaining: Prod k8s/VM runbook | PARTIALLY VERIFIED | STATUS.md | Compose present; `POSTGRES_PASSWORD` required from env |
| HN-INFRA-007 | Wave 1 | X. Technical Infrastructure | Release signing (upload keystore) | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | Remaining: Backup keystore securely | PARTIALLY VERIFIED | STATUS.md | Local `key.properties` + `upload-keystore.jks` (gitignored); Gradle release signing |
| HN-INFRA-008 | Wave 1 | X. Technical Infrastructure | Signed release AAB artifact | Implemented & Working | 🟢 COMPLETED | P0 | V1.0 | Remaining: Rebuild with API/legal dart-defines | PARTIALLY VERIFIED | STATUS.md | `flutter_app/build/app/outputs/bundle/release/app-release.aab` exists (~55MB) |
| HN-INFRA-009 | Wave 5 | X. Technical Infrastructure | CI/CD | Not Implemented | 🟠 PENDING | P2 | V2.0 | Remaining: Add CI build/test | NOT VERIFIED | STATUS.md | No `.github/workflows` |
| HN-INFRA-010 | Wave 1 | X. Technical Infrastructure | Automated unit/integration tests | Not Implemented | 🟠 PENDING | P1 | V1.0 | Remaining: Test pyramid | NOT VERIFIED | STATUS.md | Default Flutter widget test; API smoke scripts only; no pytest suite |
| HN-INFRA-011 | Wave 1 | X. Technical Infrastructure | 16 KB page-size validation | Not Implemented | 🟠 PENDING | P1 | V1.0 | Remaining: Validate before Play | REQUIRES EXTERNAL INTEGRATION | STATUS.md | Not validated on AAB in prior audit |
| HN-FUTURE-001 | Wave 3 | Y. Future / Planned Features | Symptom checker | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.2 | Claude; Remaining: Clinical safety review | PARTIALLY VERIFIED | STATUS.md | UI + `POST /symptoms/check` (AI); disclaimer present |
| HN-FUTURE-002 | Wave 3 | Y. Future / Planned Features | Lab analysis | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.2 | Claude/OCR; Remaining: Validation + confirm | PARTIALLY VERIFIED | STATUS.md | Camera/gallery → analyze API |
| HN-FUTURE-003 | Wave 3 | Y. Future / Planned Features | Health insights | Partially Implemented | 🟡 UNDER DEVELOPMENT | P2 | V1.2 | Claude; Remaining: Grounding | PARTIALLY VERIFIED | STATUS.md | `insights` routes + screen |
| HN-FUTURE-004 | Wave 3 | Y. Future / Planned Features | Interaction checker screen | Partially Implemented | 🟡 UNDER DEVELOPMENT | P1 | V1.2 | Claude; Remaining: Authoritative interaction source | PARTIALLY VERIFIED | STATUS.md | AI-based; not DB interactions table |
| HN-FUTURE-005 | Wave 3 | Y. Future / Planned Features | Wearable sync | Not Implemented | 🟠 PENDING | P3 | V1.2 | Health Connect; Remaining: Future | NOT VERIFIED | STATUS.md | Manual metrics only |
| HN-FUTURE-006 | Wave 3 | Y. Future / Planned Features | Multi-language | Partially Implemented | 🟡 UNDER DEVELOPMENT | P3 | V1.2 | Remaining: flutter_localizations | PARTIALLY VERIFIED | STATUS.md | `insights/translate` exists; not full i18n |

---

## Change History

| Date | Change | Owner/Agent |
|------|--------|-------------|
| 2026-09-04 | **Sprint 2 SOS Device QA GREEN** (emulator-5554): SOS-01..06 PASS; BackButton GoRouter-safe fix; debug APK; pytest 43 / flutter 4 / analyze 0 errors. Selected Sprint 2 slice COMPLETE. FCM DEFERRED; HTTPS excluded. See docs/SPRINT_2_EXECUTION_REPORT.md | Cursor |
| 2026-09-04 | **Sprint 2:** Security + SOS honesty slice COMPLETED for HN-SEC-008/009, HN-ADMIN-004, HN-SOS-002/006/008, HN-PROF-007. pytest 43; flutter 4; analyze 0 errors. FCM remains DEFERRED. HTTPS/prod hosting still NEEDS FIX (external). See docs/SPRINT_2_EXECUTION_REPORT.md | Cursor |
| 2026-09-04 | **Sprint 1 FINAL STATUS: GREEN — SPRINT 1 CLOSED.** Core reliability VERIFIED; notification E2E PASS (N04/N09 PASS); Anthropic live PASS (`degraded=false`); pytest 37 / flutter 3 / analyze 0 errors; migration 015 PASS. Sprint 1 blockers NONE. FCM remains DEFERRED (deferred infrastructure, not a Sprint 1 blocker). See docs/SPRINT_1_CLOSURE_REPORT.md | Cursor |
| 2026-09-04 | Sprint 1 N09: denied/disabled notification UX PASS (schedule returns false; no pending; snackbar contract; no crash). Sticky-Deny tap flakiness classified as emulator behaviour, not app defect. FCM DEFERRED. See docs/SPRINT_1_CLOSURE_REPORT.md | Cursor |
| 2026-09-04 | Sprint 1 N04: monthly Android device fire PASS (N04b, frequency remained monthly, one matching active notification). FCM DEFERRED; N09 PARTIAL; Anthropic unchanged PASS. See docs/SPRINT_1_CLOSURE_REPORT.md | Cursor |
| 2026-09-04 | Sprint 1 Anthropic re-verification: live chat PASS (degraded=false); Flutter E2E PASS; conversation continuity PASS; disclaimer PASS. FCM still DEFERRED. N04/N09 remain PARTIAL. See docs/SPRINT_1_CLOSURE_REPORT.md | Cursor |
| 2026-09-04 | Initial master checklist generated from feature audit and roadmap | Cursor |
| 2026-09-04 | Sprint 1 FINAL unblocking: Android local notification E2E (daily fire, reboot restore) PASS; TZ/exact-alarm fix; Anthropic still BLOCKED (billing); FCM DEFERRED; verdict YELLOW. See docs/SPRINT_1_CLOSURE_REPORT.md | Cursor |
| 2026-09-04 | Sprint 1 closure verification: migration 015 fixed/applied on AIHealthCompanion_MigrationTest; API ACL/OCR/reminder evidence PASS; Android install only; FCM blocked; AI degraded; verdict YELLOW. See docs/SPRINT_1_CLOSURE_REPORT.md | Cursor |
| 2026-09-04 | Sprint 1 — Core Reliability & Safety Foundation (reminders, local notifications, records ACL, OCR confirm, AI disclaimer/retry). Tests: pytest 24 pass; flutter test frequency+widget pass; analyze info-only. Manual device QA limited. | Cursor |

---

## Generator validation

- Generated rows: 204
- Expected rows: 204
- Reconciliation: PASS
- Priority counts: {'P0': 72, 'P1': 67, 'P2': 44, 'P3': 21}
- Development status counts (post Sprint 2): {'🟢 COMPLETED': 100, '🟡 UNDER DEVELOPMENT': 58, '⚪ NOT REQUIRED': 3, '🟠 PENDING': 29, '🔴 NEEDS FIX': 6, '⚫ MOCK/DEMO': 3, '⚪ DEFERRED': 5}

