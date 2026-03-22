# VitaPulse AI — Developer Setup Guide

## Quick Start

### Option A — Docker (Recommended)
```bash
cd "D:/ravishori/OzHealth AI"
docker-compose up --build
```
- PostgreSQL available at `localhost:5432`
- FastAPI backend at `http://localhost:8000`
- API docs at `http://localhost:8000/docs`

### Option B — Local (no Docker)
```bash
# 1. Start PostgreSQL 16 and create database
psql -U postgres -f database/00_run_all.sql

# 2. Install Python dependencies
cd backend
pip install -r requirements.txt

# 3. (Optional) Run Alembic migrations instead of auto-create
alembic upgrade head

# 4. Start the backend
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

---

## Database Setup

### Full fresh setup (run once):
```bash
psql -U postgres -f "database/00_run_all.sql"
```

### Run scripts individually:
| Script | What it does |
|--------|-------------|
| `01_create_database.sql` | Creates `VitaPulse AI` DB + extensions |
| `02_create_tables.sql` | All 12 tables with constraints & comments |
| `03_indexes.sql` | GIN, trigram, composite indexes |
| `04_views.sql` | 7 useful views (health summary, refill alerts, etc.) |
| `05_functions_procedures.sql` | Triggers, BMI calc, BP classification, reminder dispatch, etc. |
| `06_seed_medicines.sql` | ~25 Australian TGA-listed medicines |
| `07_seed_test_data.sql` | Dev users, family members, records, metrics |

### Useful queries:
```sql
-- Get health summary for a user
SELECT * FROM v_user_health_summary WHERE user_id = 1;

-- Find reminders due right now
SELECT * FROM fn_get_due_reminders(5);

-- Search medicines (hybrid full-text + trigram)
SELECT * FROM fn_search_medicines('metformin');

-- Refill alerts
SELECT * FROM v_refill_alerts;

-- User stats
SELECT * FROM fn_user_stats();
```

---

## Backend Configuration (backend/.env)

| Variable | Description | Required |
|----------|-------------|----------|
| `DATABASE_URL` | PostgreSQL asyncpg URL | ✅ |
| `SYNC_DATABASE_URL` | PostgreSQL psycopg2 URL (Alembic) | ✅ |
| `SECRET_KEY` | JWT signing secret | ✅ |
| `ANTHROPIC_API_KEY` | Claude API key for AI features | ✅ |
| `FIREBASE_CREDENTIALS_PATH` | Path to Firebase serviceAccountKey.json | Optional |
| `TWILIO_ACCOUNT_SID` | Twilio SID for SOS SMS | Optional |
| `TWILIO_AUTH_TOKEN` | Twilio token | Optional |
| `TWILIO_FROM_NUMBER` | Twilio phone number | Optional |

---

## Flutter App

```bash
cd "D:/ravishori/OzHealth AI/flutter_app"
flutter pub get
flutter run   # with Android emulator running
```

**Backend URL (Android emulator):** `http://10.0.2.2:8000/api/v1`

### Architecture
```
lib/
├── core/
│   ├── network/api_client.dart          # Dio + auto token refresh
│   ├── router/app_router.dart           # GoRouter (22 routes)
│   ├── theme/app_theme.dart             # Material3, teal #00897B
│   └── utils/auth_storage.dart          # FlutterSecureStorage
│
└── features/
    ├── auth/        data/ + screens/
    ├── profile/     data/ + providers/ + screens/
    ├── family/      data/ + providers/ + screens/
    ├── records/     data/ + providers/ + screens/
    ├── prescriptions/ data/ + screens/
    ├── medicines/   data/ + screens/
    ├── reminders/   data/ + providers/ + screens/
    ├── health_monitoring/ data/ + providers/ + screens/
    ├── emergency/   data/ + providers/ + screens/
    ├── nearby/      data/ + screens/
    └── ai_assistant/ data/ + providers/ + screens/
```

---

## API Reference (key endpoints)

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/auth/send-otp` | Send OTP to email or phone |
| POST | `/api/v1/auth/register` | Register new user |
| POST | `/api/v1/auth/login` | Login with OTP |
| GET | `/api/v1/users/me` | Get current user profile |
| GET | `/api/v1/family/` | List family members |
| POST | `/api/v1/records/upload` | Upload medical record (multipart) |
| POST | `/api/v1/prescriptions/scan` | OCR + AI prescription analysis |
| GET | `/api/v1/medicines/search?q=` | Search TGA medicines |
| POST | `/api/v1/health-metrics/` | Log a health reading |
| GET | `/api/v1/health-metrics/summary` | Latest reading per metric |
| POST | `/api/v1/ai/chat` | Chat with Claude AI health assistant |
| POST | `/api/v1/emergency/sos` | Trigger SOS alert |
| GET | `/api/v1/nearby/?lat=&lng=&type=` | Find nearby services (OSM) |
| GET | `/api/v1/admin/stats` | Platform statistics |

Full interactive docs: **http://localhost:8000/docs**

---

## Background Services

### Medication Reminder Worker
- Runs every **5 minutes** via APScheduler
- Calls `fn_get_due_reminders(5)` to find schedules due ±5 min
- Sends push notifications via FCM

### Refill Alert Worker
- Runs daily at **8:00 AM AEST**
- Queries `v_refill_alerts` for low stock / upcoming refills
- Sends push notifications

**Requirements:** `pip install apscheduler` (already in requirements.txt)
**FCM:** Set `FIREBASE_CREDENTIALS_PATH` in `.env` to enable push notifications.

---

## Dev OTP

In development mode, OTP codes are printed to the backend console:
```
[OTP] +61412345001 → 847392 (expires in 10 min)
```

---

## Project Structure

```
OzHealth AI/
├── backend/
│   ├── app/
│   │   ├── api/routes/          # 11 route files
│   │   ├── core/                # config, database, security, deps
│   │   ├── models/              # 10 SQLAlchemy models
│   │   ├── schemas/             # 10 Pydantic schema files
│   │   └── services/            # ai_service, ocr_service,
│   │                            #   notification_service, reminder_worker
│   ├── alembic/versions/        # 001_initial_migration.py
│   ├── main.py
│   ├── requirements.txt
│   └── .env
├── flutter_app/
│   └── lib/features/            # 11 features × (data/ + providers/ + screens/)
├── database/
│   ├── 00_run_all.sql
│   ├── 01_create_database.sql
│   ├── 02_create_tables.sql
│   ├── 03_indexes.sql
│   ├── 04_views.sql
│   ├── 05_functions_procedures.sql
│   ├── 06_seed_medicines.sql
│   └── 07_seed_test_data.sql
├── docker-compose.yml
└── SETUP.md
```
