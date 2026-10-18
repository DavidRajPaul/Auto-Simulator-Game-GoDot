"""Shared config for the Chennai OSM → Godot world pipeline (Phase 2)."""

# Bounding box covering Marina, Mylapore and Anna Salai → T. Nagar (south, west, north, east).
BBOX = (13.028, 80.230, 13.070, 80.288)
ORIGIN = ((BBOX[0] + BBOX[2]) / 2.0, (BBOX[1] + BBOX[3]) / 2.0)

# Game world is a compressed 1:2.5 representation (tech spec: stylised, compressed city).
# Road *widths* stay real-size so the auto and traffic still fit.
MAP_SCALE = 0.4
CHUNK_SIZE_M = 250.0

# Zone cores (real lat/lon, radius in real metres). Residential streets are only kept inside these.
ZONES = {
    "marina":     {"name": "Marina Beach & Kamarajar Salai", "center": (13.0520, 80.2800), "radius": 900.0,
                   "bld_height": (5.0, 14.0), "bld_density": 0.45},
    "mylapore":   {"name": "Mylapore Heritage Tank", "center": (13.0335, 80.2690), "radius": 700.0,
                   "bld_height": (5.0, 11.0), "bld_density": 0.95},
    "anna_salai": {"name": "Anna Salai (Mount Road)", "center": (13.0590, 80.2560), "radius": 900.0,
                   "bld_height": (10.0, 34.0), "bld_density": 0.85},
    "t_nagar":    {"name": "T. Nagar Usman Road", "center": (13.0410, 80.2340), "radius": 800.0,
                   "bld_height": (9.0, 26.0), "bld_density": 1.0},
}
DEFAULT_ZONE_STYLE = {"bld_height": (6.0, 16.0), "bld_density": 0.6}

# Real-world landmark positions (approximate, hand-checked against OSM). Placeholder shapes in Phase 2,
# replaced with low-poly GLTF hero models in Phase 5.
LANDMARKS = [
    {"id": "marina_lighthouse", "name": "Marina Lighthouse", "lat": 13.0398, "lon": 80.2797, "kind": "lighthouse"},
    {"id": "napier_bridge", "name": "Napier Bridge", "lat": 13.0676, "lon": 80.2817, "kind": "bridge"},
    {"id": "vivekananda_house", "name": "Vivekananda House", "lat": 13.0491, "lon": 80.2808, "kind": "heritage"},
    {"id": "kapaleeshwarar", "name": "Kapaleeshwarar Temple", "lat": 13.0337, "lon": 80.2696, "kind": "gopuram"},
    {"id": "chitrakulam_tank", "name": "Mylapore Temple Tank", "lat": 13.0330, "lon": 80.2706, "kind": "tank"},
    {"id": "lic_building", "name": "LIC Building", "lat": 13.0627, "lon": 80.2617, "kind": "tower"},
    {"id": "gemini_flyover", "name": "Gemini Flyover", "lat": 13.0558, "lon": 80.2503, "kind": "flyover"},
    {"id": "panagal_park", "name": "Panagal Park", "lat": 13.0405, "lon": 80.2354, "kind": "park"},
]

# Auto stands = player spawn / passenger hubs (Phase 3).
AUTO_STANDS = [
    {"id": "stand_mylapore", "name": "Mylapore Tank Auto Stand", "lat": 13.0342, "lon": 80.2688},
    {"id": "stand_marina", "name": "Marina Lighthouse Auto Stand", "lat": 13.0410, "lon": 80.2790},
    {"id": "stand_tnagar", "name": "Panagal Park Auto Stand", "lat": 13.0412, "lon": 80.2362},
]

# highway class → (default total width m, default lanes per direction, keep everywhere?)
ROAD_CLASSES = {
    "motorway": (20.0, 3, True), "trunk": (18.0, 3, True), "primary": (14.0, 2, True),
    "secondary": (11.0, 2, True), "tertiary": (9.0, 1, True),
    "unclassified": (7.0, 1, False), "residential": (6.5, 1, False), "living_street": (5.5, 1, False),
}
LANE_WIDTH_M = 3.3

# Service points (Phase 4). Positions are near real arterials; names are generic (no brands).
# kind: "lpg" (autogas bunk), "ev" (charging kiosk), "garage" (Puncture & Tinkering shed).
SERVICES = [
    {"id": "lpg_royapettah", "name": "Royapettah LPG Bunk", "kind": "lpg", "lat": 13.0545, "lon": 80.2640},
    {"id": "lpg_mylapore", "name": "Mylapore LPG Bunk", "kind": "lpg", "lat": 13.0365, "lon": 80.2650},
    {"id": "lpg_teynampet", "name": "Teynampet LPG Bunk", "kind": "lpg", "lat": 13.0450, "lon": 80.2510},
    {"id": "lpg_tnagar", "name": "T. Nagar LPG Bunk", "kind": "lpg", "lat": 13.0440, "lon": 80.2400},
    {"id": "ev_marina", "name": "Marina EV Kiosk", "kind": "ev", "lat": 13.0470, "lon": 80.2795},
    {"id": "ev_anna_salai", "name": "Anna Salai EV Kiosk", "kind": "ev", "lat": 13.0600, "lon": 80.2600},
    {"id": "ev_panagal", "name": "Panagal Park EV Kiosk", "kind": "ev", "lat": 13.0398, "lon": 80.2372},
    {"id": "garage_mylapore", "name": "Mylapore Puncture & Tinkering", "kind": "garage", "lat": 13.0349, "lon": 80.2683},
    {"id": "garage_marina", "name": "Marina Puncture & Tinkering", "kind": "garage", "lat": 13.0420, "lon": 80.2786},
    {"id": "garage_tnagar", "name": "T. Nagar Puncture & Tinkering", "kind": "garage", "lat": 13.0420, "lon": 80.2370},
]
