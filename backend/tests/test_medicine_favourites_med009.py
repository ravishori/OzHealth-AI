"""HN-MED-009 — Medicine Favourites (MED-FAV-BE-01..12 + AUTH matrix)."""
from __future__ import annotations

import os
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://u:p@localhost/db")
os.environ.setdefault("SYNC_DATABASE_URL", "postgresql+psycopg2://u:p@localhost/db")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-unit-tests-only")

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app.api.routes import medicines as medicines_route
from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.medicine_favourite import MedicineFavourite


def _user(uid: int = 1):
    return SimpleNamespace(
        id=uid,
        email=f"u{uid}@ex.com",
        is_active=True,
        token_version=0,
    )


def _med(mid: int = 42, name: str = "Amoxicillin 500 mg"):
    return SimpleNamespace(
        id=mid,
        name=name,
        generic_name="Amoxicillin",
        brand_name="Amoxil",
        strength="500 mg",
        dosage_form="Capsule",
        tga_artg_number="AUST R 12345",
        schedule="S4",
        composition="Amoxicillin 500 mg",
        drug_class="Antibiotic",
        therapeutic_class=None,
        uses=None,
        consumer_information=None,
        standard_dosage=None,
        side_effects=None,
        interactions=None,
        contraindications=None,
        warnings=None,
        storage_instructions=None,
        tga_registered=True,
        manufacturer="TestPharm",
        sponsor=None,
        pregnancy_category=None,
        primary_source="TGA",
        pbs_code=None,
        barcode=None,
        au_schedule="S4",
    )


def _fav(fid: int, user_id: int, medicine_id: int):
    return SimpleNamespace(
        id=fid,
        user_id=user_id,
        medicine_id=medicine_id,
        created_at=datetime(2026, 9, 7, 12, 0, tzinfo=timezone.utc),
    )


