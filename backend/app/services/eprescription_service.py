"""
ePrescription service — token validation, provider API calls, TGA enrichment.

Supported providers
───────────────────
  eRx Script Exchange  (https://erx.com.au)

  NOTE: MediSecure is discontinued. The company suffered a 12.9 million-person
  data breach in 2024 and entered voluntary administration in June 2024.
  Only eRx Script Exchange (NPDS) is supported going forward.

Modes
─────
  MOCK (default, settings.EPRESCRIPTION_MOCK_MODE=True):
      Generates deterministic, realistic Australian ePrescription data for
      development / testing — no external API calls made.

  LIVE (settings.EPRESCRIPTION_MOCK_MODE=False + ERX_API_KEY set):
      Calls the real eRx REST API. Requires ERX_API_KEY in .env.

Security
────────
  hash_token()  — SHA-256; raw token must NEVER be logged or stored.
  extract_token_from_qr() — strips URL wrapping from Australian ePrescription
  QR codes so the backend only receives the bare token.
"""
from __future__ import annotations

import hashlib
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional
from urllib.parse import parse_qs, urlparse

import httpx
from sqlalchemy import or_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.core.config import settings

logger = logging.getLogger(__name__)

# ─── Mock data ────────────────────────────────────────────────────────────────

_MOCK_PATIENTS = [
    "James Williams",
    "Emily Chen",
    "Michael O'Brien",
    "Sarah Thompson",
    "Ravi Sharma",
]

_MOCK_PRESCRIBERS = [
    {
        "name": "Dr. Sarah Johnson",
        "number": "2291234B",
        "practice": "Melbourne Medical Centre, 123 Collins St, Melbourne VIC 3000",
    },
    {
        "name": "Dr. David Nguyen",
        "number": "4415678C",
        "practice": "Sydney Health Clinic, 45 George St, Sydney NSW 2000",
    },
    {
        "name": "Dr. Priya Sharma",
        "number": "3367890D",
        "practice": "Brisbane Family Medical, 78 Queen St, Brisbane QLD 4000",
    },
    {
        "name": "Dr. Tom Bradley",
        "number": "5523456E",
        "practice": "Perth Wellness Centre, 99 St Georges Terrace, Perth WA 6000",
    },
]

_MOCK_MEDICINE_POOL = [
    {
        "name": "Amoxicillin",
        "generic_name": "amoxicillin trihydrate",
        "dosage": "500 mg",
        "frequency": "3 times daily for 7 days",
        "quantity": "21 capsules",
        "repeats": 0,
        "instructions": "Take with food. Complete the full course even if you feel better.",
    },
    {
        "name": "Atorvastatin",
        "generic_name": "atorvastatin calcium",
        "dosage": "40 mg",
        "frequency": "Once daily at night",
        "quantity": "30 tablets",
        "repeats": 5,
        "instructions": "Can be taken with or without food. Avoid grapefruit juice.",
    },
    {
        "name": "Metformin",
        "generic_name": "metformin hydrochloride",
        "dosage": "500 mg",
        "frequency": "Twice daily with meals",
        "quantity": "60 tablets",
        "repeats": 5,
        "instructions": "Take with meals to reduce gastrointestinal side effects.",
    },
    {
        "name": "Salbutamol",
        "generic_name": "salbutamol sulfate",
        "dosage": "100 mcg/puff",
        "frequency": "2 puffs as needed for breathlessness",
        "quantity": "1 inhaler (200 doses)",
        "repeats": 2,
        "instructions": "Shake well before use. Rinse mouth after each use.",
    },
    {
        "name": "Ramipril",
        "generic_name": "ramipril",
        "dosage": "5 mg",
        "frequency": "Once daily in the morning",
        "quantity": "30 tablets",
        "repeats": 5,
        "instructions": "May cause initial dizziness. Rise slowly from sitting.",
    },
    {
        "name": "Pantoprazole",
        "generic_name": "pantoprazole sodium sesquihydrate",
        "dosage": "40 mg",
        "frequency": "Once daily before breakfast",
        "quantity": "30 tablets",
        "repeats": 2,
        "instructions": "Swallow whole — do not crush or chew.",
    },
    {
        "name": "Sertraline",
        "generic_name": "sertraline hydrochloride",
        "dosage": "50 mg",
        "frequency": "Once daily in the morning",
        "quantity": "30 tablets",
        "repeats": 5,
        "instructions": "May take 2–4 weeks to feel full benefit. Do not stop abruptly.",
    },
]


