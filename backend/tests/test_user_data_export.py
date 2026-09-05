"""HN-LEGAL-007 — user data export (LEGAL-S4-*)."""

from __future__ import annotations

import inspect
from datetime import date, datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app.api.routes import users as users_route
from app.core.database import get_db
from app.core.deps import get_current_user
from app.services import user_data_export_service as export_svc
from app.services.user_data_export_service import (
    FORBIDDEN_EXPORT_KEYS,
    assert_export_has_no_secrets,
    build_user_data_export,
    profile_for_export,
)


def _user(uid: int = 1, **kwargs):
    defaults = dict(
        id=uid,
        name=f"User{uid}",
        email=f"u{uid}@example.com",
        phone=f"+6140000000{uid}",
        phone2=None,
        age=30,
        gender="Female",
        blood_group="O+",
        health_conditions='["Asthma"]',
        allergies='["Penicillin"]',
        lifestyle_preferences=None,
        suburb="Richmond",
        city="Melbourne",
        state="VIC",
        postcode="3121",
        profile_image_url=None,
        is_verified=True,
        created_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
        fcm_token="SHOULD-NEVER-EXPORT",
        token_version=7,
        password_hash="SHOULD-NEVER-EXPORT",
        is_active=True,
    )
    defaults.update(kwargs)
    return SimpleNamespace(**defaults)


def _result(rows):
    r = MagicMock()
    r.scalars.return_value.all.return_value = rows
    return r


@pytest.fixture
def export_app():
    def _make(user):
        app = FastAPI()
        app.include_router(users_route.router, prefix="/api/v1/users")

        async def _override_user():
            return user

        async def _override_db():
            db = AsyncMock()
            yield db

        app.dependency_overrides[get_current_user] = _override_user
        app.dependency_overrides[get_db] = _override_db
        return app

    return _make


def test_legal_s4_01_profile_excludes_secrets():
    """LEGAL-S4-01 — profile section has expected fields and no secrets."""
    u = _user(1)
    prof = profile_for_export(u)
    assert prof["id"] == 1
    assert prof["email"] == "u1@example.com"
    assert "fcm_token" not in prof
    assert "token_version" not in prof
    assert "password_hash" not in prof
    assert_export_has_no_secrets({"profile": prof})


@pytest.mark.asyncio
async def test_legal_s4_01_owner_export_contains_expected_sections():
    """LEGAL-S4-01 — authenticated owner payload has schema + sections."""
    owner = _user(1)
    db = AsyncMock()

    own_rx = SimpleNamespace(
        id=10,
        family_member_id=None,
        doctor_name="Dr A",
        hospital="RPH",
        prescription_date=None,
        extracted_medicines='[{"name":"Amoxicillin"}]',
        ai_summary="summary",
        created_at=None,
        user_id=1,
    )
    own_rem = SimpleNamespace(
        id=5,
        family_member_id=None,
        medicine_name="Amox",
        dosage="500mg",
        frequency="daily",
        times='["08:00"]',
        instructions=None,
        start_date=date(2026, 1, 1),
        end_date=None,
        refill_date=None,
        total_quantity=30,
        remaining_quantity=10,
        is_active=True,
        prescription_id=None,
        created_at=None,
        user_id=1,
    )

    db.execute = AsyncMock(
        side_effect=[
            _result([own_rx]),
            _result([]),
            _result([own_rem]),
            _result([]),
            _result([]),
            _result([]),
            _result([]),
            _result([]),
        ]
    )

    payload = await build_user_data_export(db, owner)
    assert payload["export_schema_version"] == "1.0"
    assert payload["user_id"] == 1
    assert "generated_at" in payload
    assert set(payload.keys()) >= {
        "profile",
        "prescriptions",
        "medical_records",
        "reminders",
        "family_members",
        "emergency_contacts",
        "health_metrics",
        "ai_conversations",
        "eprescriptions",
        "eprescription_refill_reminders",
    }
    assert payload["prescriptions"][0]["id"] == 10
    assert payload["reminders"][0]["medicine_name"] == "Amox"
    assert all(p["id"] != 99 for p in payload["prescriptions"])
    assert_export_has_no_secrets(payload)


