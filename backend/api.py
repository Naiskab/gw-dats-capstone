"""
RideShift API Server
====================
Wraps ride_shift.py in a FastAPI endpoint so the iOS app can call it.

Install dependencies:
    pip install fastapi uvicorn

Run:
    uvicorn api:app --host 0.0.0.0 --port 8000 --reload

Endpoints:
    POST /find-best-pickup   — main search
    GET  /health             — sanity check
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import traceback

# Import your existing pipeline
from ride_shift import find_best_pickup

app = FastAPI(title="RideShift API", version="1.0.0")

# Allow the simulator (and any local client) to reach the API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Request / Response models ────────────────────────────────────────────────

class SearchRequest(BaseModel):
    pickup_address: str
    destination_address: str


class CandidateResult(BaseModel):
    candidate_id: int
    lat: float
    lon: float
    fare_cents: int | None
    savings_cents: int | None
    walking_dist_m: float
    beam_step: int


class OriginResult(BaseModel):
    address: str
    lat: float
    lon: float
    fare_cents: int | None


class SearchResponse(BaseModel):
    origin: OriginResult
    best_candidate: CandidateResult | None
    candidates: list[CandidateResult]   # all visited, sorted cheapest-first


# ── Routes ───────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/find-best-pickup", response_model=SearchResponse)
def find_best_pickup_endpoint(req: SearchRequest):
    """
    Run the full beam-search pipeline and return the best pickup candidate.
    This call takes ~10–30 s depending on network latency to ORS / Overpass.
    """
    try:
        result = find_best_pickup(req.pickup_address, req.destination_address)
    except ValueError as e:
        # Geocoding failure etc.
        raise HTTPException(status_code=422, detail=str(e))
    except Exception:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Pipeline error — check server logs")

    origin_raw = result["origin"]
    origin = OriginResult(
        address=origin_raw["address"],
        lat=origin_raw["lat"],
        lon=origin_raw["lon"],
        fare_cents=origin_raw.get("fare_cents"),
    )

    def to_candidate(r: dict) -> CandidateResult:
        return CandidateResult(
            candidate_id=r["candidate_id"],
            lat=r["lat"],
            lon=r["lon"],
            fare_cents=r.get("fare_cents"),
            savings_cents=r.get("savings_cents"),
            walking_dist_m=r["walking_dist_m"],
            beam_step=r["beam_step"],
        )

    best = to_candidate(result["best_candidate"]) if result.get("best_candidate") else None
    candidates = [to_candidate(c) for c in result.get("candidates", [])]

    return SearchResponse(origin=origin, best_candidate=best, candidates=candidates)
