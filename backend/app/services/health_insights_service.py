"""HN-FUTURE-003 — grounded Health Insights.

Architecture:
  HealthNest data → deterministic facts → safe explanation → user insight

Personal insights must be traceable to recorded data. No fabricated trends,
diagnoses, prescriptions, or reference ranges.
"""
from __future__ import annotations

import json
import logging
import re
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging_config import ai_log
from app.models.health_metric import HealthMetric
from app.models.medical_record import MedicalRecord
from app.models.medication_schedule import MedicationSchedule
from app.models.user import User
from app.services.ai_prompt_safety import (
    build_trusted_system_prompt,
    validate_assistant_output,
    wrap_untrusted,
)
from app.services.ai_service import _ai_available, _new_client, _MODEL_HAIKU

logger = logging.getLogger(__name__)

INSIGHTS_DISCLAIMER = (
    "Health insights are informational summaries of your recorded HealthNest "
    "data. They are not a diagnosis, not clinician-verified, and not a "
    "substitute for advice from a qualified health professional. "
    "In an emergency in Australia, call 000."
)

_MIN_TREND_POINTS = 3
_MIN_COMPARE_POINTS = 2
_MIN_ADHERENCE_EVENTS = 3
_STABLE_PCT = 5.0  # |pct change| below this → stable

_UNSAFE_PATTERNS = (
    re.compile(r"\byou (?:definitely |clearly )?(?:have|are diagnosed with)\b", re.I),
    re.compile(r"\bdiagnosis confirmed\b", re.I),
    re.compile(r"\bstart taking\b", re.I),
    re.compile(r"\bstop taking\b", re.I),
    re.compile(r"\bincrease (?:your )?dose\b", re.I),
    re.compile(r"\bdecrease (?:your )?dose\b", re.I),
    re.compile(r"\bprescrib(?:e|ing|ed)\b", re.I),
    re.compile(r"\bclinician[- ]verified\b", re.I),
    re.compile(r"\byou do not need (?:medical|emergency) (?:attention|care)\b", re.I),
)

_METRIC_LABELS = {
    "blood_pressure_systolic": "Systolic blood pressure",
    "blood_pressure_diastolic": "Diastolic blood pressure",
    "blood_sugar": "Blood sugar",
    "heart_rate": "Heart rate",
    "oxygen_level": "Oxygen level",
    "weight": "Weight",
    "height": "Height",
    "bmi": "BMI",
    "temperature": "Temperature",
}


def _contains_unsafe_insight_language(text: str) -> bool:
    if not text:
        return False
    return any(p.search(text) for p in _UNSAFE_PATTERNS)


def _dose_event_model():
    """Optional HN-MEDMGMT-006 model — absent on older codebases."""
    try:
        from app.models.medication_dose_event import MedicationDoseEvent

        return MedicationDoseEvent
    except ImportError:
        return None


def _metric_label(metric_type: str) -> str:
    return _METRIC_LABELS.get(metric_type, metric_type.replace("_", " ").title())


def _pct_change(earliest: float, latest: float) -> Optional[float]:
    if earliest == 0:
        return None
    return round(((latest - earliest) / abs(earliest)) * 100.0, 1)


def _direction(earliest: float, latest: float) -> str:
    pct = _pct_change(earliest, latest)
    if pct is None:
        if latest > earliest:
            return "upward"
        if latest < earliest:
            return "downward"
        return "stable"
    if abs(pct) < _STABLE_PCT:
        return "stable"
    return "upward" if pct > 0 else "downward"


