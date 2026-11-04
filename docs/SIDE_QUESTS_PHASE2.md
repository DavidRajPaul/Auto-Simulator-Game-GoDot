# Side quests Phase 2 — discovery and onboarding

Status: implementation in progress. Phase 1 is merged in main (PR #80).

## Acceptance criteria

| ID | Scenario | Required result |
|---|---|---|
| D01 | Open the map with eligible quests | Gold quest badges appear at authored anchors; tap targets are at least 48 logical pixels. |
| D02 | Zoom out with overlapping quests | Markers cluster with a count; tapping expands or lists members. |
| D03 | Track a quest during a normal ride | Quest selection is retained but the fare's GPS remains authoritative. Tracking never accepts a quest. |
| D04 | Approach an available quest | One compact hint within 120 m of a reachable road approach; exit radius 170 m and 90-second cooldown prevent repeated prompts. |
| D05 | Drive past a quest or approach through a wall | No automatic acceptance, no interaction through buildings or compounds. Acceptance requires a stopped auto at its accessible kerb. |
| D06 | Tutorial, occupied ride, active mission or modal | Nearby hints are suppressed; ordinary controls and navigation remain usable. |
| D07 | Open journal | Catalogue, locked reasons, completion state and tracking state are consistent with the mission registry and save. Empty catalogue has a clear message. |
| D08 | First onboarding or existing eligible save | Optional short map/track/approach lesson appears once, uses the existing coach overlay, and accepts Later as completion. |
| D09 | Skip/replay/reload lesson | No duplicate rewards, no stuck input, no forced quest acceptance, and no loss of Career progress. |
| D10 | Run on a budget phone | No permanent scene per quest; markers are pooled/batched, discovery uses spatial lookup and cached routes. Full scene remains within existing budgets. |
| D11 | Tamil, small screen and reduced motion | Text is readable; marker states do not depend on colour alone; reduced motion disables pulses. |
| D12 | Regression and release | Import/boot, phase 13, new discovery tests, existing suites, both rendered performance probes and Android CI pass. |

## Implementation order

1. Add authoring metadata and tunable discovery parameters without changing Phase 1 resources.
2. Add discovery/tracking service and automated eligibility/cooldown/ownership tests.
3. Add map/minimap/world indicators, journal and stopped briefing UI.
4. Extend onboarding and save compatibility tests.
5. Validate representative test anchors and run the full release checks.

No playable story pack is required for the reusable discovery system. Tests must
exercise a fixture catalogue; the production catalogue remains explicitly empty
until authored quests and their exact locations pass placement acceptance.
