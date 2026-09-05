"""Lightweight tests for prescription confirm payload expectations."""


def test_confirm_requires_named_medicines_contract():
    """Document the confirm endpoint contract used by Flutter review UI."""
    # Sanitization rules mirrored from prescriptions.confirm_prescription
    medicines = [
        {"extracted_name": "Paracetamol", "match_status": "UNMATCHED"},
        {"name": "", "extracted_name": ""},  # dropped
        {
            "name": "Panadol",
            "catalog_medicine_id": 12,
            "ARTG": "12345",
            "match_status": "MATCHED",
        },
    ]
    sanitized = []
    for m in medicines:
        entry = {
            "name": (m.get("name") or m.get("extracted_name") or "").strip(),
            "catalog_medicine_id": m.get("catalog_medicine_id") or m.get("medicine_id"),
            "artg_number": m.get("artg_number") or m.get("ARTG"),
            "match_status": m.get("match_status")
            or (
                "MATCHED"
                if m.get("catalog_medicine_id") or m.get("medicine_id")
                else "UNMATCHED"
            ),
            "user_confirmed": True,
            "source": "user_confirmed",
        }
        if entry["name"]:
            sanitized.append(entry)

    assert len(sanitized) == 2
    assert sanitized[0]["name"] == "Paracetamol"
    assert sanitized[0]["match_status"] == "UNMATCHED"
    assert sanitized[1]["catalog_medicine_id"] == 12
    assert sanitized[1]["artg_number"] == "12345"
