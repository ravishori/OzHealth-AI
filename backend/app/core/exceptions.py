"""
Custom exception hierarchy for HealthNest.
All application exceptions inherit from AppException so the global handler
in main.py can format them uniformly.
"""
from fastapi import HTTPException


class AppException(Exception):
    """Base application exception."""
    status_code: int = 500
    error_code: str = "INTERNAL_ERROR"

    def __init__(self, message: str, status_code: int = None, error_code: str = None):
        self.message = message
        if status_code is not None:
            self.status_code = status_code
        if error_code is not None:
            self.error_code = error_code
        super().__init__(message)


class AuthError(AppException):
    status_code = 401
    error_code = "AUTH_ERROR"

    def __init__(self, message: str = "Authentication failed"):
        super().__init__(message)


class ForbiddenError(AppException):
    status_code = 403
    error_code = "FORBIDDEN"

    def __init__(self, message: str = "Access denied"):
        super().__init__(message)


class NotFoundError(AppException):
    status_code = 404
    error_code = "NOT_FOUND"

    def __init__(self, resource: str = "Resource"):
        super().__init__(f"{resource} not found")


class ValidationError(AppException):
    status_code = 422
    error_code = "VALIDATION_ERROR"

    def __init__(self, message: str):
        super().__init__(message)


class RateLimitError(AppException):
    status_code = 429
    error_code = "RATE_LIMIT_EXCEEDED"

    def __init__(self, message: str = "Too many requests", retry_after: int = 900):
        self.retry_after = retry_after
        super().__init__(message)


class DatabaseError(AppException):
    status_code = 503
    error_code = "DATABASE_ERROR"

    def __init__(self, message: str = "Database operation failed"):
        super().__init__(message)


class EncryptionError(AppException):
    status_code = 500
    error_code = "ENCRYPTION_ERROR"

    def __init__(self, message: str = "Data encryption/decryption failed"):
        super().__init__(message)


class ExternalServiceError(AppException):
    status_code = 502
    error_code = "EXTERNAL_SERVICE_ERROR"

    def __init__(self, service: str, message: str = ""):
        super().__init__(f"{service} service error: {message}" if message else f"{service} service unavailable")


class StorageError(AppException):
    status_code = 500
    error_code = "STORAGE_ERROR"

    def __init__(self, message: str = "File storage operation failed"):
        super().__init__(message)
