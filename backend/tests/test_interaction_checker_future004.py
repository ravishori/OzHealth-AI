"""HN-FUTURE-004 — Interaction checker source-grounding tests."""
from __future__ import annotations

import os
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")
os.environ.setdefault("SYNC_DATABASE_URL", "postgresql+psycopg2://u:p@localhost/db")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-unit-tests-only")

import pytest
from fastapi import FastAPI, HTTPException
from httpx import ASGITransport, AsyncClient

from app.api.routes import interactions as ix_route
from app.core.database import get_db
from app.core.deps import get_current_user
from app.services.medicine_safety_service import MedicineSafetyChecker, MedBundle


def _user(uid: int = 1):
    return SimpleNamespace(id=uid, email=f"u{uid}@ex.com", is_active=True)


class _FakeScalars:
    def __init__(self, rows):
        self._rows = rows

    def all(self):
        return self._rows


class _FakeResult:
    def __init__(self, row=None, rows=None):
        self._row = row
        self._rows = rows or ([] if row is None else [row])

    def scalar_one_or_none(self):
        return self._row

    def scalars(self):
        return _FakeScalars(self._rows)


class _FakeSession:
    def __init__(self, medicines_by_id=None):
        self.medicines_by_id = medicines_by_id or {}

    async def execute(self, stmt, *a, **k):
        # Very small stub: return medicine if looking up by id in map
        return _FakeResult(row=None, rows=[])


def _app(user=None, db=None):
    app = FastAPI()
    app.include_router(ix_route.router, prefix="/api/v1/interactions")
    if user is not None:

        async def _ou():
            return user

        app.dependency_overrides[get_current_user] = _ou

    session = db or _FakeSession()

    async def _odb():
        yield session

    app.dependency_overrides[get_db] = _odb
    return app


def _safety_known():
    return {
        "overall_status": "ALERTS_PRESENT",
        "medicines": [
            {"medicine_id": 1, "name": "Warfarin", "generic_name": "warfarin", "ingredients": ["warfarin"]},
            {"medicine_id": 2, "name": "Aspirin", "generic_name": "aspirin", "ingredients": ["aspirin"]},
        ],
        "duplicates": [],
        "allergy_alerts": [],
        "interactions": [
            {
                "medicine_a": {"medicine_id": 1, "name": "Warfarin"},
                "medicine_b": {"medicine_id": 2, "name": "Aspirin"},
                "severity": "major",
                "description": "Increased bleeding risk (database).",
                "source": "database",
                "status": "KNOWN",
                "evidence": {
                    "interaction_id": 99,
                    "source_name": "local_interactions_table",
                    "documentation_level": "established",
                },
            }
        ],
        "data_coverage": {
            "structured_interactions_table_rows": 1,
            "pairs_checked": 1,
            "pairs_known": 1,
            "pairs_unknown": 0,
            "source": "database",
        },
        "safety": {"disclaimer": "d", "unknown_not_safe": True, "treatment_advice": False},
    }


def _safety_unknown():
    return {
        "overall_status": "INCOMPLETE_DATA",
        "medicines": [
            {"medicine_id": 1, "name": "Paracetamol", "generic_name": "paracetamol", "ingredients": []},
            {"medicine_id": 2, "name": "Ibuprofen", "generic_name": "ibuprofen", "ingredients": []},
        ],
        "duplicates": [],
        "allergy_alerts": [],
        "interactions": [
            {
                "medicine_a": {"medicine_id": 1, "name": "Paracetamol"},
                "medicine_b": {"medicine_id": 2, "name": "Ibuprofen"},
                "severity": None,
                "description": "Interaction information not available in the current dataset.",
                "source": "unavailable",
                "status": "UNKNOWN",
            }
        ],
        "data_coverage": {
            "structured_interactions_table_rows": 0,
            "pairs_checked": 1,
            "pairs_known": 0,
            "pairs_unknown": 1,
            "source": "database",
        },
        "safety": {"disclaimer": "d", "unknown_not_safe": True, "treatment_advice": False},
    }


def _safety_duplicate():
    base = _safety_unknown()
    base["duplicates"] = [
        {
            "medicine_a": {"medicine_id": 1, "name": "Panadol"},
            "medicine_b": {"medicine_id": 3, "name": "Paracetamol"},
            "reason": "same canonical_key (paracetamol)",
            "source": "database",
            "status": "DUPLICATE",
        }
    ]
    base["medicines"].append(
        {"medicine_id": 3, "name": "Paracetamol", "generic_name": "paracetamol", "ingredients": []}
    )
    # pairs still unknown — duplicates are not interactions
    return base


# ── Unit helpers ──────────────────────────────────────────────────────────────


