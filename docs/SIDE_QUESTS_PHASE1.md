# Career side quests — Phase 1 runtime foundation

Scope follows Phase 1 of Namma_Auto_30_Side_Quests_Plan.md (4 Nov 2026).
The 30 quests, markers and tutorial extension are subsequent phases. This PR
ships an empty production catalogue and a synthetic test quest, not unfinished
quests exposed to players.

## Acceptance criteria

| ID | Given / when | Required result |
|---|---|---|
| AC01 | Load a pack with duplicate IDs, invalid stages, missing prerequisites or a cycle | Reject the whole pack with diagnostics; never partially replace the registry. |
| AC02 | Accept a valid unlocked quest while idle | Exactly one run starts; a second start, occupied fare, tutorial or wreck is refused. |
| AC03 | Drive to a goal, choose dialogue and satisfy timed constraints | Stable stage IDs advance in order; invalid/stale choice callbacks do nothing; shared resources remain immutable. |
| AC04 | Exceed the stage deadline, speed or damage constraint | Run fails without reward; free retry restores the latest objective checkpoint; abandon clears ownership. |
| AC05 | Save and reload an active quest | Resume the checkpoint by stable quest/stage ID; no saved Node references, stale timers or scene teleport. |
| AC06 | Finish, replay, reload, then make over 200 other reward grants | Completion money and XP pay once; permanent mission keys survive ledger pruning. |
| AC07 | Load a version-1 encrypted career | Existing wallet, vehicles and progression remain readable; missing mission data defaults to an empty journal. |
| AC08 | End, abandon, tow, wreck, or unload the mission scene | Release navigation/hails and restore captured time/weather; no temporary scenario remains in Career. |
| AC09 | Quest content version/stage is missing on reload | Cancel safely, retain historical completion/unknown records and report why. |
| AC10 | Save completion across a crash boundary | Completion and payout ledger are saved together through atomic file replacement; replay is idempotent. |
| AC11 | Normal Career and tutorial with empty production pack | No new visuals/actors, no changed fare flow; existing suites and performance budget pass. |
| AC12 | Build the branch | Godot 4.5.1 import/boot, all phase suites including new phase 13, perf probes and Android CI pass. |

## Contracts and limits

- Resources define GoTo, Dialogue and Wait stages, with concurrent time/speed/condition-loss constraints. Advanced stage types are rejected until implemented.
- SignalBus coordinates lifecycle and routes. Savari declares whether it is busy; mission ownership suppresses hails. Custom navigation is suspended and recomputed from the current position when restored.
- Checkpoints restore objective flags and timing, **not** vehicle fuel/damage or position in this foundation. Vehicle wear stays real, preventing retry repair/fuel exploits. Provisional vehicle-cost accounting and streamed checkpoint relocation are deferred until playable content needs them.
- Completion rewards are one-time base rewards in Phase 1. Star tiers/replay caps are content-phase work; the permanent `mission:` namespace supports separate tier keys later.
- Optional scenario time/rain is captured/restored. Phase 1 changes no traffic/world props; those later adapters must implement the same cleanup contract.
- Save schema becomes version 2; encryption identity remains version 1 so old encrypted saves can still be opened. Atomic sibling-file rename protects the previous file on interrupted writes.
- No authored Chennai quest anchors ship here. Config BBOX and generated manifest differ; placement audit remains required before the six-quest slice. This phase does not regenerate or enlarge the map.

## Validation

Automated acceptance: `tests/run_phase13_tests.tscn`. Run all existing suites,
import/boot and both performance probes as specified by AGENTS.md. Android device
feel and visual acceptance belong to the later playable slice; CI cannot prove them.
