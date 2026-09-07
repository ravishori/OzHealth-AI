# S8 Staging Bring-Up — Operator Guide

This documents the **intended** staging schema and startup behavior after the
S8 staging bring-up engineering changes. It does not contain secrets.

## Schema source of truth

1. Apply Alembic on the dedicated staging database **before** first App Service boot:
   ```bash
   cd backend
   export ENVIRONMENT=staging
   # SYNC_DATABASE_URL / DATABASE_URL / SECRET_KEY / ENCRYPTION_KEY via env or Key Vault refs
   alembic upgrade head
   ```
2. Expected head after this change: **`017`** (includes `016` `token_version` + `017` `error_logs`).
3. **Do not** use SQLAlchemy `Base.metadata.create_all` as a migration fallback.
4. Application startup:
   - `ENVIRONMENT=staging|production` → **never** runs `create_all`
   - `ENVIRONMENT=development|test` → may run `create_all` unless `AUTO_CREATE_TABLES=false`
   - Hosted startup **fails fast** if `ENCRYPTION_KEY` is empty, `DEBUG=true`, weak `SECRET_KEY`, or `AUTO_CREATE_TABLES=true`

## Health probe

- `GET /health` (unauthenticated)
- **200** `{ "status": "healthy", "version": "<APP_VERSION>" }` when DB `SELECT 1` succeeds
- **503** `{ "status": "unhealthy", "version": "<APP_VERSION>" }` when DB is unreachable
- Never returns connection strings, secrets, PHI, or stack traces

## Flutter staging build

Inject the staging API origin at compile time (no hardcoded credentials):

```bash
cd flutter_app
flutter build appbundle \
  --dart-define=API_BASE_URL=https://aihealthcompanion-api-staging.azurewebsites.net \
  --dart-define=PRIVACY_POLICY_URL=https://YOUR_HOSTED_PRIVACY \
  --dart-define=ACCOUNT_DELETION_URL=https://YOUR_HOSTED_DELETION
```

`AppEnv.normalizeApiBaseUrl` accepts either host-only or `.../api/v1`.

Release/profile builds **refuse** LAN discovery when `API_BASE_URL` is unset.

## Values that must be configured outside the repository

| Name | Where |
|------|--------|
| `DATABASE_URL` | Key Vault / App Settings (asyncpg + TLS) |
| `SYNC_DATABASE_URL` | Key Vault / App Settings (psycopg2 + TLS) — same DB as above |
| `SECRET_KEY` | Key Vault |
| `ENCRYPTION_KEY` | Key Vault (Fernet) |
| `ENVIRONMENT=staging` | App Setting |
| `DEBUG=false` | App Setting |
| `CORS_ORIGINS` | App Setting JSON list of real browser origins if any |
| SMTP / Twilio / Anthropic / Firebase | Optional for boot; required for those features |
| Flutter `API_BASE_URL` | CI/`--dart-define` only — never commit |
| PostgreSQL firewall allowlist | Azure portal / CLI |
| Alembic run from allowlisted runner | Operator/CI |

## Suggested App Service startup

```text
uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}
```

Working directory: contents of `backend/`. Do **not** use `--reload` on Azure.
