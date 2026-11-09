extends Node
## Player profile: economy, garage loadout, fuel/condition, shift clock, settings and the
## encrypted save. Gameplay systems read it directly (it is the single source of truth)
## and listen to SignalBus for changes.

## Tamil Nadu fares from 29 Oct 2026: ₹50 for 1.8 km, ₹25/km after, 1.5× from 10 PM to 5 AM.
const METER_BASE_FARE_INR: float = 50.0
const METER_BASE_KM: float = 1.8
const METER_PER_KM_INR: float = 25.0
const NIGHT_FARE_FROM_MIN: float = 1320.0 # 10 PM
const NIGHT_FARE_TO_MIN: float = 300.0 # 5 AM
const SURGE_MULTIPLIER: float = 1.5

const SAVE_PATH: String = "user://savegame.dat"
const SAVE_VERSION: int = 2
# Encryption identity must stay stable across schema migrations.
const SAVE_KEY_VERSION: int = 1
const AUTOSAVE_INTERVAL_S: float = 60.0

## Vehicle catalogue (id → resource). Prices/specs live in the .tres files.
const VEHICLES: Dictionary = {
	"singara_classic": "res://data/vehicles/Bajaj_RE_4S.tres",
	"madras_king_deluxe": "res://data/vehicles/Madras_King_Deluxe.tres",
	"namma_green_ev": "res://data/vehicles/Namma_Green_EV.tres",
}
const VEHICLE_ORDER: PackedStringArray = ["singara_classic", "madras_king_deluxe", "namma_green_ev"]

## Garage upgrades: 3 levels each; costs per level.
const UPGRADES: Dictionary = {
	"engine": {"name": "Engine Bore", "costs": [350, 700, 1260], "desc": "+7% pull, +3 km/h top speed per level"},
	"suspension": {"name": "Suspension Springs", "costs": [280, 560, 980], "desc": "−15% passenger jolts per level"},
	"tyres": {"name": "Tyres", "costs": [210, 420, 770], "desc": "+6% grip per level"},
}
## Horns (GDD): 0 stock bulb "pom-pom", 1 twin electric, 2 Madras musical air-horn.
const HORNS: Array[Dictionary] = [
	{"name": "Stock Bulb Horn", "cost": 0, "desc": "Clears cyclists & pedestrians"},
	{"name": "Twin Electric Horn", "cost": 420, "desc": "Two-wheelers & hatchbacks give way"},
	{"name": "Madras Musical Air-Horn", "cost": 1260, "desc": "Even share autos, buses & cows move"},
]
## Paints / Alangaram (cosmetic prestige → better Meter Mela odds).
const PAINTS: Array[Dictionary] = [
	{"name": "Chennai Yellow", "cost": 0, "body": Color(0.98, 0.76, 0.02), "canopy": Color(0.07, 0.07, 0.07), "prestige": 0.0},
	{"name": "Kollywood Black-Gold", "cost": 310, "body": Color(0.08, 0.08, 0.08), "canopy": Color(0.85, 0.66, 0.15), "prestige": 0.3},
	{"name": "Marina Blue", "cost": 310, "body": Color(0.12, 0.42, 0.78), "canopy": Color(0.95, 0.95, 0.95), "prestige": 0.3},
	{"name": "Mylapore Saffron", "cost": 310, "body": Color(0.95, 0.45, 0.08), "canopy": Color(0.4, 0.05, 0.08), "prestige": 0.3},
	{"name": "Neon Night", "cost": 530, "body": Color(0.75, 0.1, 0.85), "canopy": Color(0.05, 0.05, 0.1), "prestige": 0.5},
]
const REPAIR_COST_PER_POINT: int = 4

## Shift: 06:00 → 22:00 in 12 real minutes (GDD "Madras day" session length).
const SHIFT_START_MIN: float = 360.0
const SHIFT_END_MIN: float = 1320.0
## One shift (6 AM – 10 PM) lasts 18 real minutes — room for ~5 real-size rides.
const SHIFT_REAL_SECONDS: float = 1080.0
const GAME_MIN_PER_SECOND: float = (SHIFT_END_MIN - SHIFT_START_MIN) / SHIFT_REAL_SECONDS

## Driver level (XP) + daily shift goals — see scripts/progression/DriverProgress.gd.
var progress: DriverProgress = DriverProgress.new()
## Ledger, daily login calendar, achievements, rewarded-ad payouts (scripts/progression/RewardsEngine.gd).
var rewards: RewardsEngine = RewardsEngine.new()
## Bought "No Ads" (Play Billing SKU no_ads_forever): no interstitials/banners; rewarded stays opt-in.
var no_ads: bool = false
var _crashed_this_ride: bool = false
const CLEAN_RIDE_CRASH_MPS: float = 3.0
var wallet_inr: int = 500
var stand_respect_xp: int = 100
var star_rating: float = 4.5
var completed_savaris: int = 0
## Set by the weather schedule below. Riders haggle less and monsoon riders appear.
var is_raining: bool = false
## Today's rain window in shift minutes ([-1, -1] = dry day). NE monsoon: Oct–Dec.
var rain_window: Vector2 = Vector2(-1.0, -1.0)
const MONSOON_RAIN_CHANCE: float = 0.4
const SIGNAL_RESPECT_XP: int = 2

