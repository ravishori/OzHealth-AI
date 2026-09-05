# Security Hygiene — Secrets (HN-SEC-006)

This document covers **local repository / configuration secrets hygiene**.
It does **not** claim production secret-management is complete.

## LOCAL (in scope for repository hygiene)

### How secrets must be supplied

- Application secrets (`SECRET_KEY`, database URLs, API keys, SMTP/Twilio,
  encryption keys, etc.) must come from **environment variables** or a local
  untracked `.env` file loaded by configuration (`backend/app/core/config.py`).
- Never hard-code production credentials in source.
- Never copy real credentials into `backend/.env.example` or other templates.
  Examples must use placeholders only (`USER`, `PASSWORD`, empty values,
  `generate-a-long-random-string`).

### Files that must not be committed

- `backend/.env` and any `.env` containing credentials
- Service account JSON / Firebase credential files
- Local credential dumps (e.g. connection-string text files, vendor API dumps)
- Anything matching ignore patterns in the root `.gitignore`

Copy `backend/.env.example` → `backend/.env` and fill values locally.

### Secret exposure audit (repeatable)

From the repository root:

```bash
python scripts/audit_tracked_secrets.py
```

- **PASS** — no obvious forbidden paths / hard-coded secret patterns in the
  **currently tracked** tree.
- **FAIL** — prints `category=` and `path=` only. It never prints credential
  values.

Treat a FAIL as a stop-ship for committing until the offending **tracked**
file is removed from the index (and rotated if it was a real secret).

### If a credential is exposed

1. **Revoke / rotate** the credential with the vendor or secret owner
   (operational — see EXTERNAL below).
2. Remove the secret from the working tree and ensure it is gitignored.
3. Untrack the file if it was staged (`git rm --cached <path>`).
4. Re-run `python scripts/audit_tracked_secrets.py` until PASS.
5. Do **not** paste the secret into tickets, chat, or logs.

### Rotation procedure (process level)

1. Generate a new secret value offline.
2. Update the **production / staging secret store** or hosting env vars
   (EXTERNAL).
3. Update local `.env` only on developer machines that need it.
4. Redeploy / restart services that consume the secret.
5. Invalidate old credentials (JWT signing key change forces re-login;
   API keys revoke at the provider).
6. Confirm old credential no longer works; confirm app still starts with the
   new value.
7. Record the rotation in ops notes (what rotated, when) — **never** record
   the secret value itself.

## EXTERNAL (not completed by local hygiene)

These remain **operational / deployment** responsibilities and are **out of
scope** for local HN-SEC-006 hygiene alone:

| Residual | Notes |
|----------|--------|
| Production secret store | Azure Key Vault / AWS Secrets Manager / GCP Secret Manager / host env injection |
| Live credential rotation | Must be executed by ops against real providers |
| Historical Git remediation | Past commits that once contained `.env` require history purge / filter if policy requires it — not done by this local audit |
| Public remote exposure | If the repo was ever public with secrets, assume compromise and rotate |

Local hygiene + documentation can be improved without a cloud secret store.
Do **not** mark production secret-management complete solely because this
local checklist is satisfied.
