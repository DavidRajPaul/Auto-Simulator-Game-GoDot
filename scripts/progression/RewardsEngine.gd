class_name RewardsEngine
extends RefCounted
## One pipeline for every reward the game hands out, built to survive a Play Store launch:
##
##   • grant(source, inr, xp, id)  — the ONLY way rewards enter the wallet from here: logged in a
##     capped ledger, idempotent by `id` (a double-tapped "2× fare" button or a replayed ad
##     callback can never pay twice), and rate-limited per source per day.
##   • Daily login calendar — 7-day streak (₹ grows, day 7 is a jackpot), resets after a missed
##     day, claimable once per calendar day (device date; Play Games cloud save mirrors it).
##   • Achievements — persistent, one-time, mapped to Google Play Games achievement ids.
##   • Rewarded-ad payouts — 2× fare, LPG rescue, free tow, garage test drive — only after the ad
##     provider confirms the user earned it (AdMonetizationManager → SignalBus.rewarded_ad_completed).
##
## Pure logic + data; GameState owns one instance and saves it. Unit-tested (phase 7 suite).

const LEDGER_MAX: int = 200
## Daily calendar: ₹ for streak days 1–7 (day 7 = jackpot), then the cycle repeats.
const DAILY_INR: Array[int] = [50, 75, 100, 125, 150, 200, 500]
const DAILY_XP: Array[int] = [10, 10, 15, 15, 20, 25, 60]
## Max grants per source per calendar day (anti-abuse; ads also have their own caps).
const DAILY_CAPS: Dictionary = {"ad_double_fare": 12, "ad_fuel_rescue": 4, "ad_tow": 4, "ad_test_drive": 3, "ad_wreck_repair": 3, "daily_login": 1}
## Rewarded-ad offers: kind -> {text, fixed inr (0 = computed by caller)}.
const AD_OFFERS: Dictionary = {
	"ad_double_fare": {"label": "AD_DOUBLE_FARE"},
	"ad_fuel_rescue": {"label": "AD_FUEL_RESCUE"},
	"ad_tow": {"label": "AD_FREE_TOW"},
	"ad_test_drive": {"label": "AD_TEST_DRIVE"},
	"ad_wreck_repair": {"label": "AD_WRECK_REPAIR"},
}

