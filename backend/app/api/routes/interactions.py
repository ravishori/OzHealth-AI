"""
Drug Interaction Check — HN-FUTURE-004

POST /api/v1/interactions/check

Source-of-truth:
  1) structured public.interactions rows (preferred)
  2) medicines.interactions free-text mention (KNOWN_FROM_TEXT)
  3) otherwise explicit UNKNOWN / unavailable

AI is NOT an authoritative interaction source.
Empty interaction data must NEVER be reported as "safe" or "no interaction".
Duplicates are a separate catalogue-identity signal (HN-MED-007), not interactions.
"""
from __future__ import annotations

import logging
import re
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.log_decorator import LoggedAPIRoute
from app.models.medicine import Medicine
from app.models.user import User
from app.services.medicine_safety_service import (
    UNAVAILABLE_INTERACTION,
    MedicineSafetyChecker,
)

router = APIRouter(route_class=LoggedAPIRoute)
logger = logging.getLogger(__name__)

_UNAVAILABLE_PAIR_MESSAGE = (
    "Interaction information is unavailable for this medicine pair. "
    "This does not mean the medicines are confirmed safe together. "
    "Consult a pharmacist or doctor for medication-safety advice when appropriate."
)

_DISCLAIMER = (
    "Interaction checks use HealthNest catalogue/database records when available. "
    "Unavailable information does not mean medicines are safe together. "
    "This is not a substitute for a pharmacist or doctor. "
    "Do not start, stop, or change medicines based on this screen alone. "
    "In an emergency in Australia, call 000."
)


class InteractionCheckRequest(BaseModel):
    """Prefer catalogue medicine_ids; free-text names are resolved when possible."""

    medicine_ids: list[int] = Field(default_factory=list, max_length=20)
    medicines: list[str] = Field(
        default_factory=list,
        max_length=20,
        description="Legacy free-text names — resolved against the catalogue",
    )
    include_duplicate_check: bool = True

    @model_validator(mode="after")
    def _require_inputs(self) -> "InteractionCheckRequest":
        ids = [i for i in self.medicine_ids if isinstance(i, int) and i > 0]
        names = [m.strip() for m in self.medicines if m and str(m).strip()]
        object.__setattr__(self, "medicine_ids", ids)
        object.__setattr__(self, "medicines", names)
        if len(ids) + len(names) < 2:
            raise ValueError(
                "Provide at least 2 medicines (catalogue IDs and/or resolvable names)"
            )
        return self


