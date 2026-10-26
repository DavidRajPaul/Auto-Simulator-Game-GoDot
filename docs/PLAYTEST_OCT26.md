# Play-test feedback pass — 26 Oct 2026

Branch `feat/playtest-fixes-oct26`. All 7 headless suites green (`tests/run_phase1…7_tests.tscn`).

| # | Feedback | Status | What changed |
|---|----------|--------|--------------|
| 1 | Shaky driving | Done | Physics interpolation on; camera reads the interpolated pose; cockpit "neck" stabiliser (yaw tight, pitch/roll softened). `CameraRig.gd` |
| 2 | Fast-moving shadows in cockpit | Done | Sun moves in 3° steps with a 2.5 s ease (was re-aimed 4×/s → texel crawl); own-vehicle shadows off in cockpit; shadow bias/blur tuned. `Atmosphere.gd` |
| 3 | Static splash / frozen loading | Done | Painted "LOADING…" pill removed from the boot image; new live splash scene with real threaded progress. `SplashScreen.gd` |
| 4 | Full map + real street boards | Done | Tap mini-map → full OSM map (EN + Tamil names, pan/pinch/zoom, POIs). Junction street-name boards with real OSM names. `FullMap.gd`, `StreetSigns.gd`, `tools/osm/attach_road_names.py` |
| 5 | Riderless scooters | Done | Seated helmeted rider on every two-wheeler. `PersonMesh.gd` |
| 6 | Remove cows | Done | `stray_cattle_enabled = false` (code kept). |
| 7 | Stricter bargaining | Done | Markup judged against the meter, star rating, greed streak, demand; lower base odds; bigger respect hit for greedy refusals. `FareCalculator.gd` |
| 8 | Boxes at pickups | Done | 5 people styles (shirt, veshti, saree + bag, tourist, jeans) waving. |
| 9 | Bad guide line | Done | Sat-nav ribbon in the left lane, rounded, flowing chevrons, trimmed behind you; turn-by-turn banner. `GpsRoute.gd`, `RouteLine.gd`, `NavBanner.gd` |
| 10 | Bad collisions | Done | Low-friction bouncy chamfered hull (glancing hits slide: 0.3 → 2.8 m/s), contact-based impact speed, post-impact anti-spin, AI stops & honks when hit, crunch/scrape SFX, sparks, shake, haptics. `CollisionFX.gd` |
| 11 | Traffic by real peak hours | Done | TomTom Traffic Index 2025 Chennai hourly profile × zone weights → 5–18 vehicles, rush-hour crawl, feeds haggling demand. `TrafficDensity.gd` |
| 12 | Real building/road sizes | Pipeline ready | Roads already 1 : 1 OSM + osm2streets lanes. Heights: `tools/osm/apply_building_heights.py` samples Google Open Buildings 2.5D (CC BY 4.0 / ODbL) — needs the raster export (one manual Earth Engine step). |
| 13 | Ad placeholders | Done | `AdMonetizationManager` autoload + `ad_config.tres`; mock placeholder provider; AdMob bridge stub. |
| 14 | Rewards engine | Done | `RewardsEngine.gd`: idempotent ledger, daily caps, 7-day login calendar, 11 achievements (Play Games id slots), rewarded 2× fare / half tank / free tow. |
| 15 | Assets + performance | Done (perf) | `closest_point` 10 ms → 0.02 ms (segment grid), route build 11 → 2.7 ms, windowed guidance search, 60 FPS cap, RAM-based default graphics. Asset list below. |
| 16 | Music | Plan below | Licensing needed for film songs. |

## Assets still worth getting
1. **MTC bus model** — still a grey box. Low-poly bus, ≤ 1,200 tris, re-texture white/blue (Quaternius / Kenney CC0 bus).
2. **Hero landmarks** — Marina Lighthouse, Kapaleeshwarar gopuram, Napier Bridge, LIC Building as low-poly GLB (≤ 4,000 tris each).
3. **Cockpit interior** — handlebar, meter box, mirrors, jasmine garland (ties into the cockpit view fix).
4. **Animated pedestrians** (optional) — current people are static procedural; Quaternius "Ultimate Animated Characters" (CC0) if you want walking crowds.
5. **Audio** — real 2-stroke idle/rev loops, 2 more horn tiers, Tamil street crowd ambience; music (below).

## Music plan (Ilaiyaraaja / Deva)
Film songs are copyrighted; shipping them needs a licence from the label/publisher (Ilaiyaraaja has actively enforced rights over his compositions). Options: (a) license a handful of tracks, (b) commission originals in that style, (c) let the player's own music app keep playing (verify Godot doesn't grab Android audio focus).

Mood references per screen:
- **Main menu:** Deva's *"Naan Autokaaran"* (Baasha, 1995) — the auto-driver anthem.
- **Daytime driving radio:** Ilaiyaraaja *"Ilamai Itho Itho"*, *"Rakkamma Kaiya Thattu"*; Deva gaana *"Vandhenda Paalkaaran"* (Annamalai).
- **Night / monsoon:** Ilaiyaraaja *"Poongatru Thirumbuma"*, *"En Iniya Pon Nilave"*, *"Sundari Kannal"*.
- **Achievement / level-up:** 2–3 s original nadaswaram + thavil flourish.
- **Fare paid:** coin + parai hit. **Shift end:** slow flute/strings outro.
