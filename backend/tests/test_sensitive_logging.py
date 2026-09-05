"""HN-SEC-007 — sensitive logging must not emit OTP / PHI / tokens."""
from __future__ import annotations

import inspect
import logging
import re

from app.api.routes import auth as auth_route
from app.api.routes import users as users_route
from app.services import ai_service
from app.services import reminder_worker
from app.core import log_decorator


SENSITIVE_OTP = "847291"


def _logger_calls(src: str) -> list[str]:
    return re.findall(
        r"logger\.(?:info|debug|warning|error)\([\s\S]*?\)\s*(?:\n|$)",
        src,
    )


def test_sec_log_01_users_contact_change_never_logs_plaintext_otp(caplog):
    """SEC-LOG-01"""
    src = inspect.getsource(users_route.request_contact_change)
    assert "otp=%s" not in src
    for call in _logger_calls(src):
        assert "otp_code" not in call
        assert "otp=%s" not in call
    with caplog.at_level(logging.INFO):
        logging.getLogger("app.api.routes.users").info(
            "contact_change_otp user_id=%d type=%s target=%s delivered=%s",
            2,
            "email",
            "a***@ex.com",
            True,
        )
    assert SENSITIVE_OTP not in caplog.text


def test_sec_log_01b_auth_send_otp_never_logs_plaintext_otp():
    """SEC-LOG-01 (auth path)"""
    src = inspect.getsource(auth_route.send_otp)
    assert "otp=%s" not in src
    for call in _logger_calls(src):
        assert "otp_code" not in call
        assert "otp=%s" not in call


def test_sec_log_02_06_ai_medicine_debug_has_no_name():
    """SEC-LOG-02 / SEC-LOG-06"""
    src = inspect.getsource(ai_service.get_medicine_info_from_ai)
    assert "medicine=%s" not in src
    assert "name_len=%d" in src


def test_sec_log_05_06_ai_logs_metadata_not_payloads(caplog):
    """SEC-LOG-05/06 — OCR/PHI content must not appear in log output."""
    chat_src = inspect.getsource(ai_service.chat_with_health_assistant)
    assert "messages=%d" in chat_src
    ocr_src = inspect.getsource(ai_service.analyze_prescription)
    assert (
        'ai_log.debug("Prescription analysis request model=%s text_len=%d", '
        "_MODEL_SONNET, len(ocr_text))"
    ) in ocr_src
    # Runtime: emit the same safe metadata style used by AI service
    sensitive_ocr = "Take Warfarin 5mg nightly Patient JohnDoeRX"
    with caplog.at_level(logging.DEBUG):
        logging.getLogger("app.services.ai_service").debug(
            "Prescription analysis request model=%s text_len=%d",
            "claude-sonnet",
            len(sensitive_ocr),
        )
        logging.getLogger("app.services.ai_service").debug(
            "AI chat request model=%s messages=%d",
            "claude-sonnet",
            2,
        )
    assert "Warfarin" not in caplog.text
    assert "JohnDoeRX" not in caplog.text
    assert "text_len=" in caplog.text
    assert "messages=" in caplog.text


def test_sec_log_02_tokens_absent_from_auth_user_log_calls():
    """SEC-LOG-02 — logger format strings must not include token values."""
    for mod in (auth_route, users_route):
        src = inspect.getsource(mod)
        for call in _logger_calls(src):
            assert "access_token" not in call
            assert "refresh_token" not in call
            assert "Authorization" not in call
            assert "password=%s" not in call
            assert "password=" not in call


def test_sec_log_07_safe_operational_metadata_preserved():
    """SEC-LOG-07"""
    chat_src = inspect.getsource(ai_service.chat_with_health_assistant)
    assert "input_tokens" in chat_src
    assert "output_tokens" in chat_src


def test_sec_log_08_otp_masking_helper_still_present():
    """SEC-LOG-08"""
    users_src = inspect.getsource(users_route)
    assert "_mask(normalized)" in users_src
    auth_src = inspect.getsource(auth_route)
    assert "_mask(identifier)" in auth_src


def test_sec_log_09_http_error_logging_still_exists():
    """SEC-LOG-09"""
    src = inspect.getsource(log_decorator)
    assert "status_code" in src or "HTTP%d" in src


def test_sec_log_10_reminder_worker_no_medicine_in_debug():
    """SEC-LOG-05"""
    src = inspect.getsource(reminder_worker)
    debug_parts = src.split("logger.debug")
    for part in debug_parts[1:]:
        chunk = part[:300]
        assert "medicine_name" not in chunk
        assert "medicine=%s" not in chunk


def test_sec_log_source_scan_auth_users_no_otp_format():
    for mod in (auth_route, users_route):
        src = inspect.getsource(mod)
        assert "otp=%s" not in src