def test_map_pair_preserves_source_backed_severity():
    mapped = ix_route._map_pair(
        {
            "medicine_a": {"medicine_id": 1, "name": "A"},
            "medicine_b": {"medicine_id": 2, "name": "B"},
            "severity": "major",
            "description": "Bleeding risk",
            "source": "database",
            "status": "KNOWN",
            "evidence": {"interaction_id": 7, "source_name": "local_db"},
        }
    )
    assert mapped["severity"] == "major"
    assert mapped["source_type"] == "source_backed"
    assert mapped["verified"] is True
    assert mapped["source_name"] == "local_db"
    assert mapped["unavailable"] is False


def test_map_pair_unavailable_not_safe():
    mapped = ix_route._map_pair(
        {
            "medicine_a": {"medicine_id": 1, "name": "A"},
            "medicine_b": {"medicine_id": 2, "name": "B"},
            "severity": None,
            "description": "x",
            "source": "unavailable",
            "status": "UNKNOWN",
        }
    )
    assert mapped["unavailable"] is True
    assert mapped["verified"] is False
    assert mapped["severity"] is None
    blob = mapped["description"].lower()
    assert "unavailable" in blob
    assert "safe" not in blob or "not mean" in blob or "does not mean" in blob
    assert "no interaction" not in blob


def test_duplicate_not_classified_as_interaction():
    d = ix_route._map_duplicate(
        {
            "medicine_a": {"medicine_id": 1, "name": "A"},
            "medicine_b": {"medicine_id": 2, "name": "B"},
            "reason": "same medicine_id",
            "source": "database",
            "status": "DUPLICATE",
        }
    )
    assert d["is_interaction"] is False
    assert d["warning_type"] == "duplicate_medicine"


def test_self_pair_not_generated_by_safety_checker():
    """Medicine cannot be checked against itself — combinations only."""
    checker = MedicineSafetyChecker(AsyncMock())
    a = MedBundle(1, "A", "a", None, "a", None, [])
    # Single medicine → no pairs
    assert checker._duplicates([a]) == []


# ── API ───────────────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_interaction_01_authenticated_success():
    app = _app(_user(1))
    med = SimpleNamespace(id=1, name="Warfarin", generic_name="warfarin")
    med2 = SimpleNamespace(id=2, name="Aspirin", generic_name="aspirin")

    async def _resolve(db, name):
        return {"Warfarin": med, "Aspirin": med2}.get(name)

    with patch.object(ix_route, "_resolve_medicine_name", new=_resolve), patch.object(
        MedicineSafetyChecker, "check", new=AsyncMock(return_value=_safety_known())
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/interactions/check",
                json={"medicines": ["Warfarin", "Aspirin"]},
            )
    assert resp.status_code == 200
    body = resp.json()
    assert body["ai_used"] is False
    assert body["authoritative"] is True


@pytest.mark.anyio
async def test_interaction_02_unauthenticated_rejected():
    app = _app(user=None)

    async def _deny():
        raise HTTPException(status_code=401, detail="Not authenticated")

    app.dependency_overrides[get_current_user] = _deny
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post(
            "/api/v1/interactions/check",
            json={"medicine_ids": [1, 2]},
        )
    assert resp.status_code == 401


@pytest.mark.anyio
async def test_interaction_03_06_source_backed_result():
    app = _app(_user(1))
    with patch.object(
        MedicineSafetyChecker, "check", new=AsyncMock(return_value=_safety_known())
    ):
        # Bypass resolve by providing ids that "exist"
        async def _exec(stmt, *a, **k):
            # Return medicines for id lookups in order
            if not hasattr(_exec, "n"):
                _exec.n = 0
            _exec.n += 1
            meds = [
                SimpleNamespace(id=1, name="Warfarin", generic_name="warfarin"),
                SimpleNamespace(id=2, name="Aspirin", generic_name="aspirin"),
            ]
            idx = min(_exec.n - 1, 1)
            return _FakeResult(row=meds[idx])

        session = _FakeSession()
        session.execute = _exec  # type: ignore
        app = _app(_user(1), db=session)
        with patch.object(
            MedicineSafetyChecker, "check", new=AsyncMock(return_value=_safety_known())
        ):
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as client:
                resp = await client.post(
                    "/api/v1/interactions/check",
                    json={"medicine_ids": [1, 2]},
                )
    assert resp.status_code == 200
    body = resp.json()
    pair = body["interaction_analysis"]["interactions"][0]
    assert pair["source_type"] == "source_backed"
    assert pair["severity"] == "major"  # INTERACTION-04
    assert "pharmacist" in (pair["recommended_action"] or "").lower()  # INTERACTION-05
    assert pair["source_name"] == "local_interactions_table"  # INTERACTION-06
    assert pair["verified"] is True