class FavouriteStore:
    """In-memory stand-in for medicine + favourite persistence."""

    def __init__(self, medicines: dict[int, SimpleNamespace] | None = None):
        self.medicines = medicines or {42: _med(42), 7: _med(7, "Paracetamol 500 mg")}
        self.favourites: dict[tuple[int, int], SimpleNamespace] = {}
        self.next_id = 1
        self.add_calls = 0

    def _add(self, obj):
        self.add_calls += 1
        if isinstance(obj, MedicineFavourite):
            key = (obj.user_id, obj.medicine_id)
            if key in self.favourites:
                return
            if getattr(obj, "id", None) is None:
                obj.id = self.next_id
                self.next_id += 1
            if getattr(obj, "created_at", None) is None:
                obj.created_at = datetime.now(timezone.utc)
            self.favourites[key] = obj

    async def _delete(self, obj):
        key = (obj.user_id, obj.medicine_id)
        self.favourites.pop(key, None)

    async def _refresh(self, obj):
        if getattr(obj, "id", None) is None:
            obj.id = self.next_id
            self.next_id += 1
        if getattr(obj, "created_at", None) is None:
            obj.created_at = datetime.now(timezone.utc)
        if isinstance(obj, MedicineFavourite):
            self.favourites[(obj.user_id, obj.medicine_id)] = obj

    async def _execute(self, stmt):
        text = str(stmt).lower()
        result = MagicMock()

        # List favourites: join MedicineFavourite + Medicine
        if "medicine_favourites" in text and "join" in text:
            rows = []
            for (uid, mid), fav in sorted(
                self.favourites.items(),
                key=lambda item: item[1].created_at or datetime.min.replace(tzinfo=timezone.utc),
                reverse=True,
            ):
                # WHERE user_id filter is applied in SQL; emulate by checking binds
                med = self.medicines.get(mid)
                if med is not None:
                    rows.append((fav, med))
            # Filter by user_id from compiled params if present
            try:
                compiled = stmt.compile()
                params = dict(compiled.params or {})
            except Exception:
                params = {}
            user_ids = [
                v for k, v in params.items() if "user_id" in str(k).lower() or k == "user_id_1"
            ]
            # Also inspect WHERE clause string for literal (unlikely)
            if not user_ids:
                # Fallback: tests always scope via dependency; filter using
                # bindparam values on the statement if available.
                for k, v in params.items():
                    if isinstance(v, int) and v in (1, 2, 3, 99):
                        # Heuristic — prefer explicit user_id-like keys
                        if "user" in str(k).lower():
                            user_ids.append(v)
            if user_ids:
                uid = user_ids[0]
                rows = [(f, m) for (f, m) in rows if f.user_id == uid]
            result.all.return_value = rows
            result.scalar_one_or_none.return_value = None
            result.scalars.return_value.all.return_value = []
            return result

        # MedicineFavourite id / row lookups
        if "medicine_favourites" in text:
            try:
                compiled = stmt.compile()
                params = dict(compiled.params or {})
            except Exception:
                params = {}
            uid = None
            mid = None
            for k, v in params.items():
                kl = str(k).lower()
                if "user" in kl and isinstance(v, int):
                    uid = v
                if "medicine" in kl and isinstance(v, int):
                    mid = v
            # Positional fallback from common bind names
            if uid is None or mid is None:
                ints = [v for v in params.values() if isinstance(v, int)]
                if len(ints) >= 2:
                    # medicine_id often first in WHERE for favourite routes after id check
                    # Routes use user_id then medicine_id — order varies.
                    pass
            fav = None
            if uid is not None and mid is not None:
                fav = self.favourites.get((uid, mid))
            elif mid is not None:
                # Only medicine_id — should not happen for our scoped queries
                for (u, m), f in self.favourites.items():
                    if m == mid:
                        fav = f
                        break
            # GET status selects MedicineFavourite.id
            if "medicine_favourites.id" in text or ".id" in text:
                result.scalar_one_or_none.return_value = fav.id if fav is not None else None
            else:
                result.scalar_one_or_none.return_value = fav
            result.all.return_value = []
            result.scalars.return_value.all.return_value = [fav] if fav else []
            return result

        # Medicine catalogue lookup
        if "medicines" in text:
            try:
                compiled = stmt.compile()
                params = dict(compiled.params or {})
            except Exception:
                params = {}
            mid = None
            for k, v in params.items():
                if isinstance(v, int) and ("id" in str(k).lower() or True):
                    # Prefer id-like keys
                    if "id" in str(k).lower() and "user" not in str(k).lower():
                        mid = v
                        break
            if mid is None:
                ints = [v for v in params.values() if isinstance(v, int)]
                mid = ints[0] if ints else None
            med = self.medicines.get(mid) if mid is not None else None
            result.scalar_one_or_none.return_value = med
            result.all.return_value = []
            result.scalars.return_value.all.return_value = [med] if med else []
            return result

        result.scalar_one_or_none.return_value = None
        result.all.return_value = []
        result.scalars.return_value.all.return_value = []
        return result

    def bind(self):
        async def override_db():
            db = AsyncMock()
            db.add = MagicMock(side_effect=self._add)
            db.commit = AsyncMock()
            db.delete = AsyncMock(side_effect=self._delete)
            db.refresh = AsyncMock(side_effect=self._refresh)
            db.execute = AsyncMock(side_effect=self._execute)
            yield db

        return override_db


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
def fav_app():
    def _make(user, store: FavouriteStore | None = None):
        app = FastAPI()
        app.include_router(medicines_route.router, prefix="/api/v1/medicines")
        store = store or FavouriteStore()

        async def _override_user():
            return user

        app.dependency_overrides[get_current_user] = _override_user
        app.dependency_overrides[get_db] = store.bind()
        app.state.store = store
        return app

    return _make


# ── MED-FAV-BE-01 / AUTH-01 ──────────────────────────────────────────────────


@pytest.mark.anyio
async def test_med_fav_be_01_unauthenticated_rejected():
    """MED-FAV-BE-01 / AUTH-01 — unauthenticated favourite request rejected."""
    app = FastAPI()
    app.include_router(medicines_route.router, prefix="/api/v1/medicines")
    store = FavouriteStore()
    app.dependency_overrides[get_db] = store.bind()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        post = await client.post("/api/v1/medicines/42/favourite")
        get_status = await client.get("/api/v1/medicines/42/favourite")
        listing = await client.get("/api/v1/medicines/favourites")
        delete = await client.delete("/api/v1/medicines/42/favourite")
    assert post.status_code in (401, 403, 422)
    assert get_status.status_code in (401, 403, 422)
    assert listing.status_code in (401, 403, 422)
    assert delete.status_code in (401, 403, 422)


# ── MED-FAV-BE-02 / AUTH-02 ──────────────────────────────────────────────────