var owned_vehicles: PackedStringArray = ["singara_classic"]
var active_vehicle: String = "singara_classic"
var upgrades: Dictionary = {} # vehicle id → {engine, suspension, tyres}
var horns_owned: int = 0 # highest tier bought (all lower tiers usable)
var horn_equipped: int = 0
var paints_owned: PackedInt32Array = [0]
var paint_equipped: int = 0
var fuel_level: float = -1.0 # -1 = fill on first spawn
var condition: float = 100.0
## Condition and fuel of the autos not being driven: id -> {condition, fuel}. Damage and the tank
## stay with their auto, so swapping keys neither repairs nor refuels anything.
var parked_autos: Dictionary = {}
const DAMAGE: DamageTuning = preload("res://data/vehicles/damage.tres")
## Per-vehicle wear; zero is pristine. Old saves start with no component faults.
var component_damage: Dictionary = {}
## Visible crash marks per vehicle (AutoRickshawModel draws them): {"dents": [[x, y, z, strength], ...]
## in the auto mesh's space (cm), "crack": [x, y] windshield crack origin}. Saved; repair fades them.
var damage_marks: Dictionary = {}
const MAX_DENTS: int = 8
## A side hit this strong (damage points) snaps that mirror; side wear above this does too.
const MIRROR_BREAK_POINTS: float = 10.0
const MIRROR_BREAK_WEAR: float = 45.0

var day: int = 1
var shift_minute: float = SHIFT_START_MIN
var shift_running: bool = true
var day_stats: Dictionary = {"earned": 0, "rides": 0, "fuel_spent": 0, "repairs": 0}

var settings: Dictionary = {"control_scheme": 1, "controls_v2": true, "graphics": 1, "language": "en", "master_volume": 0.9, "engine_volume": 0.8,
	"vibration": true, "guidance_arrow": true, "first_ride_step": 0, "first_ride_done": false, "auto_reverse": true}

## First-ride tutorial running (TutorialDirector sets it). While true: no interstitials, no fuel
## burn, thin traffic, no random riders, and crashes cannot wear the auto below tutorial_min_condition.
var mission_reward_transaction: bool = false
var mission_active: bool = false
var mission_run: Dictionary = {}
var mission_completed: Dictionary = {}

var tutorial_active: bool = false
var tutorial_min_condition: float = 0.0

## Saving is disabled for test runs so suites never read or clobber a real profile.
var persistence_enabled: bool = true
var save_path: String = SAVE_PATH
var _autosave_timer: float = 0.0
var _clock_emit_timer: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_args():
		if a.begins_with("res://tests/"):
			persistence_enabled = false
	roll_weather()
	if persistence_enabled:
		load_game()
	SignalBus.player_collision.connect(_on_collision)
	SignalBus.player_impact.connect(_on_component_impact)
	SignalBus.signalled_turn.connect(func(_d: int) -> void:
		rewards.add_stat("signals", 1)
		add_respect(SIGNAL_RESPECT_XP)
		add_driver_xp(DriverProgress.SIGNAL_XP)
		_advance_goal("signal", 1))
	SignalBus.near_miss.connect(func(_c: float) -> void: _advance_goal("gethu", 1))
	SignalBus.ride_completed.connect(_on_ride_progress)
	SignalBus.ride_completed.connect(_on_ride_rewards)
	SignalBus.passenger_boarded.connect(func(_c: int, _l: float) -> void: _crashed_this_ride = false)
	SignalBus.player_collision.connect(func(i: float) -> void:
		if i >= CLEAN_RIDE_CRASH_MPS:
			_crashed_this_ride = true)
	SignalBus.near_miss.connect(func(_c: float) -> void:
		rewards.add_stat("near_misses", 1)
		_check_achievements())
	SignalBus.rewarded_ad_completed.connect(_on_rewarded_ad)
	if progress.goals_day != day:
		progress.roll_goals(day)
	SignalBus.fuel_changed.connect(func(level: float, _cap: float) -> void: fuel_level = level)
	SignalBus.ride_completed.connect(func(b: Dictionary) -> void:
		day_stats["earned"] = int(day_stats["earned"]) + int(b.get("total", 0))
		day_stats["rides"] = int(day_stats["rides"]) + 1
		save_game())
	_install_tamil_font()
	_auto_graphics_once()
	_apply_settings.call_deferred()

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if shift_running:
		shift_minute += delta * GAME_MIN_PER_SECOND
		_update_weather()
		_clock_emit_timer += delta
		if _clock_emit_timer >= 1.0:
			_clock_emit_timer = 0.0
			SignalBus.shift_clock_updated.emit(day, shift_minute)
		if shift_minute >= SHIFT_END_MIN:
			end_shift()
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL_S:
		_autosave_timer = 0.0
		save_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		SignalBus.back_requested.emit()
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save_game()
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# Phone call / app switch: never leave the auto driving unattended.
		SignalBus.pause_requested.emit(true)

# --- Driver level & shift goals -----------------------------------------------------------

func driver_level() -> int:
	return progress.level()

## Add Driver XP; pays the cash bonus for every level crossed and announces it.
func add_driver_xp(amount: int) -> void:
	var before: int = progress.level()
	progress.xp += maxi(0, amount)
	var after: int = progress.level()
	for lvl: int in range(before + 1, after + 1):
		var reward: int = DriverProgress.level_reward_inr(lvl)
		add_inr(reward)
		SignalBus.driver_level_up.emit(lvl, DriverProgress.title(lvl), reward, str(DriverProgress.UNLOCKS.get(lvl, "")))
	SignalBus.driver_xp_changed.emit(progress.xp, after, progress.level_progress())
	if after > before:
		_check_achievements()

## Whether a garage item ("horn:2", "vehicle:namma_green_ev", "paint:4") is unlocked yet.
func is_unlocked(key: String) -> bool:
	return driver_level() >= DriverProgress.required_level(key)

func _on_ride_progress(b: Dictionary) -> void:
	add_driver_xp(DriverProgress.ride_xp(b))
	_advance_goal("rides", 1)
	_advance_goal("earn", int(b.get("total", 0)))
	if float(b.get("comfort", 0.0)) >= DriverProgress.SMOOTH_COMFORT:
		_advance_goal("smooth", 1)
	if int(b.get("offer", -1)) == 0:
		_advance_goal("meter", 1)