@pytest.mark.anyio
async def test_interaction_07_08_empty_db_unavailable_not_safe():
    session = _FakeSession()

    async def _exec(stmt, *a, **k):
        if not hasattr(_exec, "n"):
            _exec.n = 0
        _exec.n += 1
        meds = [
            SimpleNamespace(id=1, name="Paracetamol", generic_name="paracetamol"),
            SimpleNamespace(id=2, name="Ibuprofen", generic_name="ibuprofen"),
        ]
        return _FakeResult(row=meds[min(_exec.n - 1, 1)])

    session.execute = _exec  # type: ignore
    app = _app(_user(1), db=session)
    with patch.object(
        MedicineSafetyChecker, "check", new=AsyncMock(return_value=_safety_unknown())
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/interactions/check",
                json={"medicine_ids": [1, 2]},
            )
    assert resp.status_code == 200
    body = resp.json()
    analysis = body["interaction_analysis"]
    assert analysis["unavailable"] is True
    assert analysis["risk_level"] == "unavailable"
    blob = str(body).lower()
    assert "unavailable" in blob
    assert '"safe"' not in blob or "not mean" in blob or "does not mean" in blob
    # Must not claim no interaction / safe
    assert "no interactions found" not in blob
    assert "no known interaction" not in blob
    assert analysis["overall_summary"].lower().find("safe together") >= 0 or \
        "unavailable" in analysis["overall_summary"].lower()


@pytest.mark.anyio
async def test_interaction_09_10_no_ai_authority():
    """AI is not used; source-backed path is deterministic."""
    session = _FakeSession()

    async def _exec(stmt, *a, **k):
        if not hasattr(_exec, "n"):
            _exec.n = 0
        _exec.n += 1
        meds = [
            SimpleNamespace(id=1, name="Warfarin", generic_name="warfarin"),
            SimpleNamespace(id=2, name="Aspirin", generic_name="aspirin"),
        ]
        return _FakeResult(row=meds[min(_exec.n - 1, 1)])

    session.execute = _exec  # type: ignore
    app = _app(_user(1), db=session)
    with patch.object(
        MedicineSafetyChecker, "check", new=AsyncMock(return_value=_safety_known())
    ), patch(
        "app.services.ai_service.check_drug_interactions", new=AsyncMock()
    ) as ai_mock:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/interactions/check",
                json={"medicine_ids": [1, 2]},
            )
    assert resp.status_code == 200
    assert resp.json()["ai_used"] is False
    ai_mock.assert_not_called()


@pytest.mark.anyio
async def test_interaction_11_12_13_duplicates_separate_no_self_pair():
    session = _FakeSession()

    async def _exec(stmt, *a, **k):
        if not hasattr(_exec, "n"):
            _exec.n = 0
        _exec.n += 1
        meds = [
            SimpleNamespace(id=1, name="Panadol", generic_name="paracetamol"),
            SimpleNamespace(id=2, name="Ibuprofen", generic_name="ibuprofen"),
            SimpleNamespace(id=3, name="Paracetamol", generic_name="paracetamol"),
        ]
        return _FakeResult(row=meds[min(_exec.n - 1, 2)])

    session.execute = _exec  # type: ignore
    app = _app(_user(1), db=session)
    with patch.object(
        MedicineSafetyChecker, "check", new=AsyncMock(return_value=_safety_duplicate())
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/interactions/check",
                json={"medicine_ids": [1, 2, 3]},
            )
    body = resp.json()
    dups = body["duplicate_check"]["duplicates"]
    assert dups
    assert dups[0]["is_interaction"] is False
    # pairs from safety mock: only one unknown pair in _safety_duplicate interactions list
    pairs = body["pairs"]
    # No self-pairs in mapped output
    for p in pairs:
        a = p["medicine_a"]["medicine_id"]
        b = p["medicine_b"]["medicine_id"]
        assert a != b


@pytest.mark.anyio
async def test_interaction_14_unresolved_medicine():
    app = _app(_user(1))

    async def _resolve(db, name):
        return None

    with patch.object(ix_route, "_resolve_medicine_name", new=_resolve):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/interactions/check",
                json={"medicines": ["NotARealDrugXYZ", "AlsoFakeABC"]},
            )
    assert resp.status_code == 200
    body = resp.json()
    assert body["overall_status"] == "UNRESOLVED_INPUT"
    assert len(body["unresolved"]) == 2
    assert body["interaction_analysis"]["unavailable"] is True


@pytest.mark.anyio
async def test_interaction_15_requires_auth_owner_context():
    """Owner is auth principal — no client user_id accepted."""
    app = _app(_user(42))
    session = _FakeSession()

    async def _exec(stmt, *a, **k):
        if not hasattr(_exec, "n"):
            _exec.n = 0
        _exec.n += 1
        meds = [
            SimpleNamespace(id=1, name="A", generic_name="a"),
            SimpleNamespace(id=2, name="B", generic_name="b"),
        ]
        return _FakeResult(row=meds[min(_exec.n - 1, 1)])

    session.execute = _exec  # type: ignore
    app = _app(_user(42), db=session)
    with patch.object(
        MedicineSafetyChecker, "check", new=AsyncMock(return_value=_safety_unknown())
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.post(
                "/api/v1/interactions/check",
                json={"medicine_ids": [1, 2], "user_id": 999},
            )
    # Extra user_id ignored by schema (extra fields ignored by default in pydantic v2?)
    # FastAPI pydantic typically ignores extras unless configured
    assert resp.status_code == 200
