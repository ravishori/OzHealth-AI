"""
Rule-based medicine line extraction from OCR text.

Extracts ONLY clearly present:
  - medicine name
  - strength
  - dosage/frequency
  - route

Does not guess missing values. No diagnosis or clinical advice.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, asdict
from typing import Any, Optional

# Strength patterns commonly printed on AU scripts / labels
_STRENGTH_RE = re.compile(
    r"(?P<strength>\d+(?:\.\d+)?\s*(?:mg|mcg|micrograms?|g|ml|mL|IU|units?|%)(?:\s*/\s*\d+(?:\.\d+)?\s*(?:ml|mL))?)",
    re.IGNORECASE,
)

_FREQ_RE = re.compile(
    r"\b(?P<freq>"
    r"BD|TDS|QID|OD|QD|BID|TID|"
    r"once\s+daily|twice\s+daily|three\s+times\s+(?:a\s+)?day|"
    r"1\s*[xX×]\s*[1234]|1-0-0|1-0-1|1-1-1|0-0-1|"
    r"mane|nocte|morning|night|evening"
    r")\b",
    re.IGNORECASE,
)

_ROUTE_RE = re.compile(
    r"\b(?P<route>oral|po|p\.o\.|topical|inhaled|inhalation|sublingual|"
    r"iv|i\.v\.|im|i\.m\.|sc|s\.c\.|nasal|ocular|rectal|vaginal)\b",
    re.IGNORECASE,
)

# Lines that are clearly not medicines
_SKIP_LINE = re.compile(
    r"(?i)^(patient|name|age|sex|address|date|doctor|dr\.|hospital|clinic|"
    r"valid|signature|rx\b|prescription|medicare|phone|tel|fax|email|"
    r"weight|dob|address|diagnosis|history|lab|cbc|tsh|hba1c|"
    r"not valid|medico|page\s*\d)"
)

_FORM_HINT = re.compile(
    r"\b(tablet|tab|capsule|cap|syrup|injection|cream|ointment|drops|"
    r"inhaler|patch|powder|suspension|solution)\b",
    re.IGNORECASE,
)

# Medicine-like token: Capitalised / brand-like words, not pure numbers
_MED_START = re.compile(
    r"^(?:T\.?\s*|Tab\.?\s*|Cap\.?\s*|Syp\.?\s*)?(?P<name>[A-Za-z][A-Za-z0-9\-/']{1,}(?:\s+[A-Za-z][A-Za-z0-9\-/']{1,}){0,4})",
)


@dataclass
class ExtractedMedicineLine:
    extracted_name: str
    extracted_strength: Optional[str] = None
    extracted_frequency: Optional[str] = None
    extracted_route: Optional[str] = None
    source_line: Optional[str] = None
    confirmed: bool = False  # always False until DB match elsewhere

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["source"] = "ocr_extracted"
        d["disclaimer"] = (
            "OCR-extracted text only — not a confirmed medicine identity "
            "until matched to the medicine database."
        )
        return d


def extract_medicine_candidates(ocr_text: str) -> list[ExtractedMedicineLine]:
    if not ocr_text or ocr_text.startswith("[OCR"):
        return []

    # Normalise OCR quirks
    ocr_text = ocr_text.lstrip("\ufeff").replace("\u2014", "-").replace("\u2013", "-")
    lines = [ln.strip() for ln in ocr_text.splitlines() if ln.strip()]
    out: list[ExtractedMedicineLine] = []
    seen: set[str] = set()

    for raw_line in lines:
        line = re.sub(r"^\d+[\).:\-]\s*", "", raw_line).strip()
        line = re.sub(r"^[-*•]\s*", "", line).strip()
        if _SKIP_LINE.search(line) or _SKIP_LINE.search(raw_line):
            continue
        if len(line) < 3 or len(line) > 200:
            continue
        # Skip pure lab numeric lines
        if re.fullmatch(r"[\d\s./:%\-]+", line):
            continue

        strength_m = _STRENGTH_RE.search(line)
        freq_m = _FREQ_RE.search(line)
        route_m = _ROUTE_RE.search(line)
        form_m = _FORM_HINT.search(line)
        name_m = _MED_START.match(line)

        # Require a plausible medicine cue: strength OR form OR frequency with a name
        if not name_m:
            continue
        name = name_m.group("name").strip(" -,:;")
        # Drop if name is a skip word
        if _SKIP_LINE.match(name):
            continue
        if not (strength_m or form_m or freq_m):
            # Without cues, only accept if original line had Rx numbering / form prefix
            if not re.match(r"^\d+[\).]\s*", raw_line) and not re.match(
                r"^(?:T\.|Tab\.|Cap\.)", line, re.I
            ):
                continue

        strength = strength_m.group("strength").strip() if strength_m else None
        # Strip strength from name if embedded
        if strength and strength.lower() in name.lower():
            name = re.sub(re.escape(strength), "", name, flags=re.I).strip(" -")

        key = f"{name.lower()}|{strength or ''}"
        if key in seen:
            continue
        seen.add(key)

        out.append(
            ExtractedMedicineLine(
                extracted_name=name,
                extracted_strength=strength,
                extracted_frequency=freq_m.group("freq").strip() if freq_m else None,
                extracted_route=route_m.group("route").strip() if route_m else None,
                source_line=raw_line,
                confirmed=False,
            )
        )

    return out
