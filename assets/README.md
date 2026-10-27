# 🎨 Namma Auto — game assets

Every file the game ships (audio, fonts, models, textures, UI art, icons) lives in this folder.
Nothing outside `assets/` is art: code builds the rest (the procedural auto body, the city from
OpenStreetMap, the landmark lighthouse and gopuram, the synth fallback sounds).

```text
assets/                    ← game-ready files, committed, exported in the APK/AAB
assets_src/incoming/       ← raw downloads (WAV/MP3, Sketchfab glTF, Stitch PNGs), NOT exported, mostly git-ignored
tools/assets/, tools/art/  ← scripts that turn assets_src/incoming into assets/
docs/ASSETS.md             ← shopping list: where to download more, with checked licences
```

**Licence rule:** CC0, CC BY or the Pixabay Content Licence only. No NC (non-commercial),
Sketchfab "Standard"/"Editorial", or likenesses of real people. Every CC BY file must appear in
the in-game Credits text (`CREDITS` in `scripts/ui/MainMenu.gd`).

## How to add or improve an asset

1. **Drop the raw file** in `assets_src/incoming/<category>/` (`audio/`, `models/`, `art/`, `textures/`, …)
   and add a row to `assets_src/incoming/SOURCES.md` (file, link, author, licence).
2. **Run the matching tool** (table below). It writes the optimised file into `assets/…` and
   updates that folder's `CREDITS_*.md`.
3. **Keep the file name** when you *replace* an asset: the code loads fixed paths, so a better
   `horn_bulb.ogg` or `bus_tnstc.glb` drops straight in. A *new* asset needs a line of code
   (or a JSON manifest entry) that loads it.
4. **Credit it**: add CC BY authors to `CREDITS` in `scripts/ui/MainMenu.gd`.
5. **Check it**: `godot --headless --path . --import`, run the test suites and the perf probe
   (≤ 150 draw calls). Models: check the facing with a side render (glTF faces +Z, traffic drives −Z).

| Category | Folder | Rebuild / import tool | Budget |
|---|---|---|---|
| Vehicle sounds, horns, ambience | `audio/vehicle`, `audio/ambience`, `audio/traffic` | `python3 tools/assets/process_incoming.py` (cut, loop crossfade, normalise, mono Vorbis 96 kbps) | whole `audio/` ≤ 5 MB |
| CC0 sounds that can be downloaded by CI | `audio/ambience`, `audio/traffic` | `tools/assets/fetch_assets.py` → **Actions → Fetch Assets** | |
| UI sounds | `audio/ui` | copied from Kenney Interface Sounds | |
| Traffic and player auto models | `models/traffic`, `models/vehicles` | `python3 tools/assets/process_models.py` (gltf-transform: decimate, 256–1024 px textures) | 1.4k–6.3k tris each |
| People (walk + idle) | `models/people` | `python3 tools/assets/process_people.py` (22-bone rig, retargeted walk/idle, one atlas, `people.json`) | 1 draw call each |
| Landmarks, police, service vehicles | `models/city`, `models/people/police_*`, `models/traffic/svc_*` | `python3 tools/assets/process_city.py` (one-draw-call static GLB) | |
| Impact FX textures | `fx` | `tools/assets/fetch_fx.py` → **Actions → Fetch FX Textures** | |
| Facade atlas (building skins) | `textures` | `python3 tools/art/make_facade_atlas.py` | |
| Driving-control icons (v1) | `ui/controls_atlas.png` | `python3 tools/art/make_ui_icons.py` | |
| Painted UI art, logo, icons, splash | `ui/*_v2.png`, `ui/rewards.png`, `ui/portraits.png`, `ui/logo.png`, `ui/loading_bg.jpg`, `icon/` | `python3 tools/art/import_game_art.py` (cuts Stitch PNGs from `assets_src/incoming/art/`) | one atlas per HUD |
| Fonts | `fonts` | copy the `.ttf` + its `OFL.txt` | |