func _advance_goal(kind: String, amount: int) -> void:
	var had_all: bool = progress.all_goals_done()
	var done: Array[Dictionary] = progress.advance(kind, amount)
	for g: Dictionary in done:
		add_inr(DriverProgress.GOAL_INR)
		add_driver_xp(DriverProgress.GOAL_XP)
		SignalBus.goal_completed.emit(g)
	if not had_all and progress.all_goals_done():
		add_inr(DriverProgress.ALL_GOALS_BONUS_INR)
		rewards.add_stat("all_goal_days", 1)
		SignalBus.all_goals_completed.emit(DriverProgress.ALL_GOALS_BONUS_INR)
	if not done.is_empty() or amount > 0:
		SignalBus.goals_updated.emit(progress.goals)

# --- Rewards engine ----------------------------------------------------------------

## The one entry point for bonus rewards (daily, achievements, ads). Idempotent by `id`.
func grant_reward(source: String, inr: int, xp: int, id: String = "") -> Dictionary:
	var g: Dictionary = rewards.grant(source, inr, xp, id, RewardsEngine.today_string())
	if str(g["refused"]) == "":
		if int(g["inr"]) > 0:
			add_inr(int(g["inr"]))
		if int(g["xp"]) > 0:
			add_driver_xp(int(g["xp"]))
		SignalBus.reward_granted.emit(source, int(g["inr"]), int(g["xp"]))
		save_game()
	return g

func daily_reward_status() -> Dictionary:
	return rewards.daily_status(RewardsEngine.today_string())

func claim_daily_reward() -> Dictionary:
	var today: String = RewardsEngine.today_string()
	var st: Dictionary = rewards.daily_status(today)
	if not bool(st["available"]):
		return {"inr": 0, "xp": 0, "refused": "claimed"}
	var g: Dictionary = rewards.claim_daily(today)
	if str(g["refused"]) == "":
		add_inr(int(g["inr"]))
		add_driver_xp(int(g["xp"]))
		SignalBus.reward_granted.emit("daily_login", int(g["inr"]), int(g["xp"]))
		_check_achievements()
		save_game()
	SignalBus.daily_reward_status.emit(rewards.daily_status(today))
	return g

func _on_ride_rewards(b: Dictionary) -> void:
	rewards.add_stat("rides", 1)
	rewards.add_stat("earned", int(b.get("total", 0)))
	rewards.add_stat("ride_m", roundi(float(b.get("distance_km", 0.0)) * 1000.0))
	rewards.bump_stat_max("best_fare", int(b.get("total", 0)))
	if int(b.get("offer", -1)) == 0:
		rewards.add_stat("meter_rides", 1)
	elif int(b.get("offer", -1)) == 1:
		rewards.add_stat("mela_rides", 1)
	if bool(b.get("on_time", false)):
		rewards.add_stat("on_time_rides", 1)
	if float(b.get("stars", 0.0)) >= 4.75:
		rewards.add_stat("five_star_rides", 1)
	if str(b.get("archetype", "")) != "":
		rewards.stats["seen_" + str(b["archetype"])] = 1
		rewards.set_stat("rider_types", rewards.stats.keys().filter(func(k: Variant) -> bool: return str(k).begins_with("seen_")).size())
	if float(b.get("comfort", 0.0)) >= DriverProgress.SMOOTH_COMFORT:
		rewards.add_stat("smooth_rides", 1)
	if is_raining:
		rewards.add_stat("rain_rides", 1)
	if is_night():
		rewards.add_stat("night_rides", 1)
	if _crashed_this_ride:
		rewards.set_stat("clean_streak", 0)
	else:
		rewards.add_stat("clean_streak", 1)
		rewards.bump_stat_max("best_clean_streak", int(rewards.stats.get("clean_streak", 0)))
	_check_achievements()

## Career totals that can simply be read from the profile.
func _sync_career_stats() -> void:
	rewards.bump_stat_max("level", driver_level())
	rewards.bump_stat_max("autos_owned", owned_vehicles.size())
	rewards.bump_stat_max("paints_owned", paints_owned.size())
	var bought: int = 0
	for vehicle: String in upgrades:
		for level: Variant in (upgrades[vehicle] as Dictionary).values():
			bought += int(level)
	rewards.bump_stat_max("upgrades_bought", bought)

func _check_achievements() -> void:
	_sync_career_stats()
	var today: String = RewardsEngine.today_string()
	for id: String in rewards.check_achievements(today):
		var a: Dictionary = RewardsEngine.ACHIEVEMENTS[id]
		grant_reward("achievement", int(a["inr"]), int(a["xp"]), "ach:" + id)
		SignalBus.achievement_unlocked.emit(id, a)

## Rewarded ad finished and the provider confirmed the reward. Context carries what to pay.
func _on_rewarded_ad(placement: String, ctx: Dictionary) -> void:
	match placement:
		"ad_double_fare":
			grant_reward(placement, int(ctx.get("inr", 0)), 0, "%s:%s" % [placement, str(ctx.get("ride_id", ""))])
		"ad_fuel_rescue":
			var s: VehicleStats = base_stats(active_vehicle)
			var g: Dictionary = grant_reward(placement, 0, 0, "%s:%d:%d" % [placement, day, int(shift_minute)])
			if str(g["refused"]) == "":
				fuel_level = maxf(fuel_level, s.fuel_capacity * 0.5)
				SignalBus.refueled.emit(fuel_level)
		"ad_wreck_repair":
			# Placeholder until real ads: the mock provider shows a fake ad, then this runs.
			var g3: Dictionary = grant_reward(placement, 0, 0, "%s:%d:%d" % [placement, day, int(shift_minute)])
			if str(g3["refused"]) == "":
				repair_free()
		"ad_tow":
			# Credit the tow fee, then tow: the ad makes the tow free.
			var g2: Dictionary = grant_reward(placement, ServicePoints.TOW_COST_INR, 0, "%s:%d:%d" % [placement, day, int(shift_minute)])
			if str(g2["refused"]) == "":
				# A wrecked auto is towed to a garage; an empty tank to a fuel station.
				if str(ctx.get("to", "")) == "garage":
					SignalBus.wreck_tow_requested.emit(Vector3(ctx.get("from", Vector3.ZERO)))
				else:
					SignalBus.tow_requested.emit(Vector3(ctx.get("from", Vector3.ZERO)))
		_:
			grant_reward(placement, int(ctx.get("inr", 0)), int(ctx.get("xp", 0)), "%s:%s" % [placement, str(ctx.get("id", Time.get_ticks_msec()))])