## Achievements: id -> {title, desc, cat, stat, target, inr, xp, unit?, gpgs (Play Games id placeholder)}.
## title/desc are the English source; screens show tr(title_key(id)) / tr(desc_key(id)).
## Listed in display order inside each category. unit: "inr" or "km" (stat in metres) for the progress text.
## Replace the gpgs ids with the real ones from Play Console → Play Games Services → Achievements.
const ACHIEVEMENTS: Dictionary = {
	"first_savari": {"title": "Muthal Savari", "desc": "Complete your first ride", "cat": "rides", "stat": "rides", "target": 1, "inr": 50, "xp": 20, "gpgs": "CgkI_PLACEHOLDER_01"},
	"savari_25": {"title": "Stand Regular", "desc": "Complete 25 rides", "cat": "rides", "stat": "rides", "target": 25, "inr": 250, "xp": 100, "gpgs": "CgkI_PLACEHOLDER_02"},
	"savari_100": {"title": "100 Savaris", "desc": "Complete 100 rides", "cat": "rides", "stat": "rides", "target": 100, "inr": 1000, "xp": 300, "gpgs": "CgkI_PLACEHOLDER_03"},
	"savari_250": {"title": "Route Expert", "desc": "Complete 250 rides", "cat": "rides", "stat": "rides", "target": 250, "inr": 1500, "xp": 400, "gpgs": "CgkI_PLACEHOLDER_12"},
	"savari_500": {"title": "Auto Anna", "desc": "Complete 500 rides", "cat": "rides", "stat": "rides", "target": 500, "inr": 3000, "xp": 800, "gpgs": "CgkI_PLACEHOLDER_13"},
	"km_50": {"title": "City Rounds", "desc": "Carry riders for 50 km", "cat": "rides", "stat": "ride_m", "target": 50000, "inr": 300, "xp": 120, "unit": "km", "gpgs": "CgkI_PLACEHOLDER_14"},
	"km_250": {"title": "Every Street Known", "desc": "Carry riders for 250 km", "cat": "rides", "stat": "ride_m", "target": 250000, "inr": 1000, "xp": 300, "unit": "km", "gpgs": "CgkI_PLACEHOLDER_15"},
	"honest_meter_20": {"title": "Meter Podu!", "desc": "Charge the correct meter 20 times", "cat": "honest", "stat": "meter_rides", "target": 20, "inr": 300, "xp": 120, "gpgs": "CgkI_PLACEHOLDER_04"},
	"honest_meter_100": {"title": "Meter Mannan", "desc": "Charge the correct meter 100 times", "cat": "honest", "stat": "meter_rides", "target": 100, "inr": 1000, "xp": 300, "gpgs": "CgkI_PLACEHOLDER_16"},
	"mela_25": {"title": "Meter Mela Master", "desc": "Win 25 Meter Mela bargains", "cat": "honest", "stat": "mela_rides", "target": 25, "inr": 400, "xp": 120, "gpgs": "CgkI_PLACEHOLDER_17"},
	"on_time_25": {"title": "Right on Time", "desc": "Finish 25 rides on time", "cat": "honest", "stat": "on_time_rides", "target": 25, "inr": 300, "xp": 120, "gpgs": "CgkI_PLACEHOLDER_18"},
	"rider_types_5": {"title": "Everyone's Auto", "desc": "Carry all 5 kinds of rider", "cat": "honest", "stat": "rider_types", "target": 5, "inr": 300, "xp": 120, "gpgs": "CgkI_PLACEHOLDER_19"},
	"smooth_10": {"title": "Tea Didn't Spill", "desc": "10 rides with a full tea cup", "cat": "comfort", "stat": "smooth_rides", "target": 10, "inr": 200, "xp": 80, "gpgs": "CgkI_PLACEHOLDER_05"},
	"smooth_50": {"title": "Tea Master", "desc": "50 rides with a full tea cup", "cat": "comfort", "stat": "smooth_rides", "target": 50, "inr": 800, "xp": 250, "gpgs": "CgkI_PLACEHOLDER_20"},
	"stars_25": {"title": "Five-Star Savari", "desc": "Earn 5 stars on 25 rides", "cat": "comfort", "stat": "five_star_rides", "target": 25, "inr": 600, "xp": 200, "gpgs": "CgkI_PLACEHOLDER_21"},
	"no_crash_5": {"title": "Clean Hands", "desc": "5 rides in a row without a crash", "cat": "comfort", "stat": "best_clean_streak", "target": 5, "inr": 200, "xp": 80, "gpgs": "CgkI_PLACEHOLDER_11"},
	"no_crash_20": {"title": "Not a Scratch", "desc": "20 rides in a row without a crash", "cat": "comfort", "stat": "best_clean_streak", "target": 20, "inr": 800, "xp": 250, "gpgs": "CgkI_PLACEHOLDER_22"},
	"gethu_50": {"title": "Gap-la Guru", "desc": "50 Gap-la Gethu near misses", "cat": "skill", "stat": "near_misses", "target": 50, "inr": 250, "xp": 100, "gpgs": "CgkI_PLACEHOLDER_06"},
	"gethu_250": {"title": "Gap Thalaivar", "desc": "250 Gap-la Gethu near misses", "cat": "skill", "stat": "near_misses", "target": 250, "inr": 800, "xp": 250, "gpgs": "CgkI_PLACEHOLDER_23"},
	"signals_100": {"title": "Indicator Podu", "desc": "Signal 100 turns", "cat": "skill", "stat": "signals", "target": 100, "inr": 300, "xp": 100, "gpgs": "CgkI_PLACEHOLDER_24"},
	"monsoon_10": {"title": "Monsoon Warrior", "desc": "10 rides in the rain", "cat": "city", "stat": "rain_rides", "target": 10, "inr": 300, "xp": 120, "gpgs": "CgkI_PLACEHOLDER_08"},
	"monsoon_50": {"title": "Mazhai Raja", "desc": "50 rides in the rain", "cat": "city", "stat": "rain_rides", "target": 50, "inr": 1000, "xp": 300, "gpgs": "CgkI_PLACEHOLDER_25"},
	"night_10": {"title": "Marina Night Rider", "desc": "10 rides after 7 PM", "cat": "city", "stat": "night_rides", "target": 10, "inr": 300, "xp": 120, "gpgs": "CgkI_PLACEHOLDER_09"},
	"night_50": {"title": "Night Shift Legend", "desc": "50 rides after 7 PM", "cat": "city", "stat": "night_rides", "target": 50, "inr": 1000, "xp": 300, "gpgs": "CgkI_PLACEHOLDER_26"},
	"earn_10k": {"title": "Pocket Full of Rupees", "desc": "Earn ₹10,000 in fares", "cat": "money", "stat": "earned", "target": 10000, "inr": 500, "xp": 150, "unit": "inr", "gpgs": "CgkI_PLACEHOLDER_07"},
	"earn_50k": {"title": "Stand Owner Material", "desc": "Earn ₹50,000 in fares", "cat": "money", "stat": "earned", "target": 50000, "inr": 1500, "xp": 400, "unit": "inr", "gpgs": "CgkI_PLACEHOLDER_27"},
	"earn_100k": {"title": "Lakhpati Auto", "desc": "Earn ₹1,00,000 in fares", "cat": "money", "stat": "earned", "target": 100000, "inr": 3000, "xp": 800, "unit": "inr", "gpgs": "CgkI_PLACEHOLDER_28"},
	"best_fare_200": {"title": "Long Trip Jackpot", "desc": "Earn ₹200 or more from one ride", "cat": "money", "stat": "best_fare", "target": 200, "inr": 200, "xp": 80, "unit": "inr", "gpgs": "CgkI_PLACEHOLDER_29"},
	"streak_7": {"title": "Every Day at the Stand", "desc": "Log in 7 days in a row", "cat": "career", "stat": "best_streak", "target": 7, "inr": 300, "xp": 100, "gpgs": "CgkI_PLACEHOLDER_10"},
	"streak_30": {"title": "Stand Pillar", "desc": "Log in 30 days in a row", "cat": "career", "stat": "best_streak", "target": 30, "inr": 1500, "xp": 400, "gpgs": "CgkI_PLACEHOLDER_30"},
	"shifts_7": {"title": "Full Week", "desc": "Finish 7 shifts", "cat": "career", "stat": "shifts", "target": 7, "inr": 500, "xp": 150, "gpgs": "CgkI_PLACEHOLDER_31"},
	"goals_10": {"title": "Goal Getter", "desc": "Finish all 3 shift goals on 10 days", "cat": "career", "stat": "all_goal_days", "target": 10, "inr": 600, "xp": 200, "gpgs": "CgkI_PLACEHOLDER_32"},
	"level_5": {"title": "Mylapore Regular", "desc": "Reach Driver Level 5", "cat": "career", "stat": "level", "target": 5, "inr": 250, "xp": 0, "gpgs": "CgkI_PLACEHOLDER_33"},
	"level_10": {"title": "Stand Leader", "desc": "Reach Driver Level 10", "cat": "career", "stat": "level", "target": 10, "inr": 750, "xp": 0, "gpgs": "CgkI_PLACEHOLDER_34"},
	"level_20": {"title": "Madras Legend", "desc": "Reach Driver Level 20", "cat": "career", "stat": "level", "target": 20, "inr": 3000, "xp": 0, "gpgs": "CgkI_PLACEHOLDER_35"},
	"paint_first": {"title": "Alangaram", "desc": "Buy your first paint job", "cat": "career", "stat": "paints_owned", "target": 2, "inr": 100, "xp": 40, "gpgs": "CgkI_PLACEHOLDER_36"},
	"tuned_9": {"title": "Fully Tuned", "desc": "Buy 9 garage upgrades", "cat": "career", "stat": "upgrades_bought", "target": 9, "inr": 800, "xp": 250, "gpgs": "CgkI_PLACEHOLDER_37"},
	"own_autos_3": {"title": "Full Stand", "desc": "Own all 3 autos", "cat": "career", "stat": "autos_owned", "target": 3, "inr": 1000, "xp": 300, "gpgs": "CgkI_PLACEHOLDER_38"},
}
## Display order of the achievement categories: cat id -> translation key.
const ACHIEVEMENT_CATEGORIES: Dictionary = {
	"rides": "ACH_CAT_RIDES", "honest": "ACH_CAT_HONEST", "comfort": "ACH_CAT_COMFORT", "skill": "ACH_CAT_SKILL",
	"city": "ACH_CAT_CITY", "money": "ACH_CAT_MONEY", "career": "ACH_CAT_CAREER",
}

