from pydantic import BaseModel
from typing import Optional, List, Any
from datetime import datetime


class MedicineResponse(BaseModel):
    id: int
    name: str
    generic_name: Optional[str] = None
    brand_names: Optional[List[str]] = None
    composition: Optional[str] = None
    drug_class: Optional[str] = None
    dosage_forms: Optional[List[str]] = None
    standard_dosage: Optional[str] = None
    side_effects: Optional[str] = None
    interactions: Optional[str] = None
    contraindications: Optional[str] = None
    warnings: Optional[str] = None
    storage_instructions: Optional[str] = None
    pregnancy_category: Optional[str] = None
    tga_registered: bool = False
    tga_artg_number: Optional[str] = None
    schedule: Optional[str] = None
    atc_code: Optional[str] = None
    barcode: Optional[str] = None

    class Config:
        from_attributes = True


class MedicineSearchResult(BaseModel):
    """Lightweight result returned from the search endpoint."""
    id: int
    name: str
    generic_name: Optional[str] = None
    brand_names: Optional[List[str]] = None
    drug_class: Optional[str] = None
    schedule: Optional[str] = None
    tga_registered: bool = False

    class Config:
        from_attributes = True


class MedicineSearchResponse(BaseModel):
    results: List[Any]  # MedicineSearchResult or AI dict
    source: str  # "database" | "ai"


class AIMedicineInfo(BaseModel):
    """Shape of the AI-generated medicine info response."""
    name: str
    generic_name: Optional[str] = None
    drug_class: Optional[str] = None
    uses: Optional[str] = None
    standard_dosage: Optional[str] = None
    side_effects: Optional[str] = None
    warnings: Optional[str] = None
    interactions: Optional[str] = None
    storage_instructions: Optional[str] = None
    source: str = "ai"
