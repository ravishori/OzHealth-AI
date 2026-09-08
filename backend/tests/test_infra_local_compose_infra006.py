"""HN-INFRA-006 — local Compose / env hardening static checks (INFRA06)."""
from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "validate_local_compose.py"
COMPOSE = REPO_ROOT / "docker-compose.yml"
ALEMBIC_INI = REPO_ROOT / "backend" / "alembic.ini"
MAIN_PY = REPO_ROOT / "backend" / "main.py"


def _load_validator():
    spec = importlib.util.spec_from_file_location("validate_local_compose", SCRIPT)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_infra06_01_compose_file_present_and_validator_pass():
    """INFRA06-01 / INFRA06-07 / INFRA06-08 / INFRA06-09 — static validation PASS."""
    assert COMPOSE.is_file()
    assert SCRIPT.is_file()
    proc = subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert "INFRA06 validation PASS" in proc.stdout


def test_infra06_07_no_hardcoded_alembic_password():
    """INFRA06-07 — alembic.ini must not embed real credentials."""
    text = ALEMBIC_INI.read_text(encoding="utf-8")
    assert "London2026" not in text
    assert "AUSMedicine_DB" not in text
    assert "driver://user:pass@localhost/dbname" in text


def test_infra06_08_compose_uses_service_dns_not_localhost_for_db():
    """INFRA06-08"""
    text = COMPOSE.read_text(encoding="utf-8")
    assert "@postgres:" in text or "@postgres/" in text
    assert "redis://redis:" in text
    assert "DATABASE_URL: postgresql+asyncpg://postgres:" in text
    # environment block must not point DB at localhost
    assert "DATABASE_URL: postgresql+asyncpg://postgres:PASSWORD@localhost" not in text


def test_infra06_09_local_only_markers():
    """INFRA06-09 — docs/compose separated from production cloud hosts."""
    text = COMPOSE.read_text(encoding="utf-8")
    assert "LOCAL development" in text or "local" in text.lower()
    lowered = text.lower()
    assert "azure.com" not in lowered
    assert "database.windows.net" not in lowered
    doc = (REPO_ROOT / "docs" / "LOCAL_DEVELOPMENT.md").read_text(encoding="utf-8")
    assert "10.0.2.2" in doc
    assert "postgres" in doc
    assert "LOCAL" in doc or "local" in doc.lower()


def test_infra06_ready_endpoint_exists():
    """Readiness endpoint used by Compose healthcheck."""
    src = MAIN_PY.read_text(encoding="utf-8")
    assert '@app.get("/ready"' in src
    assert "SELECT 1" in src


def test_infra06_validator_module_checks():
    mod = _load_validator()
    assert mod.check_files_exist() == []
    assert mod.check_compose_static() == []
    assert mod.check_secret_hygiene() == []


@pytest.mark.skipif(
    os.environ.get("INFRA06_REQUIRE_DOCKER") != "1",
    reason="Docker runtime optional; set INFRA06_REQUIRE_DOCKER=1 to enforce",
)
def test_infra06_01_docker_compose_config_when_forced():
    """INFRA06-01 runtime — only when Docker is required by env."""
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "--runtime"],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr
