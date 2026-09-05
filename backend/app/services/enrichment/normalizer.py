"""
Cross-source value normalisation.

Every source has its own conventions for dosage forms, strengths, units, etc.
This module turns the messy raw strings into a clean canonical form so the
audit log sees consistent values regardless of which source produced them.

Conservative by design — when in doubt, return the input unchanged. Better to
under-normalise than to silently rewrite something the orchestrator hasn't
asked to change.
"""
from __future__ import annotations

import re
from typing import Optional

# ─── Dosage forms ─────────────────────────────────────────────────────────────
# Map raw token → canonical form (Title-Case singular).
_DOSAGE_FORM_MAP: dict[str, str] = {
    # tablets
    "tab":          "Tablet",
    "tabs":         "Tablet",
    "tablet":       "Tablet",
    "tablets":      "Tablet",
    "tab.":         "Tablet",
    "film-coated tablet":       "Tablet",
    "modified release tablet":  "Modified-release tablet",
    "controlled release tablet": "Modified-release tablet",
    # capsules
    "cap":          "Capsule",
    "caps":         "Capsule",
    "capsule":      "Capsule",
    "capsules":     "Capsule",
    "soft capsule": "Capsule",
    # liquids
    "syrup":        "Syrup",
    "suspension":   "Suspension",
    "solution":     "Solution",
    "oral solution":"Solution",
    "oral liquid":  "Liquid",
    "elixir":       "Elixir",
    "drops":        "Drops",
    # parenterals
    "injection":    "Injection",
    "injectable":   "Injection",
    "iv":           "Injection",
    "im":           "Injection",
    # topicals
    "cream":        "Cream",
    "ointment":     "Ointment",
    "gel":          "Gel",
    "lotion":       "Lotion",
    "spray":        "Spray",
    "patch":        "Patch",
    # respiratory
    "inhaler":      "Inhaler",
    "nebuliser":    "Nebuliser solution",
    # other
    "suppository":  "Suppository",
    "powder":       "Powder",
    "sachet":       "Sachet",
}

# Strength regex: "500 mg", "5mg/ml", "1.25 mg", "10mcg", "0.5%".
_STRENGTH_RE = re.compile(
    r"(?P<value>\d+(?:[.,]\d+)?)\s*"
    r"(?P<unit>mg|g|mcg|µg|ug|ml|l|iu|u|%|mg/ml|mg/g|mcg/ml|mg/l)\b",
    re.IGNORECASE,
)

_UNIT_CANON: dict[str, str] = {
    "mg": "mg", "g": "g", "mcg": "mcg", "µg": "mcg", "ug": "mcg",
    "ml": "mL", "l": "L", "iu": "IU", "u": "U", "%": "%",
    "mg/ml": "mg/mL", "mg/g": "mg/g", "mcg/ml": "mcg/mL", "mg/l": "mg/L",
}


def normalize_dosage_form(raw: Optional[str]) -> Optional[str]:
    if not raw:
        return None
    lower = raw.strip().lower()
    # Exact map first.
    if lower in _DOSAGE_FORM_MAP:
        return _DOSAGE_FORM_MAP[lower]
    # Containment fallback ("500 mg tablet" → Tablet).
    for token, canon in _DOSAGE_FORM_MAP.items():
        if token in lower.split():
            return canon
    # Title-case as last resort so casing is stable.
    return raw.strip().title()


def normalize_strength(raw: Optional[str]) -> Optional[str]:
    """Extract first numeric strength and canonicalise the unit."""
    if not raw:
        return None
    m = _STRENGTH_RE.search(raw)
    if not m:
        return raw.strip()
    value = m.group("value").replace(",", ".")
    unit  = _UNIT_CANON.get(m.group("unit").lower(), m.group("unit"))
    # Trim trailing ".0".
    if value.endswith(".0"):
        value = value[:-2]
    return f"{value} {unit}"


def extract_dosage_form_and_strength(raw: Optional[str]) -> tuple[Optional[str], Optional[str]]:
    """
    Split a combined string like "500 mg tablet" into ("Tablet", "500 mg").

    If both can't be extracted, returns whatever was found and None for the
    missing one. Used when a source supplies a single freeform field.
    """
    if not raw:
        return None, None
    strength = normalize_strength(raw)
    form     = normalize_dosage_form(raw)
    return form, strength


def clean_text(raw: Optional[str], *, max_len: int = 4000) -> Optional[str]:
    """
    Trim, collapse whitespace, drop HTML-ish residue. Used on consumer-facing
    text scraped from HealthDirect, etc.
    """
    if raw is None:
        return None
    s = re.sub(r"<[^>]+>", " ", str(raw))         # strip tags
    s = re.sub(r"\s+", " ", s).strip()
    if not s:
        return None
    return s[:max_len]


def join_list(items, *, sep: str = ", ", limit: int = 20) -> Optional[str]:
    """Collapse a list of strings into a comma-separated value."""
    if not items:
        return None
    cleaned = [clean_text(str(i)) for i in items]
    cleaned = [c for c in cleaned if c][:limit]
    return sep.join(cleaned) if cleaned else None