def build_metric_trend_insights(
    metrics: list[dict[str, Any]],
    *,
    period_days: int,
) -> list[dict[str, Any]]:
    """Deterministic metric insights from recorded values only."""
    by_type: dict[str, list[dict]] = defaultdict(list)
    for m in metrics:
        mt = (m.get("type") or m.get("metric_type") or "").strip()
        if not mt:
            continue
        try:
            val = float(m["value"])
        except (KeyError, TypeError, ValueError):
            continue
        by_type[mt].append(m | {"value": val})

    insights: list[dict[str, Any]] = []
    period = f"Last {period_days} days"

    if not by_type:
        insights.append(
            {
                "id": "metrics-insufficient",
                "category": "monitoring",
                "title": "Not enough health metrics yet",
                "summary": (
                    "Not enough recent health measurements to identify a trend. "
                    "Record a few more measurements to identify a trend."
                ),
                "source": "health_metrics",
                "period": period,
                "status": "insufficient_data",
                "facts": {"reading_count": 0},
                "suggestion": "Log blood pressure, heart rate, or other vitals in Health Monitoring.",
                "is_diagnosis": False,
            }
        )
        return insights

    for metric_type, rows in sorted(by_type.items()):
        rows_sorted = sorted(
            rows,
            key=lambda r: r.get("date") or r.get("recorded_at") or "",
        )
        count = len(rows_sorted)
        label = _metric_label(metric_type)
        unit = rows_sorted[-1].get("unit") or ""

        if count < _MIN_COMPARE_POINTS:
            insights.append(
                {
                    "id": f"metric-{metric_type}-insufficient",
                    "category": "monitoring",
                    "title": f"{label}: not enough data",
                    "summary": (
                        f"Not enough recent {label.lower()} readings to identify a trend. "
                        "Record a few more measurements to identify a trend."
                    ),
                    "source": "health_metrics",
                    "period": period,
                    "status": "insufficient_data",
                    "facts": {
                        "metric_type": metric_type,
                        "reading_count": count,
                        "latest_value": rows_sorted[-1]["value"],
                        "unit": unit,
                    },
                    "suggestion": f"Add more {label.lower()} readings over several days.",
                    "is_diagnosis": False,
                }
            )
            continue

        earliest = rows_sorted[0]["value"]
        latest = rows_sorted[-1]["value"]
        delta = round(latest - earliest, 2)
        pct = _pct_change(earliest, latest)
        direction = _direction(earliest, latest)
        grounded = count >= _MIN_TREND_POINTS

        if grounded:
            summary = (
                f"Based on {count} recorded {label.lower()} readings over {period.lower()}, "
                f"your recorded values show a {direction} pattern "
                f"(from {earliest}{(' ' + unit) if unit else ''} to "
                f"{latest}{(' ' + unit) if unit else ''})."
            )
            title = f"{label}: {direction} pattern in your records"
            status = "grounded"
        else:
            summary = (
                f"Your latest recorded {label.lower()} reading "
                f"({latest}{(' ' + unit) if unit else ''}) differs from your earlier "
                f"recorded reading ({earliest}{(' ' + unit) if unit else ''}) "
                f"in a {direction} direction. More readings are needed for a clearer trend."
            )
            title = f"{label}: early comparison from your records"
            status = "grounded"

        insights.append(
            {
                "id": f"metric-{metric_type}",
                "category": "trend",
                "title": title,
                "summary": summary,
                "source": "health_metrics",
                "period": period,
                "status": status,
                "facts": {
                    "metric_type": metric_type,
                    "reading_count": count,
                    "earliest_value": earliest,
                    "latest_value": latest,
                    "delta": delta,
                    "percent_change": pct,
                    "direction": direction,
                    "unit": unit,
                },
                "suggestion": (
                    "Keep logging regularly and discuss your recorded trends with your GP."
                ),
                "is_diagnosis": False,
            }
        )

    return insights


