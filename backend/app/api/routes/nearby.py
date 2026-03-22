from fastapi import APIRouter, Depends, Query
from app.core.deps import get_current_user
from app.models.user import User
import httpx

router = APIRouter()

# Uses OpenStreetMap Nominatim (free, no API key required)
OVERPASS_URL = "https://overpass-api.de/api/interpreter"


@router.get("/")
async def get_nearby(
    lat: float = Query(...),
    lng: float = Query(...),
    type: str = Query("hospital"),  # hospital, pharmacy, lab
    radius: int = Query(5000, le=20000),
    current_user: User = Depends(get_current_user),
):
    osm_tags = {
        "hospital": 'amenity~"hospital|clinic"',
        "pharmacy": 'amenity="pharmacy"',
        "lab": 'amenity~"laboratory|medical_laboratory"',
    }

    tag = osm_tags.get(type, 'amenity="hospital"')
    query = f"""
    [out:json][timeout:25];
    node[{tag}](around:{radius},{lat},{lng});
    out body;
    """

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(OVERPASS_URL, data={"data": query})
            data = resp.json()

        results = []
        for el in data.get("elements", [])[:20]:
            tags = el.get("tags", {})
            results.append({
                "id": el.get("id"),
                "name": tags.get("name", f"Unnamed {type.title()}"),
                "type": type,
                "lat": el.get("lat"),
                "lng": el.get("lon"),
                "phone": tags.get("phone", tags.get("contact:phone")),
                "address": tags.get("addr:full", f"{tags.get('addr:street', '')} {tags.get('addr:city', '')}".strip()),
                "opening_hours": tags.get("opening_hours"),
                "website": tags.get("website", tags.get("contact:website")),
            })

        return {"results": results, "count": len(results), "type": type}

    except Exception as e:
        return {"results": [], "count": 0, "error": str(e)}
