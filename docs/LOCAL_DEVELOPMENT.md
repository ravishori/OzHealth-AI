# Local Development Environment (HN-INFRA-006)

Local-only guidance for running HealthNest / VitaPulse with Docker Compose.
This does **not** configure Azure, staging, or production.

## Connectivity model (do not confuse these)

| Context | How to reach the API | How to reach PostgreSQL |
|---------|----------------------|-------------------------|
| Browser / host tools | `http://localhost:8000` | `localhost:5432` |
| Backend **container** | n/a (self) | hostname **`postgres`** (Compose DNS) |
| Android **emulator** | `http://10.0.2.2:8000` | n/a (app talks to API only) |
| iOS simulator / desktop Flutter | `http://localhost:8000` | n/a |

Inside a container, `localhost` is the container itself — never use `localhost`
as the Postgres/Redis host in Compose service environment.

Flutter already probes `10.0.2.2:8000` for Android emulator discovery
(`flutter_app/lib/core/network/server_discovery.dart`). Documenting that
address does **not** by itself verify feature E2E.

## Quick start (Compose)

```bash
# From repository root
cp .env.example .env
cp backend/.env.example backend/.env
# Edit both files: set POSTGRES_PASSWORD + SECRET_KEY (local placeholders only)

docker compose up --build
```

Services:

| Service | Host port | Notes |
|---------|-----------|--------|
| `postgres` | 5432 | Health: `pg_isready` |
| `redis` | 6379 | Health: `redis-cli ping` |
| `backend` | 8000 | Health: `GET /ready` (DB connectivity) |

Useful endpoints:

- Liveness: `GET http://localhost:8000/health`
- Readiness: `GET http://localhost:8000/ready`
- OpenAPI: `http://localhost:8000/docs`

## Migrations (local)

Compose injects `SYNC_DATABASE_URL` pointing at service `postgres`.
Alembic reads the URL from application settings (`alembic/env.py`), not from
any hard-coded password in `alembic.ini`.

```bash
docker compose exec backend alembic current
docker compose exec backend alembic heads
docker compose exec backend alembic upgrade head
```

Do **not** renumber or squash historical Alembic revisions for local Docker.

## Validation without claiming cloud deploy

```bash
python scripts/validate_local_compose.py
```

If Docker is not installed in the environment, the script still validates the
Compose file statically and reports runtime checks as skipped.

## Secrets

- Never commit `.env` or real API keys / SMTP / Twilio / JWT secrets.
- Root `.env.example` and `backend/.env.example` are placeholders only.
- Compose requires `POSTGRES_PASSWORD` and `SECRET_KEY` via environment /
  root `.env` substitution (`:?` fail-fast if missing).

## Out of scope for HN-INFRA-006

- Production Kubernetes / Azure runbooks
- Connecting Compose to managed cloud databases
- Importing PHI / production dumps
- Marking feature Android E2E verified solely because Compose works

## Continuous integration (HN-INFRA-009)

GitHub Actions workflow: `.github/workflows/ci.yml`.

**When it runs:** every `push` and `pull_request`.

**What it runs (fail closed — no deploy):**

| Job | Commands |
|-----|----------|
| Backend | `pip install -r requirements-dev.txt` then `pytest -q` (Python 3.12) |
| Flutter | `flutter pub get`, `flutter test`, `flutter analyze` (stable channel) |

CI uses **placeholder** `DATABASE_URL` / `SECRET_KEY` env vars required by settings import. It does **not** use production DB credentials, Azure secrets, Anthropic keys, or Firebase credentials, and it does **not** deploy.

### Reproduce the same checks locally

```bash
# Backend (from repository root) — placeholders only, never production secrets
cd backend
python -m venv .venv && source .venv/bin/activate   # or use an existing venv
pip install -r requirements-dev.txt
export DATABASE_URL='postgresql+asyncpg://ci:ci@127.0.0.1:5432/ci'
export SYNC_DATABASE_URL='postgresql+psycopg2://ci:ci@127.0.0.1:5432/ci'
export SECRET_KEY='ci-only-secret-key-not-for-production'
export EPRESCRIPTION_MOCK_MODE=true
pytest -q

# Flutter
cd flutter_app
flutter pub get
flutter test
flutter analyze
```

Most backend tests mock DB/IO and do not need a live Postgres instance when those env vars are set.