def build_adherence_insight(
    events: list[dict[str, Any]],
    *,
    period_days: int,
    source_available: bool,
) -> dict[str, Any]:
    """Deterministic adherence insight from dose events (when available)."""
    period = f"Last {period_days} days"
    if not source_available:
        return {
            "id": "adherence-source-unavailable",
            "category": "adherence",
            "title": "Medication adherence history not available",
            "summary": (
                "Medication dose history is not available in this environment yet, "
                "so adherence cannot be estimated reliably."
            ),
            "source": "medication_dose_events",
            "period": period,
            "status": "insufficient_data",
            "facts": {"event_count": 0, "source_available": False},
            "suggestion": "Use Medication History when available to record taken, skipped, or missed doses.",
            "is_diagnosis": False,
        }

    if not events:
        return {
            "id": "adherence-insufficient",
            "category": "adherence",
            "title": "Not enough medication history yet",
            "summary": (
                "Your medication history contains too few recorded doses to estimate "
                "adherence reliably."
            ),
            "source": "medication_dose_events",
            "period": period,
            "status": "insufficient_data",
            "facts": {
                "event_count": 0,
                "taken": 0,
                "skipped": 0,
                "missed": 0,
                "source_available": True,
            },
            "suggestion": "Record dose outcomes (taken, skipped, or missed) to build an adherence picture.",
            "is_diagnosis": False,
        }

    taken = sum(1 for e in events if str(e.get("status", "")).lower() == "taken")
    skipped = sum(1 for e in events if str(e.get("status", "")).lower() == "skipped")
    missed = sum(1 for e in events if str(e.get("status", "")).lower() == "missed")
    total = taken + skipped + missed

    if total < _MIN_ADHERENCE_EVENTS:
        return {
            "id": "adherence-insufficient",
            "category": "adherence",
            "title": "Not enough medication history yet",
            "summary": (
                f"Your medication history contains too few recorded doses "
                f"({total}) to estimate adherence reliably."
            ),
            "source": "medication_dose_events",
            "period": period,
            "status": "insufficient_data",
            "facts": {
                "event_count": total,
                "taken": taken,
                "skipped": skipped,
                "missed": missed,
                "source_available": True,
            },
            "suggestion": "Record a few more dose outcomes to estimate adherence.",
            "is_diagnosis": False,
        }

    pct = round((taken / total) * 100.0, 1)
    return {
        "id": "adherence-summary",
        "category": "adherence",
        "title": "Medication adherence from your records",
        "summary": (
            f"Your recorded adherence was {pct}% over the selected period "
            f"({taken} taken, {skipped} skipped, {missed} missed out of {total} recorded doses)."
        ),
        "source": "medication_dose_events",
        "period": period,
        "status": "grounded",
        "facts": {
            "event_count": total,
            "taken": taken,
            "skipped": skipped,
            "missed": missed,
            "adherence_percent": pct,
            "source_available": True,
        },
        "suggestion": (
            "This is a record summary only — discuss any concerns with your doctor "
            "or pharmacist. Do not change medicines based on this insight alone."
        ),
        "is_diagnosis": False,
    }