# --- Money, respect, rating ------------------------------------------------------

func add_inr(amount: int) -> void:
	wallet_inr = maxi(0, wallet_inr + amount)
	SignalBus.wallet_balance_changed.emit(wallet_inr, amount)

func spend(amount: int) -> bool:
	if amount > wallet_inr:
		return false
	add_inr(-amount)
	return true

## Rolling Auto Stand rating: each ride nudges it toward that ride's stars.
func record_ride_rating(stars: float) -> void:
	star_rating = clampf(lerpf(star_rating, stars, 0.15), 1.0, 5.0)
	completed_savaris += 1
	SignalBus.stand_respect_changed.emit(stand_respect_xp, star_rating)

func add_respect(xp: int) -> void:
	stand_respect_xp = maxi(0, stand_respect_xp + xp)
	SignalBus.stand_respect_changed.emit(stand_respect_xp, star_rating)

## Chennai meter: ₹50 for the first 1.8 km, ₹25/km after, rounded to nearest ₹5.
## True while the legal night fare applies.
func night_fare_now() -> bool:
	return shift_minute >= NIGHT_FARE_FROM_MIN or shift_minute < NIGHT_FARE_TO_MIN

func calculate_meter_fare(distance_km: float, is_night_or_monsoon: bool = false) -> int:
	var extra_km: float = maxf(0.0, distance_km - METER_BASE_KM)
	var raw_fare: float = METER_BASE_FARE_INR + extra_km * METER_PER_KM_INR
	if is_night_or_monsoon:
		raw_fare *= SURGE_MULTIPLIER
	return int(roundf(raw_fare / 5.0) * 5.0)

# --- Loadout -------------------------------------------------------------------------

func base_stats(vehicle_id: String) -> VehicleStats:
	return load(str(VEHICLES.get(vehicle_id, VEHICLES["singara_classic"]))) as VehicleStats

func upgrade_level(vehicle_id: String, kind: String) -> int:
	return int((upgrades.get(vehicle_id, {}) as Dictionary).get(kind, 0))

## The active auto's stats with garage upgrades, horn, paint and condition applied.
## Always a fresh copy — callers may keep it.
func active_stats() -> VehicleStats:
	return effective_stats(active_vehicle)

func effective_stats(vehicle_id: String) -> VehicleStats:
	var s: VehicleStats = base_stats(vehicle_id).duplicate() as VehicleStats
	var eng: int = upgrade_level(vehicle_id, "engine")
	var sus: int = upgrade_level(vehicle_id, "suspension")
	var tyr: int = upgrade_level(vehicle_id, "tyres")
	s.engine_peak_force_n *= 1.0 + 0.07 * eng
	s.max_speed_kmh += 3.0 * eng
	s.comfort_damping *= pow(0.85, sus)
	s.spring_damping_coeff *= 1.0 + 0.08 * sus
	s.front_lateral_grip *= 1.0 + 0.06 * tyr
	s.rear_lateral_grip *= 1.0 + 0.06 * tyr
	s.horn_tier = maxi(s.horn_tier, horn_equipped)
	if paint_equipped > 0:
		s.body_colour = PAINTS[paint_equipped]["body"]
		s.canopy_colour = PAINTS[paint_equipped]["canopy"]
	if condition < 40.0:
		# Worn out: the engine coughs and the bodywork rattles.
		s.max_speed_kmh *= 0.85
		s.engine_peak_force_n *= 0.9
	return s

## Alangaram prestige 0–1: paint plus visible upgrades.
func prestige() -> float:
	var p: float = float(PAINTS[paint_equipped]["prestige"])
	for kind: String in UPGRADES:
		p += 0.05 * upgrade_level(active_vehicle, kind)
	p += 0.1 * horn_equipped
	return clampf(p, 0.0, 1.0)

func _loadout_changed() -> void:
	SignalBus.vehicle_loadout_changed.emit(active_stats())
	_check_achievements()
	save_game()

# --- Garage purchases (return true on success) ------------------------------------------

func buy_vehicle(vehicle_id: String) -> bool:
	if owned_vehicles.has(vehicle_id) or not VEHICLES.has(vehicle_id) or not is_unlocked("vehicle:" + vehicle_id):
		return false
	if not spend(base_stats(vehicle_id).price_inr):
		return false
	owned_vehicles.append(vehicle_id)
	select_vehicle(vehicle_id)
	return true

func select_vehicle(vehicle_id: String) -> bool:
	if not owned_vehicles.has(vehicle_id):
		return false
	if vehicle_id == active_vehicle:
		return true
	parked_autos[active_vehicle] = {"condition": condition, "fuel": fuel_level}
	active_vehicle = vehicle_id
	# An auto that never left the stand: new keys come with a full tank and no scratches.
	var parked: Dictionary = parked_autos.get(vehicle_id, {})
	condition = clampf(float(parked.get("condition", 100.0)), 0.0, 100.0)
	fuel_level = float(parked.get("fuel", base_stats(vehicle_id).fuel_capacity))
	if fuel_level < 0.0:
		fuel_level = base_stats(vehicle_id).fuel_capacity
	_loadout_changed()
	SignalBus.condition_changed.emit(condition)
	SignalBus.damage_changed.emit()
	SignalBus.refueled.emit(fuel_level)
	return true

