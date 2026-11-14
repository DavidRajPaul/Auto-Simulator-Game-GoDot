extends Node
## Global typed event bus. Subsystems never reach into each other's node trees;
## they emit and connect here instead (AGENTS.md Rule 1).

# --- Vehicle -------------------------------------------------------------
signal speed_updated(speed_kmh: float)
## Low-rate (10 Hz) dashboard snapshot. Keys: speed_kmh, lpg_liters, lpg_capacity,
## odometer_km, roll_deg, is_stalled, is_on_two_wheels.
signal telemetry_updated(data: Dictionary)
signal two_wheel_tilt_changed(is_on_two_wheels: bool)
signal gethu_stunt_bonus_earned(stunt_name: String, bonus_inr: int)
signal engine_stalled_in_water(world_pos: Vector3)
## Driver tried to restart with the engine still submerged.
signal flood_restart_blocked()
signal kick_start_attempt(progress_ratio: float)
signal engine_restarted()
signal lpg_empty()
## Fires once when the tank crosses 20%, re-armed after refuelling.
signal fuel_low(level: float, capacity: float)

# --- World ---------------------------------------------------------------
## Emitted by waterlogging zones when the player auto enters/leaves (depth 0 = dry).
signal water_depth_changed(depth_m: float)

# --- Horn / traffic ------------------------------------------------------
signal horn_blasted(origin: Vector3, forward_dir: Vector3, radius_m: float, horn_tier: int)
signal traffic_vehicle_shifted(sub_lane: int)
## Police enforcement at a randomly selected red-light junction.
## A traffic fine (GameState.issue_fine): what it was for, where, the amount, what was paid now
## and what is still due. GarageUI shows it as a notice.
signal traffic_fine_issued(info: Dictionary)
## Part of a pending fine was taken from money that just came in.
signal fine_recovered(taken_inr: int, still_due_inr: int)

# --- UI / controls -------------------------------------------------------
signal wiper_toggled(is_on: bool)
signal camera_mode_changed(mode_name: String)
## Short camera kick on impacts, 0–1 strength.
signal camera_shake(strength: float)
## A player wheel climbed out of a pothole (severity 0..1), or dropped into a rain-filled one
## (severity 0): VehicleAudio thuds, RainSplashes splashes.
signal pothole_hit(pos: Vector3, severity: float)

## Hero and parked auto persist independently while walking.

# --- Navigation ------------------------------------------------------------
## Latest published road graph, for listeners that start after road_graph_ready fired.
var current_road_graph: RoadGraph = null
## The BusStops node (real MTC stops) once the city scene is up; buses ask it for the next stop.
var current_bus_stops: Node = null
## Set by WorldChunkStreamer: (x, z, fallback) -> height of the drawn ground (walk/road/park/bare).
var surface_height_provider: Callable = Callable()
## Set by WorldChunkStreamer: (x, z) -> false inside a building footprint.
var walkable_provider: Callable = Callable()
## Set by ServicePoints: (from: Vector3) -> {name, km, pos} of the nearest garage, {} if none.
var garage_quote_provider: Callable = Callable()

## Set by WorldChunkStreamer: (kind, at, radius) -> Array of [Vector3 position, yaw, record] from
## the loaded chunks' street-life data ("kolams", "shop_people").
var street_spots_provider: Callable = Callable()

func street_spots(kind: String, at: Vector3, radius: float) -> Array:
	return street_spots_provider.call(kind, at, radius) as Array if street_spots_provider.is_valid() else []

## Can a person stand at (x, z)? (not inside a building). True when no world is streaming.
func walkable(x: float, z: float) -> bool:
	return bool(walkable_provider.call(x, z)) if walkable_provider.is_valid() else true

## Nearest garage to `from` for the wreck panel's tow offer: {name, km, pos}, or {}.
func garage_quote(from: Vector3) -> Dictionary:
	return garage_quote_provider.call(from) as Dictionary if garage_quote_provider.is_valid() else {}