@pytest.mark.anyio
async def test_legal_s4_01_http_owner_gets_attachment(export_app):
    """LEGAL-S4-01 HTTP — owner receives JSON attachment with sections."""
    app = export_app(_user(1))
    fake = {
        "export_schema_version": "1.0",
        "generated_at": "2026-09-05T00:00:00+00:00",
        "user_id": 1,
        "profile": {"id": 1, "name": "User1"},
        "prescriptions": [],
        "medical_records": [],
        "reminders": [],
        "family_members": [],
        "emergency_contacts": [],
        "health_metrics": [],
        "ai_conversations": [],
        "eprescriptions": [],
        "eprescription_refill_reminders": [],
    }
    with patch.object(
        users_route, "build_user_data_export", new=AsyncMock(return_value=fake)
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/users/me/data-export")
    assert resp.status_code == 200
    assert "application/json" in resp.headers.get("content-type", "")
    assert "attachment" in resp.headers.get("content-disposition", "")
    assert "healthnest-data-export-1.json" in resp.headers.get(
        "content-disposition", ""
    )
    body = resp.json()
    assert body["user_id"] == 1
    assert body["export_schema_version"] == "1.0"
    assert "profile" in body


@pytest.mark.anyio
async def test_legal_s4_02_unauthenticated_denied():
    """LEGAL-S4-02 — no auth → 401/403."""
    app = FastAPI()
    app.include_router(users_route.router, prefix="/api/v1/users")

    async def _override_db():
        yield AsyncMock()

    app.dependency_overrides[get_db] = _override_db

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/users/me/data-export")
    assert resp.status_code in (401, 403)


@pytest.mark.asyncio
async def test_legal_s4_03_queries_filter_by_current_user_id_only():
    """LEGAL-S4-03 — every select is scoped to owner user_id; no client user_id."""
    src = inspect.getsource(build_user_data_export)
    assert "user_id == uid" in src
    route_src = inspect.getsource(users_route.export_my_data)
    assert "Query(" not in route_src
    assert "build_user_data_export(db, current_user)" in route_src

    owner = _user(1)
    db = AsyncMock()
    captured = []

    async def _exec(stmt):
        captured.append(str(stmt))
        return _result([])

    db.execute = AsyncMock(side_effect=_exec)
    await build_user_data_export(db, owner)
    assert captured
    joined = " | ".join(captured)
    assert "user_id" in joined.lower()


@pytest.mark.asyncio
async def test_legal_s4_03_second_user_rows_never_in_owner_export():
    """LEGAL-S4-03 — owner export user_id is the authenticated owner."""
    owner = _user(2)
    db = AsyncMock()
    db.execute = AsyncMock(return_value=_result([]))
    payload = await build_user_data_export(db, owner)
    assert payload["user_id"] == 2
    assert payload["prescriptions"] == []
    assert payload["reminders"] == []
    assert db.execute.await_count >= 1


def test_legal_s4_04_forbidden_keys_detected():
    """LEGAL-S4-04 — secret key detector works; clean payload passes."""
    with pytest.raises(AssertionError):
        assert_export_has_no_secrets({"profile": {"fcm_token": "x"}})
    with pytest.raises(AssertionError):
        assert_export_has_no_secrets({"a": [{"password_hash": "x"}]})
    with pytest.raises(AssertionError):
        assert_export_has_no_secrets({"token_hash": "abc"})
    clean = {
        "profile": profile_for_export(_user(1)),
        "prescriptions": [{"id": 1, "doctor_name": "Dr"}],
        "medical_records": [{"id": 1, "file_name": "a.pdf", "notes": "n"}],
    }
    assert_export_has_no_secrets(clean)
    assert "fcm_token" in FORBIDDEN_EXPORT_KEYS
    assert "token_hash" in FORBIDDEN_EXPORT_KEYS


def test_legal_s4_04_eprescription_serializer_omits_token_hash():
    ep = SimpleNamespace(
        id=1,
        provider="mock",
        status="validated",
        token_last4="1234",
        token_hash="deadbeef" * 8,
        patient_name="Pat",
        prescriber_name="Dr",
        prescriber_provider_number=None,
        prescriber_practice=None,
        medicines="[]",
        prescription_date=None,
        expiry_date=None,
        created_at=None,
    )
    row = export_svc._eprescription_row(ep)
    assert "token_hash" not in row
    assert row["token_last4"] == "1234"


def test_legal_s4_04_record_serializer_omits_file_bytes_and_url():
    rec = SimpleNamespace(
        id=3,
        family_member_id=None,
        record_type="lab_report",
        title="Labs",
        file_url="records/1/secret.pdf",
        file_name="labs.pdf",
        file_type="pdf",
        file_size=100,
        notes="ok",
        record_date=None,
        is_active=True,
        created_at=None,
    )
    row = export_svc._record_row(rec)
    assert "file_url" not in row
    assert row["file_name"] == "labs.pdf"


def test_legal_s4_route_does_not_log_export_body():
    src = inspect.getsource(users_route.export_my_data)
    assert "json.dumps(payload" in src
    audit_part = src[src.index("audit_log.info") :]
    assert "health_conditions" not in audit_part
    assert "allergies" not in audit_part
    assert "byte_length" in audit_part
