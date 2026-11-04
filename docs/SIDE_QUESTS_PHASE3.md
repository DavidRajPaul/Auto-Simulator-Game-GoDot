# Side quests Phase 3 — six playable stories

Six stories from the 30 quest plan: SQ01, SQ06, SQ12, SQ16, SQ21 and SQ26.
This slice spans Mylapore, Marina, Chepauk, Royapettah, Anna Salai and T. Nagar.

## Acceptance criteria

| ID | Scenario | Required result |
|---|---|---|
| Q01 | Fresh or migrated Career | Six stable IDs appear in the journal and map at six distinct, drivable positions inside the configured box. Existing saves and ordinary rides still work. |
| Q02 | Start each quest | A stopped auto at the marker can explicitly start a quest; moving, fare-occupied, tutorial and completed states cannot. The objective and route appear without an empty/stranded stage. |
| Q03 | Play all six | Every stage can be completed with a starter auto. Movement is road-routed; conversations have visible, tappable choices; the driver can retry a failed quest or abandon it. |
| Q04 | Wedding Gold and Match-Day | An incorrect identification adds a verification detour. The correct choice reaches the handover directly; either path completes once. |
| Q05 | Before the Last Light | Two separate coastal photo stops require a stopped auto facing the composition direction; temporary sunset time is restored afterward. |
| Q06 | Room for an Ambulance | A pooled service vehicle is scripted as an ambulance behind the auto. Three safe pull-ins require signaling and stopping; no extra traffic slot is created. |
| Q07 | Interview Folder and Garland Deadline | Choices change the route or pickup order; every resulting branch remains drivable. Time/speed/damage limits are visible and tuneable; a mistake has a fair retry or correction path. |
| Q08 | Profile and rewards | Abandon/fail/retry/reload preserve the active stage and selection safely. Completion pays exactly once, appears in the journal, and never pays a normal fare. |
| Q09 | Placement validation | Source lat/lon and resolved world anchors correspond to the current OSM transform. Every start/destination is in a loaded chunk, near a connected drivable road and away from mapped building/compound/water blockers. CI rejects broken routes after a map rebuild. |
| Q10 | Regression and performance | Import/boot, prior suites, six-quest simulation, map placement checks, both rendered probes and APK/AAB export pass. No permanent per-quest scene or per-frame route search. |

The headless suite proves mechanics and route connectivity. Readability, safe physical kerbs,
ambulance behavior in traffic and story fun still need an Android playtest before release.
