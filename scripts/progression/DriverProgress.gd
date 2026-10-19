class_name DriverProgress
extends RefCounted
## Driver levels + daily shift goals (pure data/logic; GameState owns one and saves it).
##
## Namma Auto has no "level 1-2-3" stages: the whole city is open from minute one (GDD
## pillar 2, and the top complaint about rival games was gated free roam). Instead:
##   • Driver Level 1–20 from Driver XP, earned by every ride (more for comfort, on-time,
##     honest "Correct Meter" fares and near misses) and by signalling your turns.
##     Each level pays a cash bonus and gives a stand title; a few cosmetics/autos unlock.
##   • Three shift goals per day (e.g. "3 smooth rides", "Earn ₹300"), a short-session hook.

const MAX_LEVEL: int = 20
## Stand titles per level (index = level - 1). Tanglish, like the stand would call you.
const TITLES: PackedStringArray = [
	"Puthu Driver", "Stand Member", "Meter Maestro", "Gap-la Guru", "Mylapore Regular",
	"Marina Night Rider", "Usman Road Pro", "Anna Salai Ace", "Monsoon Warrior", "Stand Leader",
	"Kapali Koil Express", "T. Nagar Tiger", "Gemini Flyer", "Mount Road Master", "Chennai Captain",
	"Madras Maverick", "Singara Star", "Auto Annachi", "Stand Thalaivar", "Madras Legend",
]
## What each level unlocks (shown on level-up and in the garage). Never core gameplay.
const UNLOCKS: Dictionary = {
	3: "UNLOCK_DISPATCH_TEASER", 4: "UNLOCK_AIR_HORN", 5: "UNLOCK_EV", 6: "UNLOCK_NEON", 10: "UNLOCK_GOLD_METER",
}
## Garage items that need a driver level ("kind:id" → level).
const REQUIRED_LEVEL: Dictionary = {"horn:2": 4, "vehicle:namma_green_ev": 5, "paint:4": 6}

const RIDE_XP_BASE: int = 20
const RIDE_XP_COMFORT: int = 10 # × comfort (0–1)
const RIDE_XP_ON_TIME: int = 5
const RIDE_XP_HONEST_METER: int = 3
const RIDE_XP_PER_NEAR_MISS: int = 2
const SIGNAL_XP: int = 2
const GOAL_XP: int = 60
const GOAL_INR: int = 40
const ALL_GOALS_BONUS_INR: int = 100

## Goal templates: kind → [text key, min target, max target].
const GOAL_TEMPLATES: Dictionary = {
	"rides": ["GOAL_RIDES", 3, 5],
	"smooth": ["GOAL_SMOOTH", 2, 3],
	"earn": ["GOAL_EARN", 250, 400],
	"meter": ["GOAL_METER", 2, 3],
	"gethu": ["GOAL_GETHU", 3, 5],
	"signal": ["GOAL_SIGNAL", 4, 6],
}
const SMOOTH_COMFORT: float = 0.8

var xp: int = 0
var goals: Array[Dictionary] = [] # {kind, text, target, progress, done}
var goals_day: int = -1

static func xp_for_level(level: int) -> int:
	return 50 * level * (level - 1)

static func level_for_xp(total_xp: int) -> int:
	var lvl: int = 1
	while lvl < MAX_LEVEL and total_xp >= xp_for_level(lvl + 1):
		lvl += 1
	return lvl

static func title(level: int) -> String:
	return TITLES[clampi(level, 1, MAX_LEVEL) - 1]

## Cash bonus paid when reaching `level`.
static func level_reward_inr(level: int) -> int:
	return 50 * level

static func required_level(key: String) -> int:
	return int(REQUIRED_LEVEL.get(key, 1))

func level() -> int:
	return level_for_xp(xp)

## 0–1 progress towards the next level.
func level_progress() -> float:
	var l: int = level()
	if l >= MAX_LEVEL:
		return 1.0
	var a: int = xp_for_level(l)
	return float(xp - a) / float(xp_for_level(l + 1) - a)

static func ride_xp(breakdown: Dictionary) -> int:
	var x: int = RIDE_XP_BASE + roundi(RIDE_XP_COMFORT * clampf(float(breakdown.get("comfort", 0.0)), 0.0, 1.0))
	if bool(breakdown.get("on_time", false)):
		x += RIDE_XP_ON_TIME
	if int(breakdown.get("offer", -1)) == 0:
		x += RIDE_XP_HONEST_METER
	x += RIDE_XP_PER_NEAR_MISS * int(breakdown.get("near_misses", 0))
	return x

## Three distinct goals for a day, deterministic per day number.
func roll_goals(day: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("goals-%d" % day)
	var kinds: Array = GOAL_TEMPLATES.keys()
	goals.clear()
	while goals.size() < 3:
		var k: String = kinds[rng.randi() % kinds.size()]
		var taken: bool = false
		for g: Dictionary in goals:
			taken = taken or str(g["kind"]) == k
		if taken:
			continue
		var t: Array = GOAL_TEMPLATES[k]
		var target: int = rng.randi_range(int(t[1]), int(t[2]))
		if k == "earn":
			target = int(roundf(float(target) / 50.0) * 50.0)
		goals.append({"kind": k, "text": str(t[0]), "target": target, "progress": 0, "done": false})
	goals_day = day

## Apply an event to the goals. Returns the goals that just completed.
func advance(kind: String, amount: int) -> Array[Dictionary]:
	var done: Array[Dictionary] = []
	for g: Dictionary in goals:
		if bool(g["done"]) or str(g["kind"]) != kind:
			continue
		g["progress"] = mini(int(g["target"]), int(g["progress"]) + amount)
		if int(g["progress"]) >= int(g["target"]):
			g["done"] = true
			done.append(g)
	return done

func all_goals_done() -> bool:
	for g: Dictionary in goals:
		if not bool(g["done"]):
			return false
	return not goals.is_empty()

func to_dict() -> Dictionary:
	return {"xp": xp, "goals": goals, "goals_day": goals_day}

func from_dict(d: Dictionary) -> void:
	xp = int(d.get("xp", 0))
	goals_day = int(d.get("goals_day", -1))
	goals.clear()
	for g: Variant in d.get("goals", []):
		if g is Dictionary:
			goals.append(g as Dictionary)