## Ask the world to stand a model on the drawn ground at its (x, z) once that chunk's surface
## heights are known (now if loaded, else when the chunk streams in). Used by every static prop
## and parked vehicle so nothing is buried in, or floats above, the road or kerb.
signal ground_snap_requested(node: Node3D)

## Drawn-ground height at (x, z) so people and props stand on what is visible; `fallback` when
## no world streamer is running or the chunk isn't loaded.
func surface_height(x: float, z: float, fallback: float) -> float:
	if surface_height_provider.is_valid():
		return float(surface_height_provider.call(x, z, fallback))
	return fallback
signal road_graph_ready(graph: RoadGraph)
## Player pose for the mini-map / ride logic (every physics frame).
signal player_pose_updated(position: Vector3, heading: Vector3)
## Active GPS route polyline (empty = no route).
signal route_updated(points: PackedVector3Array)
## Full sat-nav route (GpsRoute: guide path + turn-by-turn), null when cleared.
signal gps_route_changed(gps: RefCounted)
## Turn-by-turn prompt for the HUD: {turn, text, glyph, distance_m, road, road_ta, remaining_m}.
signal nav_instruction(info: Dictionary)
## Compact remaining guidance distance displayed at the top of the driving HUD.
signal guidance_distance_updated(text: String)
## Tap the mini-map: open (true) or close (false) the full-screen city map.
signal full_map_requested(open: bool)
signal full_map_state_changed(open: bool)
## Gap-la Gethu: passed a moving vehicle with < 0.6 m clearance above 35 km/h.
signal near_miss(clearance_m: float)
## Traffic model (TrafficDensity) around the player: 0–1 density, current zone id, rush hour?
## Also drives rider demand in haggling.
signal traffic_density_changed(density: float, zone_id: String, is_peak: bool)
signal player_collision(impulse: float)
## Richer impact info (CollisionFX, traffic): {speed_mps, kind: "wall"|"vehicle"|"prop", point, normal, severity 0–1}.
signal player_impact(info: Dictionary)
## Sliding along a wall/vehicle: tangential speed (m/s), 0 when the scrape ends.
signal player_scraping(speed_mps: float, point: Vector3)
## The player bumped this AI vehicle (it stops, honks, then carries on).
signal traffic_bumped(vehicle: Node3D, impact_mps: float)
## Per-physics-frame ride dynamics for the comfort meter (g units; jolt = vertical speed change).
signal vehicle_dynamics(lateral_g: float, longitudinal_g: float, vertical_jolt: float)

## Custom player-selected GPS (independent of passenger trips).
signal custom_navigation_requested(start: Vector3, destination: Vector3)
signal custom_navigation_cleared()
signal custom_navigation_state_changed(active: bool, start: Vector3, destination: Vector3)

# --- Passengers & economy (Phase 3) --------------------------------------
## Hails visible to the HUD / mini-map: Array of {id, position, archetype}.
signal hails_updated(hails: Array)
## Haggle card. info: {archetype, name, line, destination, distance_km, quotes: [int, int, int], odds: [f, f, f]}.
signal haggle_started(info: Dictionary, seconds: float)
## The rider countered: same info, fresh timer.
signal haggle_updated(info: Dictionary, seconds: float)
signal haggle_choice_made(choice: int)
## result: {accepted, offer, fare, line}
signal haggle_resolved(result: Dictionary)
signal passenger_boarded(passenger_count: int, luggage_weight_kg: float)
## Ride HUD tick. info: {destination, remaining_m, time_left_s, comfort, fare, near_misses}
signal ride_updated(info: Dictionary)
signal passenger_alighted()
## breakdown from FareCalculator.settle() plus {destination, archetype_name, line}
signal ride_completed(breakdown: Dictionary)
## The auto caught fire mid-ride: the rider got out and ran, no fare (SavariManager). `line` is
## the already-translated message for the HUD.
signal ride_abandoned(line: String)
signal wallet_balance_changed(new_balance_inr: int, delta_inr: int)
signal stand_respect_changed(new_xp: int, star_rating: float)