## Catalog

### 🔊 Audio — `assets/audio/` (1.9 MB)

| File | Used for (loaded by) | Source | Licence |
|---|---|---|---|
| `vehicle/engine_lpg_loop.ogg` | Stock LPG auto engine loop (`VehicleAudio.gd`) | kalhan, Freesound #261059 | CC BY 4.0 |
| `vehicle/engine_diesel_loop.ogg` | Madras King Deluxe diesel engine | recordx_media, Pixabay #199866 | Pixabay |
| `vehicle/kick_start.ogg` | Kick-start | kalhan, Freesound #261063 | CC BY 4.0 |
| `vehicle/horn_bulb.ogg` | Bulb "pom-pom" horn | alex_jauk, Pixabay | Pixabay |
| `vehicle/horn_air.ogg` | Twin / musical air-horn (pitch-shifted) | goose278, Freesound #174819 | CC0 |
| `vehicle/indicator_tick.ogg` | Indicator relay | ProductionNow, Freesound #195994 | CC0 |
| `vehicle/crash_light.ogg`, `crash_hard.ogg`, `scrape_loop.ogg` | Collisions (`CollisionFX.gd`) | synthesised for this project | CC0 |
| `ambience/city_traffic_loop.ogg` | City road bed everywhere (`AmbienceAudio.gd`) | SoundQue field recording, Pixabay #446354 | Pixabay |
| `ambience/sea_waves_loop.ogg` | Marina coast | BigSoundBank #0698 | CC0 |
| `ambience/market_loop.ogg` | Mylapore / T. Nagar / Anna Salai markets (placeholder, French market) | BigSoundBank #2728 | CC0 |
| `ambience/rain_roof_loop.ogg` | Monsoon rain on the canopy | BigSoundBank #1293 | CC0 |
| `traffic/truck_horn.ogg` | Bus / lorry honk-back | BigSoundBank #2721 | CC0 |
| `ui/click, select, back, coin, goal, level_up, refused.ogg` | Menus, fare paid, goal, level-up, "can't" (`UISfx.gd`) | Kenney Interface Sounds | CC0 |

Credits: `audio/CREDITS_vehicle.md`, `audio/CREDITS_fetched.md`, `audio/ui/LICENSE_Kenney_Interface_Sounds.txt`.
Missing files are fine: `VehicleAudio.stream_or()` falls back to the synthesised sound, so builds and tests never depend on downloads.

### 🔤 Fonts — `assets/fonts/` (1.2 MB)

| File | Used for | Licence |
|---|---|---|
| `ui/BricolageGrotesque.ttf` | Titles, buttons (`UIKit.gd`) | SIL OFL 1.1 (`ui/OFL_Bricolage.txt`) |
| `ui/Rubik.ttf` | Body text | SIL OFL 1.1 (`ui/OFL_Rubik.txt`) |
| `NotoSansTamil-Regular.ttf` | Tamil fallback for every label | SIL OFL 1.1 (`OFL.txt`) |
| `baloo_thambi_2/BalooThambi2-Variable.ttf` | Tamil + Latin display font | SIL OFL 1.1 |

### 🚗 Models — `assets/models/` (22 MB)

**Player auto** (`vehicles/`): `player_auto.glb` + 3 textures — Auto Rickshaw by rSquare (Sketchfab), CC BY 4.0, 6.3k tris. Used while the paint is stock yellow; other garage paints use the procedural body (`AutoRickshawModel.gd`).

**Traffic** (`traffic/`, loaded by `TrafficVehicleAI.gd` / `TrafficModelFit.gd` as visuals on the collision boxes):

