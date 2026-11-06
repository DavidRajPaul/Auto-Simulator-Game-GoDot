# Side quests Phase 6: device playtest fixes (Nov 6)

The first on-device run of the quests showed that they worked but made no sense to a player.

## Rules for every quest

| Rule | Why | Checked by |
|---|---|---|
| Every stop has a named place (`place_key`) and a sign position by a building (`place_pos`). Beach stops may stand in the open. | Stops were bare road coordinates, so "the music shop" was nowhere. | `validate_quests.py`, quest experience suite |
| Simple English and Tamil. No jargon (integrity, kerb, bay, façade...). | Players did not know what "Instrument integrity" meant. | `validate_quests.py` word list |
| `job_key` lists the steps and any rule, in numbered lines, shown before Start. | A player must know the goal before accepting. | `MissionRegistry`, quest experience suite |
| No hidden GPS routes and no unseen rules such as a facing direction. | Hidden rules read as bugs. | Both checks above |
| Cargo is safe until it is loaded: no `quality_key` on the load stage. | The drum lost condition before pick-up. | Quest experience suite |
| A GPS route must never enter a stage's closed zone. | Festival Detour's route led straight into its own failure. | Quest experience suite |
| An objective is never a button label. | Three stages showed "Wider office road" as the task. | Quest experience suite |

## What the player sees

* **Gold gem and ring** on the road at a quest start (`QuestMarkers`, one MultiMesh, up to 4 markers).
* **Stop at the ring:** a card shows the title, story, job, reward and Start, with a second Start above the minimap.
* **During a job:** a green ring, a named sign and a person waiting at the stop. The left-kerb panel says what to do next. Its action button appears only once a tap will work.
* **Speed limits warn first:** the job stops after `speed_grace_s` over the limit, not at the first frame.
* **Leaving takes two taps**, because the × is near the steering thumb.

## Not done

There are no shop models for quest places yet. A stop is a real building plus a floating sign, not a modelled music shop.