# --- Garage, fuel, shift, settings (Phase 4) -------------------------------
## Active auto's effective stats changed (purchase, upgrade, paint, repair, swap).
signal vehicle_loadout_changed(stats: VehicleStats)
signal fuel_changed(level: float, capacity: float)
signal refueled(level: float)
signal condition_changed(condition: float)
## Visible damage changed (dents, mirrors, glass, wear) — AutoRickshawModel refreshes its shaders.
signal damage_changed
## Condition reached 0 (true) or the wreck was repaired (false). Engine dead, fire, wreck panel.
signal vehicle_wrecked(wrecked: bool)
## kind: "lpg", "ev", "garage". info: {id, name, kind}. Fired when stopped at a service point.
signal service_available(kind: String, info: Dictionary)
signal service_unavailable()
signal shift_clock_updated(day: int, minute: float)
signal shift_ended(summary: Dictionary)
signal settings_changed(settings: Dictionary)
signal pause_requested(open: bool)
signal tow_requested(from_position: Vector3)
## A wrecked auto can't drive to a garage: tow it to the nearest one (ServicePoints).
signal wreck_tow_requested(from_position: Vector3)
signal teleport_requested(xform: Transform3D)
# --- Comfort (Phase 5) ------------------------------------------------------
signal recover_available(available: bool)
signal recover_requested()
signal hint_requested(text: String, seconds: float)
signal weather_changed(raining: bool)
## Kick-start rhythm: one kick (good = kept the steady rhythm).
signal kick_timed(good: bool)
## Android back button / Esc (GameState turns NOTIFICATION_WM_GO_BACK_REQUEST into this).
signal back_requested()
## A full-screen menu (pause, garage, summary) opened or closed: HUDs hide underneath to save draws.
signal ui_modal_changed(open: bool)
## A walker had to jump out of the auto's way (PedestrianManager).
signal pedestrian_startled(pos: Vector3)
## The player's auto hit someone who had not got out of the way: the auto loses speed by the
## pedestrian's share of the mass (AutoRickshawController), the person goes down along its path.
signal pedestrian_bumped(pos: Vector3, car_velocity: Vector3)
## The player's auto caught fire (true) or the fire was put out (false).
signal vehicle_burning(on: bool)
## ShopPeople took the shopkeepers / customers near the burning auto out of its static mesh:
## [Vector3 position, yaw, figure id] each. PedestrianManager stands walkers there to flee.
signal shop_people_scattered(spots: Array)
## The failing engine cut out for this long (limp mode under black smoke or fire).
signal engine_misfired(seconds: float)
# --- Controls (gear, indicators, lamps) --------------------------------------------
## +1 drive, -1 reverse.
signal gear_changed(gear: int)
## Tried to change gear while moving.
signal gear_change_refused()
## -1 left, 0 off, +1 right.
signal indicator_changed(direction: int)
## Each blink (lamp on/off) — drives the tick sound and HUD arrows.
signal indicator_blink(direction: int, lamp_on: bool)
## A turn made with the matching indicator on (Respect bonus, courtesy goals).
signal signalled_turn(direction: int)
signal brake_lights_changed(on: bool)
# --- Driver level & shift goals ---------------------------------------------------------
signal driver_xp_changed(total_xp: int, level: int, progress: float)
## unlock_key: translation key of what this level unlocks ("" if nothing).
signal driver_level_up(level: int, title: String, reward_inr: int, unlock_key: String)
signal goals_updated(goals: Array)
signal goal_completed(goal: Dictionary)
signal all_goals_completed(bonus_inr: int)

