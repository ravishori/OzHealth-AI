#!/usr/bin/env python3
"""HN-INFRA-006 — static (+ optional runtime) validation for local Compose.

Safe to run without Docker: static checks always execute.
Runtime docker compose checks run only when the Docker CLI is available.
Never prints secret values.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPOSE = ROOT / "docker-compose.yml"
ROOT_ENV_EXAMPLE = ROOT / ".env.example"
BACKEND_ENV_EXAMPLE = ROOT / "backend" / ".env.example"
ALEMBIC_INI = ROOT / "backend" / "alembic.ini"
DOCKERFILE = ROOT / "backend" / "Dockerfile"


FORBIDDEN_SECRET_PATTERNS = [
    re.compile(r"sk-[A-Za-z0-9]{20,}"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"-----BEGIN (RSA |OPENSSH )?PRIVATE KEY-----"),
]


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def check_files_exist() -> list[str]:
    errors = []
    for p in (COMPOSE, ROOT_ENV_EXAMPLE, BACKEND_ENV_EXAMPLE, ALEMBIC_INI, DOCKERFILE):
        if not p.is_file():
            errors.append(f"missing required file: {p.relative_to(ROOT)}")
    return errors


def check_compose_static() -> list[str]:
    errors: list[str] = []
    text = _read(COMPOSE)

    for svc in ("postgres:", "redis:", "backend:"):
        if svc not in text:
            errors.append(f"compose missing service block `{svc}`")

    if "healthnest_local" not in text and "networks:" not in text:
        errors.append("compose missing explicit network declaration")

    if "pg_isready" not in text:
        errors.append("postgres healthcheck must use pg_isready")

    if "/ready" not in text:
        errors.append("backend healthcheck must probe application /ready")

    if "@postgres:" not in text and "@postgres/" not in text:
        errors.append("backend DATABASE_URL must use Compose host `postgres`")

    if "redis://redis:" not in text:
        errors.append("backend REDIS_URL must use Compose host `redis`")

    # Inside-container localhost for DB is incorrect
    if re.search(r"DATABASE_URL:.*@localhost", text):
        errors.append("backend must not use localhost for DATABASE_URL in Compose")
    if re.search(r"REDIS_URL:.*localhost", text):
        errors.append("backend must not use localhost for REDIS_URL in Compose")

    if "POSTGRES_PASSWORD:${POSTGRES_PASSWORD" not in text.replace(" ", "") and \
       "${POSTGRES_PASSWORD" not in text:
        errors.append("POSTGRES_PASSWORD must come from environment substitution")

    if "privileged:" in text:
        errors.append("privileged containers are not allowed for local Compose")

    for pat in FORBIDDEN_SECRET_PATTERNS:
        if pat.search(text):
            errors.append("compose appears to contain a hard-coded secret pattern")
            break

    return errors


def check_secret_hygiene() -> list[str]:
    errors: list[str] = []
    alembic = _read(ALEMBIC_INI)
    if "London2026" in alembic or "AUSMedicine_DB" in alembic:
        errors.append("alembic.ini must not embed historical hard-coded credentials")
    if "postgresql+psycopg2://postgres:" in alembic and "PASSWORD" not in alembic.upper():
        # Real-looking inline DSN in ini
        if "driver://user:pass@" not in alembic:
            errors.append("alembic.ini should use a non-secret placeholder URL")

    for path in (ROOT_ENV_EXAMPLE, BACKEND_ENV_EXAMPLE):
        text = _read(path)
        for pat in FORBIDDEN_SECRET_PATTERNS:
            if pat.search(text):
                errors.append(f"{path.name} contains forbidden secret pattern")
                break
        if "sk-ant-" in text:
            errors.append(f"{path.name} must not contain Anthropic key material")

    compose = _read(COMPOSE)
    lowered = compose.lower()
    remote_markers = (
        "azure.com",
        "database.windows.net",
        "amazonaws.com",
        "neon.tech",
        "supabase.co",
    )
    for marker in remote_markers:
        if marker in lowered:
            errors.append(f"compose must stay local-only (found remote host marker: {marker})")
            break

    return errors


def check_compose_config(docker_bin: str) -> list[str]:
    """INFRA06-01 — `docker compose config` must parse."""
    env = os.environ.copy()
    env.setdefault("POSTGRES_PASSWORD", "local_dev_only_validation")
    env.setdefault("SECRET_KEY", "local_dev_only_validation_secret")
    try:
        proc = subprocess.run(
            [docker_bin, "compose", "-f", str(COMPOSE), "config"],
            cwd=str(ROOT),
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
    except OSError as exc:
        return [f"docker compose config failed to execute: {exc}"]
    if proc.returncode != 0:
        # Do not echo stderr if it might include env — keep generic
        return [f"docker compose config failed (exit {proc.returncode})"]
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--runtime",
        action="store_true",
        help="Also run docker compose config when Docker CLI is available",
    )
    args = parser.parse_args()

    errors: list[str] = []
    errors.extend(check_files_exist())
    if not errors:
        errors.extend(check_compose_static())
        errors.extend(check_secret_hygiene())

    docker_bin = shutil.which("docker")
    runtime_status = "skipped (docker CLI not found)"
    if args.runtime and docker_bin:
        runtime_errors = check_compose_config(docker_bin)
        errors.extend(runtime_errors)
        runtime_status = "ok" if not runtime_errors else "failed"
    elif args.runtime and not docker_bin:
        runtime_status = "skipped (docker CLI not found)"

    if errors:
        print("INFRA06 validation FAIL")
        for e in errors:
            print(f"  - {e}")
        print(f"runtime_compose_config={runtime_status}")
        return 1

    print("INFRA06 validation PASS")
    print("  static_checks=ok")
    print(f"  runtime_compose_config={runtime_status}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
