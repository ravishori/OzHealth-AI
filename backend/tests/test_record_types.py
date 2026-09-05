"""Tests for medical record type normalization and access-control helpers."""
from app.api.routes.records import normalize_record_type, VALID_TYPES


def test_discharge_alias_maps_to_canonical():
    assert normalize_record_type("discharge") == "discharge_summary"
    assert normalize_record_type("Discharge") == "discharge_summary"
    assert normalize_record_type("discharge_summary") == "discharge_summary"


def test_canonical_types_unchanged():
    for t in VALID_TYPES:
        assert normalize_record_type(t) == t


def test_imaging_alias_to_radiology():
    assert normalize_record_type("imaging") == "radiology"
