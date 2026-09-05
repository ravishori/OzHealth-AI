"""
Medicine enrichment orchestrator.

Drives the per-medicine workflow:

  1. Build a lookup-key dict from whatever the row already has.
  2. Walk the priority-ordered list of sources, calling each one
     concurrently up to a small cap (3) so a slow source doesn't block.
  3. Merge results respecting two rules:
        - NEVER overwrite a populated existing field with a less-confident
          new value.
        - Empty/whitespace/'unknown' counts as NULL and IS overwriteable.
  4. Apply the merged patch to `medicines`, log each field change to
     `medicine_enrichment_log`, bump `enrichment_attempts`, set
     `data_source`, `confidence_score`, `last_verified`.
  5. If average confidence < 0.70 → mark `needs_manual_review = TRUE`.
  6. Cache the enriched row in Redis under `medicine:{amt_code|id}`
     with a 30-day TTL.

Outputs a structured summary so callers (CLI / API) can render it.
"""
from __future__ import annotations

import asyncio
import json
import logging
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Iterable

from sqlalchemy import or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.medicine import Medicine
from app.services.cache_service import CacheService
from app.services.enrichment.log_repository import EnrichmentLogRepository
from app.services.enrichment.name_extractor import (
    extract_drug_name,
    is_supplement_like,
)
from app.services.enrichment.normalizer import (
    normalize_dosage_form,
    normalize_strength,
)
from app.services.enrichment.sources.amt           import AmtSource
from app.services.enrichment.sources.artg          import ArtgSource
from app.services.enrichment.sources.base          import EnrichmentResult, EnrichmentSource
from app.services.enrichment.sources.dailymed      import DailyMedSource
from app.services.enrichment.sources.healthdirect  import HealthDirectSource
from app.services.enrichment.sources.openfda       import OpenFdaSource
from app.services.enrichment.sources.pbs           import PbsSource

logger = logging.getLogger(__name__)

# ─── Fields the orchestrator is allowed to update ───────────────────────────
# Anything not in this set is ignored even if a source returns it. Keeps the
# blast radius of bad source data tightly bounded.
_ALLOWED_FIELDS = {
    "generic_name", "brand_name", "active_ingredient", "therapeutic_class",
    "uses", "side_effects", "contraindications", "warnings",
    "pregnancy_warning", "breastfeeding_warning", "storage_instructions",
    "consumer_information", "image_url", "dosage_form", "strength",
    "standard_dosage", "pack_size", "atc_code", "amt_code",
    "tga_artg_number", "pbs_code", "sponsor", "manufacturer",
    "registration_status", "approval_date", "approval_type", "route",
    "interactions",
}

# Field-specific normalisers.
_NORMALISERS = {
    "dosage_form": normalize_dosage_form,
    "strength":    normalize_strength,
}

# Values that we treat as "missing" — overwriteable.
_EMPTY_SENTINELS = {None, "", "null", "unknown", "n/a", "na", "-"}


# ─── Result containers ──────────────────────────────────────────────────────
@dataclass
class MedicineEnrichmentReport:
    medicine_id: int
    name:        str | None
    run_id:      uuid.UUID
    sources_tried: list[str]                  = field(default_factory=list)
    sources_used:  list[str]                  = field(default_factory=list)
    changed_fields: dict[str, dict[str, Any]] = field(default_factory=dict)
    confidence_score: float = 0.0
    needs_manual_review: bool = False
    sql_update: str = ""
    cache_key:  str | None = None
    skipped:    str | None = None       # set when the row was skipped


