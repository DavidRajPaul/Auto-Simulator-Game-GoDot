# Career side quests Phase 5 — twenty-four stories

Adds SQ03, SQ05, SQ07, SQ08, SQ10, SQ14, SQ15, SQ17, SQ18, SQ20, SQ23 and SQ25 to the existing offline pack. Each has a distinct roadside start, reachable map targets and English/Tamil UI copy. The story names and destinations are fictional; road anchors use the generated Chennai map.

## Acceptance criteria

| ID | Scenario | Required result |
|---|---|---|
| P01 | Old/new Career save | The original twelve and twelve new stable IDs load; completion, checkpoint and first-reward records are retained. A second run does not pay the first reward again. |
| P02 | Map and discovery | Twelve new starts are at least 120 m apart from all existing starts, within the configured bounding box, clear of mapped walls/buildings/parking/water and connected to all stage targets. Nearby hint, marker and tutorial rules apply without extra per-quest UI. |
| P03 | SQ03/SQ05 | Instrument and festival lamps use a visible integrity meter. A wrong gate or closed-shortcut choice offers a recoverable clue; the festival run requires the alternate approach and reverse bay parking. |
| P04 | SQ07/SQ14/SQ25 | Clues and mistaken choices remain recoverable; the heritage finale hides GPS until both clues are inspected. No quest asks the player to drive through beach crowds. |
| P05 | SQ08/SQ10/SQ15/SQ17 | Cargo transfers require a stopped auto, respect seat/load capacity, and survive stage changes. Either stop order reaches the correct target; rainy paper/supplies lose condition over time, and restoring Career restores prior weather. Two clean-up loops unload before the second pickup. |
| P06 | SQ18/SQ20/SQ23 | Quiet ride reacts to horn and dynamics; night service uses an accessible alternate bay; mirror integrity reacts to motion and parking requires reverse alignment. Technicians and repair work remain narrative interactions from the auto. |
| P07 | Failure and retry | Closed-route entry, low integrity, speed or deadline failures show a reason. Retry restores the stage checkpoint and load without yielding money; abandon, tow, wreck and shift end return navigation, clock and weather ownership. |
| P08 | Regression | Import/boot, prior suites, twenty-four-story simulation, placement validation, performance probes, and Android APK/AAB export pass. Physical Android review checks Tamil wrapping, zone readability, route geometry and pacing. |

## Implementation limits to verify on device

The diversion rule is a mission-local no-entry zone with a signed alternate waypoint. The world does not yet spawn a physical parade, flooded-road barrier or blackout prop; those staged visuals should be added after route and clearance playtests. Cargo and passenger transfers are stopped interactions with text feedback, not character animations. Headless tests cannot establish story quality or touch-control ease.
