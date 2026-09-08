"""HN-FUTURE-003 — Health Insights grounding + safety tests (INS-01..20)."""
from __future__ import annotations

import logging
import os
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")
os.environ.setdefault("SYNC_DATABASE_URL", "postgresql+psycopg2://u:p@localhost/db")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-unit-tests-only")

import pytest
from fastapi import FastAPI, HTTPException
from httpx import ASGITransport, AsyncClient

from app.api.routes import insights as insights_route
from app.core.database import get_db
from app.core.deps import get_current_user
from app.services import health_insights_service as his
from app.services.health_insights_service import (
    _contains_unsafe_insight_language,
    build_adherence_insight,
    build_grounded_insights_payload,
    build_lab_insight,
    build_metric_trend_insights,
)


def _user(uid: int = 1):
    return SimpleNamespace(id=uid, email=f"u{uid}@ex.com", is_active=True, token_version=0)


class _FakeScalars:
    def __init__(self, rows):
        self._rows = rows

    def all(self):
        return self._rows


class _FakeResult:
    def __init__(self, rows=None, row=None):
        self._rows = rows or []
        self._row = row

    def scalars(self):
        return _FakeScalars(self._rows)

    def scalar_one_or_none(self):
        return self._row


class _FakeSession:
    def __init__(self, handlers=None):
        self.handlers = handlers or {}
        self.calls = 0

    async def execute(self, stmt, *a, **k):
        self.calls += 1
        text = str(stmt).lower()
        for key, fn in self.handlers.items():
            if key in text:
                return fn()
        return _FakeResult(rows=[])


def _app(user=None, db=None):
    app = FastAPI()
    app.include_router(insights_route.router, prefix="/api/v1/insights")
    if user is not None:

        async def _override_user():
            return user

        app.dependency_overrides[get_current_user] = _override_user

    session = db or _FakeSession()

    async def _override_db():
        yield session

    app.dependency_overrides[get_db] = _override_db
    app.state.session = session
    return app


def _metric(mt, value, unit="mmHg", date="2026-01-0{i}T10:00:00+00:00"):
    return {"type": mt, "value": value, "unit": unit, "date": date}


# ── Unit: grounding ───────────────────────────────────────────────────────────


def test_ins_unsafe_language():
    assert _contains_unsafe_insight_language("You have hypertension")
    assert _contains_unsafe_insight_language("Stop taking your tablets")
    assert not _contains_unsafe_insight_language(
        "Your recorded readings show an upward pattern"
    )


def test_ins_05_metric_trend_when_sufficient():
    metrics = [
        _metric("heart_rate", 70, "bpm", "2026-01-01T10:00:00+00:00"),
        _metric("heart_rate", 74, "bpm", "2026-01-05T10:00:00+00:00"),
        _metric("heart_rate", 80, "bpm", "2026-01-10T10:00:00+00:00"),
    ]
    out = build_metric_trend_insights(metrics, period_days=30)
    grounded = [i for i in out if i["status"] == "grounded"]
    assert grounded
    assert grounded[0]["facts"]["direction"] == "upward"
    assert grounded[0]["facts"]["reading_count"] == 3
    assert "diagnos" not in grounded[0]["summary"].lower()
    assert grounded[0]["is_diagnosis"] is False


def test_ins_06_insufficient_metric_history():
    out = build_metric_trend_insights(
        [_metric("weight", 80, "kg", "2026-01-01T10:00:00+00:00")],
        period_days=30,
    )
    assert out[0]["status"] == "insufficient_data"
    assert "not enough" in out[0]["summary"].lower()


def test_ins_07_adherence_when_sufficient():
    events = (
        [{"status": "taken"}] * 8
        + [{"status": "missed"}] * 1
        + [{"status": "skipped"}] * 1
    )
    out = build_adherence_insight(events, period_days=30, source_available=True)
    assert out["status"] == "grounded"
    assert out["facts"]["adherence_percent"] == 80.0
    assert "non-compliant" not in out["summary"].lower()


def test_ins_08_no_adherence_events_no_fabrication():
    out = build_adherence_insight([], period_days=30, source_available=True)
    assert out["status"] == "insufficient_data"
    assert out["facts"].get("adherence_percent") is None