@dataclass
class BatchEnrichmentReport:
    started_at:  datetime
    finished_at: datetime
    examined: int = 0
    updated:  int = 0
    skipped:  int = 0
    per_medicine: list[MedicineEnrichmentReport] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "started_at":  self.started_at.isoformat(),
            "finished_at": self.finished_at.isoformat(),
            "examined":    self.examined,
            "updated":     self.updated,
            "skipped":     self.skipped,
            "items": [
                {
                    "medicine_id":         r.medicine_id,
                    "name":                r.name,
                    "run_id":              str(r.run_id),
                    "sources_tried":       r.sources_tried,
                    "sources_used":        r.sources_used,
                    "changed_fields":      r.changed_fields,
                    "confidence_score":    r.confidence_score,
                    "needs_manual_review": r.needs_manual_review,
                    "sql_update":          r.sql_update,
                    "cache_key":           r.cache_key,
                    "skipped":             r.skipped,
                }
                for r in self.per_medicine
            ],
        }


# ─── Orchestrator ───────────────────────────────────────────────────────────
class MedicineEnrichmentOrchestrator:
    """The only class callers (CLI, scheduler, API) need to know about."""

    def __init__(
        self,
        db: AsyncSession,
        *,
        sources: list[EnrichmentSource] | None = None,
        cache_ttl_seconds: int = 30 * 24 * 3600,
        manual_review_threshold: float = 0.70,
        per_source_concurrency: int = 3,
    ):
        self.db        = db
        self.log_repo  = EnrichmentLogRepository(db)
        self.ttl       = cache_ttl_seconds
        self.threshold = manual_review_threshold
        self.sem       = asyncio.Semaphore(per_source_concurrency)

        # Default source order (priority high → low).
        self.sources: list[EnrichmentSource] = sources or self._default_sources()
        logger.info("[enrichment] sources: %s",
                    ", ".join(s.source_name for s in self.sources))

    @staticmethod
    def _default_sources() -> list[EnrichmentSource]:
        return [
            AmtSource(bearer_token=getattr(settings, "NCTS_API_KEY", None) or None),
            ArtgSource(local_index_path=getattr(settings, "ARTG_INDEX_PATH", None) or None),
            PbsSource(subscription_key=getattr(settings, "PBS_SUBSCRIPTION_KEY", None) or None),
            HealthDirectSource(),
            DailyMedSource(),
            OpenFdaSource(api_key=getattr(settings, "OPENFDA_API_KEY", None) or None),
        ]

    # ── Public entry points ────────────────────────────────────────────────

    async def enrich_incomplete(self, *, limit: int = 500) -> BatchEnrichmentReport:
        """Enrich up to `limit` medicines with NULL critical fields."""
        report = BatchEnrichmentReport(
            started_at=datetime.now(timezone.utc),
            finished_at=datetime.now(timezone.utc),
        )
        rows = await self._find_incomplete(limit=limit)
        report.examined = len(rows)

        for med in rows:
            try:
                item = await self.enrich_one(med)
                report.per_medicine.append(item)
                if item.skipped:
                    report.skipped += 1
                else:
                    report.updated += 1
            except Exception:
                logger.exception("enrichment failed for medicine_id=%s", med.id)
                report.skipped += 1

        report.finished_at = datetime.now(timezone.utc)
        return report

    async def enrich_one(self, medicine: Medicine) -> MedicineEnrichmentReport:
        """Enrich a single medicine row. Caller commits the session."""
        run_id   = uuid.uuid4()
        rpt      = MedicineEnrichmentReport(
            medicine_id=medicine.id, name=medicine.name, run_id=run_id,
        )
        lookup   = self._build_lookup(medicine)
        if not any(lookup.values()):
            rpt.skipped = "no_lookup_keys"
            return rpt

        # 1) Run every source. (Sources internally fast-fail when they don't
        # have credentials, so total runtime is bounded by the slowest one
        # that actually fires.)
        results = await self._gather(medicine.id, lookup)
        rpt.sources_tried = [r.source for r in results]

        # 2) Merge.
        merged, confs, used = self._merge(medicine, results)
        rpt.sources_used = used

        if not merged:
            rpt.skipped = "no_new_data"
            return rpt

        # 3) Compute confidence.
        avg_conf = round(sum(confs.values()) / len(confs), 2) if confs else 0.0
        rpt.confidence_score    = avg_conf
        rpt.needs_manual_review = avg_conf < self.threshold

        # 4) Build SQL + log + apply.
        rpt.sql_update = self._render_sql(medicine.id, merged, avg_conf, used)

        for fname, fvalue in merged.items():
            old = getattr(medicine, fname, None)
            rpt.changed_fields[fname] = {"old": old, "new": fvalue}
            await self.log_repo.log_change(
                medicine_id = medicine.id,
                field       = fname,
                old_value   = old,
                new_value   = fvalue,
                source      = self._winning_source(fname, results),
                confidence  = confs.get(fname, avg_conf),
                run_id      = run_id,
            )

        await self._apply(medicine.id, merged, sources=used,
                          confidence=avg_conf,
                          needs_review=rpt.needs_manual_review)

        # 5) Cache.
        rpt.cache_key = await self._cache(medicine, merged)

        return rpt

    # ── Selection of incomplete rows ───────────────────────────────────────

    async def _find_incomplete(self, *, limit: int) -> list[Medicine]:
        """
        Pick the next batch of medicines to enrich.

        Ranking strategy
        ────────────────
        The catalog contains a long tail of supplements / complementary
        products / never-marketed brand variants that no public drug API
        knows about. If we just `ORDER BY enrichment_attempts ASC` we
        spend the whole batch on those duds. Instead we score each
        candidate by how *likely* a source has data for it:

          score = 4   if `tga_artg_number IS NOT NULL`      (AU registered)
                + 2   if `pbs_code IS NOT NULL`             (PBS subsidised)
                + 2   if `generic_name IS NOT NULL`         (we have a real
                                                              search term)
                - 4   if name matches supplement markers    (waste of time)

        Then within that score we prefer never-attempted rows, then the
        oldest attempt. This puts genuine drugs at the front of every
        batch — operators see meaningful results immediately and
        supplements naturally drift to the back of the queue.
        """
        from sqlalchemy import case, func, literal

        # Marker patterns we DON'T want at the front of the queue.
        # We can't reuse the Python set here — it's a SQL LIKE expression.
        supp_marker_like = (
            func.lower(Medicine.name).like("%fish oil%")
            | func.lower(Medicine.name).like("%omega%")
            | func.lower(Medicine.name).like("%creatine%")
            | func.lower(Medicine.name).like("%multivitamin%")
            | func.lower(Medicine.name).like("%probiotic%")
            | func.lower(Medicine.name).like("%collagen%")
            | func.lower(Medicine.name).like("%kids smart%")
            | func.lower(Medicine.name).like("%young living%")
            | func.lower(Medicine.name).like("%swisse%")
            | func.lower(Medicine.name).like("%blackmores%")
            | func.lower(Medicine.name).like("%nature's%")
            | func.lower(Medicine.name).like("%berocca%")
            | func.lower(Medicine.name).like("%caruso%")
        )

        enrichable_score = (
            case((Medicine.tga_artg_number.is_not(None), literal(4)), else_=literal(0))
            + case((Medicine.pbs_code.is_not(None),        literal(2)), else_=literal(0))
            + case((Medicine.generic_name.is_not(None),    literal(2)), else_=literal(0))
            + case((supp_marker_like,                       literal(-4)), else_=literal(0))
        ).label("enrichable_score")

        stmt = (
            select(Medicine)
            .where(
                or_(
                    Medicine.generic_name.is_(None),
                    Medicine.side_effects.is_(None),
                    Medicine.active_ingredient.is_(None),
                    Medicine.therapeutic_class.is_(None),
                    Medicine.uses.is_(None),
                    Medicine.dosage_form.is_(None),
                    Medicine.pregnancy_warning.is_(None),
                )
            )
            .order_by(
                enrichable_score.desc(),
                Medicine.enrichment_attempts.asc(),
                Medicine.enrichment_attempted_at.asc().nullsfirst(),
            )
            .limit(limit)
        )
        return list((await self.db.execute(stmt)).scalars().all())

    # ── Lookup key extraction ──────────────────────────────────────────────

    @staticmethod
    def _build_lookup(m: Medicine) -> dict[str, Any]:
        """
        Build clean lookup keys for the source connectors.

        The raw `medicines.name` is often noisy ("dapagliflozin viatris
        dapagliflozin 10 mg tablet blister"). Source APIs filter on EXACT
        brand_name / generic_name strings, so we run the name through
        `extract_drug_name()` to recover the drug-like token
        ("dapagliflozin") before handing it off.

        If a row looks like a supplement / complementary product the
        extractor returns None, which most sources treat as a no-op —
        saving us a wasted round trip to APIs that don't index that data.
        """
        # Best clean candidate to feed external APIs.
        clean_brand   = extract_drug_name(m.brand_name) or extract_drug_name(m.name)
        clean_generic = extract_drug_name(m.generic_name) or clean_brand

        return {
            "amt_code":        m.amt_code,
            "artg_id":         m.tga_artg_number,
            "tga_artg_number": m.tga_artg_number,
            "pbs_code":        m.pbs_code,
            # Clean names for API filters; fall back to raw if extractor
            # rejected the name (e.g. supplement) — gives sources a chance
            # to fail their own way rather than us pre-empting silently.
            "brand_name":      clean_brand   or m.brand_name or m.name,
            "generic_name":    clean_generic or m.generic_name,
            "name":            clean_brand   or m.name,
            # Surface the supplement hint so sources can fast-fail.
            "is_supplement":   is_supplement_like(m.name),
        }

    # ── Source fan-out ─────────────────────────────────────────────────────

    async def _gather(self, medicine_id: int, lookup: dict) -> list[EnrichmentResult]:
        async def _call(src: EnrichmentSource) -> EnrichmentResult:
            async with self.sem:
                try:
                    return await asyncio.wait_for(
                        src.fetch(medicine_id=medicine_id, **lookup),
                        timeout=25,
                    )
                except asyncio.TimeoutError:
                    return EnrichmentResult(source=src.source_name, found=False,
                                            error="timeout")
                except Exception as exc:
                    return EnrichmentResult(source=src.source_name, found=False,
                                            error=f"{type(exc).__name__}: {exc}")

        return await asyncio.gather(*[_call(s) for s in self.sources])

    # ── Merge logic ────────────────────────────────────────────────────────

    @classmethod
    def _is_empty(cls, value: Any) -> bool:
        if value is None:
            return True
        s = str(value).strip().lower()
        return s in _EMPTY_SENTINELS

    def _merge(
        self,
        medicine: Medicine,
        results: list[EnrichmentResult],
    ) -> tuple[dict[str, Any], dict[str, float], list[str]]:
        """
        Apply the "never overwrite unless confidence is higher" rule, with
        empty values always overwriteable.
        """
        merged: dict[str, Any] = {}
        confs:  dict[str, float] = {}
        used:   set[str] = set()

        # Sources arrive in self.sources order — high priority first.
        for r in results:
            if not r.found:
                continue
            for field_name, raw_value in r.fields.items():
                if field_name not in _ALLOWED_FIELDS:
                    continue
                value = _NORMALISERS.get(field_name, lambda v: v)(raw_value)
                if value is None or (isinstance(value, str) and not value.strip()):
                    continue

                existing = getattr(medicine, field_name, None)
                src_conf = r.field_confidence.get(field_name, self._base_conf_of(r.source))

                # Already-merged value from a higher-priority source.
                if field_name in merged:
                    if src_conf <= confs[field_name]:
                        continue

                # Existing populated DB value — only replace if better.
                if not self._is_empty(existing):
                    # Existing values count as "moderately high" trust;
                    # only overwrite if the new source clears a margin.
                    existing_conf = float(medicine.confidence_score or 0.85)
                    if src_conf <= existing_conf + 0.05:
                        continue

                merged[field_name] = value
                confs[field_name]  = src_conf
                used.add(r.source)

        return merged, confs, sorted(used)

    @staticmethod
    def _base_conf_of(source_name: str) -> float:
        from app.services.enrichment.sources.amt           import AmtSource          # local imports avoid cycle
        from app.services.enrichment.sources.artg          import ArtgSource
        from app.services.enrichment.sources.pbs           import PbsSource
        from app.services.enrichment.sources.healthdirect  import HealthDirectSource
        from app.services.enrichment.sources.dailymed      import DailyMedSource
        from app.services.enrichment.sources.openfda       import OpenFdaSource
        return {
            "amt":          AmtSource.BASE_CONFIDENCE,
            "tga_artg":     ArtgSource.BASE_CONFIDENCE,
            "pbs":          PbsSource.BASE_CONFIDENCE,
            "healthdirect": HealthDirectSource.BASE_CONFIDENCE,
            "dailymed":     DailyMedSource.BASE_CONFIDENCE,
            "openfda":      OpenFdaSource.BASE_CONFIDENCE,
        }.get(source_name, 0.5)

    @staticmethod
    def _winning_source(field_name: str, results: list[EnrichmentResult]) -> str:
        """Which source's value won for this field."""
        best = (None, -1.0)
        for r in results:
            if not r.found or field_name not in r.fields:
                continue
            c = r.field_confidence.get(field_name, 0.0)
            if c > best[1]:
                best = (r.source, c)
        return best[0] or "unknown"

    # ── Persistence ────────────────────────────────────────────────────────

    async def _apply(
        self,
        medicine_id: int,
        patch: dict[str, Any],
        *,
        sources: Iterable[str],
        confidence: float,
        needs_review: bool,
    ) -> None:
        patch_full = dict(patch)
        patch_full["data_source"]            = "+".join(sources)
        patch_full["confidence_score"]       = round(confidence, 2)
        patch_full["last_verified"]          = datetime.now(timezone.utc)
        patch_full["enrichment_attempts"]    = Medicine.enrichment_attempts + 1
        patch_full["enrichment_attempted_at"] = datetime.now(timezone.utc)
        patch_full["needs_manual_review"]    = needs_review

        await self.db.execute(
            update(Medicine).where(Medicine.id == medicine_id).values(**patch_full)
        )

    async def _cache(self, medicine: Medicine, patch: dict) -> str | None:
        key = f"medicine:{medicine.amt_code or medicine.id}"
        try:
            payload = {
                "medicine_id":   medicine.id,
                "amt_code":      medicine.amt_code,
                "name":          medicine.name,
                **patch,
            }
            await CacheService.set(key, payload, ttl=self.ttl)
            return key
        except Exception as exc:
            logger.warning("[enrichment] cache set failed for %s: %s", key, exc)
            return None

    # ── SQL rendering for the CLI/API output ───────────────────────────────

    @staticmethod
    def _render_sql(medicine_id: int, patch: dict, conf: float, sources: list[str]) -> str:
        parts = [f"{k} = {MedicineEnrichmentOrchestrator._sql_literal(v)}" for k, v in patch.items()]
        parts.append(f"data_source = '{'+'.join(sources)}'")
        parts.append(f"confidence_score = {conf}")
        parts.append("last_verified = NOW()")
        return (
            "UPDATE medicines\nSET   "
            + ",\n      ".join(parts)
            + f"\nWHERE id = {medicine_id};"
        )

    @staticmethod
    def _sql_literal(value: Any) -> str:
        if value is None:
            return "NULL"
        if isinstance(value, bool):
            return "TRUE" if value else "FALSE"
        if isinstance(value, (int, float)):
            return str(value)
        s = str(value).replace("'", "''")
        return f"'{s}'"
