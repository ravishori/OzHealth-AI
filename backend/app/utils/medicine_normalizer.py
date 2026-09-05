"""
Medicine query normalisation.

Converts free-text search inputs into a canonical form that the cache lookup
can hit deterministically. Same canonical form for every variant a user might
type so we never call the AI twice for the same drug.

    "Panadol"          → "panadol"
    "panadol"          → "panadol"
    "Panadol Tablet"   → "panadol"
    "PANADOL 500MG"    → "panadol"
    "Panadol  500 mg"  → "panadol"
    "Amoxicillin 5ml"  → "amoxicillin"

The normaliser is intentionally light:
  - Casefold + trim.
  - Strip common dosage-form words (tablet, capsule, syrup, ...).
  - Strip common units (mg, ml, g, mcg, ...).
  - Strip standalone numeric tokens.
  - Collapse runs of whitespace.

It deliberately does NOT do stemming or alias resolution — that's the
enrichment layer's job (it queries TGA/PBS/ARTG for true synonyms).
"""
from __future__ import annotations

import re

# Words we strip outright (in addition to anything matched by the unit/number regex).
_FORM_TOKENS = {
    "tablet", "tablets", "tab", "tabs",
    "capsule", "capsules", "cap", "caps",
    "syrup", "suspension", "solution", "drops", "drop",
    "injection", "injectable", "vial", "ampoule",
    "cream", "ointment", "gel", "lotion",
    "patch", "spray", "inhaler", "nebuliser",
    "sachet", "powder", "granules",
    "tablet)", "capsule)",
}

# Units we strip when they appear standalone OR glued to a number.
_UNIT_TOKENS = {
    "mg", "g", "mcg", "µg", "ug",
    "ml", "l",
    "iu", "u",
    "%", "percent",
    "hr", "hrs", "h",
}

# One regex covers number+unit ("500mg", "5 ml", "1.5g") AND bare numbers ("500").
_NUMBER_UNIT_RE = re.compile(
    r"\b\d+(?:[.,]\d+)?\s*(?:" + "|".join(re.escape(u) for u in _UNIT_TOKENS) + r")\b",
    re.IGNORECASE,
)
_BARE_NUMBER_RE = re.compile(r"\b\d+(?:[.,]\d+)?\b")
_WHITESPACE_RE  = re.compile(r"\s+")
_PUNCT_RE       = re.compile(r"[(){}\[\],;:!?\"']")


def normalize_query(raw: str | None) -> str:
    """
    Canonical, cache-lookup-safe form of a user query.

    Always returns a string (possibly empty). The empty string is a valid
    cache key for "user typed nothing usable" — callers should reject it
    before doing a lookup.
    """
    if not raw:
        return ""

    s = raw.casefold().strip()
    s = _PUNCT_RE.sub(" ", s)
    s = _NUMBER_UNIT_RE.sub(" ", s)        # "500mg", "5 ml"
    s = _BARE_NUMBER_RE.sub(" ", s)        # "500"
    # Token-level strip of form/unit words.
    kept = [t for t in s.split() if t not in _FORM_TOKENS and t not in _UNIT_TOKENS]
    return _WHITESPACE_RE.sub(" ", " ".join(kept)).strip()


def is_meaningful(normalized: str, *, min_chars: int = 2) -> bool:
    """A normalised query is meaningful if it has at least `min_chars` letters."""
    return bool(normalized) and sum(c.isalpha() for c in normalized) >= min_chars