# ─── Token utilities ──────────────────────────────────────────────────────────

def hash_token(token: str) -> str:
    """
    Return the SHA-256 hex digest of the raw token.
    The raw token must NEVER be logged or stored — only the hash.
    """
    return hashlib.sha256(token.strip().encode("utf-8")).hexdigest()


def extract_token_from_qr(raw_qr: str) -> str:
    """
    Extract the bare ePrescription token from a QR code value.

    Australian QR codes may contain:
      eRx:    https://erx.com.au/?s=<TOKEN>
      Legacy: bare token string

    Returns the extracted token, or the raw value if no URL pattern matches.
    """
    raw = raw_qr.strip()
    if raw.startswith(("http://", "https://")):
        parsed = urlparse(raw)
        params = parse_qs(parsed.query)
        for key in ("s", "t", "token", "id", "scid", "script"):
            if key in params:
                return params[key][0]
        # Fallback: last non-empty path segment
        parts = [p for p in parsed.path.split("/") if p]
        if parts:
            return parts[-1]
    return raw


def detect_provider_from_qr(raw_qr: str) -> str:
    """
    Always returns 'erx'. MediSecure is discontinued (2024).
    Only eRx Script Exchange (NPDS) is supported.
    """
    return "erx"


# ─── Mock provider ────────────────────────────────────────────────────────────

async def _get_mock_prescription(token: str) -> dict:
    """
    Return deterministic mock data — same token always produces same data.
    Simulates a realistic Australian ePrescription with PBS-style medicines.
    """
    h = int(hashlib.md5(token.encode()).hexdigest(), 16)  # noqa: S324 (not security-critical)
    patient    = _MOCK_PATIENTS[h % len(_MOCK_PATIENTS)]
    prescriber = _MOCK_PRESCRIBERS[h % len(_MOCK_PRESCRIBERS)]

    # 1–3 medicines deterministically selected
    med_count = (h % 3) + 1
    medicines = [
        _MOCK_MEDICINE_POOL[(h + i) % len(_MOCK_MEDICINE_POOL)]
        for i in range(med_count)
    ]

    now = datetime.now(timezone.utc)
    logger.info(
        "[MOCK ePrescription] token_last4=%s  patient=%s  medicines=%d",
        token[-4:],
        patient,
        len(medicines),
    )
    return {
        "patient_name":               patient,
        "prescriber_name":            prescriber["name"],
        "prescriber_provider_number": prescriber["number"],
        "prescriber_practice":        prescriber["practice"],
        "prescription_date":          (now - timedelta(days=3)).isoformat(),
        "expiry_date":                (now + timedelta(days=180)).isoformat(),
        "medicines":                  medicines,
        "status":                     "validated",
    }


# ─── Live provider calls ──────────────────────────────────────────────────────

async def _call_erx_api(token: str) -> dict:
    """Call eRx Script Exchange REST API (requires ERX_API_KEY)."""
    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.post(
            f"{settings.ERX_API_URL}/prescriptions/token",
            headers={
                "Authorization":  f"Bearer {settings.ERX_API_KEY}",
                "Content-Type":   "application/json",
                "Accept":         "application/json",
            },
            json={"token": token},
        )
        resp.raise_for_status()
        return _parse_erx_response(resp.json())


def _parse_erx_response(raw: dict) -> dict:
    """Map eRx API response → internal format."""
    medicines = [
        {
            "name":         m.get("productName", ""),
            "generic_name": m.get("genericName"),
            "dosage":       m.get("strength"),
            "frequency":    m.get("directions"),
            "quantity":     str(m.get("quantity", "")),
            "repeats":      m.get("repeats", 0),
            "instructions": m.get("additionalInstructions"),
        }
        for m in raw.get("medications", [])
    ]
    p = raw.get("prescriber", {})
    return {
        "patient_name":               raw.get("patient", {}).get("name"),
        "prescriber_name":            p.get("name"),
        "prescriber_provider_number": p.get("providerNumber"),
        "prescriber_practice":        p.get("practiceName"),
        "prescription_date":          raw.get("prescribedDate"),
        "expiry_date":                raw.get("expiryDate"),
        "medicines":                  medicines,
        "status":                     "validated",
    }


# ─── Main validation entry point ──────────────────────────────────────────────

