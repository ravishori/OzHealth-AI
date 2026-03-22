from app.schemas.auth import (
    SendOTPRequest, VerifyOTPRequest, RegisterRequest,
    LoginRequest, RefreshTokenRequest, TokenResponse,
)
from app.schemas.user import UserUpdate, UserResponse
from app.schemas.family import (
    FamilyMemberCreate, FamilyMemberUpdate, FamilyMemberResponse,
)
from app.schemas.health_metric import (
    HealthMetricCreate, HealthMetricResponse, HealthMetricSummary,
)
from app.schemas.medication import (
    MedicationScheduleCreate, MedicationScheduleUpdate, MedicationScheduleResponse,
)
from app.schemas.medicine import (
    MedicineResponse, MedicineSearchResult, MedicineSearchResponse, AIMedicineInfo,
)
from app.schemas.prescription import (
    ExtractedMedicine, PrescriptionScanResponse, PrescriptionResponse,
)
from app.schemas.record import MedicalRecordResponse, MedicalRecordUploadResponse
from app.schemas.emergency import (
    EmergencyContactCreate, EmergencyContactResponse, SOSRequest, SOSResponse,
)
from app.schemas.ai_conversation import (
    ChatMessage, ChatRequest, ChatResponse,
    HealthGuidanceRequest, ConversationSummary, ConversationDetail,
)

__all__ = [
    # Auth
    "SendOTPRequest", "VerifyOTPRequest", "RegisterRequest",
    "LoginRequest", "RefreshTokenRequest", "TokenResponse",
    # User
    "UserUpdate", "UserResponse",
    # Family
    "FamilyMemberCreate", "FamilyMemberUpdate", "FamilyMemberResponse",
    # Health Metrics
    "HealthMetricCreate", "HealthMetricResponse", "HealthMetricSummary",
    # Medication
    "MedicationScheduleCreate", "MedicationScheduleUpdate", "MedicationScheduleResponse",
    # Medicine
    "MedicineResponse", "MedicineSearchResult", "MedicineSearchResponse", "AIMedicineInfo",
    # Prescription
    "ExtractedMedicine", "PrescriptionScanResponse", "PrescriptionResponse",
    # Record
    "MedicalRecordResponse", "MedicalRecordUploadResponse",
    # Emergency
    "EmergencyContactCreate", "EmergencyContactResponse", "SOSRequest", "SOSResponse",
    # AI Conversation
    "ChatMessage", "ChatRequest", "ChatResponse",
    "HealthGuidanceRequest", "ConversationSummary", "ConversationDetail",
]