func next_upgrade_cost(kind: String) -> int:
	var lvl: int = upgrade_level(active_vehicle, kind)
	var costs: Array = UPGRADES[kind]["costs"]
	return -1 if lvl >= costs.size() else int(costs[lvl])

func buy_upgrade(kind: String) -> bool:
	var cost: int = next_upgrade_cost(kind)
	if cost < 0 or not spend(cost):
		return false
	var u: Dictionary = upgrades.get(active_vehicle, {})
	u[kind] = upgrade_level(active_vehicle, kind) + 1
	upgrades[active_vehicle] = u
	_loadout_changed()
	return true

func buy_horn(tier: int) -> bool:
	if tier <= horns_owned:
		horn_equipped = tier
		_loadout_changed()
		return true
	if tier != horns_owned + 1 or not is_unlocked("horn:%d" % tier) or not spend(int(HORNS[tier]["cost"])):
		return false
	horns_owned = tier
	horn_equipped = tier
	_loadout_changed()
	return true

func buy_paint(index: int) -> bool:
	if not paints_owned.has(index):
		if not is_unlocked("paint:%d" % index) or not spend(int(PAINTS[index]["cost"])):
			return false
		paints_owned.append(index)
	paint_equipped = index
	_loadout_changed()
	return true

func repair_cost() -> int:
	var points: float = 100.0 - condition
	for value: Variant in damage_state().values():
		points = maxf(points, float(value) / DAMAGE.component_multiplier)
	return ceili(points * REPAIR_COST_PER_POINT)

## Repairs as much as the wallet allows (₹3 per condition point).
func repair() -> bool:
	var pay: int = mini(repair_cost(), wallet_inr)
	if pay <= 0:
		return false
	spend(pay)
	var fraction: float = minf(1.0, float(pay) / maxf(float(repair_cost()), 1.0))
	var was_wrecked: bool = is_wrecked()
	var wear: Dictionary = damage_state()
	for key: String in wear:
		wear[key] = float(wear[key]) * (1.0 - fraction)
	# Dents fade with the paid share; a full repair leaves none (mirrors/glass follow their wear:
	# below 50 % a mirror is back, and the windshield crack shrinks with "glass").
	var kept: Array = []
	for q: Array in marks()["dents"]:
		var w: float = float(q[3]) * (1.0 - fraction)
		if w > 0.05:
			kept.append([q[0], q[1], q[2], w])
	marks()["dents"] = kept
	condition = minf(100.0, condition + float(pay) / REPAIR_COST_PER_POINT)
	SignalBus.damage_changed.emit()
	if was_wrecked and not is_wrecked():
		SignalBus.vehicle_wrecked.emit(false)
	day_stats["repairs"] = int(day_stats["repairs"]) + pay
	SignalBus.condition_changed.emit(condition)
	_loadout_changed()
	return true

## Fill as much as the wallet allows. Returns units added.
func buy_fuel() -> float:
	var s: VehicleStats = base_stats(active_vehicle)
	var missing: float = maxf(0.0, s.fuel_capacity - maxf(fuel_level, 0.0))
	var affordable: float = float(wallet_inr) / s.fuel_price_inr
	var units: float = minf(missing, affordable)
	if units < 0.05:
		return 0.0
	var cost: int = ceili(units * s.fuel_price_inr)
	spend(mini(cost, wallet_inr))
	fuel_level = maxf(fuel_level, 0.0) + units
	day_stats["fuel_spent"] = int(day_stats["fuel_spent"]) + cost
	SignalBus.refueled.emit(fuel_level)
	save_game()
	return units

func fuel_cost_to_fill() -> int:
	var s: VehicleStats = base_stats(active_vehicle)
	return ceili(maxf(0.0, s.fuel_capacity - maxf(fuel_level, 0.0)) * s.fuel_price_inr)

func _on_collision(impulse: float) -> void:
	var floor_c: float = minf(tutorial_min_condition, condition) if tutorial_active else 0.0
	var previous: float = condition
	condition = maxf(floor_c, condition - DAMAGE.points(impulse))
	SignalBus.condition_changed.emit(condition)
	if is_wrecked() and previous > 0.0:
		SignalBus.vehicle_wrecked.emit(true)
	if condition < 40.0 and previous >= 40.0:
		_loadout_changed() # crossed into "worn out"

## Condition 0: the engine is dead and the auto burns until it is repaired or towed.
func is_wrecked() -> bool:
	return condition <= 0.0 and not tutorial_active

## Flames are showing (DamageFX fire stage) or the auto is wrecked. Nobody gets in, no refuelling,
## no side quests; the controller's limp mode is cutting the engine.
func is_on_fire() -> bool:
	return is_wrecked() or (not tutorial_active and damage_severity() >= DamageFX.FIRE_FROM)

## 0 (fine) .. 1 (wrecked): drives the smoke, then the fire (DamageFX).
func damage_severity() -> float:
	return clampf(1.0 - condition / 100.0, 0.0, 1.0)

func marks() -> Dictionary:
	if not damage_marks.has(active_vehicle):
		damage_marks[active_vehicle] = {"dents": [], "crack": [0.0, 136.0]}
	return damage_marks[active_vehicle] as Dictionary

