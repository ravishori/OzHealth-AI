"""OCR confirm-before-save contract tests (Sprint 1 closure)."""
import inspect

from app.api.routes import prescriptions as rx


def test_scan_persist_defaults_false():
    sig = inspect.signature(rx.scan_prescription)
    default = sig.parameters["persist"].default
    value = getattr(default, "default", default)
    assert value is False


def test_confirm_endpoint_exists():
    assert hasattr(rx, "confirm_prescription")
    sig = inspect.signature(rx.confirm_prescription)
    assert "medicines_json" in sig.parameters
    assert "file" in sig.parameters


def test_ocr_endpoint_exists():
    assert hasattr(rx, "prescription_ocr_minimum")