async def validate_eprescription_token(token: str, provider: str = "erx") -> dict:
    """
    Validate an ePrescription token against eRx Script Exchange and return
    structured prescription data.

    Only eRx (NPDS) is supported. MediSecure is discontinued (2024).

    Uses mock mode when:
      • settings.EPRESCRIPTION_MOCK_MODE is True  (default), OR
      • No ERX_API_KEY is configured.

    Raises:
      ValueError      — token not found / already used / expired
      PermissionError — API authentication failure
      TimeoutError    — provider API did not respond in 15 s
      RuntimeError    — unexpected HTTP error from provider
    """
    use_mock = settings.EPRESCRIPTION_MOCK_MODE or not settings.ERX_API_KEY

    if use_mock:
        result = await _get_mock_prescription(token)
        result["provider"] = "erx"
        return result

    try:
        result = await _call_erx_api(token)
        result["provider"] = "erx"
        return result

    except httpx.TimeoutException as exc:
        raise TimeoutError(
            f"{provider} API timed out. Please try again shortly."
        ) from exc
    except httpx.HTTPStatusError as exc:
        code = exc.response.status_code
        body = exc.response.text[:300]
        if code == 404:
            raise ValueError(
                f"ePrescription token not found in the {provider} system. "
                "Check the token and try again."
            ) from exc
        if code == 410:
            raise ValueError(
                "This ePrescription token has already been dispensed or has expired."
            ) from exc
        if code == 401:
            raise PermissionError(
                f"{provider} API authentication failed. Contact support."
            ) from exc
        raise RuntimeError(
            f"{provider} API returned HTTP {code}: {body}"
        ) from exc


# ─── TGA enrichment ───────────────────────────────────────────────────────────

async def enrich_with_tga(medicines: list[dict], db: AsyncSession) -> list[dict]:
    """
    Look up each medicine in the local TGA database and attach:
    drug_class, side_effects, warnings, schedule, tga_registered.

    Matching order: exact name → exact generic_name → ILIKE name → ILIKE generic.
    Silently skips any medicine that cannot be matched (no crash).
    """
    from app.models.medicine import Medicine  # local import — avoids circular deps
    from sqlalchemy import func as sqlfunc

    enriched: list[dict] = []
    for med in medicines:
        query_name = (med.get("name") or "").strip()
        if not query_name:
            enriched.append(med)
            continue

        tga_med = None
        try:
            # 1. Exact name or generic_name match (case-insensitive)
            res = await db.execute(
                select(Medicine).where(
                    or_(
                        sqlfunc.lower(Medicine.name)         == query_name.lower(),
                        sqlfunc.lower(Medicine.generic_name) == query_name.lower(),
                    )
                ).limit(1)
            )
            tga_med = res.scalar_one_or_none()

            if tga_med is None:
                # 2. Partial ILIKE fallback
                res = await db.execute(
                    select(Medicine).where(
                        or_(
                            Medicine.name.ilike(f"%{query_name}%"),
                            Medicine.generic_name.ilike(f"%{query_name}%"),
                        )
                    ).limit(1)
                )
                tga_med = res.scalar_one_or_none()

        except Exception as exc:
            logger.warning("TGA lookup failed for %r: %s", query_name, exc)

        if tga_med:
            enriched.append({
                **med,
                "drug_class":    tga_med.drug_class,
                "side_effects":  tga_med.side_effects,
                "warnings":      tga_med.warnings,
                "schedule":      tga_med.schedule,
                "tga_registered": tga_med.tga_registered,
            })
        else:
            enriched.append(med)

    return enriched


# ─── Date parser ──────────────────────────────────────────────────────────────

def parse_date(value: Optional[str]) -> Optional[datetime]:
    """Parse ISO-8601 date string → timezone-aware datetime. Returns None on failure."""
    if not value:
        return None
    for fmt in (
        "%Y-%m-%dT%H:%M:%S%z",
        "%Y-%m-%dT%H:%M:%S.%f%z",
        "%Y-%m-%dT%H:%M:%SZ",
        "%Y-%m-%d",
    ):
        try:
            dt = datetime.strptime(value[:26], fmt)  # truncate sub-second noise
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt
        except ValueError:
            pass
    try:
        # Final fallback — Python 3.11+ fromisoformat handles most formats
        return datetime.fromisoformat(value)
    except ValueError:
        logger.warning("Could not parse date: %r", value)
        return None