## A dent at `p` (auto mesh space). Close to an existing dent it deepens that one instead.
func add_dent(p: Vector3, strength: float) -> void:
	if tutorial_active or strength <= 0.0 or not p.is_finite():
		return
	var dents: Array = marks()["dents"]
	var best: int = -1
	var best_d: float = INF
	for i: int in dents.size():
		var q: Array = dents[i]
		var d: float = p.distance_to(Vector3(float(q[0]), float(q[1]), float(q[2])))
		if d < best_d:
			best_d = d
			best = i
	if best >= 0 and (best_d < 18.0 or dents.size() >= MAX_DENTS):
		var q2: Array = dents[best]
		q2[3] = minf(1.0, float(q2[3]) + strength * 0.7)
	else:
		dents.append([p.x, p.y, p.z, clampf(strength, 0.0, 1.0)])
	SignalBus.damage_changed.emit()

func set_crack_origin(x: float, y: float) -> void:
	if tutorial_active or not is_finite(x) or not is_finite(y):
		return
	if float(damage_state()["glass"]) < 1.0:
		marks()["crack"] = [x, y]

## Last resort when the wallet is empty and no ad is available: the mechanic gets a wrecked auto
## running again at PATCH_UP_CONDITION (still smoking), so the player is never stuck.
const PATCH_UP_CONDITION: float = 15.0

func patch_up() -> void:
	if not is_wrecked():
		return
	condition = PATCH_UP_CONDITION
	SignalBus.condition_changed.emit(condition)
	SignalBus.damage_changed.emit()
	SignalBus.vehicle_wrecked.emit(false)

## The rewarded "free repair" for a wrecked auto: everything back to new.
func repair_free() -> void:
	var was_wrecked: bool = is_wrecked()
	component_damage[active_vehicle] = clean_damage({})
	damage_marks.erase(active_vehicle)
	condition = 100.0
	SignalBus.condition_changed.emit(condition)
	SignalBus.damage_changed.emit()
	if was_wrecked:
		SignalBus.vehicle_wrecked.emit(false)
	_loadout_changed()

func damage_state() -> Dictionary:
	if not component_damage.has(active_vehicle):
		component_damage[active_vehicle] = clean_damage({})
	return component_damage[active_vehicle] as Dictionary