var ledger: Array[Dictionary] = [] # newest last: {id, source, inr, xp, date}
var granted_ids: Dictionary = {} # id -> true (kept small: ledger ids + one-time ids)
var daily_counts: Dictionary = {} # "source" -> count for daily_counts_date
var daily_counts_date: String = ""
var streak: int = 0
var last_login_date: String = "" # date of the last CLAIMED daily reward
var stats: Dictionary = {}
var achieved: Dictionary = {} # id -> date

# --- Grants ---------------------------------------------------------------------

## Returns the granted {inr, xp} (zeros if refused as duplicate or over the daily cap).
## Caller applies it to the wallet/XP (GameState does that through grant_reward()).
func grant(source: String, inr: int, xp: int, id: String, today: String) -> Dictionary:
	_roll_day(today)
	if id != "" and granted_ids.has(id):
		return {"inr": 0, "xp": 0, "refused": "duplicate"}
	var cap: int = int(DAILY_CAPS.get(source, 1000000))
	if int(daily_counts.get(source, 0)) >= cap:
		return {"inr": 0, "xp": 0, "refused": "daily_cap"}
	daily_counts[source] = int(daily_counts.get(source, 0)) + 1
	if id != "":
		granted_ids[id] = true
	ledger.append({"id": id, "source": source, "inr": inr, "xp": xp, "date": today})
	while ledger.size() > LEDGER_MAX:
		var old: Dictionary = ledger.pop_front()
		# Keep one-time ids (achievements, daily claims) forever; ride/ad ids can expire.
		if not str(old["id"]).begins_with("ach:") and not str(old["id"]).begins_with("daily:") and not str(old["id"]).begins_with("mission:"):
			granted_ids.erase(old["id"])
	return {"inr": maxi(0, inr), "xp": maxi(0, xp), "refused": ""}