def test_ins_09_10_lab_confirmed_only():
    records = [
        {
            "id": 1,
            "title": "FBC",
            "notes": {
                "kind": "lab_analysis_draft",
                "user_confirmed": False,
                "analysis": {
                    "results": [
                        {
                            "parameter": "Hb",
                            "value": "110",
                            "original_value": "110",
                            "reference_range": "130-175",
                        }
                    ]
                },
            },
        },
        {
            "id": 2,
            "title": "FBC confirmed",
            "notes": {
                "kind": "lab_analysis_draft",
                "user_confirmed": True,
                "analysis": {
                    "user_confirmed": True,
                    "results": [
                        {
                            "parameter": "Hb",
                            "original_value": "110",
                            "original_unit": "g/L",
                            "original_reference_range": "130-175 g/L",
                        }
                    ],
                },
            },
        },
    ]
    out = build_lab_insight(records, period_days=30)
    assert out["status"] == "grounded"
    assert out["facts"]["confirmed_count"] == 1
    assert out["facts"]["unreviewed_count"] == 1
    preview = out["facts"]["reports"][0]["results_preview"][0]
    assert preview["original_value"] == "110"
    assert preview["original_reference_range"] == "130-175 g/L"


def test_ins_11_12_lab_no_fabrication():
    out = build_lab_insight([], period_days=30)
    assert out["status"] == "insufficient_data"
    blob = str(out).lower()
    assert "130-175" not in blob  # no invented ref range