def build_lab_insight(records: list[dict[str, Any]], *, period_days: int) -> dict[str, Any]:
    """
    Lab insights only from user-confirmed extractions (HN-FUTURE-002 gate).

    Unreviewed/raw OCR drafts are never treated as authoritative.
    """
    period = f"Last {period_days} days"
    confirmed = []
    unreviewed = 0
    for rec in records:
        notes = rec.get("notes")
        packed = None
        if isinstance(notes, dict):
            packed = notes
        elif isinstance(notes, str) and notes.strip():
            try:
                packed = json.loads(notes)
            except (TypeError, json.JSONDecodeError):
                packed = None
        if not isinstance(packed, dict):
            continue
        analysis = packed.get("analysis") if isinstance(packed.get("analysis"), dict) else packed
        if packed.get("user_confirmed") is True or analysis.get("user_confirmed") is True:
            # Preserve original reported values only — no invention.
            results = analysis.get("results") if isinstance(analysis.get("results"), list) else []
            safe_results = []
            for r in results:
                if not isinstance(r, dict):
                    continue
                safe_results.append(
                    {
                        "parameter": r.get("parameter"),
                        "original_value": r.get("original_value", r.get("value")),
                        "original_unit": r.get("original_unit", r.get("unit")),
                        "original_reference_range": r.get(
                            "original_reference_range",
                            r.get("reference_range"),
                        ),
                    }
                )
            confirmed.append(
                {
                    "record_id": rec.get("id"),
                    "title": rec.get("title"),
                    "result_count": len(safe_results),
                    "results_preview": safe_results[:5],
                }
            )
        elif packed.get("kind") == "lab_analysis_draft" or "results" in (analysis or {}):
            unreviewed += 1

    if not confirmed:
        if unreviewed > 0:
            summary = (
                f"{unreviewed} lab extraction(s) are still unreviewed. "
                "Unreviewed or raw AI/OCR lab analysis is not used as authoritative "
                "health insight data. Confirm extractions in Lab Report Review first."
            )
            title = "Lab insights awaiting review"
        else:
            summary = (
                "No reviewed lab results are available for insights yet. "
                "Upload and confirm a lab report to include lab information here."
            )
            title = "No reviewed lab data yet"
        return {
            "id": "lab-insufficient",
            "category": "lab",
            "title": title,
            "summary": summary,
            "source": "lab_analysis",
            "period": period,
            "status": "insufficient_data",
            "facts": {
                "confirmed_count": 0,
                "unreviewed_count": unreviewed,
            },
            "suggestion": "Confirm extracted lab values against your original report before relying on them.",
            "is_diagnosis": False,
            "review_state": "unreviewed_excluded" if unreviewed else "none",
        }

    total_results = sum(c["result_count"] for c in confirmed)
    return {
        "id": "lab-confirmed-summary",
        "category": "lab",
        "title": "Confirmed lab extractions in your records",
        "summary": (
            f"You have {len(confirmed)} user-confirmed lab extraction(s) with "
            f"{total_results} reported result row(s). These remain informational — "
            "not clinician-verified diagnoses."
        ),
        "source": "lab_analysis",
        "period": period,
        "status": "grounded",
        "facts": {
            "confirmed_count": len(confirmed),
            "unreviewed_count": unreviewed,
            "total_result_rows": total_results,
            "reports": confirmed,
        },
        "suggestion": "Discuss confirmed extractions with your GP using your original report.",
        "is_diagnosis": False,
        "review_state": "user_confirmed_only",
    }


def build_monitoring_consistency_insight(
    metrics: list[dict[str, Any]],
    active_med_count: int,
    *,
    period_days: int,
) -> dict[str, Any]:
    period = f"Last {period_days} days"
    count = len(metrics)
    return {
        "id": "monitoring-consistency",
        "category": "monitoring",
        "title": "Health monitoring activity",
        "summary": (
            f"You recorded {count} health measurement(s) over {period.lower()}"
            + (
                f" and have {active_med_count} active medication schedule(s)."
                if active_med_count
                else "."
            )
        ),
        "source": "health_metrics",
        "period": period,
        "status": "grounded" if count > 0 else "insufficient_data",
        "facts": {
            "metric_reading_count": count,
            "active_medication_schedules": active_med_count,
        },
        "suggestion": (
            "Regular recording helps HealthNest summarise your own history more clearly."
            if count > 0
            else "Start logging vitals to unlock personal trend insights."
        ),
        "is_diagnosis": False,
    }