func remaining_today(source: String, today: String) -> int:
	_roll_day(today)
	return maxi(0, int(DAILY_CAPS.get(source, 1000000)) - int(daily_counts.get(source, 0)))

func _roll_day(today: String) -> void:
	if daily_counts_date != today:
		daily_counts_date = today
		daily_counts = {}

# --- Daily login calendar ---------------------------------------------------------

## What today's claim would pay and whether it's available: {available, day_index 0–6, inr, xp, streak}.
func daily_status(today: String) -> Dictionary:
	var next_streak: int = 1
	if last_login_date == today:
		return {"available": false, "day_index": (streak - 1) % 7, "inr": 0, "xp": 0, "streak": streak}
	if last_login_date != "" and days_between(last_login_date, today) == 1:
		next_streak = streak + 1
	var idx: int = (next_streak - 1) % 7
	return {"available": true, "day_index": idx, "inr": DAILY_INR[idx], "xp": DAILY_XP[idx], "streak": next_streak}

func claim_daily(today: String) -> Dictionary:
	var st: Dictionary = daily_status(today)
	if not bool(st["available"]):
		return {"inr": 0, "xp": 0, "refused": "claimed"}
	var g: Dictionary = grant("daily_login", int(st["inr"]), int(st["xp"]), "daily:" + today, today)
	if str(g["refused"]) == "":
		streak = int(st["streak"])
		last_login_date = today
		bump_stat_max("best_streak", streak)
		g["streak"] = streak
		g["day_index"] = st["day_index"]
	return g