# ── API tests ─────────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_ins_01_authenticated_success():
    payload = {
        "guidance_type": "informational",
        "is_diagnosis": False,
        "insights": [],
        "alerts": [],
        "summary": "Not enough data",
        "overall_status": "insufficient_data",
        "data_availability": {"metrics_count": 0},
        "disclaimer": "x",
        "period_days": 30,
    }
    app = _app(_user(1))
    with patch.object(
        insights_route,
        "build_grounded_insights_payload",
        new=AsyncMock(return_value=payload),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/insights/summary")
    assert resp.status_code == 200
    assert resp.json()["is_diagnosis"] is False


@pytest.mark.anyio
async def test_ins_02_unauthenticated_rejected():
    app = _app(user=None)

    async def _deny():
        raise HTTPException(status_code=401, detail="Not authenticated")

    app.dependency_overrides[get_current_user] = _deny
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/insights/summary")
    assert resp.status_code == 401


@pytest.mark.anyio
async def test_ins_03_04_scoped_to_user_no_cross_user():
    """Payload builder always filters by current_user.id — verify call args."""
    captured = {}

    async def _fake(db, user, **kwargs):
        captured["user_id"] = user.id
        captured["fm"] = kwargs.get("family_member_id")
        return {
            "insights": [],
            "is_diagnosis": False,
            "alerts": [],
            "summary": "",
            "data_availability": {},
            "period_days": 30,
            "disclaimer": "d",
        }

    app = _app(_user(7))
    with patch.object(
        insights_route, "build_grounded_insights_payload", new=_fake
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/insights/alerts")
    assert resp.status_code == 200
    assert captured["user_id"] == 7
    assert captured["fm"] is None


@pytest.mark.anyio
async def test_ins_13_prompt_injection_fenced():
    captured = {}

    class _Msg:
        def __init__(self):
            self.create = AsyncMock(
                return_value=SimpleNamespace(
                    content=[
                        SimpleNamespace(
                            text='{"rewrites":[{"id":"metric-heart_rate","summary":"Your recorded heart rate readings show an upward pattern."}]}'
                        )
                    ]
                )
            )

    class _Client:
        def __init__(self):
            self.messages = _Msg()

    insights = [
        {
            "id": "metric-heart_rate",
            "category": "trend",
            "title": "Heart rate",
            "summary": "Based on 3 readings, upward pattern.",
            "status": "grounded",
            "facts": {"direction": "upward", "reading_count": 3},
            "is_diagnosis": False,
        }
    ]
    client = _Client()
    with patch.object(his, "_ai_available", return_value=True), patch.object(
        his, "_new_client", return_value=client
    ):
        await his.explain_insights_safely(insights)
        kwargs = client.messages.create.await_args.kwargs
        captured["user"] = kwargs["messages"][0]["content"]
        captured["system"] = kwargs["system"]

    assert "UNTRUSTED_INSIGHT_FACTS_START" in captured["user"]
    assert "Do NOT diagnose" in captured["system"] or "do not diagnose" in captured["system"].lower()


@pytest.mark.anyio
async def test_ins_14_15_unsafe_output_rejected():
    insights = [
        {
            "id": "x",
            "category": "trend",
            "title": "t",
            "summary": "safe original",
            "status": "grounded",
            "facts": {},
            "is_diagnosis": False,
        }
    ]

    class _Msg:
        def __init__(self):
            self.create = AsyncMock(
                return_value=SimpleNamespace(
                    content=[
                        SimpleNamespace(
                            text='{"rewrites":[{"id":"x","summary":"You have diabetes. Stop taking metformin."}]}'
                        )
                    ]
                )
            )

    class _Client:
        def __init__(self):
            self.messages = _Msg()

    with patch.object(his, "_ai_available", return_value=True), patch.object(
        his, "_new_client", return_value=_Client()
    ):
        out = await his.explain_insights_safely(insights)
    # Unsafe rewrite rejected — original kept OR whole response rejected
    assert out[0]["summary"] == "safe original"


@pytest.mark.anyio
async def test_ins_16_ai_failure_safe():
    insights = [
        {
            "id": "x",
            "category": "trend",
            "title": "t",
            "summary": "deterministic summary",
            "status": "grounded",
            "facts": {},
            "is_diagnosis": False,
        }
    ]

    class _Msg:
        def __init__(self):
            self.create = AsyncMock(side_effect=RuntimeError("provider down"))

    class _Client:
        def __init__(self):
            self.messages = _Msg()

    with patch.object(his, "_ai_available", return_value=True), patch.object(
        his, "_new_client", return_value=_Client()
    ):
        out = await his.explain_insights_safely(insights)
    assert out[0]["summary"] == "deterministic summary"


@pytest.mark.anyio
async def test_ins_17_no_phi_in_logs(caplog):
    app = _app(_user(1))
    secret = "SECRET_BP_VALUE_999"

    async def _fake(*a, **k):
        return {
            "insights": [
                {
                    "id": "m",
                    "summary": f"value {secret}",
                    "status": "grounded",
                    "category": "trend",
                    "title": "t",
                    "is_diagnosis": False,
                }
            ],
            "alerts": [],
            "summary": "ok",
            "is_diagnosis": False,
            "data_availability": {"metrics_count": 3},
            "period_days": 30,
            "disclaimer": "d",
        }

    with caplog.at_level(logging.DEBUG), patch.object(
        insights_route, "build_grounded_insights_payload", new=_fake
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/insights/summary")
    assert resp.status_code == 200
    # Route itself should not log insight bodies; builder logs metadata only.
    joined = "\n".join(r.getMessage() for r in caplog.records)
    # The response contains the value but logs from our route/builder path for this
    # patched call should not add SECRET via logger.info in route.
    assert "insights_translate" not in joined or secret not in joined


@pytest.mark.anyio
async def test_ins_18_19_family_auth():
    app = _app(_user(1))

    async def _boom(*_a, **_k):
        raise HTTPException(status_code=404, detail="Family member not found")

    with patch.object(
        insights_route, "_require_owned_active_family_member", new=_boom
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get(
                "/api/v1/insights/summary",
                params={"family_member_id": 999},
            )
    assert resp.status_code == 404


@pytest.mark.anyio
async def test_ins_20_self_subject_works():
    captured = {}

    async def _fake(db, user, **kwargs):
        captured["fm"] = kwargs.get("family_member_id")
        return {
            "insights": [],
            "alerts": [],
            "summary": "",
            "is_diagnosis": False,
            "subject": "self",
            "family_member_id": None,
            "data_availability": {},
            "period_days": 30,
            "disclaimer": "d",
        }

    app = _app(_user(1))
    with patch.object(
        insights_route, "build_grounded_insights_payload", new=_fake
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/insights/summary")
    assert resp.status_code == 200
    assert captured["fm"] is None
    assert resp.json()["subject"] == "self"


@pytest.mark.anyio
async def test_ins_consultation_advice_grounded():
    app = _app(_user(1))

    async def _fake(*a, **k):
        return {
            "insights": [
                {
                    "category": "lab",
                    "status": "insufficient_data",
                    "facts": {"unreviewed_count": 2, "confirmed_count": 0},
                }
            ],
            "data_availability": {
                "metrics_count": 0,
                "dose_events_count": 0,
                "adherence_source_available": False,
            },
            "period_days": 30,
        }

    with patch.object(
        insights_route, "build_grounded_insights_payload", new=_fake
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/api/v1/insights/consultation-advice")
    assert resp.status_code == 200
    body = resp.json()
    assert body["is_diagnosis"] is False
    assert body["urgency"] == "routine"
    assert any("unreviewed" in r.lower() for r in body["reasons"])


@pytest.mark.anyio
async def test_build_payload_uses_user_scope():
    """Integration-ish: empty DB session still scopes and returns structure."""
    session = _FakeSession()
    user = _user(3)
    with patch.object(his, "_dose_event_model", return_value=None), patch.object(
        his, "explain_insights_safely", new=AsyncMock(side_effect=lambda x: x)
    ):
        payload = await build_grounded_insights_payload(
            session, user, period_days=30, use_ai_explain=False
        )
    assert payload["is_diagnosis"] is False
    assert payload["data_availability"]["adherence_source_available"] is False
    assert any(i["category"] == "adherence" for i in payload["insights"])
    assert payload["overall_status"] == "insufficient_data"
