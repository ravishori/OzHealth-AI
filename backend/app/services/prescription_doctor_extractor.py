"""
Deterministic doctor/prescriber extraction from OCR text (HN-OCR-006).

Extracts ONLY when an explicit doctor/prescriber label or Dr./Doctor title
signal is present. Never invents names. Never uses an LLM.

Returned values are OCR prefill only — user review/edit remains authoritative.
This does NOT verify AHPRA credentials, eRx, PBS, or TGA status.
"""
from __future__ import annotations

import re
from typing import Optional

# Explicit label with name on the same line: "Doctor: Jane Smith"
_LABEL_INLINE = re.compile(
    r"(?i)^\s*(?:"
    r"doctor|"
    r"prescriber(?:\s+name)?|"
    r"prescribed\s+by|"
    r"treating\s+doctor|"
    r"medical\s+practitioner"
    r")\s*[:\-]\s*(?P<name>.+?)\s*$"
)

# Inline title form: "Dr. Jane Smith" / "Dr Jane Smith" / "Doctor Jane Smith"
_TITLE_INLINE = re.compile(
    r"(?i)^\s*(?:dr\.?|doctor)\s+"
    r"(?P<name>[A-Za-z][A-Za-z\-'.]*(?:\s+[A-Za-z][A-Za-z\-'.]*){0,4})\s*$"
)

# Label alone on a line (name may follow on next line)
_LABEL_ONLY = re.compile(
    r"(?i)^\s*(?:"
    r"doctor|"
    r"dr\.?|"
    r"prescriber(?:\s+name)?|"
    r"prescribed\s+by|"
    r"treating\s+doctor|"
    r"medical\s+practitioner"
    r")\s*[:\-]?\s*$"
)

# Conservative person-name line after a label
_NAME_LINE = re.compile(
    r"^\s*(?P<name>[A-Za-z][A-Za-z\-'.]*(?:\s+[A-Za-z][A-Za-z\-'.]*){0,4})\s*$"
)

# Reject medicine-like or non-person content
_REJECT_NAME = re.compile(
    r"(?i)\b(?:"
    r"mg|mcg|ml|tablet|capsule|syrup|injection|cream|ointment|"
    r"patient|address|phone|medicare|signature|hospital|clinic|"
    r"prescription|pharmacy|dose|daily|bd|tds|qid"
    r")\b"
)


def _clean_name(raw: Optional[str]) -> Optional[str]:
    if not raw:
        return None
    s = raw.strip()
    # Strip wrapping punctuation / OCR noise
    s = s.strip(" \t\r\n\"'`*_~|[](){}<>")
    s = re.sub(r"\s+", " ", s).strip()
    # Drop leading title if still present after label capture
    s = re.sub(r"(?i)^(dr\.?|doctor)\s+", "", s).strip()
    # Trailing role noise (conservative, explicit suffixes only)
    s = re.sub(
        r"(?i)\s*(?:,?\s*)(?:mbbs|fracr?p|gp|md|phd)\.?$",
        "",
        s,
    ).strip(" ,.-")
    if not s:
        return None
    if _REJECT_NAME.search(s):
        return None
    # Require enough alphabetic content for a real name token
    alpha = sum(c.isalpha() for c in s)
    if alpha < 2 or len(s) > 80:
        return None
    if not _NAME_LINE.match(s):
        return None
    return s


def extract_doctor_name(ocr_text: Optional[str]) -> Optional[str]:
    """
    Return a doctor/prescriber name from OCR text when an explicit signal exists.

    Returns None when no sufficiently strong doctor/prescriber signal is found.
    """
    if not ocr_text or not str(ocr_text).strip():
        return None
    if str(ocr_text).startswith("[OCR"):
        return None

    text = str(ocr_text).lstrip("\ufeff").replace("\u2014", "-").replace("\u2013", "-")
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]

    for idx, raw in enumerate(lines):
        # 1) Label + name same line
        m = _LABEL_INLINE.match(raw)
        if m:
            cleaned = _clean_name(m.group("name"))
            if cleaned:
                return cleaned

        # 2) Title + name same line (Dr. / Doctor)
        m = _TITLE_INLINE.match(raw)
        if m:
            cleaned = _clean_name(m.group("name"))
            if cleaned:
                return cleaned

        # 3) Label alone → next line name
        if _LABEL_ONLY.match(raw) and idx + 1 < len(lines):
            nxt = lines[idx + 1]
            # Do not consume another labelled metadata line
            if _LABEL_ONLY.match(nxt) or _LABEL_INLINE.match(nxt):
                continue
            cleaned = _clean_name(nxt)
            if cleaned:
                return cleaned

    return None
