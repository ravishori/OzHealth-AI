import anthropic
import json
import logging
from typing import List, Dict, Optional, Any
from app.core.config import settings

logger = logging.getLogger(__name__)

HEALTH_SYSTEM_PROMPT = """You are VitaPulse AI, an intelligent personal health companion for Australia.
You provide reliable, evidence-based health information to help users understand their medications,
manage their health, and make informed decisions.

Guidelines:
- Always recommend consulting a qualified healthcare professional for medical advice
- Reference Australian health standards and TGA (Therapeutic Goods Administration) where relevant
- Be empathetic, clear, and concise
- Never diagnose conditions or prescribe medications
- For emergencies, always direct users to call 000 (Australia emergency number)
- Comply with Australian Privacy Principles when handling health data
"""


async def chat_with_health_assistant(
    messages: List[Dict],
    user_context: Optional[dict] = None,
    system_override: Optional[str] = None,
) -> str:
    if not settings.ANTHROPIC_API_KEY or settings.ANTHROPIC_API_KEY == "your-anthropic-api-key-here":
        return _fallback_response(messages[-1].get("content", "") if messages else "")

    try:
        client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY)

        system = system_override or HEALTH_SYSTEM_PROMPT
        if user_context:
            ctx_parts = []
            if user_context.get("name"):
                ctx_parts.append(f"User: {user_context['name']}")
            if user_context.get("age"):
                ctx_parts.append(f"Age: {user_context['age']}")
            if user_context.get("gender"):
                ctx_parts.append(f"Gender: {user_context['gender']}")
            if user_context.get("health_conditions"):
                ctx_parts.append(f"Health conditions: {', '.join(user_context['health_conditions'])}")
            if user_context.get("allergies"):
                ctx_parts.append(f"Allergies: {', '.join(user_context['allergies'])}")
            if ctx_parts:
                system += f"\n\nUser Profile:\n" + "\n".join(ctx_parts)

        # Convert to Anthropic message format
        api_messages = [
            {"role": m["role"], "content": m["content"]}
            for m in messages
            if m["role"] in ("user", "assistant")
        ]

        response = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=1024,
            system=system,
            messages=api_messages,
        )

        return response.content[0].text

    except Exception as e:
        logger.error(f"AI chat error: {e}")
        return "I'm sorry, I'm having trouble connecting to the AI service. Please try again later."


async def analyze_prescription(ocr_text: str) -> dict:
    if not settings.ANTHROPIC_API_KEY or settings.ANTHROPIC_API_KEY == "your-anthropic-api-key-here":
        return {"medicines": [], "doctor_name": None, "hospital": None, "summary": "AI analysis unavailable"}

    try:
        client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY)

        response = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=1024,
            system="You are a medical prescription analyser. Extract structured information from prescription text. Always respond with valid JSON.",
            messages=[{
                "role": "user",
                "content": f"""Analyse this prescription text and extract:
1. List of medicines (name, dosage, frequency, duration)
2. Doctor name
3. Hospital/clinic name
4. Brief summary

Return as JSON:
{{
  "medicines": [{{"name": "", "dosage": "", "frequency": "", "duration": "", "instructions": ""}}],
  "doctor_name": "",
  "hospital": "",
  "summary": ""
}}

Prescription text:
{ocr_text}"""
            }],
        )

        text = response.content[0].text
        # Extract JSON from response
        import re
        json_match = re.search(r'\{.*\}', text, re.DOTALL)
        if json_match:
            return json.loads(json_match.group())
        return {"medicines": [], "doctor_name": None, "hospital": None, "summary": text}

    except Exception as e:
        logger.error(f"Prescription analysis error: {e}")
        return {"medicines": [], "doctor_name": None, "hospital": None, "summary": "Analysis failed"}


async def get_medicine_info_from_ai(medicine_name: str) -> Optional[dict]:
    if not settings.ANTHROPIC_API_KEY or settings.ANTHROPIC_API_KEY == "your-anthropic-api-key-here":
        return None

    try:
        client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY)

        response = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=800,
            system="You are a pharmacist providing medicine information for Australia. Return structured JSON.",
            messages=[{
                "role": "user",
                "content": f"""Provide information about the medicine: {medicine_name}
Return as JSON:
{{
  "name": "",
  "generic_name": "",
  "composition": "",
  "drug_class": "",
  "standard_dosage": "",
  "side_effects": "",
  "interactions": "",
  "contraindications": "",
  "warnings": "",
  "tga_registered": true/false,
  "schedule": ""
}}"""
            }],
        )

        text = response.content[0].text
        import re
        json_match = re.search(r'\{.*\}', text, re.DOTALL)
        if json_match:
            return json.loads(json_match.group())
        return None

    except Exception as e:
        logger.error(f"Medicine AI info error: {e}")
        return None


def _fallback_response(query: str) -> str:
    q = query.lower()
    if any(w in q for w in ["emergency", "chest pain", "breathing", "unconscious"]):
        return "This sounds like an emergency. Please call 000 immediately (Australia's emergency number)."
    if any(w in q for w in ["paracetamol", "ibuprofen", "aspirin"]):
        return "For common pain relievers, always follow the dosage on the package and consult your pharmacist. Do not exceed recommended doses."
    return "I'm here to help with health questions. Please add your Anthropic API key to get full AI-powered responses. In an emergency, call 000."
