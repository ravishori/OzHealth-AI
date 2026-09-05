"""Pydantic request/response models for the medicine cache endpoints."""
from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field


class MedicineSearchResponse(BaseModel):
    """Response payload returned by GET /api/medicine/search."""

    medicine_id:      int | None = None
    name:             str | None = None
    generic_name:     str | None = None

    # The AI-enriched payload (free-form JSON keyed by section).
    ai_response:      dict[str, Any] = Field(default_factory=dict)

    # Provenance.
    source:           str  = Field(..., description="cache | db | ai | external")
    cache_hit:        bool = False
    ai_call_made:     bool = False
    normalized_query: str  = ""
    prompt_version:   str | None = None
    cached_at:        datetime | None = None
    cache_expires:    datetime | None = None


class CacheRefreshRequest(BaseModel):
    """Body for POST /api/cache/refresh — refresh a single cache entry."""

    query: str = Field(..., min_length=2)
    force: bool = Field(False, description="Bypass TTL and re-run AI.")


class CacheRefreshResponse(BaseModel):
    normalized_query: str
    refreshed:        bool
    new_expiry:       datetime | None = None
    detail:           str | None = None


class PopularMedicine(BaseModel):
    medicine_id:      int
    name:             str
    generic_name:     str | None
    search_count:     int
    cache_hit_count:  int
    ai_hit_count:     int
    popular_score:    float
    last_searched_at: datetime | None


class PopularMedicinesResponse(BaseModel):
    items: list[PopularMedicine]
    total: int