## Validates saved marks: at most MAX_DENTS finite dents with strength 0..1, a finite crack origin.
func clean_marks(raw: Variant) -> Dictionary:
	var out: Dictionary = {"dents": [], "crack": [0.0, 136.0]}
	if not raw is Dictionary:
		return out
	var dents: Variant = (raw as Dictionary).get("dents", [])
	if dents is Array:
		for q: Variant in dents:
			if q is Array and (q as Array).size() == 4:
				var a: Array = q
				var v: Vector4 = Vector4(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
				if v.is_finite() and (out["dents"] as Array).size() < MAX_DENTS:
					(out["dents"] as Array).append([v.x, v.y, v.z, clampf(v.w, 0.0, 1.0)])
	var c: Variant = (raw as Dictionary).get("crack", [])
	if c is Array and (c as Array).size() == 2 and is_finite(float((c as Array)[0])) and is_finite(float((c as Array)[1])):
		out["crack"] = [float((c as Array)[0]), float((c as Array)[1])]
	return out

func clean_damage(raw: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["front", "rear", "left", "right", "engine", "steering", "suspension", "tyres", "lights",
			"mirror_l", "mirror_r", "glass"]:
		var value: float = float(raw.get(key, 0.0))
		result[key] = clampf(value, 0.0, 100.0) if is_finite(value) else 0.0
	return result

func _on_component_impact(info: Dictionary) -> void:
	if tutorial_active:
		return
	var hit: Vector3 = info.get("local_point", Vector3(0, 0, -1))
	var amount: float = DAMAGE.points(float(info.get("speed_mps", 0.0))) * DAMAGE.component_multiplier
	var zone: String = ("front" if hit.z < 0.0 else "rear") if absf(hit.z) >= absf(hit.x) else ("left" if hit.x < 0.0 else "right")
	var wear: Dictionary = damage_state()
	wear[zone] = minf(100.0, float(wear[zone]) + amount)
	var mechanical: String = "steering" if zone == "front" else ("engine" if zone == "rear" else "suspension")
	wear[mechanical] = minf(100.0, float(wear[mechanical]) + amount)
	wear["tyres"] = minf(100.0, float(wear["tyres"]) + amount * 0.25)
	wear["lights"] = minf(100.0, float(wear["lights"]) + amount * (0.7 if zone == "front" else 0.1))
	if zone == "front":
		wear["glass"] = minf(100.0, float(wear["glass"]) + amount * 1.2)
	# Side hits snap the mirror on that side (game -X = the auto's left).
	if zone == "left" and (amount >= MIRROR_BREAK_POINTS or float(wear["left"]) >= MIRROR_BREAK_WEAR):
		wear["mirror_l"] = 100.0
	if zone == "right" and (amount >= MIRROR_BREAK_POINTS or float(wear["right"]) >= MIRROR_BREAK_WEAR):
		wear["mirror_r"] = 100.0
	SignalBus.damage_changed.emit()

# --- Shift clock ------------------------------------------------------------------------

func clock_text() -> String:
	var m: int = int(shift_minute)
	var h: int = m / 60
	return "%d:%02d %s" % [((h + 11) % 12) + 1, m % 60, "AM" if h < 12 else "PM"]

func roll_weather() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(day * 7919)
	var month: int = int(Time.get_date_dict_from_system()["month"])
	var chance: float = MONSOON_RAIN_CHANCE if month >= 10 or month <= 1 else 0.12
	if rng.randf() < chance:
		var start: float = rng.randf_range(540.0, 960.0) # 9 AM – 4 PM
		rain_window = Vector2(start, start + rng.randf_range(120.0, 300.0))
	else:
		rain_window = Vector2(-1.0, -1.0)

## Force weather (tests, debug menu). duration in game minutes.
func set_rain(on: bool, duration_min: float = 180.0) -> void:
	# Vector2 is 32-bit: start a hair early so float rounding can't put "now" outside the window.
	rain_window = Vector2(shift_minute - 0.05, shift_minute + duration_min) if on else Vector2(-1.0, -1.0)
	_update_weather()

func _update_weather() -> void:
	var raining: bool = shift_minute >= rain_window.x and shift_minute < rain_window.y
	if raining != is_raining:
		is_raining = raining
		SignalBus.weather_changed.emit(is_raining)

func is_night() -> bool:
	return shift_minute >= 1140.0 or shift_minute < 375.0 # after 7 PM

func end_shift() -> void:
	shift_running = false
	shift_minute = SHIFT_END_MIN
	var summary: Dictionary = day_stats.duplicate()
	summary["day"] = day
	summary["wallet"] = wallet_inr
	summary["rating"] = star_rating
	rewards.add_stat("shifts", 1)
	_check_achievements()
	SignalBus.shift_ended.emit(summary)
	save_game()

func start_next_day() -> void:
	day += 1
	shift_minute = SHIFT_START_MIN
	shift_running = true
	day_stats = {"earned": 0, "rides": 0, "fuel_spent": 0, "repairs": 0}
	roll_weather()
	_update_weather()
	progress.roll_goals(day)
	SignalBus.goals_updated.emit(progress.goals)
	SignalBus.shift_clock_updated.emit(day, shift_minute)
	save_game()

# --- Settings -------------------------------------------------------------------------

func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	_apply_settings()
	SignalBus.settings_changed.emit(settings)
	save_game()

## Tamil glyphs: add Noto Sans Tamil (OFL) as a fallback to the default UI font.
## First launch on a phone: pick the graphics preset from device RAM (3–4 GB budget phones
## like Helio G85 / SD 680 start on Low: no shadows, 70 % 3D resolution). Player can change it.
func _auto_graphics_once() -> void:
	if settings.has("graphics_auto") or OS.get_name() != "Android":
		return
	var ram_gb: float = float(OS.get_memory_info().get("physical", 0)) / 1073741824.0
	settings["graphics"] = 0 if ram_gb > 0.0 and ram_gb < 4.5 else (1 if ram_gb < 7.0 else 2)
	settings["graphics_auto"] = true

func _install_tamil_font() -> void:
	var tamil: Font = load("res://assets/fonts/NotoSansTamil-Regular.ttf") as Font
	if tamil != null and ThemeDB.fallback_font != null:
		var fb: Array[Font] = ThemeDB.fallback_font.fallbacks
		if not fb.has(tamil):
			fb.append(tamil)
			ThemeDB.fallback_font.fallbacks = fb

## Graphics presets: 0 Low (no shadows, 70% 3D resolution), 1 Medium, 2 High.
const GRAPHICS_SCALE: Array[float] = [0.7, 0.85, 1.0]
## Shadow edges per preset. Oct 31 device test: shadows looked jagged. On Android the engine's
## ".mobile" default is HARD (unfiltered) directional shadows and no anti-aliasing, so every
## shadow edge stair-stepped. Medium and High use soft PCF (the "very low" level dithers into
## visible grain on car bodies, so it is skipped). High also doubles the
## shadow map and adds 2x MSAA (tile GPUs resolve it on-chip).
const SHADOW_FILTER: Array[int] = [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW]
const SHADOW_ATLAS: Array[int] = [1024, 2048, 4096]
const MSAA_3D: Array[int] = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X]

func _apply_settings() -> void:
	TranslationServer.set_locale(str(settings.get("language", "en")))
	var gfx: int = clampi(int(settings.get("graphics", 1)), 0, 2)
	get_tree().root.scaling_3d_scale = GRAPHICS_SCALE[gfx]
	for n: Node in get_tree().get_nodes_in_group("sun_light"):
		(n as DirectionalLight3D).shadow_enabled = gfx > 0
	RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_FILTER[gfx])
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[gfx], true)
	get_tree().root.msaa_3d = MSAA_3D[gfx] as Viewport.MSAA
	var master: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, linear_to_db(maxf(float(settings.get("master_volume", 0.9)), 0.001)))

# --- Save / load ---------------------------------------------------------------------

func _key() -> String:
	return "namma-auto-%d|%s" % [SAVE_KEY_VERSION, OS.get_unique_id()]

func to_dict() -> Dictionary:
	return {
		"missions": {"schema": 1, "run": mission_run.duplicate(true), "completed": mission_completed.duplicate(true)},
		"version": SAVE_VERSION, "wallet": wallet_inr, "respect": stand_respect_xp, "rating": star_rating,
		"rides": completed_savaris, "owned": Array(owned_vehicles), "active": active_vehicle, "upgrades": upgrades,
		"horns_owned": horns_owned, "horn": horn_equipped, "paints": Array(paints_owned), "paint": paint_equipped,
		"fuel": fuel_level, "condition": condition, "parked": parked_autos.duplicate(true), "damage": component_damage.duplicate(true), "marks": damage_marks.duplicate(true), "day": day, "minute": shift_minute, "day_stats": day_stats,
		"settings": settings, "rain": [rain_window.x, rain_window.y], "progress": progress.to_dict(),
		"rewards": rewards.to_dict(), "no_ads": no_ads,
	}

