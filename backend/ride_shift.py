"""
Smart Pickup Optimizer
======================
Given a pickup address and a destination address this pipeline:

  1. Geocodes both addresses → (lat, lon)
  2. Fetches a 5-minute walking isochrone around the pickup point (in-memory)
  3. Queries drivable roads inside the isochrone via Overpass / OpenStreetMap
  4. Samples up to 99 candidate pickup points every 50 m along those roads
  5. Builds a KD-tree + kNN graph over the candidates
  6. Runs beam search — fetching the ride fare API ONLY for nodes actually
     visited, rather than blindly calling it for all 99 candidates.
     - Starts at the candidate nearest to the user's origin
     - Each layer: expands the current beam → fetches fares for new neighbours
       → keeps the BEAM_WIDTH cheapest as the next beam
  7. Returns:
       • origin fare (always fetched)
       • all visited candidates sorted cheapest-first, each with:
           fare_cents, savings_cents, walking_dist_m, beam_step (visit order)
       • exploration_order list — candidate indices in visit order
                                  (lets the frontend animate the search path)
       • best_candidate — single cheapest visited node

Environment variables (put in a .env file next to this script):
    ORS_API_KEY     – OpenRouteService key  (geocoding + isochrone)
    RAPIDAPI_KEY    – RapidAPI key          (taxi-fare-calculator)

Extra dependencies beyond the standard library:
    pip install requests python-dotenv shapely numpy scikit-learn folium branca
"""

import json
import math
import time
import os
import csv

import numpy as np
import requests
from dotenv import load_dotenv
from shapely.geometry import shape, LineString
from sklearn.neighbors import KDTree

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

load_dotenv()

ORS_API_KEY  = os.getenv("ORS_API_KEY")
RAPIDAPI_KEY = os.getenv("RAPIDAPI_KEY")

if not ORS_API_KEY:
    raise RuntimeError("Missing ORS_API_KEY in .env")
if not RAPIDAPI_KEY:
    raise RuntimeError("Missing RAPIDAPI_KEY in .env")

GEOCODE_URL   = "https://api.openrouteservice.org/geocode/search"
ISOCHRONE_URL = "https://api.openrouteservice.org/v2/isochrones/foot-walking"
OVERPASS_URL  = "https://overpass.kumi.systems/api/interpreter"
RAPIDAPI_HOST = "taxi-fare-calculator.p.rapidapi.com"
FARE_URL      = f"https://{RAPIDAPI_HOST}/search-geo"

# Candidate generation
WALK_MINUTES   = 5     # isochrone radius

# ---------------------------------------------------------------------------
# Module-level caches — avoids redundant ORS API calls for same addresses
# ---------------------------------------------------------------------------
_geocode_cache:   dict[str, tuple[float, float]] = {}
_isochrone_cache: dict[tuple[float, float], object] = {}
SAMPLE_SPACING = 50    # metres between sampled points along roads
MAX_CANDIDATES = 100    # hard cap on candidate pool size
DEDUPE_TOL     = 10    # metres — points closer than this are merged

# Beam search
K_NEIGHBORS        = 6    # edges per node in the kNN graph
BEAM_WIDTH         = 10   # nodes kept alive per depth layer
MAX_DEPTH          = 12   # maximum expansion layers
BEAM_EXPLORE_LIMIT = 100   # max fare API calls for candidates
                          # (≤ MAX_CANDIDATES; beam can visit at most
                          #  BEAM_WIDTH × MAX_DEPTH = 120 nodes, but we
                          #  cap at 99 to stay inside the candidate pool)


# ---------------------------------------------------------------------------
# Step 1 – Geocoding
# ---------------------------------------------------------------------------

def geocode_address(address: str) -> tuple[float, float]:
    """Return (lat, lon) for a free-text address via OpenRouteService."""
    resp = requests.get(
        GEOCODE_URL,
        headers={"Authorization": ORS_API_KEY},
        params={"text": address, "size": 1},
        timeout=5,
    )
    resp.raise_for_status()
    data = resp.json()

    if not data.get("features"):
        raise ValueError(f"No geocoding result for: {address!r}")

    lon, lat = data["features"][0]["geometry"]["coordinates"]
    return lat, lon


# ---------------------------------------------------------------------------
# Step 2 – Walking isochrone (in-memory only, never saved to disk)
# ---------------------------------------------------------------------------

