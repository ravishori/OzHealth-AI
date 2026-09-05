"""
Pull a clean drug name out of a noisy medicines.name string.

The local medicines table stores names like:
    "candesartan viatris 8 mg tablet blister pack 30"
    "acamprosate-wgr acamprosate calcium 333 mg enteric coated tablets"
    "kids smart dha omega-3 fish oil"
    "young living inner defense"

For external lookups (PBS, OpenFDA, RxNorm, HealthDirect) we need the
*drug-like* token, not the brand+strength+form+pack soup. This module
returns either:
  - a short candidate name suitable for an exact-match API filter, or
  - None when the input looks like a supplement / complementary product
    that those drug-registry APIs won't recognise.

Heuristics are deliberately simple — we only need to keep good signal
out of obvious noise. Anything ambiguous is left to the source itself.
"""
from __future__ import annotations

import re

# Phrases that strongly suggest a non-PBS, non-FDA complementary product.
#
# CAREFUL: single tokens like "calcium", "iron", "magnesium", "vitamin" are
# legitimately part of real drug names — "acamprosate calcium", "ferrous
# sulfate", "magnesium oxide" — and must NOT trigger the supplement filter.
# We match phrases / multi-word brand markers instead.
_SUPPLEMENT_MARKERS = {
    # Generic product-category phrases
    "fish oil", "krill oil",
    "multivitamin", "vitamin complex", "mineral complex",
    "omega-3", "omega 3", "omega-6", "omega 6",
    "probiotic", "probiotics", "prebiotic",
    "collagen powder", "creatine ultra", "creatine chew",
    "whey protein", "amino acid", "amino acids",
    "essential oil", "cbd oil", "hemp oil",
    # Australian supplement brand families (consumer products, not PBS)
    "kids smart", "young living", "lifecykel", "swisse",
    "blackmores", "nature's way", "nature's own", "ostelin",
    "berocca", "centrum", "caruso's", "thompson's", "cognisense",
    "nutri glow", "sup creatine", "fefol",
    # Wellness-style category phrases
    "weight loss", "weight management",
    "immune support", "energy support", "joint support",
    "hair skin", "skin nails", "beauty wellness",
}

# Manufacturer / sponsor tokens we drop from the middle of names.
_SPONSOR_TOKENS = {
    "viatris", "sandoz", "mylan", "teva", "apotex", "generichealth",
    "amneal", "ascend", "blooms", "chemmart", "actavis", "alphapharm",
    "arrotex", "aspen", "douglas", "fresenius", "hospira", "lupin",
    "nbs", "novartis", "pfizer", "wgr", "msn", "noumed", "ranbaxy",
    "sun", "drla", "auro", "amgen", "bayer", "novo", "boehringer",
    "aurobindo", "intas", "cipla", "dr reddy", "dr. reddy",
    "generic", "ge", "ah", "trade",
}

# Dosage form / unit tokens we strip from the tail.
_FORM_TOKENS = {
    "tablet", "tablets", "tab", "tabs",
    "capsule", "capsules", "cap", "caps",
    "syrup", "suspension", "solution", "drops",
    "injection", "injectable", "vial", "ampoule",
    "cream", "ointment", "gel", "patch", "spray",
    "inhaler", "nebuliser",
    "blister", "pack", "bottle", "sachet", "strip",
    "enteric", "coated", "delayed", "release", "modified",
    "immediate",
}
_UNIT_RE   = re.compile(r"\b\d+(?:[.,]\d+)?\s*(?:mg|g|mcg|µg|ug|ml|l|iu|u|%)\b",
                        re.IGNORECASE)
_NUMBER_RE = re.compile(r"\b\d+(?:[.,]\d+)?\b")
# Hyphens are part of catalog noise (`acamprosate-wgr`, `msn-dapagliflozin`)
# — split on them so the leading drug token isn't `acamprosate-wgr` (which
# would fail the all-alphabetic check and break the loop early).
_PUNCT_RE  = re.compile(r"[(){}\[\],;:!?\"'\-]")


def is_supplement_like(name: str | None) -> bool:
    """Return True if the name screams 'complementary medicine / supplement'."""
    if not name:
        return False
    low = name.casefold()
    return any(marker in low for marker in _SUPPLEMENT_MARKERS)


def extract_drug_name(name: str | None) -> str | None:
    """
    Best-effort: pull the leading drug name out of a noisy product string.

    Returns None when the input looks like a supplement, a vague product
    name, or yields fewer than 3 letters of signal after stripping noise.
    """
    if not name:
        return None
    if is_supplement_like(name):
        return None

    s = name.casefold()
    s = _PUNCT_RE.sub(" ", s)
    s = _UNIT_RE.sub(" ", s)
    s = _NUMBER_RE.sub(" ", s)

    tokens = [
        t for t in s.split()
        if t not in _SPONSOR_TOKENS
        and t not in _FORM_TOKENS
        and not t.startswith("-")
    ]
    if not tokens:
        return None

    # Take the longest leading run of all-alphabetic tokens. That captures
    # multi-word drug names like "acetylsalicylic acid" or "olmesartan
    # medoxomil" while dropping trailing junk. Dedupe consecutive
    # repetitions ("dapagliflozin dapagliflozin" — common when the catalog
    # name embeds both brand and generic for the same active ingredient).
    leading: list[str] = []
    seen: set[str] = set()
    for t in tokens:
        if not t.isalpha():
            break
        if t in seen:                  # drop repeats
            continue
        leading.append(t)
        seen.add(t)
        if len(leading) >= 3:
            break

    candidate = " ".join(leading).strip()
    if len(candidate) < 3:
        return None
    return candidate