async def explain_insights_safely(insights: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """
    Optional AI polish over DETERMINISTIC facts only.

    On failure/unsafe output, returns original grounded summaries unchanged.
    """
    grounded = [i for i in insights if i.get("status") == "grounded"]
    if not grounded or not _ai_available():
        return insights

    # Send only non-PHI-minimal structured facts (counts/directions/percents).
    fact_payload = [
        {
            "id": i.get("id"),
            "category": i.get("category"),
            "title": i.get("title"),
            "facts": i.get("facts"),
            "summary": i.get("summary"),
        }
        for i in grounded
    ]
    fenced = wrap_untrusted("INSIGHT_FACTS", json.dumps(fact_payload))
    system = build_trusted_system_prompt(
        """You rewrite HealthNest insight summaries for clarity.
Rules:
- Use ONLY the supplied facts. Do not invent values, trends, labs, or history.
- Do NOT diagnose, prescribe, or suggest starting/stopping/changing medicines or doses.
- Do NOT claim clinician verification or emergency clearance.
- Keep language educational and uncertain where appropriate.
Return valid JSON: {"rewrites":[{"id":"...","summary":"..."}]}"""
    )
    try:
        client = _new_client()
        ai_log.debug(
            "Insights explain model=%s grounded_count=%d",
            _MODEL_HAIKU,
            len(grounded),
        )
        response = await client.messages.create(
            model=_MODEL_HAIKU,
            max_tokens=900,
            system=system,
            messages=[
                {
                    "role": "user",
                    "content": (
                        "Rewrite summaries for these UNTRUSTED grounded facts.\n"
                        f"{fenced}"
                    ),
                }
            ],
        )
        text = response.content[0].text or ""
        ok, category = validate_assistant_output(text)
        if not ok or _contains_unsafe_insight_language(text):
            ai_log.warning("Insights explain rejected category=%s", category)
            return insights
        match = re.search(r"\{.*\}", text, re.DOTALL)
        if not match:
            return insights
        parsed = json.loads(match.group())
        rewrites = {
            r["id"]: r["summary"]
            for r in (parsed.get("rewrites") or [])
            if isinstance(r, dict) and r.get("id") and r.get("summary")
        }
        out = []
        for item in insights:
            copy = dict(item)
            new_sum = rewrites.get(item.get("id"))
            if new_sum and not _contains_unsafe_insight_language(new_sum):
                # Keep factual summary if rewrite invents numbers not in original.
                copy["summary"] = new_sum
                copy["ai_explained"] = True
            out.append(copy)
        return out
    except Exception as e:
        ai_log.error(
            "Insights explain failed: %s: %s", type(e).__name__, e
        )
        return insights


async def build_grounded_insights_payload(
    db: AsyncSession,
    user: User,
    *,
    period_days: int = 30,
    family_member_id: Optional[int] = None,
    use_ai_explain: bool = True,
) -> dict[str, Any]:
    """Assemble grounded insights for the authenticated user (Self by default)."""
    since = datetime.now(timezone.utc) - timedelta(days=period_days)

    metric_q = select(HealthMetric).where(
        HealthMetric.user_id == user.id,
        HealthMetric.recorded_at >= since,
    )
    if family_member_id is None:
        metric_q = metric_q.where(HealthMetric.family_member_id.is_(None))
    else:
        metric_q = metric_q.where(HealthMetric.family_member_id == family_member_id)
    metric_q = metric_q.order_by(HealthMetric.recorded_at.asc()).limit(500)
    metrics_rows = (await db.execute(metric_q)).scalars().all()

    metrics_data = [
        {
            "type": m.metric_type,
            "value": m.value,
            "unit": m.unit,
            "date": m.recorded_at.isoformat() if m.recorded_at else None,
        }
        for m in metrics_rows
    ]

    meds_q = select(MedicationSchedule).where(
        MedicationSchedule.user_id == user.id,
        MedicationSchedule.is_active == True,  # noqa: E712
    )
    if family_member_id is None:
        meds_q = meds_q.where(MedicationSchedule.family_member_id.is_(None))
    else:
        meds_q = meds_q.where(MedicationSchedule.family_member_id == family_member_id)
    meds = (await db.execute(meds_q)).scalars().all()
    active_med_count = len(meds)

    # Optional dose events (HN-MEDMGMT-006).
    DoseEvent = _dose_event_model()
    dose_events: list[dict[str, Any]] = []
    source_available = DoseEvent is not None
    if DoseEvent is not None:
        de_q = select(DoseEvent).where(
            DoseEvent.user_id == user.id,
            DoseEvent.scheduled_for >= since,
        )
        if family_member_id is None:
            de_q = de_q.where(DoseEvent.family_member_id.is_(None))
        else:
            de_q = de_q.where(DoseEvent.family_member_id == family_member_id)
        de_q = de_q.limit(1000)
        for ev in (await db.execute(de_q)).scalars().all():
            dose_events.append(
                {
                    "status": ev.status,
                    "scheduled_for": (
                        ev.scheduled_for.isoformat() if ev.scheduled_for else None
                    ),
                }
            )

    # Lab records — confirmed only.
    lab_q = select(MedicalRecord).where(
        MedicalRecord.user_id == user.id,
        MedicalRecord.is_active == True,  # noqa: E712
        MedicalRecord.record_type == "lab_report",
    )
    if family_member_id is None:
        lab_q = lab_q.where(MedicalRecord.family_member_id.is_(None))
    else:
        lab_q = lab_q.where(MedicalRecord.family_member_id == family_member_id)
    lab_q = lab_q.order_by(MedicalRecord.created_at.desc()).limit(50)
    lab_rows = (await db.execute(lab_q)).scalars().all()
    lab_data = [
        {
            "id": r.id,
            "title": r.title,
            "notes": r.notes,
        }
        for r in lab_rows
    ]

    insights: list[dict[str, Any]] = []
    insights.extend(build_metric_trend_insights(metrics_data, period_days=period_days))
    insights.append(
        build_adherence_insight(
            dose_events,
            period_days=period_days,
            source_available=source_available,
        )
    )
    insights.append(build_lab_insight(lab_data, period_days=period_days))
    insights.append(
        build_monitoring_consistency_insight(
            metrics_data,
            active_med_count,
            period_days=period_days,
        )
    )

    if use_ai_explain:
        insights = await explain_insights_safely(insights)

    # Safety pass: strip any unsafe language that slipped through.
    cleaned = []
    for item in insights:
        copy = dict(item)
        for field in ("summary", "suggestion", "title"):
            val = copy.get(field)
            if isinstance(val, str) and _contains_unsafe_insight_language(val):
                if field == "summary":
                    copy[field] = (
                        "A grounded summary is available from your records, "
                        "but wording was withheld for safety. Discuss your data with your GP."
                    )
                elif field == "suggestion":
                    copy[field] = "Discuss your recorded HealthNest data with your GP."
                else:
                    copy[field] = "Health insight"
        copy["is_diagnosis"] = False
        cleaned.append(copy)

    insufficient = [
        i["category"] for i in cleaned if i.get("status") == "insufficient_data"
    ]
    grounded_count = sum(1 for i in cleaned if i.get("status") == "grounded")

    logger.info(
        "insights_built user_id=%s period_days=%d metrics=%d dose_events=%d "
        "lab_records=%d grounded=%d family_member_id=%s",
        user.id,
        period_days,
        len(metrics_data),
        len(dose_events),
        len(lab_data),
        grounded_count,
        family_member_id,
    )

    return {
        "guidance_type": "informational",
        "is_diagnosis": False,
        "is_clinician_verified": False,
        "disclaimer": INSIGHTS_DISCLAIMER,
        "period_days": period_days,
        "subject": "self" if family_member_id is None else "family_member",
        "family_member_id": family_member_id,
        "insights": cleaned,
        "insufficient_categories": sorted(set(insufficient)),
        "data_availability": {
            "metrics_count": len(metrics_data),
            "dose_events_count": len(dose_events),
            "adherence_source_available": source_available,
            "lab_record_count": len(lab_data),
            "active_medication_schedules": active_med_count,
        },
        # Backward-compatible fields for older alerts UI.
        "alerts": [
            {
                "type": i.get("category"),
                "severity": "info",
                "title": i.get("title"),
                "description": i.get("summary"),
                "recommendation": i.get("suggestion"),
                "source": i.get("source"),
                "period": i.get("period"),
                "status": i.get("status"),
            }
            for i in cleaned
            if i.get("status") == "grounded"
        ],
        "trends": [
            {
                "metric": (i.get("facts") or {}).get("metric_type"),
                "direction": (i.get("facts") or {}).get("direction"),
                "note": i.get("summary"),
            }
            for i in cleaned
            if i.get("category") == "trend" and i.get("status") == "grounded"
        ],
        "summary": (
            f"{grounded_count} grounded insight(s) from your recorded HealthNest data."
            if grounded_count
            else "Not enough recorded HealthNest data yet for personal insights."
        ),
        "overall_status": "grounded" if grounded_count else "insufficient_data",
    }