def get_walk_isochrone(lat: float, lon: float, minutes: int = WALK_MINUTES) -> dict:
    """Fetch a walking-time isochrone polygon from OpenRouteService."""
    resp = requests.post(
        ISOCHRONE_URL,
        headers={"Authorization": ORS_API_KEY, "Content-Type": "application/json"},
        json={
            "locations":  [[lon, lat]],
            "range":      [minutes * 60],   # ORS expects seconds
            "range_type": "time",
            "smoothing":  0.5,
        },
        timeout=5,
    )
    resp.raise_for_status()
    return resp.json()


def isochrone_to_polygon(iso_geojson: dict):
    """Convert the raw GeoJSON dict to a Shapely Polygon."""
    return shape(iso_geojson["features"][0]["geometry"])


# ---------------------------------------------------------------------------
# Step 3 – Drivable roads via Overpass API
# ---------------------------------------------------------------------------

CSV_CANDIDATE_FALLBACK = "pickup_candidates.csv"  # same folder as ride_shift.py


def _load_csv_candidates(poly) -> list[tuple[float, float]]:
    """
    Load all candidate points from the CSV fallback as (lat, lon) tuples.
    Only keeps points that fall inside (or very near) the isochrone.
    """
    import csv as _csv
    from shapely.geometry import Point

    csv_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        CSV_CANDIDATE_FALLBACK
    )

    candidates = []
    with open(csv_path, newline="") as fh:
        reader = _csv.DictReader(fh)
        for row in reader:
            lat = float(row["lat"])
            lon = float(row["lon"])
            if poly.buffer(0.001).contains(Point(lon, lat)):
                candidates.append((lat, lon))

    if not candidates:
        raise RuntimeError(
            "CSV fallback loaded but no points fall inside the isochrone. "
            "The saved candidates may be from a different pickup area."
        )

    print(f"  CSV fallback: {len(candidates)} candidates loaded.")
    return candidates


def _load_csv_lines(poly) -> list[LineString]:
    """Legacy shim — not used when CSV path is taken directly."""
    candidates = _load_csv_candidates(poly)
    delta = 0.000009
    return [
        LineString([(lon, lat), (lon + delta, lat + delta)])
        for lat, lon in candidates
    ]