| File | Archetype | Source | Licence |
|---|---|---|---|
| `two_wheeler.glb` | Scooter (procedural rider on top) | Indian Scooter, Shiveloper (Sketchfab) | CC BY 4.0 |
| `hatchback.glb` | Car | Kenney Car Kit | CC0 |
| `share_auto.glb` | Share auto / other autos | Auto Rickshaw, rSquare (Sketchfab) | CC BY 4.0 |
| `bus_tnstc.glb`, `bus_setc.glb` | Town bus, SETC coach | Nobel Tech (Sketchfab) | CC BY 4.0 |
| `lorry.glb` | Goods lorry | Oren garage (Sketchfab) | CC BY 4.0 |
| `stray_cow.glb`, `stray_cow_fadly.glb` | Stray cattle (off by default: `stray_cattle_enabled = false`) | Quaternius (CC0); Fadly.W (Sketchfab, CC BY 4.0) | |
| `svc_ambulance, svc_fire_truck, svc_garbage_truck, svc_police_car, svc_school_bus, svc_tow_truck.glb` | Civil service vehicles | "Generic civil service vehicles pack", Comrade1280 (Sketchfab) | CC BY 4.0 |

**People** (`people/`, `PedestrianManager.gd`, `TrafficPolice.gd`; pace and credits in `people.json`):

| File | Source | Licence |
|---|---|---|
| `old_man_veshti.glb` (+ shared walk clip) | "Indian Old man walking", anandmohan662 | CC BY 4.0 |
| `young_man.glb` | "Alex Texel A-pose", alex.texelsales | CC BY 4.0 |
| `woman_saree_violet / green / maroon.glb` (+ shared idle) | "Female test", CloudHubOmniTeam (sarees recoloured) | CC BY 4.0 |
| `woman_modern.glb` | "Modern Indian Woman", Pixel_Monster | CC BY 4.0 |
| `man_casual.glb` | "Dhanush 3d model", Peter Charles — face repainted as a generic character | CC BY 4.0 ⚠️ see audit |
| `girl_churidar.glb`, `girl_pavadai.glb` | "South Indian Women", alnmathew | CC BY 4.0 |
| `police_f_khaki.glb`, `police_m_ips.glb` | Umar; `@MgsGamer5` (uniform painted) | CC BY 4.0 |

**City** (`city/`, placed from `data/world/city_props.json`; `city_models.json` holds sizes and credits):
`chennai_central.glb` (SudharsanArivalagan), `water_tower.glb` (TamilarasanRG), `slum_cluster.glb` (aswin.baskaran),
`gas_station.glb` (Karim.Fares, rebranded as the fictional NAMMA GAS) — all Sketchfab, CC BY 4.0.
The Marina lighthouse and Kapaleeshwarar-style gopuram are **procedural** (`scripts/world/LandmarkKit.gd`) because the free models are NC-licensed.

Credits: `models/CREDITS_models.md`, `models/city/CREDITS_city.md`, `models/people/CREDITS_people.md`, `models/people/CREDITS_static.md`, `models/traffic/CREDITS_static.md`.

### ✨ FX — `assets/fx/` (232 KB)

`smoke_a/b/c`, `puff_a/b`, `puff_black`, `dirt_a/b`, `spark_streak`, `flare`, `scorch.png` — impact sparks, dust and smoke (`CollisionFX.gd`; the future damage smoke will reuse them). Kenney *Particle Pack* + *Smoke Particle Assets*, CC0 (`CREDITS_fx.md`, `MANIFEST.txt`).

### 🧱 Textures — `assets/textures/` (148 KB)

| File | Used for | Source |
|---|---|---|
| `facade_atlas.png` | Chennai building skins: grilled windows, sunshades, balconies, AC units, shops with Tamil/English boards, temple stripes (`shaders/building_facade.gdshader`) | generated by `tools/art/make_facade_atlas.py` (ours) |
| `facade_glow.png` | Windows and shops lit at night | same |

### 🖼️ UI art — `assets/ui/` (5 MB)