# --- Achievements -----------------------------------------------------------------

func add_stat(stat: String, amount: int) -> void:
	stats[stat] = int(stats.get(stat, 0)) + amount

func set_stat(stat: String, value: int) -> void:
	stats[stat] = value

func bump_stat_max(stat: String, value: int) -> void:
	stats[stat] = maxi(int(stats.get(stat, 0)), value)

## Newly unlocked achievement ids (caller grants & announces them).
func check_achievements(today: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in ACHIEVEMENTS:
		if achieved.has(id):
			continue
		var a: Dictionary = ACHIEVEMENTS[id]
		if int(stats.get(str(a["stat"]), 0)) >= int(a["target"]):
			achieved[id] = today
			out.append(id)
	return out

func achievement_progress(id: String) -> float:
	var a: Dictionary = ACHIEVEMENTS[id]
	return clampf(float(stats.get(str(a["stat"]), 0)) / float(a["target"]), 0.0, 1.0)

static func title_key(id: String) -> String:
	return "ACH_%s" % id.to_upper()

static func desc_key(id: String) -> String:
	return "ACH_%s_DESC" % id.to_upper()

## "7 / 20", "₹1,860 / ₹10,000" or "12 / 50 km".
func achievement_progress_text(id: String) -> String:
	var a: Dictionary = ACHIEVEMENTS[id]
	var target: int = int(a["target"])
	var have: int = mini(int(stats.get(str(a["stat"]), 0)), target)
	match str(a.get("unit", "")):
		"inr":
			return "₹%s / ₹%s" % [UIKit.inr(have), UIKit.inr(target)]
		"km":
			return "%d / %d km" % [have / 1000, target / 1000]
		_:
			return "%d / %d" % [have, target]

## Ids still locked with some progress, closest to done first.
func nearest_achievements(count: int) -> Array[String]:
	var open: Array[String] = []
	for id: String in ACHIEVEMENTS:
		if not achieved.has(id) and achievement_progress(id) > 0.0:
			open.append(id)
	open.sort_custom(func(a: String, b: String) -> bool: return achievement_progress(a) > achievement_progress(b))
	return open.slice(0, count)

# --- Dates & persistence ----------------------------------------------------------

static func today_string() -> String:
	return Time.get_date_string_from_system()

static func days_between(a: String, b: String) -> int:
	var ua: int = Time.get_unix_time_from_datetime_string(a + "T00:00:00")
	var ub: int = Time.get_unix_time_from_datetime_string(b + "T00:00:00")
	return int(round(float(ub - ua) / 86400.0))

func to_dict() -> Dictionary:
	return {"ledger": ledger, "ids": granted_ids.keys(), "counts": daily_counts, "counts_date": daily_counts_date,
		"streak": streak, "last_login": last_login_date, "stats": stats, "achieved": achieved}

func from_dict(d: Dictionary) -> void:
	ledger.clear()
	for e: Variant in d.get("ledger", []):
		if e is Dictionary:
			ledger.append(e as Dictionary)
	granted_ids.clear()
	for id: Variant in d.get("ids", []):
		granted_ids[str(id)] = true
	daily_counts = d.get("counts", {})
	daily_counts_date = str(d.get("counts_date", ""))
	streak = int(d.get("streak", 0))
	last_login_date = str(d.get("last_login", ""))
	stats = d.get("stats", {})
	achieved = d.get("achieved", {})
