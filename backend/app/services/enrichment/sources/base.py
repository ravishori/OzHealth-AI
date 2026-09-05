"""
Source-connector abstract base.

Every external system (AMT, ARTG, PBS, HealthDirect, DailyMed, OpenFDA) is
implemented as a small async class with a single `fetch()` method that returns
an `EnrichmentResult`. The orchestrator iterates a priority-ordered list of
sources and merges the results — see orchestrator.py.

Confidence convention
─────────────────────
Each source declares a `BASE_CONFIDENCE` reflecting how authoritative its data
is for the AU market:

    AMT (SNOMED CT-AU)       0.97   — canonical AU clinical terminology
    ARTG (TGA register)      0.95   — official AU registration
    PBS (pharma benefits)    0.92   — government subsidy data
    HealthDirect             0.88   — AU govt patient-facing portal
    DailyMed (FDA US label)  0.70   — relevant but US-centric
    OpenFDA                  0.68   — US-centric, sometimes stale

A per-field confidence is `BASE_CONFIDENCE × source-specific multiplier`.
"""
from __future__ import annotations

import abc
from dataclasses import dataclass, field
from typing import Any


@dataclass
class EnrichmentResult:
    """
    What a source returns for one medicine.

    `fields` is a dict of {column_name → value}. The orchestrator merges
    multiple sources by field, never blindly overwriting.

    `field_confidence` maps each field to a 0.0–1.0 score. Missing keys
    default to the source's BASE_CONFIDENCE.

    `evidence` is a free-form dict (URL, payload hash, …) carried into the
    audit log so a reviewer can trace exactly where a value came from.
    """

    source: str                                       # short id: 'pbs', 'tga_artg', …
    found:  bool                                      # source had any data
    fields: dict[str, Any]                = field(default_factory=dict)
    field_confidence: dict[str, float]   = field(default_factory=dict)
    evidence: dict[str, Any]              = field(default_factory=dict)
    error: str | None                     = None


class EnrichmentSource(abc.ABC):
    """Async source connector. Subclasses must override `fetch`."""

    source_name: str       = ""    # short id (e.g. 'pbs')
    BASE_CONFIDENCE: float = 0.70  # subclasses override

    def __init__(self):
        if not self.source_name:
            raise RuntimeError(f"{type(self).__name__} must set `source_name`")

    @abc.abstractmethod
    async def fetch(self, *, medicine_id: int, **lookup_keys) -> EnrichmentResult:
        """
        Look up a medicine by whichever keys the source accepts.
        `lookup_keys` may include any of:
            amt_code, artg_id, pbs_code, brand_name, generic_name, name

        Sources should consume what they can and ignore the rest.
        Return a populated `EnrichmentResult`, OR an empty one with
        `found=False` if nothing matched.
        """

    # ── Helpers for subclasses ───────────────────────────────────────────────

    def _ok(self, *, fields: dict[str, Any], evidence: dict | None = None,
            field_confidence: dict[str, float] | None = None) -> EnrichmentResult:
        """Convenience constructor for a successful fetch."""
        return EnrichmentResult(
            source=self.source_name,
            found=True,
            fields=fields,
            field_confidence=field_confidence or {},
            evidence=evidence or {},
        )

    def _none(self, *, reason: str = "not_found") -> EnrichmentResult:
        return EnrichmentResult(
            source=self.source_name, found=False, error=reason,
        )

    def _err(self, exc: BaseException) -> EnrichmentResult:
        return EnrichmentResult(
            source=self.source_name, found=False, error=f"{type(exc).__name__}: {exc}",
        )
