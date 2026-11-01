# Chennai buses, routes and stops in the game

This is the research behind the bus liveries (`tools/assets/bake_ebus.py`), the real bus stops (`tools/osm/build_bus_stops.py`) and the way buses behave at stops (`TrafficVehicleAI._bus_stop_gap`). It was compiled in November 2026.

## One model, every livery

The owner made the electric bus with Tripo AI. The raw file was 60 MB with 1.9 million triangles and a shuffled 512 px texture atlas. `bake_ebus.py` turns it into small game models:

1. **Simplify.** It simplifies the shape to about 5,000 triangles.
2. **Classify.** It reads each triangle's original colour and sorts it into a part: tyre, rim, glass, interior, lamps or mirror. Everything else is painted body.
3. **Cut zones.** It cuts the body at fixed heights into skirt, stripe, body, belt line, window band, roof band and roof. Each livery band then gets a straight edge.
4. **Lengthen.** It repeats the window bay between the axles, the way a coachbuilder makes a longer body. This turns the stubby source, a 6–7 m midi bus at real width, into a 10 m city bus, a 7.5 m small bus or an 8.8 m college bus, with round wheels and normal windows.
5. **Paint.** It paints every livery as one vertex-coloured mesh with one material. Each bus is about 11,700 triangles, about 0.37 MB and one draw call.

| Game id | Real service | Livery | Share in traffic |
|---|---|---|---|
| `mtc_ordinary` | MTC ordinary city service (diesel, standard floor) | sky blue `#86c6ef`, yellow stripe `#f2c230`, separate windows | 5 |
| `mtc_pink` | MTC ordinary "pink bus": free travel for women and transgender people (*Magalir Vidiyal Payanam*) | full pink | 4 |
| `mtc_electric` | MTC electric non-AC (Switch EiV12, low floor) | cyan `#45d2e6` body, purple `#5a2ad0` roof and skirt, orange stripe, black glass band | 3 |
| `mtc_electric_ac` | MTC electric AC (Switch EiV12) | red `#e2343c`, black glass band, yellow stripe | 2 |
| `mtc_ordinary_ac` | MTC diesel AC / deluxe AC | deep blue `#2c62b8`, pale roof | 1 |
| `mtc_premium` | MTC Premium "Gold", launched 11 Mar 2026: P570S Siruseri IT Park – CMBT, P91 Thiruvanmiyur – KCBT | champagne gold `#c9a24f` and black | 1 |
| `mtc_small` | MTC small / mini bus (first-and-last-mile, `S` routes); the 2026 batch is yellow and red | yellow and red, short body | 2 |
| `college` | Private college and school buses | fully yellow, as Tamil Nadu's educational-institution bus rules require, with a black band | 2 (×2.5 at 7:00–9:30 and 15:30–18:00, ×0.25 otherwise) |
| `bus_tnstc`, `bus_setc` | TNSTC town bus and SETC coach passing through | the existing models | 1 each |

The MTC colours come from the livery definitions in Reclaim Chennai's live MTC map (`web/buses.js`), which tells fleets apart from Chennai One's per-bus flags: electric, low floor, AC and tier.

## Stops and routes

- **Stops.** There are 3,414 MTC stops, from Chennai One (CUMTA / MTC) via the Reclaim Chennai MTC bus map (network snapshot of 17 Oct 2026, ODbL). 271 of them fall inside the game map.
  - `build_bus_stops.py` snaps each stop to its road and puts it on the left kerb of the travel direction it serves.
  - It keeps every shelter out of buildings and merges duplicates.
  - The result is **191 stops** with real names (Luz Corner, Mylapore Tank, Mandaveli, Panagal Park, LIC…) and the real route numbers that serve them.
- **Routes.** 307 real routes use these stops. Each route's destination is the last stop of its first working.
  - An MTC bus shows a route that serves the stop nearest to where it appears, for example "21G BROADWAY".
  - Small buses prefer `S` routes. Premium buses show P570S or P91. College buses show "COLLEGE".
- **Shelters.** The design follows Greater Chennai Corporation shelters (about 11 m²):
  - a raised plinth, steel posts and a flat steel roof;
  - a blue name board hung at the front, showing the stop name and its routes;
  - a back panel, a steel bench and a blue BUS STOP sign.

  The nearest 8 share one MultiMesh, the nearest 2 get a name board, and each has collision.
- **Buses stop.** MTC, small and Premium buses treat the next stop on their road as a stopped vehicle 3 m further on. They pull in to the kerb, dwell for 6–11 s and drive on. College buses and state buses don't stop at MTC stops.

## Sources

- MTC liveries: [Reclaim Chennai MTC bus map, `web/buses.js` and README](https://github.com/magesh-V/mtc-bus-map) (MIT code; data under ODbL)
- Electric fleet, blue non-AC and red AC: [Chennai Updates on X, Aug 2025](https://x.com/UpdatesChennai/status/1952957998936338767); [MTC Chennai on X](https://x.com/MtcChennai/status/1955270059980660855)
- First e-bus routes and depot: [DT Next, Vyasarpadi e-buses](https://www.dtnext.in/news/chennai/tns-first-fleet-of-low-floor-green-buses-rolls-out-from-vyasarpadi-838732)
- Premium Gold service: [Sustainable Bus](https://www.sustainable-bus.com/electric-bus/mtc-gold-premium-bus-chennai-switch-electric-buses); [Coach Builders India](https://coachbuildersindia.com/mtc-chennai-premium-ac-electric-bus-service/)
- Pink buses: [TNSTC Enthusiasts on X](https://x.com/tnstcbus/status/1557703829327454209); [Wikipedia: MTC Chennai](https://en.wikipedia.org/wiki/Metropolitan_Transport_Corporation_(Chennai))
- 2026 small buses in yellow and red: [Chennai Live on X](https://x.com/chennailive1048/status/2079838248676057531); [TNIE Tamil Nadu on X](https://x.com/xpresstn/status/2079510897425596464)
- SETC liveries: [Wikipedia: SETC](https://en.wikipedia.org/wiki/State_Express_Transport_Corporation)
- Yellow educational-institution buses: [Tamil Nadu Government Gazette 2012, draft rules, rule 6(2)(a)](https://www.stationeryprinting.tn.gov.in/extraordinary/2012/243-Ex-III-1a.pdf)
- Shelters: [DT Next, 844 shelters facelift (11.4 m², lighting, top ad panel)](https://www.dtnext.in/news/tamilnadu/844-bus-shelters-to-get-facelift-through-ppp-mode)