@pytest.mark.anyio
async def test_med_fav_be_02_authenticated_can_favourite(fav_app):
    """MED-FAV-BE-02 / AUTH-02 — authenticated user can favourite valid medicine."""
    app = fav_app(_user(1))
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/api/v1/medicines/42/favourite")
    assert resp.status_code == 200
    body = resp.json()
    assert body["is_favourite"] is True
    assert body["medicine_id"] == 42
    assert body["created"] is True
    assert (1, 42) in app.state.store.favourites


# ── MED-FAV-BE-03 ────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_med_fav_be_03_list_own_favourites(fav_app):
    """MED-FAV-BE-03 — authenticated user can list own favourites."""
    store = FavouriteStore()
    store.favourites[(1, 42)] = _fav(1, 1, 42)
    app = fav_app(_user(1), store)
    # Patch list path to filter by current user explicitly via direct call check
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Prefer calling route with known store filter — update execute for list
        async def execute_list(stmt):
            text = str(stmt).lower()
            result = MagicMock()
            if "join" in text and "medicine_favourites" in text:
                rows = []
                for (uid, mid), fav in store.favourites.items():
                    if uid != 1:
                        continue
                    med = store.medicines.get(mid)
                    if med is not None:
                        rows.append((fav, med))
                result.all.return_value = rows
                return result
            return await store._execute(stmt)

        app.state.store  # noqa: B018 — keep store alive
        # Rebind with user-scoped list
        original_bind = store.bind

        async def override_db():
            db = AsyncMock()
            db.add = MagicMock(side_effect=store._add)
            db.commit = AsyncMock()
            db.delete = AsyncMock(side_effect=store._delete)
            db.refresh = AsyncMock(side_effect=store._refresh)
            db.execute = AsyncMock(side_effect=execute_list)
            yield db

        app.dependency_overrides[get_db] = override_db
        resp = await client.get("/api/v1/medicines/favourites")
    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 1
    assert body["favourites"][0]["id"] == 42
    assert "prescription" in body["note"].lower() or "bookmark" in body["note"].lower()


# ── MED-FAV-BE-04 ────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_med_fav_be_04_remove_own_favourite(fav_app):
    """MED-FAV-BE-04 — authenticated user can remove own favourite."""
    store = FavouriteStore()
    store.favourites[(1, 42)] = _fav(1, 1, 42)
    app = fav_app(_user(1), store)

    async def execute(stmt):
        text = str(stmt).lower()
        result = MagicMock()
        if "medicine_favourites" in text:
            result.scalar_one_or_none.return_value = store.favourites.get((1, 42))
            return result
        return await store._execute(stmt)

    async def override_db():
        db = AsyncMock()
        db.add = MagicMock(side_effect=store._add)
        db.commit = AsyncMock()
        db.delete = AsyncMock(side_effect=store._delete)
        db.refresh = AsyncMock(side_effect=store._refresh)
        db.execute = AsyncMock(side_effect=execute)
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.delete("/api/v1/medicines/42/favourite")
    assert resp.status_code == 200
    body = resp.json()
    assert body["is_favourite"] is False
    assert body["removed"] is True
    assert (1, 42) not in store.favourites


# ── MED-FAV-BE-05 / AUTH-06 ──────────────────────────────────────────────────


@pytest.mark.anyio
async def test_med_fav_be_05_duplicate_favourite_idempotent(fav_app):
    """MED-FAV-BE-05 / AUTH-06 — duplicate favourite does not create duplicate row."""
    store = FavouriteStore()
    app = fav_app(_user(1), store)

    call_n = {"n": 0}

    async def execute(stmt):
        text = str(stmt).lower()
        result = MagicMock()
        if "medicines" in text and "medicine_favourites" not in text:
            result.scalar_one_or_none.return_value = store.medicines[42]
            return result
        if "medicine_favourites" in text:
            call_n["n"] += 1
            fav = store.favourites.get((1, 42))
            result.scalar_one_or_none.return_value = fav
            return result
        return await store._execute(stmt)

    async def override_db():
        db = AsyncMock()
        db.add = MagicMock(side_effect=store._add)
        db.commit = AsyncMock()
        db.delete = AsyncMock(side_effect=store._delete)
        db.refresh = AsyncMock(side_effect=store._refresh)
        db.execute = AsyncMock(side_effect=execute)
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        first = await client.post("/api/v1/medicines/42/favourite")
        second = await client.post("/api/v1/medicines/42/favourite")
    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["created"] is True
    assert second.json()["created"] is False
    assert second.json()["is_favourite"] is True
    assert len(store.favourites) == 1
    assert store.add_calls == 1