def fetch_drivable_roads(poly) -> list[LineString] | None:
    """
    Query Overpass (kumi.systems) for drivable roads inside the isochrone.
    If the request fails for any reason, falls back to pickup_candidates.csv.
    """
    minx, miny, maxx, maxy = poly.bounds
    pad   = 0.001
    south = miny - pad
    west  = minx - pad
    north = maxy + pad
    east  = maxx + pad

    query = f"""
    [out:json][timeout:25];
    (
      way["highway"~"residential|tertiary|secondary|primary|unclassified|living_street|service"]
        ["access"!~"private"]
        ["service"!~"driveway"]
        ({south},{west},{north},{east});
    );
    (._;>;);
    out body;
    """

    # ── Overpass API temporarily disabled for presentation ──────────────────
    # To re-enable, uncomment the try/except block below and remove the
    # early return above it.
    #
    # try:
    #     print(f"  Overpass: querying {OVERPASS_URL} …")
    #     resp = requests.post(
    #         OVERPASS_URL,
    #         data=query.encode("utf-8"),
    #         headers={"User-Agent": "capstone-pickup-optimizer (student project)"},
    #         timeout=5,
    #     )
    #     resp.raise_for_status()
    #     if not resp.text.strip():
    #         raise ValueError("Empty response from Overpass")
    #     elements = resp.json().get("elements", [])
    #
    #     nodes: dict[int, tuple[float, float]] = {}
    #     ways:  list[dict] = []
    #     for el in elements:
    #         if el["type"] == "node":
    #             nodes[el["id"]] = (el["lon"], el["lat"])
    #         elif el["type"] == "way":
    #             ways.append(el)
    #
    #     all_lines: list[LineString] = []
    #     for way in ways:
    #         coords = [nodes[nid] for nid in way.get("nodes", []) if nid in nodes]
    #         if len(coords) >= 2:
    #             all_lines.append(LineString(coords))
    #
    #     clipped: list[LineString] = []
    #     for ln in all_lines:
    #         if not ln.intersects(poly):
    #             continue
    #         inter = ln.intersection(poly)
    #         if inter.is_empty:
    #             continue
    #         if inter.geom_type == "LineString":
    #             clipped.append(inter)
    #         elif inter.geom_type == "MultiLineString":
    #             clipped.extend(list(inter.geoms))
    #
    #     print(f"  Overpass: {len(clipped)} road segments found.")
    #     return clipped
    #
    # except Exception as e:
    #     print(f"  ⚠️  Overpass failed ({e}). Will use pickup_candidates.csv fallback …")
    #     return None

    print("  Using CSV candidates directly (Overpass disabled).")
    return None


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in metres between two (lat, lon) points."""
    R = 6_371_000.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi  = math.radians(lat2 - lat1)
    dlmbd = math.radians(lon2 - lon1)
    a = (math.sin(dphi / 2) ** 2
         + math.cos(phi1) * math.cos(phi2) * math.sin(dlmbd / 2) ** 2)
    return 2 * R * math.asin(math.sqrt(a))


def sample_points_along_lines(
    lines: list[LineString],
    spacing_m: float = SAMPLE_SPACING,
) -> list[tuple[float, float]]:
    """
    Walk every clipped road LineString and emit a point every `spacing_m` metres.
    Shapely coordinates are (lon, lat); we return (lat, lon) tuples.
    """
    pts: list[tuple[float, float]] = []

    for ln in lines:
        coords = list(ln.coords)
        if len(coords) < 2:
            continue

        lon0, lat0 = coords[0]
        pts.append((lat0, lon0))

        dist_from_last = 0.0
        last_lon, last_lat = coords[0]

        for i in range(1, len(coords)):
            lon1, lat1 = last_lon, last_lat
            lon2, lat2 = coords[i]

            seg_len = haversine_m(lat1, lon1, lat2, lon2)
            if seg_len <= 0:
                last_lon, last_lat = lon2, lat2
                continue

            traveled = 0.0
            while dist_from_last + (seg_len - traveled) >= spacing_m:
                need = spacing_m - dist_from_last
                t    = (traveled + need) / seg_len      # interpolation 0..1
                pts.append((
                    lat1 + (lat2 - lat1) * t,
                    lon1 + (lon2 - lon1) * t,
                ))
                traveled      += need
                dist_from_last = 0.0

            dist_from_last += seg_len - traveled
            last_lon, last_lat = lon2, lat2

    return pts


def dedupe_points(
    points: list[tuple[float, float]],
    tol_m: float = DEDUPE_TOL,
) -> list[tuple[float, float]]:
    """
    Remove points that fall within `tol_m` metres of an already-kept point.
    O(n²) — acceptable for n ≤ 99.
    """
    kept: list[tuple[float, float]] = []
    for lat, lon in points:
        if all(haversine_m(lat, lon, klat, klon) >= tol_m for klat, klon in kept):
            kept.append((lat, lon))
    return kept


def generate_candidates(
    road_lines: list[LineString],
    max_candidates: int = MAX_CANDIDATES,
) -> list[tuple[float, float]]:
    """Sample, de-duplicate, and cap candidate pickup points."""
    pts = sample_points_along_lines(road_lines, spacing_m=SAMPLE_SPACING)
    pts = dedupe_points(pts, tol_m=DEDUPE_TOL)
    return pts[:max_candidates]


# ---------------------------------------------------------------------------
# Step 5 – KD-tree + kNN graph
# ---------------------------------------------------------------------------

def build_knn_graph(
    coords: np.ndarray,
    k: int = K_NEIGHBORS,
) -> tuple[KDTree, dict[int, list[int]]]:
    """
    Build a KD-tree and a kNN adjacency list over candidate coordinates.

    Parameters
    ----------
    coords : np.ndarray, shape (N, 2)   – (lat, lon) rows
    k      : int                         – neighbours per node

    Returns
    -------
    tree      : KDTree
    neighbors : dict[int → list[int]]   – index-based adjacency list
    """
    tree  = KDTree(coords, leaf_size=40)
    k_eff = min(k + 1, len(coords))    # +1 because query includes the node itself
    _, idxs = tree.query(coords, k=k_eff)

    neighbors: dict[int, list[int]] = {}
    for i in range(len(coords)):
        neighbors[i] = [int(j) for j in idxs[i][1:] if int(j) != i]

    return tree, neighbors


# ---------------------------------------------------------------------------
# Step 6 – Fare fetching + beam search
# ---------------------------------------------------------------------------
def estimate_fare_dc(
        dep_lat: float,
        dep_lon: float,
        arr_lat: float,
        arr_lon: float,
) -> int:
    """
    Estimate a DC taxicab fare using the official DFHV rate schedule.
    Returns fare in cents.

    Formula:
        distance_miles = haversine(dep, arr) / 1609.34
        fare = base($4.00) + surcharge($0.50)
               + max(0, distance_miles - 0.125) * $2.56/mile
    """
    distance_m = haversine_m(dep_lat, dep_lon, arr_lat, arr_lon)
    distance_miles = distance_m / 1609.34

    base_fare_cents = 400  # $4.00 — covers first 1/8 mile
    surcharge_cents = 50  # $0.50 passenger surcharge
    rate_per_mile_cents = 256  # $2.56 per additional mile

    additional_miles = max(0.0, distance_miles - 0.125)
    additional_cents = int(additional_miles * rate_per_mile_cents)

    total_cents = base_fare_cents + surcharge_cents + additional_cents
    return total_cents


# Tracks whether we've already printed the "switching to DC formula" notice
_fare_fallback_announced = False

def fetch_fare(
        dep_lat: float,
        dep_lon: float,
        arr_lat: float,
        arr_lon: float,
) -> int | None:
    """
    Try the RapidAPI taxi-fare-calculator first.
    On any error (429 rate-limit, 500 server error, timeout, etc.)
    fall back to the official DC DFHV taxicab fare formula.
    Always returns an int (cents) — never None.
    """
    global _fare_fallback_announced

    try:
        resp = requests.get(
            FARE_URL,
            headers={
                "x-rapidapi-key": RAPIDAPI_KEY,
                "x-rapidapi-host": RAPIDAPI_HOST,
            },
            params={
                "dep_lat": dep_lat,
                "dep_lng": dep_lon,
                "arr_lat": arr_lat,
                "arr_lng": arr_lon,
            },
            timeout=5,
        )
        resp.raise_for_status()
        data = resp.json()

        journey = data.get("journey", {})
        fares = journey.get("fares", []) if isinstance(journey, dict) else []
        prices: list[int] = []
        for f in fares:
            if isinstance(f, dict) and "price_in_cents" in f:
                try:
                    prices.append(int(f["price_in_cents"]))
                except (ValueError, TypeError):
                    pass

        if prices:
            _fare_fallback_announced = False  # reset if API recovers
            return min(prices)

    except Exception:
        pass

    # ── DC DFHV formula fallback ──────────────────────────────────────────────
    if not _fare_fallback_announced:
        print("  ⚠️  Fare API unavailable — switching to DC DFHV formula estimates.")
        _fare_fallback_announced = True
    return estimate_fare_dc(dep_lat, dep_lon, arr_lat, arr_lon)

def beam_search_fares(
    candidates: list[tuple[float, float]],
    origin_lat: float,
    origin_lon: float,
    dest_lat: float,
    dest_lon: float,
    rate_limit_sleep: float = 0.25,
) -> tuple[int | None, list[dict], list[int]]:
    """
    Fetch the origin fare, then use beam search to explore the candidate
    graph — only calling the fare API for nodes the beam actually visits.

    Why beam search instead of querying all candidates?
    ---------------------------------------------------
    Fares are spatially smooth: nearby points tend to have similar prices.
    Beam search exploits this by starting near the user, greedily following
    cheaper neighbours, and pruning expensive branches early. In practice
    this finds a near-optimal pickup point with far fewer API calls than
    querying all 99 candidates.

    Algorithm
    ---------
    1. Build a KD-tree + kNN graph over the candidate coordinates.
    2. Fetch the fare from the user's exact origin (always 1 call).
    3. Seed the beam with the candidate nearest to the origin.
    4. Each depth layer:
         a. Expand every node in the current beam → collect unvisited
            neighbours.
         b. Fetch the fare for each new neighbour.
         c. Sort by fare (cheapest first); keep the top BEAM_WIDTH nodes
            as the next beam.
    5. Stop when MAX_DEPTH layers are done or BEAM_EXPLORE_LIMIT total
       candidate nodes have been visited.

    Returns
    -------
    origin_fare    : int | None
        Fare in cents from the user's exact location.

    priced_results : list[dict]
        All visited candidates sorted cheapest-first. Each dict contains:
            candidate_id    – 1-based display ID
            lat, lon        – coordinates
            fare_cents      – fare in cents (None if API failed)
            savings_cents   – origin_fare − fare_cents (None if either missing)
            walking_dist_m  – haversine distance from origin
            beam_step       – visit order (1 = first visited, for animation)

    exploration    : list[int]
        Candidate indices in the exact order they were visited.
        Pass this to the frontend to drive step-by-step animation.
    """
    coords = np.array([[lat, lon] for lat, lon in candidates], dtype=float)
    tree, neighbors = build_knn_graph(coords)
    print(f"  KD-tree built over {len(candidates)} candidates "
          f"(k={K_NEIGHBORS} neighbours each).")

    # --- Always fetch the fare for the user's exact origin first ---
    origin_fare: int | None = None
    try:
        origin_fare = fetch_fare(origin_lat, origin_lon, dest_lat, dest_lon)
        print(f"  [origin] fare = {origin_fare} cents")
    except Exception as e:
        print(f"  [origin] fare fetch failed: {e}")
    # --- Seed: candidate nearest to the origin ---
    user_coord = np.array([[origin_lat, origin_lon]], dtype=float)
    _, start_idxs = tree.query(user_coord, k=1)
    start_idx = int(start_idxs[0][0])
    print(f"  Beam search start: candidate {start_idx} "
          f"({candidates[start_idx][0]:.6f}, {candidates[start_idx][1]:.6f})")

    # fare_cache[idx] = fare in cents, or None if the API call failed
    fare_cache: dict[int, int | None] = {}

    def get_fare_cached(idx: int) -> int | None:
        """Fetch the fare for candidates[idx], caching to avoid duplicate calls."""
        if idx not in fare_cache:
            lat, lon = candidates[idx]
            try:
                fare_cache[idx] = fetch_fare(lat, lon, dest_lat, dest_lon)
            except Exception as e:
                print(f"    candidate {idx}: fare fetch error: {e}")
                fare_cache[idx] = None
        return fare_cache[idx]

    # Fetch fare for the seed node right away
    get_fare_cached(start_idx)
    print(f"  [depth 0 / seed] candidate {start_idx}: "
          f"fare = {fare_cache[start_idx]} cents")

    visited:     set[int]  = {start_idx}
    exploration: list[int] = [start_idx]   # full visit order — for the frontend
    beam:        list[int] = [start_idx]

    # --- Main beam search loop ---
    no_improve_streak = 0
    best_fare_seen    = fare_cache.get(start_idx)

    for depth in range(1, MAX_DEPTH + 1):
        if len(exploration) >= BEAM_EXPLORE_LIMIT:
            break

        # Expand: gather all unvisited neighbours of every node in the beam
        new_nodes: list[int] = []
        for node in beam:
            for nb in neighbors.get(node, []):
                if nb not in visited:
                    visited.add(nb)
                    new_nodes.append(nb)
                    exploration.append(nb)
                    if len(exploration) >= BEAM_EXPLORE_LIMIT:
                        break
            if len(exploration) >= BEAM_EXPLORE_LIMIT:
                break

        if not new_nodes:
            print(f"  [depth {depth}] no new nodes to expand — stopping early.")
            break

        # Fetch fares for all new nodes at this depth in parallel
        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=32) as executor:
            executor.map(get_fare_cached, new_nodes)
        for idx in new_nodes:
            print(f"  [depth {depth}] candidate {idx}: fare = {fare_cache.get(idx)} cents")

        # Rank cheapest-first; push None fares to the back
        new_nodes.sort(
            key=lambda idx: (fare_cache[idx] is None, fare_cache[idx] or 0)
        )

        # Prune: only the BEAM_WIDTH cheapest survive to the next layer
        beam = new_nodes[:BEAM_WIDTH]

        best_this_layer = fare_cache[beam[0]] if fare_cache[beam[0]] is not None else None
        print(f"  → depth {depth} done: {len(new_nodes)} new nodes explored, "
              f"beam best = {best_this_layer} cents, "
              f"total visited = {len(exploration)}")

        # Early stopping — if no improvement for 2 consecutive layers, stop
        if best_this_layer is not None:
            if best_fare_seen is None or best_this_layer < best_fare_seen:
                best_fare_seen    = best_this_layer
                no_improve_streak = 0
            else:
                no_improve_streak += 1
                if no_improve_streak >= 2:
                    print(f"  → no improvement for 2 layers, stopping early.")
                    break

    print(f"  Beam search complete — "
          f"visited {len(exploration)} of {len(candidates)} candidates "
          f"({len(candidates) - len(exploration)} fare API calls saved).")

    # --- Build the result list for every visited candidate ---
    priced_results: list[dict] = []
    for beam_step, idx in enumerate(exploration, start=1):
        lat, lon = candidates[idx]
        fare     = fare_cache.get(idx)
        savings  = (
            (origin_fare - fare)
            if (origin_fare is not None and fare is not None)
            else None
        )
        priced_results.append({
            "candidate_id":   idx + 1,          # 1-based for display
            "lat":            lat,
            "lon":            lon,
            "fare_cents":     fare,
            "savings_cents":  savings,
            "walking_dist_m": round(haversine_m(origin_lat, origin_lon, lat, lon), 1),
            "beam_step":      beam_step,         # 1 = first visited (for animation)
        })

    # Return candidates sorted cheapest-first (None fares at the end)
    priced_results.sort(
        key=lambda r: (r["fare_cents"] is None, r["fare_cents"] or 0)
    )

    return origin_fare, priced_results, exploration


# ---------------------------------------------------------------------------
# Main orchestration
# ---------------------------------------------------------------------------

def find_best_pickup(
    pickup_address: str,
    destination_address: str,
) -> dict:
    """
    Full end-to-end pipeline. This is the single function your frontend
    (Flask/FastAPI endpoint) should call.

    Parameters
    ----------
    pickup_address      : str   e.g. "2121 Eye St NW, Washington DC"
    destination_address : str   e.g. "Reagan National Airport, Arlington VA"

    Returns
    -------
    {
      "origin": {
        "address":    str,
        "lat":        float,
        "lon":        float,
        "fare_cents": int | None          # fare from exact user location
      },
      "destination": {
        "address": str,
        "lat":     float,
        "lon":     float
      },
      "candidates": [                     # all visited nodes, cheapest first
        {
          "candidate_id":   int,
          "lat":            float,
          "lon":            float,
          "fare_cents":     int | None,
          "savings_cents":  int | None,   # positive = cheaper than origin
          "walking_dist_m": float,
          "beam_step":      int           # 1 = first visited (for animation)
        },
        ...
      ],
      "best_candidate":    dict | None,   # cheapest candidate found
      "exploration_order": [int, ...]     # candidate_ids in visit order
                                          # — feed this to the frontend
                                          #   to animate the beam search
    }
    """

    # 1. Geocode both addresses (cached)
    print("Geocoding pickup …")
    if pickup_address not in _geocode_cache:
        _geocode_cache[pickup_address] = geocode_address(pickup_address)
    origin_lat, origin_lon = _geocode_cache[pickup_address]
    print(f"  Pickup → lat={origin_lat:.6f}, lon={origin_lon:.6f}")

    print("Geocoding destination …")
    if destination_address not in _geocode_cache:
        _geocode_cache[destination_address] = geocode_address(destination_address)
    dest_lat, dest_lon = _geocode_cache[destination_address]
    print(f"  Destination → lat={dest_lat:.6f}, lon={dest_lon:.6f}")

    # 2. Walking isochrone — cached per origin coordinate
    print(f"Fetching {WALK_MINUTES}-minute walking isochrone …")
    origin_key = (round(origin_lat, 4), round(origin_lon, 4))
    if origin_key not in _isochrone_cache:
        iso_geojson = get_walk_isochrone(origin_lat, origin_lon, minutes=WALK_MINUTES)
        _isochrone_cache[origin_key] = isochrone_to_polygon(iso_geojson)
        print("  Isochrone polygon ready.")
    else:
        print("  Isochrone polygon ready (cached).")
    poly = _isochrone_cache[origin_key]

    # 3. Get candidate pickup points — try Overpass first, fall back to CSV
    print("Querying drivable roads inside isochrone …")
    road_lines = fetch_drivable_roads(poly)

    if road_lines is None:
        # CSV fallback — load candidates directly, skip sampling entirely
        print("  Using CSV candidates directly …")
        candidates = _load_csv_candidates(poly)
    else:
        print(f"  {len(road_lines)} road segment(s) found.")
        if not road_lines:
            raise RuntimeError(
                "No drivable roads found inside the isochrone. "
                "Try a different address or increase the walk time."
            )
        # 4. Sample candidate pickup points from road lines
        print("Sampling candidate pickup points …")
        candidates = generate_candidates(road_lines, max_candidates=MAX_CANDIDATES)
        print(f"  {len(candidates)} candidate(s) generated "
              f"(spacing = {SAMPLE_SPACING} m, max = {MAX_CANDIDATES}).")
        if not candidates:
            raise RuntimeError("No candidate pickup points could be generated.")

    # 5. Beam search — intelligently explores candidates, minimising API calls
    print("Running beam search over candidates …")
    origin_fare, priced_results, exploration = beam_search_fares(
        candidates=candidates,
        origin_lat=origin_lat,
        origin_lon=origin_lon,
        dest_lat=dest_lat,
        dest_lon=dest_lon,
    )

    best = next((r for r in priced_results if r["fare_cents"] is not None), None)

    return {
        "origin": {
            "address":    pickup_address,
            "lat":        origin_lat,
            "lon":        origin_lon,
            "fare_cents": origin_fare,
        },
        "destination": {
            "address": destination_address,
            "lat":     dest_lat,
            "lon":     dest_lon,
        },
        "candidates":     priced_results,
        "best_candidate": best,
        # exploration_order: 1-based candidate_ids in visit order
        # — pass to the frontend to drive step-by-step animation
        "exploration_order": [exploration[i] + 1 for i in range(len(exploration))],
        # all_candidates: full pool before beam-search pruning
        # — used by save_debug_map() to draw the grey "not visited" dots
        "all_candidates": [{"lat": lat, "lon": lon}
                           for lat, lon in candidates],
    }


# ---------------------------------------------------------------------------
# Debug visualization  (folium — open the output HTML in any browser)
# ---------------------------------------------------------------------------

def save_debug_map(
    result: dict,
    all_candidates: list[tuple[float, float]],
    out_html: str = "debug_map.html",
) -> None:
    """
    Render a folium map showing exactly what the beam search did.

    Layers
    ------
    • Isochrone polygon          – blue outline (not available here, skipped)
    • Origin marker              – blue pin
    • Unvisited candidates       – small grey dots (beam search never reached these)
    • Visited candidates         – circles coloured green→amber→red by fare,
                                   labelled with their beam-step number so you
                                   can trace the exact search path
    • Best candidate             – large green star marker

    Parameters
    ----------
    result          : dict returned by find_best_pickup()
    all_candidates  : the full list[(lat, lon)] before beam search pruning,
                      so we can draw the grey "pruned" dots too
    out_html        : filename to write
    """
    try:
        import folium
        from branca.colormap import LinearColormap
        from folium.features import DivIcon
    except ImportError:
        print("  [debug map] folium / branca not installed — skipping.\n"
              "  Run: pip install folium branca")
        return

    origin   = result["origin"]
    visited  = result["candidates"]       # already sorted cheapest-first
    best     = result["best_candidate"]

    # Centre the map on the origin
    m = folium.Map(location=[origin["lat"], origin["lon"]], zoom_start=15)

    # ------------------------------------------------------------------
    # Fare colour scale (only over visited nodes that have a price)
    # ------------------------------------------------------------------
    priced_fares = [r["fare_cents"] for r in visited if r["fare_cents"] is not None]
    if priced_fares:
        colormap = LinearColormap(
            colors=["#16a34a", "#f59e0b", "#dc2626"],   # green → amber → red
            vmin=min(priced_fares),
            vmax=max(priced_fares),
        )
        colormap.caption = "Estimated fare ($)"
        colormap.add_to(m)
    else:
        colormap = None

    # ------------------------------------------------------------------
    # Unvisited (pruned) candidates — grey dots
    # ------------------------------------------------------------------
    visited_ids = {r["candidate_id"] - 1 for r in visited}   # 0-based indices
    unvisited_group = folium.FeatureGroup(name="Unvisited candidates (pruned)", show=True)

    for idx, (lat, lon) in enumerate(all_candidates):
        if idx in visited_ids:
            continue
        folium.CircleMarker(
            location=[lat, lon],
            radius=4,
            color="#9ca3af",       # tailwind gray-400
            weight=1,
            fill=True,
            fill_color="#d1d5db",  # tailwind gray-300
            fill_opacity=0.6,
            tooltip=f"Pruned candidate {idx + 1} — not visited by beam search",
        ).add_to(unvisited_group)

    unvisited_group.add_to(m)

    # ------------------------------------------------------------------
    # Visited candidates — coloured circles + beam-step labels
    # ------------------------------------------------------------------
    # Re-sort by beam_step so the labels make visual sense on the map
    visited_by_step = sorted(visited, key=lambda r: r["beam_step"])
    visited_group   = folium.FeatureGroup(name="Visited candidates (beam search)", show=True)

    for row in visited_by_step:
        fare     = row["fare_cents"]
        step     = row["beam_step"]
        is_best  = (best is not None and row["candidate_id"] == best["candidate_id"])

        fill_color = colormap(fare) if (colormap and fare is not None) else "#6b7280"
        fare_str   = f"${fare / 100:.2f}" if fare is not None else "n/a"
        savings    = row["savings_cents"]
        saving_str = (f"saves ${savings / 100:.2f}" if savings and savings > 0
                      else ("no saving" if savings is not None else "n/a"))

        # Slightly larger ring for the best node
        radius = 10 if is_best else 7

        folium.CircleMarker(
            location=[row["lat"], row["lon"]],
            radius=radius,
            color="#111827",
            weight=3 if is_best else 1,
            fill=True,
            fill_color=fill_color,
            fill_opacity=0.95,
            tooltip=f"Step {step} | fare {fare_str} | {saving_str}",
            popup=folium.Popup(
                html=(
                    f"<b>Beam step:</b> {step}<br>"
                    f"<b>Candidate ID:</b> {row['candidate_id']}<br>"
                    f"<b>Fare:</b> {fare_str}<br>"
                    f"<b>Savings vs origin:</b> {saving_str}<br>"
                    f"<b>Walking dist:</b> {row['walking_dist_m']} m<br>"
                    f"<b>Lat/Lon:</b> {row['lat']:.6f}, {row['lon']:.6f}"
                    + ("<br><b>⭐ BEST CANDIDATE</b>" if is_best else "")
                ),
                max_width=300,
            ),
        ).add_to(visited_group)

        # Beam-step number label floated on top of the circle
        folium.Marker(
            location=[row["lat"], row["lon"]],
            icon=DivIcon(
                icon_size=(20, 20),
                icon_anchor=(10, 10),
                html=(
                    f'<div style="'
                    f'font-size:9px;font-weight:700;color:#111827;'
                    f'text-align:center;line-height:20px;'
                    f'width:20px;height:20px;">'
                    f'{"★" if is_best else step}'
                    f'</div>'
                ),
            ),
        ).add_to(visited_group)

    visited_group.add_to(m)

    # ------------------------------------------------------------------
    # Origin marker
    # ------------------------------------------------------------------
    origin_fare_str = (f"${origin['fare_cents'] / 100:.2f}"
                       if origin["fare_cents"] is not None else "n/a")
    folium.Marker(
        location=[origin["lat"], origin["lon"]],
        popup=folium.Popup(
            html=(
                f"<b>Origin</b><br>"
                f"{origin['address']}<br>"
                f"<b>Fare from here:</b> {origin_fare_str}"
            ),
            max_width=300,
        ),
        tooltip=f"Origin — fare {origin_fare_str}",
        icon=folium.Icon(color="blue", icon="user", prefix="fa"),
    ).add_to(m)

    # ------------------------------------------------------------------
    # Best candidate — prominent green star marker
    # ------------------------------------------------------------------
    if best:
        best_fare_str    = f"${best['fare_cents'] / 100:.2f}" if best["fare_cents"] else "n/a"
        best_saving_str  = (f"${best['savings_cents'] / 100:.2f}"
                            if best["savings_cents"] is not None else "n/a")
        folium.Marker(
            location=[best["lat"], best["lon"]],
            popup=folium.Popup(
                html=(
                    f"<b>⭐ Best pickup</b><br>"
                    f"<b>Fare:</b> {best_fare_str}<br>"
                    f"<b>Saves:</b> {best_saving_str} vs. origin<br>"
                    f"<b>Walk:</b> {best['walking_dist_m']} m<br>"
                    f"<b>Found at beam step:</b> {best['beam_step']}"
                ),
                max_width=300,
            ),
            tooltip=f"⭐ Best — {best_fare_str} (saves {best_saving_str})",
            icon=folium.Icon(color="green", icon="star", prefix="fa"),
        ).add_to(m)

    # ------------------------------------------------------------------
    # Layer control + save
    # ------------------------------------------------------------------
    folium.LayerControl(collapsed=False).add_to(m)
    m.save(out_html)
    print(f"  Debug map saved → {out_html}  (open in any browser)")


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    pickup_addr = input("Enter pickup address:      ").strip()
    dest_addr   = input("Enter destination address: ").strip()

    result = find_best_pickup(pickup_addr, dest_addr)

    origin = result["origin"]
    best   = result["best_candidate"]

    print("\n" + "=" * 60)
    print("RESULTS")
    print("=" * 60)
    print(f"Origin:  {origin['address']}")
    print(f"         fare = {origin['fare_cents']} cents "
          f"(${(origin['fare_cents'] or 0) / 100:.2f})")

    if best:
        savings_usd = (best["savings_cents"] or 0) / 100
        print(f"\nBest pickup found by beam search:")
        print(f"  coordinates  : ({best['lat']:.6f}, {best['lon']:.6f})")
        print(f"  fare         : {best['fare_cents']} cents "
              f"(${best['fare_cents'] / 100:.2f})")
        print(f"  savings      : ${savings_usd:.2f} vs. origin")
        print(f"  walking dist : {best['walking_dist_m']} m")
        print(f"  visited at   : beam step {best['beam_step']} "
              f"of {len(result['candidates'])}")
    else:
        print("\nNo priced candidates returned.")

    # Save full result as JSON — useful for debugging and frontend development
    out_file = "smart_pickup_results.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
    print(f"\nFull results saved → {out_file}")

    # Save debug map — open debug_map.html in a browser to inspect the run
    print("\nSaving debug map …")
    all_candidates = [(c["lat"], c["lon"]) for c in result["all_candidates"]]
    save_debug_map(result, all_candidates=all_candidates, out_html="debug_map.html")