| File | Used for | Source |
|---|---|---|
| `controls_v2.png` | Driving buttons, pause, touch ripple (one atlas, `TouchHUD.ART_CELLS`) | Stitch art 2B–2I via `import_game_art.py` (ours) |
| `hud_v2.png` | Speedometer, LPG dial, needle, mini-map ring and pins, fare meter, ribbons | Stitch 3A–3E (ours) |
| `rewards.png` | Coins, stars, XP, LPG, tick, gift, padlock, rank badges (`UIKit.gd`) | Stitch 5A–5B (ours) |
| `portraits.png` | Rider portraits on the haggle card | Stitch 4F–4G (ours) |
| `logo.png` | Menu logo with Tamil subtitle | Stitch 1G (ours) |
| `loading_bg.jpg` | Splash and loading screen | Stitch 1F (ours) |
| `controls_atlas.png` | v1 control icons (fallback) | `make_ui_icons.py` (ours) |

### 📱 App icon and splash — `assets/icon/` (1.9 MB)

`icon.png` (512 px, project icon), `icon_192.png`, `adaptive_fg/bg/mono_432.png` (Android adaptive icon, set in `export_presets.cfg`), `boot_splash.png` (engine boot splash). Stitch 1B, 1D, 1E via `import_game_art.py` (ours).

## Procedural (no files)

| What | Where |
|---|---|
| Player auto body for custom paints, wheels | `scripts/vehicle/AutoRickshawModel.gd`, `WheelModel.gd`, `MeshKit.gd` |
| City: roads, 21.6k buildings, detail (sunshades, parapets, Sintex tanks, awnings), EB poles, wires, trees | `scripts/world/WorldChunkStreamer.gd` from `data/world/` (OpenStreetMap, ODbL) |
| Lighthouse, gopuram | `scripts/world/LandmarkKit.gd` |
| Scooter riders, waving riders at pickups | `scripts/world/PersonMesh.gd` |
| Street-name boards, building name boards | `scripts/world/StreetSigns.gd`, `BuildingBoards.gd` (real OSM names) |
| Menu skyline | `scripts/ui/ChennaiBackdrop.gd` |
| Rain, windscreen drops, wiper | `shaders/rain_overlay.gdshader` |
| Fallback engine putter, EV whine, horn, kick clunk | `scripts/vehicle/VehicleAudio.gd` |

## Wanted next

From the roadmap (README → Roadmap) and `docs/PLAYTEST_OCT26.md`:

- **Voice:** ≈ 20 tutorial + ≈ 70 mission lines, Tamil + English (`TutorialStep.voice_path` is already wired).
- **Portraits:** Murugan Anna (mentor) + 8 mission characters → add cells to `ui/portraits.png`.
- **Damage:** smoke puff and scratch/dent decal textures (in-house).
- **Mission board** model for the auto stands.
- **Cockpit interior:** handlebar, meter box, mirrors, jasmine garland.
- **Hero landmarks:** Napier Bridge, LIC Building as low-poly GLB (≤ 4,000 tris).
- **Audio:** cockpit cabin bed, gravel, bumps and boarding sounds from the kalhan pack (clips listed in `docs/ASSETS.md`); Chennai recordings (T. Nagar crowd, temple bells, tea kadai); a real market loop.
- **Music:** licensed or commissioned (see the music plan in `docs/PLAYTEST_OCT26.md`).

## Licence audit (Oct 2026)

Open items found while writing this catalog — fix before a store release (roadmap Phase 11):

- The Credits text in `MainMenu.gd` lists *"Indian Woman in Saree" by Pixel_Monster (Sketchfab Standard licence)*, but the shipped file is *"Modern Indian Woman"* by Pixel_Monster, **CC BY 4.0**. Standard-licence assets are not allowed; correct the credit line.
- Not yet in the Credits text: Peter Charles (`man_casual`), Umar and `@MgsGamer5` (police), Comrade1280 (service vehicles), Karim.Fares (gas station), Kenney particle packs (CC0, optional).
- `man_casual.glb` comes from a model named after a real actor. The face is repainted, but the project rule bans likenesses of real people; consider replacing it.