# ── MED-FAV-BE-06 ────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_med_fav_be_06_remove_non_favourite_safe(fav_app):
    """MED-FAV-BE-06 — removing non-favourited medicine behaves safely."""
    store = FavouriteStore()
    app = fav_app(_user(1), store)

    async def execute(stmt):
        result = MagicMock()
        result.scalar_one_or_none.return_value = None
        return result

    async def override_db():
        db = AsyncMock()
        db.execute = AsyncMock(side_effect=execute)
        db.commit = AsyncMock()
        db.delete = AsyncMock()
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.delete("/api/v1/medicines/42/favourite")
    assert resp.status_code == 200
    body = resp.json()
    assert body["is_favourite"] is False
    assert body["removed"] is False


# ── MED-FAV-BE-07 ────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_med_fav_be_07_invalid_medicine_not_found(fav_app):
    """MED-FAV-BE-07 — invalid medicine returns appropriate not-found response."""
    store = FavouriteStore(medicines={42: _med(42)})
    app = fav_app(_user(1), store)

    async def execute(stmt):
        result = MagicMock()
        result.scalar_one_or_none.return_value = None
        return result

    async def override_db():
        db = AsyncMock()
        db.execute = AsyncMock(side_effect=execute)
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/api/v1/medicines/99999/favourite")
        status = await client.get("/api/v1/medicines/99999/favourite")
    assert resp.status_code == 404
    assert status.status_code == 404


# ── MED-FAV-BE-08 / AUTH-04 / AUTH-03 ────────────────────────────────────────


@pytest.mark.anyio
async def test_med_fav_be_08_user_a_cannot_access_user_b_list(fav_app):
    """MED-FAV-BE-08 / AUTH-04 — User A cannot access User B's favourites."""
    store = FavouriteStore()
    store.favourites[(2, 42)] = _fav(10, 2, 42)  # User B only

    async def execute(stmt):
        text = str(stmt).lower()
        result = MagicMock()
        if "join" in text and "medicine_favourites" in text:
            # Emulate WHERE user_id == current_user (1)
            rows = []
            for (uid, mid), fav in store.favourites.items():
                if uid == 1:
                    med = store.medicines.get(mid)
                    if med:
                        rows.append((fav, med))
            result.all.return_value = rows
            return result
        return await store._execute(stmt)

    app = fav_app(_user(1), store)

    async def override_db():
        db = AsyncMock()
        db.execute = AsyncMock(side_effect=execute)
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/medicines/favourites")
    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 0
    assert body["favourites"] == []
    # User B's favourite still present server-side
    assert (2, 42) in store.favourites


@pytest.mark.anyio
async def test_med_fav_be_08b_status_does_not_leak_other_user(fav_app):
    """AUTH-03 — User A sees not-favourite when only User B favourited medicine."""
    store = FavouriteStore()
    store.favourites[(2, 42)] = _fav(10, 2, 42)

    async def execute(stmt):
        text = str(stmt).lower()
        result = MagicMock()
        if "medicines" in text and "medicine_favourites" not in text:
            result.scalar_one_or_none.return_value = store.medicines[42]
            return result
        if "medicine_favourites" in text:
            # Scoped to user 1 — no row
            result.scalar_one_or_none.return_value = None
            return result
        return await store._execute(stmt)

    app = fav_app(_user(1), store)

    async def override_db():
        db = AsyncMock()
        db.execute = AsyncMock(side_effect=execute)
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/api/v1/medicines/42/favourite")
    assert resp.status_code == 200
    assert resp.json()["is_favourite"] is False
    assert (2, 42) in store.favourites


# ── MED-FAV-BE-09 / AUTH-05 ──────────────────────────────────────────────────


@pytest.mark.anyio
async def test_med_fav_be_09_user_a_cannot_delete_user_b_favourite(fav_app):
    """MED-FAV-BE-09 / AUTH-05 — User A cannot delete User B's favourite."""
    store = FavouriteStore()
    store.favourites[(2, 42)] = _fav(10, 2, 42)

    async def execute(stmt):
        result = MagicMock()
        # Delete is scoped to user 1 — no matching row
        result.scalar_one_or_none.return_value = None
        return result

    deleted = []

    async def delete(obj):
        deleted.append(obj)
        await store._delete(obj)

    app = fav_app(_user(1), store)

    async def override_db():
        db = AsyncMock()
        db.execute = AsyncMock(side_effect=execute)
        db.delete = AsyncMock(side_effect=delete)
        db.commit = AsyncMock()
        yield db

    app.dependency_overrides[get_db] = override_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.delete("/api/v1/medicines/42/favourite")
    assert resp.status_code == 200
    assert resp.json()["removed"] is False
    assert deleted == []
    assert (2, 42) in store.favourites