def _norm_name(s: str) -> str:
    s = s.lower().strip()
    s = re.sub(r"[®™©]", "", s)
    s = re.sub(r"[^a-z0-9\s/+.-]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


async def _resolve_medicine_name(
    db: AsyncSession, name: str
) -> Optional[Medicine]:
    """Resolve free-text to a catalogue medicine. Ambiguous → None (unresolved)."""
    raw = (name or "").strip()
    if not raw:
        return None
    # Exact (case-insensitive) name or generic_name
    result = await db.execute(
        select(Medicine).where(
            or_(
                func.lower(Medicine.name) == raw.lower(),
                func.lower(func.coalesce(Medicine.generic_name, "")) == raw.lower(),
            )
        ).limit(5)
    )
    rows = list(result.scalars().all())
    if len(rows) == 1:
        return rows[0]
    if len(rows) > 1:
        # Prefer exact trade-name match
        exact = [m for m in rows if (m.name or "").lower() == raw.lower()]
        if len(exact) == 1:
            return exact[0]
        return None  # ambiguous

    # Normalized containment fallback — only if uniquely matches
    needle = _norm_name(raw)
    if len(needle) < 3:
        return None
    result = await db.execute(
        select(Medicine)
        .where(
            or_(
                func.lower(Medicine.name).like(f"%{needle}%"),
                func.lower(func.coalesce(Medicine.generic_name, "")).like(
                    f"%{needle}%"
                ),
            )
        )
        .limit(10)
    )
    candidates = list(result.scalars().all())
    exact_norm = [
        m
        for m in candidates
        if _norm_name(m.name or "") == needle
        or _norm_name(m.generic_name or "") == needle
    ]
    if len(exact_norm) == 1:
        return exact_norm[0]
    return None


def _map_pair(row: dict[str, Any]) -> dict[str, Any]:
    """Normalize MedicineSafetyChecker interaction row for the checker API."""
    status = row.get("status")
    evidence = row.get("evidence") or {}
    source_name = evidence.get("source_name")
    if status == "KNOWN":
        source_type = "source_backed"
        verified = True
        description = row.get("description") or UNAVAILABLE_INTERACTION
        unavailable = False
    elif status == "KNOWN_FROM_TEXT":
        source_type = "source_backed_incomplete"
        verified = False
        description = row.get("description") or UNAVAILABLE_INTERACTION
        unavailable = False
    else:
        source_type = "unavailable"
        verified = False
        description = _UNAVAILABLE_PAIR_MESSAGE
        unavailable = True

    return {
        "medicine_a": row.get("medicine_a"),
        "medicine_b": row.get("medicine_b"),
        # Compat fields used by Flutter cards
        "drug_a": (row.get("medicine_a") or {}).get("name"),
        "drug_b": (row.get("medicine_b") or {}).get("name"),
        "severity": None if unavailable else row.get("severity"),
        "description": description,
        "recommendation": (
            None
            if unavailable
            else (
                "Discuss this database-recorded interaction with a pharmacist "
                "or doctor before changing medicines."
            )
        ),
        "recommended_action": (
            None
            if unavailable
            else (
                "Discuss this database-recorded interaction with a pharmacist "
                "or doctor before changing medicines."
            )
        ),
        "clinical_significance": None if unavailable else row.get("severity"),
        "source_type": source_type,
        "source_name": source_name if source_type.startswith("source_backed") else None,
        "source_reference": evidence.get("interaction_id"),
        "source": row.get("source"),
        "status": status,
        "verified": verified,
        "unavailable": unavailable,
        "note": row.get("note"),
        "evidence": evidence if status == "KNOWN" else None,
    }


def _map_duplicate(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "medicine_a": (row.get("medicine_a") or {}).get("name"),
        "medicine_b": (row.get("medicine_b") or {}).get("name"),
        "medicine_a_id": (row.get("medicine_a") or {}).get("medicine_id"),
        "medicine_b_id": (row.get("medicine_b") or {}).get("medicine_id"),
        "reason": row.get("reason"),
        "risk": row.get("reason"),  # Flutter legacy field — catalogue identity, not DDI
        "status": row.get("status"),
        "source": row.get("source"),
        "is_interaction": False,
        "warning_type": "duplicate_medicine",
    }


@router.post("/check")
async def check_interactions(
    req: InteractionCheckRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Source-grounded interaction check.

    Prefer medicine_ids. Free-text names are resolved against the catalogue;
    unresolved identities do not receive invented interaction claims.
    """
    unresolved: list[dict[str, Any]] = []
    resolved_ids: list[int] = []
    seen: set[int] = set()

    for mid in req.medicine_ids:
        if mid in seen:
            continue
        result = await db.execute(select(Medicine).where(Medicine.id == mid))
        med = result.scalar_one_or_none()
        if not med:
            unresolved.append(
                {
                    "input": mid,
                    "kind": "medicine_id",
                    "reason": "Medicine not found in catalogue",
                }
            )
            continue
        seen.add(mid)
        resolved_ids.append(mid)

    for name in req.medicines:
        med = await _resolve_medicine_name(db, name)
        if med is None:
            unresolved.append(
                {
                    "input": name,
                    "kind": "medicine_name",
                    "reason": "Medicine identity could not be resolved in the catalogue",
                }
            )
            continue
        if med.id in seen:
            continue
        seen.add(med.id)
        resolved_ids.append(med.id)

    logger.info(
        "interaction_check user_id=%s resolved=%d unresolved=%d",
        current_user.id,
        len(resolved_ids),
        len(unresolved),
    )

    if len(resolved_ids) < 2:
        return {
            "medicines_checked": resolved_ids,
            "resolved_medicines": [],
            "unresolved": unresolved,
            "overall_status": "UNRESOLVED_INPUT",
            "authoritative": True,
            "ai_used": False,
            "disclaimer": _DISCLAIMER,
            "pairs": [],
            "interaction_analysis": {
                "risk_level": "unavailable",
                "overall_summary": (
                    "Not enough catalogue-resolved medicines to run an "
                    "authoritative interaction check. "
                    "Unresolved names are not treated as verified medicines."
                ),
                "interactions": [],
                "recommendations": [
                    "Select medicines from the HealthNest catalogue and try again.",
                    "Consult a pharmacist or doctor for medication-safety advice.",
                ],
                "source_backed": False,
                "verified": False,
                "unavailable": True,
                "consult_doctor": True,
            },
            "duplicate_check": {
                "safe": True,
                "duplicates": [],
                "summary": "Duplicate check skipped — insufficient resolved medicines.",
                "is_interaction": False,
            },
        }

    try:
        checker = MedicineSafetyChecker(db)
        safety = await checker.check(resolved_ids, allergies=[])
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    pairs = [_map_pair(p) for p in (safety.get("interactions") or [])]
    known_pairs = [p for p in pairs if p["status"] in ("KNOWN", "KNOWN_FROM_TEXT")]
    unknown_pairs = [p for p in pairs if p["status"] == "UNKNOWN"]

    duplicates_raw = safety.get("duplicates") or [] if req.include_duplicate_check else []
    duplicates = [_map_duplicate(d) for d in duplicates_raw]

    if known_pairs:
        risk_level = "known"
        summary = (
            f"{len(known_pairs)} source-backed interaction record(s) found "
            f"for {len(pairs)} unique medicine pair(s). "
            f"{len(unknown_pairs)} pair(s) have no authoritative record."
        )
    elif unknown_pairs:
        risk_level = "unavailable"
        summary = (
            "Interaction information is unavailable for the selected medicine "
            "pair(s). This does not mean the medicines are confirmed safe together."
        )
    else:
        risk_level = "unavailable"
        summary = _UNAVAILABLE_PAIR_MESSAGE

    # Never claim "safe" / "no interaction" for empty DB coverage.
    recommendations = [
        "Unavailable interaction information must not be treated as confirmation of safety.",
        "Consult a pharmacist or doctor before changing medicines.",
    ]
    if known_pairs:
        recommendations.insert(
            0,
            "Review the source-backed interaction details below with a health professional.",
        )

    return {
        "medicines_checked": [
            {"medicine_id": m["medicine_id"], "name": m["name"]}
            for m in (safety.get("medicines") or [])
        ],
        "resolved_medicines": safety.get("medicines") or [],
        "unresolved": unresolved,
        "overall_status": safety.get("overall_status"),
        "authoritative": True,
        "ai_used": False,
        "disclaimer": _DISCLAIMER,
        "data_coverage": safety.get("data_coverage"),
        "pairs": pairs,
        "interaction_analysis": {
            "risk_level": risk_level,
            "overall_summary": summary,
            "interactions": pairs,
            "recommendations": recommendations,
            "source_backed": bool(known_pairs),
            "verified": any(p.get("verified") for p in known_pairs),
            "unavailable": not bool(known_pairs),
            "consult_doctor": True,
            "unknown_pair_count": len(unknown_pairs),
            "known_pair_count": len(known_pairs),
        },
        "duplicate_check": {
            "safe": len(duplicates) == 0,
            "duplicates": duplicates,
            "summary": (
                f"{len(duplicates)} catalogue duplicate warning(s)."
                if duplicates
                else "No catalogue-identity duplicates detected among resolved medicines."
            ),
            "is_interaction": False,
            "warning_type": "duplicate_medicine",
        },
        "safety": safety.get("safety"),
    }
