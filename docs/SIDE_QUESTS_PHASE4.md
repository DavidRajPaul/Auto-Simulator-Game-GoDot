# Side quests Phase 4 — twelve playable stories

Add SQ02, SQ04, SQ09, SQ19, SQ24 and SQ27 to the six-story pack. Content is offline and
optional in Career. Each new resource has a stable ID and a separate start anchor.

## Acceptance criteria

| ID | Scenario | Required result |
|---|---|---|
| T01 | New or existing save | All twelve IDs appear in map/journal without removing old completion or reward records. Six starts are at distinct, reachable positions within the existing bounding box. |
| T02 | SQ02 coffee run | Player picks a delivery order and visits three shopfronts; the visible fill meter responds to hard turns, acceleration, braking and impacts. The reward pays once, and failed load can retry. |
| T03 | SQ04 landmark clues | Two roadside inspections and dialogue reveal the destination. Exact GPS is hidden until the last clue; a wrong guess provides a recoverable hint. |
| T04 | SQ09 puppy | Horns, jolts and impacts increase distress. A chosen calm stop restores a bounded amount. Both calm and direct routes can finish. |
| T05 | SQ19 mixed parcels | Labels and shop clues are visible in objectives. An incorrect parcel choice adds verification; correct deliveries complete at two separate shops. |
| T06 | SQ24 mechanic | Fault clue leads to a part choice. A wrong choice adds a verification stop; a stopped interaction at the stranded auto completes the handover. |
| T07 | SQ27 narrow lane | Player chooses the narrow or wider approach and finishes with a stopped, correctly oriented reverse parking interaction. Impact or unsafe speed can fail with a free retry. |
| T08 | Sensors and save | Quality remains within 0–100, is included in active-run checkpoints, survives reload, and cannot drain for ordinary fares. Retry/abandon restore Career ownership and never duplicate rewards. |
| T09 | Placement after map rebuild | Starts, destinations and branches remain inside configured bounds and loaded chunks, near the road and clear of mapped buildings, water, walls and parking. CI fails if data drift. |
| T10 | Regression | Import/boot, twelve-story simulations, prior suites, rendered probes, and APK/AAB export pass. Physical Android review still checks touch controls, traffic, Tamil wrapping and whether each mechanic feels distinct. |