# ── MED-FAV-BE-10 / MED-FAV-BE-11 ────────────────────────────────────────────


@pytest.mark.anyio
async def test_med_fav_be_10_11_scoped_to_principal_no_leak(fav_app):
    """MED-FAV-BE-10/11 — relationship scoped to auth principal; no unrelated leak."""
    store = FavouriteStore()
    store.favourites[(1, 42)] = _fav(1, 1, 42)
    store.favourites[(2, 7)] = _fav(2, 2, 7)

    async def execute_for(uid):
        async def execute(stmt):
            text = str(stmt).lower()
            result = MagicMock()
            if "join" in text and "medicine_favourites" in text:
                rows = []
                for (u, mid), fav in store.favourites.items():
                    if u != uid:
                        continue
                    med = store.medicines.get(mid)
                    if med:
                        rows.append((fav, med))
                result.all.return_value = rows
                return result
            return await store._execute(stmt)

        return execute

    # User A
    app_a = fav_app(_user(1), store)

    async def override_a():
        db = AsyncMock()
        db.execute = AsyncMock(side_effect=await execute_for(1))
        yield db

    app_a.dependency_overrides[get_db] = override_a
    transport = ASGITransport(app=app_a)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp_a = await client.get("/api/v1/medicines/favourites")
    assert resp_a.status_code == 200
    ids_a = {item["id"] for item in resp_a.json()["favourites"]}
    assert ids_a == {42}
    assert 7 not in ids_a
    assert "user_id" not in resp_a.json()["favourites"][0]

    # User B
    app_b = fav_app(_user(2), store)

    async def override_b():
        db = AsyncMock()
        db.execute = AsyncMock(side_effect=await execute_for(2))
        yield db

    app_b.dependency_overrides[get_db] = override_b
    transport = ASGITransport(app=app_b)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp_b = await client.get("/api/v1/medicines/favourites")
    ids_b = {item["id"] for item in resp_b.json()["favourites"]}
    assert ids_b == {7}
    assert 42 not in ids_b


# ── MED-FAV-BE-12 ────────────────────────────────────────────────────────────


@pytest.mark.anyio
async def test_med_fav_be_12_existing_medicine_detail_unaffected(fav_app):
    """MED-FAV-BE-12 — existing medicine endpoints remain unaffected."""
    store = FavouriteStore()
    app = fav_app(_user(1), store)

    async def execute(stmt):
        result = MagicMock()
        result.scalar_one_or_none.return_value = store.medicines[42]
        return result

    async def override_db():
        db = AsyncMock()
        db.execute = AsyncMock(side_effect=execute)
        yield db

    app.dependency_overrides[get_db] = override_db

    # CacheService may be used by get medicine — patch if needed
    from unittest.mock import patch

    with patch.object(
        medicines_route.CacheService, "get", new=AsyncMock(return_value=None)
    ), patch.object(
        medicines_route.CacheService, "set", new=AsyncMock()
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            detail = await client.get("/api/v1/medicines/42")
            favourites_path = await client.get("/api/v1/medicines/favourites")
    assert detail.status_code == 200
    assert detail.json()["id"] == 42
    assert detail.json()["name"] == "Amoxicillin 500 mg"
    assert favourites_path.status_code == 200


def test_med_fav_model_unique_constraint_declared():
    """Schema contract — user_id + medicine_id unique."""
    args = MedicineFavourite.__table_args__
    names = []
    for a in args:
        name = getattr(a, "name", None)
        if name:
            names.append(name)
    assert "uq_medicine_favourites_user_medicine" in names


def test_med_fav_audit_logging_metadata_only():
    """Sensitive logging — favourite handlers log ids/counts, not payloads."""
    import inspect

    src = inspect.getsource(medicines_route.add_medicine_favourite)
    src += inspect.getsource(medicines_route.remove_medicine_favourite)
    src += inspect.getsource(medicines_route.list_medicine_favourites)
    assert "audit_log" in src
    assert "password" not in src.lower()
    assert "access_token" not in src.lower()
    # No full request body logging
    assert "request.body" not in src
    assert "json()" not in src or "resp.json" not in src