# --- Rewards & ads (Phase 7: publishing-ready) -----------------------------------------------
## Any reward paid through GameState.grant_reward (source: "ride_bonus", "daily_login", "achievement", "ad_*").
signal reward_granted(source: String, inr: int, xp: int)
signal achievement_unlocked(id: String, info: Dictionary)
## Daily login calendar status changed / claimable: RewardsEngine.daily_status().
signal daily_reward_status(status: Dictionary)
## Ad flow. Requests go to the AdMonetizationManager autoload directly (it's a service);
## results come back here so any UI can react.
signal rewarded_ad_completed(placement: String, context: Dictionary)
signal rewarded_ad_failed(placement: String, reason: String)
signal interstitial_closed(placement: String)
signal ad_state_changed(info: Dictionary)

# --- First-ride tutorial (Plan Phase 2 · suite phase 11) --------------------------------------
## A step began. info: {index, count, id, line, mentor, highlight, hint}.
signal tutorial_step_started(info: Dictionary)
## Analytics hook (Firebase later): how long the player took on each step.
signal tutorial_step_completed(step_id: String, seconds: float)
## Re-show the current line with its nudge (player is stuck).
signal tutorial_hint(text: String)
## The tutorial ended (skipped = true when the player skipped it).
signal tutorial_finished(skipped: bool)
## Spotlight a TouchHUD control ("" clears it).
signal tutorial_highlight(control_id: String)
## The HUD that owns the highlighted control answers with its screen rect (Rect2() = none).
signal tutorial_spotlight(rect: Rect2)
## Pause menu "Skip tutorial" / Settings "Replay tutorial".
signal tutorial_skip_requested()
signal tutorial_replay_requested()
## Scripted world for guided rides and missions.
## Switch the engine off so the player has to kick-start it.
signal engine_switch_off_requested()
## Engine stopped for a reason other than water (shows the KICK button).
signal engine_switched_off()
## Place a waiting rider: {near: Vector3, archetype: String, trip_min_m, trip_max_m}. Always
## accepts the deal, never times out, rides to a fixed destination.
signal scripted_hail_requested(info: Dictionary)
## Put a slow vehicle of `kind` ("two_wheeler") in the player's lane `ahead_m` metres ahead.
signal scripted_traffic_requested(kind: String, ahead_m: float)
## An MTC bus pulled in at a stop (TrafficVehicleAI): position and its route board text.
signal bus_stopped(at: Vector3, route: String)

# Career mission runtime. Providers avoid cross-scene node paths.
var savari_busy_provider: Callable = Callable()
signal mission_start_requested(id: String)
signal mission_choice_requested(quest_id: String, stage_id: String, choice: String)
signal mission_retry_requested
signal mission_abandon_requested(reason: String)
signal mission_ownership_changed(active: bool)
signal mission_stage_changed(quest_id: String, stage_id: String, objective_key: String, choices: PackedStringArray)
signal mission_finished(quest_id: String, status: String, reason: String)
## True while the quest's rider (QuestRider) is in the auto. Unset: no rider system in the scene.
var quest_rider_aboard_provider: Callable = Callable()
signal mission_profile_loaded
signal mission_interact_requested(quest_id: String, stage_id: String)
signal mission_stage_info(info: Dictionary)
signal mission_timer_updated(seconds_remaining: float)
signal mission_quality_changed(kind: String, value: float)
## Returns true only if an out-of-view pooled service slot was reserved.
var scripted_ambulance_provider: Callable = Callable()
## Discovery is read-only until an explicit stopped-kerb start request.
var quest_discovery_provider: Callable = Callable()
var quest_action_provider: Callable = Callable()
signal quest_tracking_changed(id: String)
signal quest_catalogue_changed
## The stopped auto can begin this quest (empty dictionary = no longer).
signal quest_prompt_changed(quest: Dictionary)
signal quest_prompt_dismissed
## The panel's stop-and-do button is usable: true only inside the stop while slow enough.
signal mission_action_ready(ready: bool, in_range: bool)
## Seconds left before an ongoing speed breach stops the job (0 = no breach).
signal mission_speed_warning(seconds_left: float)