func from_dict(d: Dictionary) -> void:
	mission_active = false
	mission_run = {}
	mission_completed = {}
	var missions: Variant = d.get("missions", {})
	if missions is Dictionary:
		if missions.get("run") is Dictionary:
			mission_run = (missions["run"] as Dictionary).duplicate(true)
		if missions.get("completed") is Dictionary:
			mission_completed = (missions["completed"] as Dictionary).duplicate(true)
	wallet_inr = int(d.get("wallet", wallet_inr))
	stand_respect_xp = int(d.get("respect", stand_respect_xp))
	star_rating = float(d.get("rating", star_rating))
	completed_savaris = int(d.get("rides", completed_savaris))
	owned_vehicles = PackedStringArray(d.get("owned", ["singara_classic"]))
	active_vehicle = str(d.get("active", "singara_classic"))
	if not owned_vehicles.has(active_vehicle):
		active_vehicle = "singara_classic"
	upgrades = d.get("upgrades", {})
	horns_owned = int(d.get("horns_owned", 0))
	horn_equipped = clampi(int(d.get("horn", 0)), 0, horns_owned)
	paints_owned = PackedInt32Array(d.get("paints", [0]))
	paint_equipped = int(d.get("paint", 0)) if paints_owned.has(int(d.get("paint", 0))) else 0
	fuel_level = float(d.get("fuel", -1.0))
	condition = float(d.get("condition", 100.0))
	parked_autos = {}
	var raw_parked: Variant = d.get("parked", {})
	if raw_parked is Dictionary:
		for vehicle: String in raw_parked:
			if raw_parked[vehicle] is Dictionary:
				parked_autos[vehicle] = (raw_parked[vehicle] as Dictionary).duplicate()
	component_damage = (d.get("damage", {}) as Dictionary).duplicate(true)
	for vehicle: String in component_damage:
		component_damage[vehicle] = clean_damage(component_damage[vehicle] as Dictionary)
	damage_marks = {}
	var raw_marks: Variant = d.get("marks", {})
	if raw_marks is Dictionary:
		for vehicle: String in raw_marks:
			damage_marks[vehicle] = clean_marks(raw_marks[vehicle])
	day = int(d.get("day", 1))
	shift_minute = float(d.get("minute", SHIFT_START_MIN))
	day_stats = d.get("day_stats", day_stats)
	var rw: Array = d.get("rain", [-1.0, -1.0])
	rain_window = Vector2(float(rw[0]), float(rw[1]))
	progress = DriverProgress.new()
	progress.from_dict(d.get("progress", {}))
	rewards = RewardsEngine.new()
	rewards.from_dict(d.get("rewards", {}))
	no_ads = bool(d.get("no_ads", false))
	if progress.goals_day != day:
		progress.roll_goals(day)
	var s: Dictionary = d.get("settings", {})
	for k: String in s:
		settings[k] = s[k]
	# Saves from before the guided first ride: a driver who already earned a fare skips it.
	if not d.is_empty() and not s.has("first_ride_done"):
		settings["first_ride_done"] = completed_savaris > 0
		settings["first_ride_step"] = 0
	settings.erase("tutorial_step") # old 5-hint system (ComfortAssist), replaced by TutorialDirector
	# Controls v2 (steer buttons + pedals) became the default; move old saves onto it once.
	if not bool(s.get("controls_v2", false)):
		settings["control_scheme"] = 1
		settings["controls_v2"] = true

	# A saved scenario must not leak into the menu before the gameplay scene resumes.
	var scenario: Variant = mission_run.get("scenario", {})
	if scenario is Dictionary and scenario.has("minute"):
		shift_minute = float(scenario["minute"])
		shift_running = bool(scenario.get("running", true))
		var saved_rain: Variant = scenario.get("rain", [])
		if saved_rain is Array and saved_rain.size() == 2:
			rain_window = Vector2(float(saved_rain[0]), float(saved_rain[1]))
		is_raining = bool(scenario.get("raining", false))
	SignalBus.mission_profile_loaded.emit()

func save_game() -> bool:
	if not persistence_enabled or mission_reward_transaction:
		return false
	var payload: String = JSON.stringify(to_dict())
	var f: FileAccess = FileAccess.open_encrypted_with_pass(save_path + ".tmp", FileAccess.WRITE, _key())
	if f == null:
		return false
	# Encrypted container already detects corruption; the hash also catches edits made
	# with the right key but outside the game (e.g. a patched build).
	f.store_string(JSON.stringify({"p": payload, "h": (payload + _key()).sha256_text()}))
	f.flush()
	var write_error: Error = f.get_error()
	f.close()
	if write_error != OK:
		return false
	return DirAccess.rename_absolute(save_path + ".tmp", save_path) == OK

## Returns false (and keeps defaults) for a missing, corrupt or tampered save.
func load_game() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var f: FileAccess = FileAccess.open_encrypted_with_pass(save_path, FileAccess.READ, _key())
	if f == null:
		push_warning("GameState: save unreadable (tampered or from another device) — starting fresh")
		return false
	var wrapper: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (wrapper is Dictionary) or not (wrapper as Dictionary).has("p"):
		return false
	var payload: String = str((wrapper as Dictionary)["p"])
	if (payload + _key()).sha256_text() != str((wrapper as Dictionary).get("h", "")):
		push_warning("GameState: save checksum mismatch — starting fresh")
		return false
	var d: Variant = JSON.parse_string(payload)
	if not (d is Dictionary):
		return false
	from_dict(d as Dictionary)
	return true

## Back to a brand-new driver (tests and a future "reset progress" button).
func has_save() -> bool:
	return persistence_enabled and FileAccess.file_exists(save_path)

## Main menu "New game": fresh career, but keep the player's settings (language, controls…).
func new_career() -> void:
	var keep: Dictionary = settings.duplicate()
	reset_profile()
	keep["first_ride_step"] = 0
	keep["first_ride_done"] = false
	keep.erase("quest_track_id")
	keep.erase("quest_lesson_done")
	settings = keep
	day = 1
	shift_minute = SHIFT_START_MIN
	roll_weather()
	_update_weather()
	_apply_settings()
	save_game()

func reset_profile() -> void:
	from_dict({})
	wallet_inr = 500
	stand_respect_xp = 100
	star_rating = 4.5
	completed_savaris = 0
	upgrades = {}
	day_stats = {"earned": 0, "rides": 0, "fuel_spent": 0, "repairs": 0}
	shift_running = true
