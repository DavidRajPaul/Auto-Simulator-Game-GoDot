"""Shared config for the Chennai OSM → Godot world pipeline (Phase 2)."""

# Original playable map bounds restored; keep the original coordinate origin so existing city content remains aligned.
# Bounding box: (south, west, north, east).
BBOX = (13.028, 80.230, 13.070, 80.288)
ORIGIN = (13.049, 80.259)

# 1.0 = real size. Real lane geometry (osm2streets) and real building outlines only line up at 1:1.
# (Phases 2–4 used a 1 : 2.5 compressed map; fares then counted "real-equivalent" km.)
MAP_SCALE = 1.0
CHUNK_SIZE_M = 250.0

# Zone cores (real lat/lon, radius in real metres). Density is the deterministic
# probability of adding a procedural infill plot, NOT a multiplier on real OSM
# footprints. Preserve Marina's open beach character and avoid 100% citywide.
# Raster checks in build_world.py still reject roads, walks and water.
ZONES = {
    "marina":     {"name": "Marina Beach & Kamarajar Salai", "center": (13.0520, 80.2800), "radius": 900.0,
                   "bld_height": (5.0, 14.0), "bld_density": 0.45},
    "mylapore":   {"name": "Mylapore Heritage Tank", "center": (13.0335, 80.2690), "radius": 700.0,
                   "bld_height": (5.0, 11.0), "bld_density": 1.0},
    "anna_salai": {"name": "Anna Salai (Mount Road)", "center": (13.0590, 80.2560), "radius": 900.0,
                   "bld_height": (10.0, 34.0), "bld_density": 1.0},
    "t_nagar":    {"name": "T. Nagar Usman Road", "center": (13.0410, 80.2340), "radius": 800.0,
                   "bld_height": (9.0, 26.0), "bld_density": 1.0},
}
DEFAULT_ZONE_STYLE = {"bld_height": (6.0, 16.0), "bld_density": 0.94}

# Real-world landmark positions (approximate, hand-checked against OSM). Placeholder shapes in Phase 2,
# replaced with low-poly GLTF hero models in Phase 5.
LANDMARKS = [
    {"id": "marina_lighthouse", "name": "Marina Lighthouse", "lat": 13.0398, "lon": 80.2797, "kind": "lighthouse"},
    # Midway along the two OSM Napier Bridge carriageways (ways 24888589 / 28295242) over the Cooum.
    {"id": "napier_bridge", "name": "Napier Bridge", "lat": 13.06875, "lon": 80.28448, "kind": "bridge"},
    # Vivekanandar Illam stands on the LAND side of Kamarajar Salai facing the sea (Nov 27: it sat on the
    # beach side); "yaw" turns its curved front (-Z of LandmarkKit.vivekananda_house) to face east.
    {"id": "vivekananda_house", "name": "Vivekananda House", "lat": 13.049054, "lon": 80.280319, "kind": "heritage", "yaw": -1.571},
    # kind "temple": drawn by the procedural model in data/world/landmark_models.json (make_landmarks.py).
    {"id": "kapaleeshwarar", "name": "Kapaleeshwarar Temple", "lat": 13.033807, "lon": 80.269876, "kind": "temple"},
    {"id": "chitrakulam_tank", "name": "Mylapore Temple Tank", "lat": 13.03354, "lon": 80.268701, "kind": "tank"},
    # The real LIC (OSM way 1110170916; Wikipedia 13.064283, 80.266065); drawn by landmark_models.json.
    {"id": "lic_building", "name": "LIC Building", "lat": 13.06425, "lon": 80.26609, "kind": "model"},
    {"id": "gemini_flyover", "name": "Gemini Flyover", "lat": 13.0558, "lon": 80.2503, "kind": "flyover"},
    {"id": "panagal_park", "name": "Panagal Park", "lat": 13.04066, "lon": 80.23314, "kind": "park"},  # OSM way 209513246
    # Imported GLBs are placed via city_props, not generic landmark placeholders.

]

# Auto stands = player spawn / passenger hubs (Phase 3).
AUTO_STANDS = [
    {"id": "stand_mylapore", "name": "Mylapore Tank Auto Stand", "lat": 13.0342, "lon": 80.2688},
    {"id": "stand_marina", "name": "Marina Lighthouse Auto Stand", "lat": 13.0410, "lon": 80.2790},
    {"id": "stand_tnagar", "name": "Panagal Park Auto Stand", "lat": 13.0412, "lon": 80.2362},
]

# highway class → (default total width m, default lanes per direction, keep everywhere? else zones only)
ROAD_CLASSES = {
    "motorway": (20.0, 3, True), "trunk": (18.0, 3, True), "primary": (14.0, 2, True),
    "secondary": (11.0, 2, True), "tertiary": (9.0, 1, True),
    "unclassified": (7.0, 1, True), "residential": (6.5, 1, True), "living_street": (5.5, 1, True),
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

# Monsoon waterlogging spots (only flooded while it rains). Approximate, near roads known to flood;
# depth ≥ 0.28 m stalls a petrol/LPG auto, shallower ones just splash and slow you down.
FLOOD_SPOTS = [
    {"id": "flood_usman_road", "name": "Usman Road", "lat": 13.0405, "lon": 80.2335, "depth": 0.34, "r": 10.0},
    {"id": "flood_luz", "name": "Luz Corner", "lat": 13.0355, "lon": 80.2660, "depth": 0.22, "r": 9.0},
    {"id": "flood_royapettah", "name": "Royapettah High Road", "lat": 13.0480, "lon": 80.2625, "depth": 0.22, "r": 9.0},
    {"id": "flood_santhome", "name": "Santhome High Road", "lat": 13.0330, "lon": 80.2775, "depth": 0.3, "r": 10.0},
    {"id": "flood_gemini", "name": "Anna Salai, Gemini", "lat": 13.0545, "lon": 80.2520, "depth": 0.24, "r": 11.0},
]

# The Cooum from the Buckingham Canal mouth, under Napier Bridge, to the sea (world x, z), hand
# traced (Nov 27): OSM maps this stretch as a multipolygon relation, which fetch_osm.py does not
# download. South bank west -> east along Swami Sivananda Salai, then the north bank back west.
# Applied by tools/osm/add_cooum_napier.py (merged with the canal mouth and upstream water).
COOUM_NAPIER = [
    (2404.0, -2312.0), (2470.0, -2298.0), (2530.0, -2299.0), (2557.0, -2297.0), (2568.0, -2250.0), (2552.0, -2180.0),
    (2541.0, -2104.0),
    (2566.0, -2103.0), (2600.0, -2116.0), (2660.0, -2122.0), (2720.0, -2125.0), (2780.0, -2128.0), (2860.0, -2128.0),
    (2960.0, -2118.0), (3060.0, -2102.0), (3160.0, -2088.0), (3260.0, -2082.0), (3360.0, -2084.0), (3440.0, -2088.0),
    (3505.0, -2084.0), (3530.0, -2084.0), (3530.0, -2160.0),  # out into the sea: the mouth has no bank
    (3443.0, -2160.0), (3380.0, -2158.0), (3300.0, -2150.0), (3230.0, -2142.0), (3170.0, -2140.0), (3106.0, -2165.0),
    (3040.0, -2185.0), (2975.0, -2205.0), (2890.0, -2232.0), (2850.0, -2240.0), (2790.0, -2244.0), (2760.0, -2250.0),
    (2700.0, -2252.0), (2640.0, -2268.0), (2580.0, -2305.0), (2520.0, -2328.0), (2470.0, -2345.0), (2434.0, -2345.0),
]
