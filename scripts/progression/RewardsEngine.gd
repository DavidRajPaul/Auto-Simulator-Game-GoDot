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
const DAILY_CAPS: Dictionary = {"ad_double_fare": 12, "ad_fuel_rescue": 4, "ad_tow": 4, "ad_test_drive": 3, "daily_login": 1}
## Rewarded-ad offers: kind -> {text, fixed inr (0 = computed by caller)}.
const AD_OFFERS: Dictionary = {
	"ad_double_fare": {"label": "AD_DOUBLE_FARE"},
	"ad_fuel_rescue": {"label": "AD_FUEL_RESCUE"},
	"ad_tow": {"label": "AD_FREE_TOW"},
	"ad_test_drive": {"label": "AD_TEST_DRIVE"},
}

## Achievements: id -> {title, desc, stat, target, inr, xp, gpgs (Play Games id placeholder)}.
## Replace the gpgs ids with the real ones from Play Console → Play Games Services → Achievements.
const ACHIEVEMENTS: Dictionary = {
	"first_savari": {"title": "Muthal Savari", "desc": "Complete your first ride", "stat": "rides", "target": 1, "inr": 50, "xp": 20, "gpgs": "CgkI_PLACEHOLDER_01"},
	"savari_25": {"title": "Stand Regular", "desc": "Complete 25 rides", "stat": "rides", "target": 25, "inr": 250, "xp": 100, "gpgs": "CgkI_PLACEHOLDER_02"},
	"savari_100": {"title": "100 Savaris", "desc": "Complete 100 rides", "stat": "rides", "target": 100, "inr": 1000, "xp": 300, "gpgs": "CgkI_PLACEHOLDER_03"},
	"honest_meter_20": {"title": "Meter Podu!", "desc": "Charge the correct meter 20 times", "stat": "meter_rides", "target": 20, "inr": 300, "xp": 120, "gpgs": "CgkI_PLACEHOLDER_04"},
	"smooth_10": {"title": "Tea Didn't Spill", "desc": "10 rides with a full tea cup", "stat": "smooth_rides", "target": 10, "inr": 200, "xp": 80, "gpgs": "CgkI_PLACEHOLDER_05"},
	"gethu_50": {"title": "Gap-la Guru", "desc": "50 Gap-la Gethu near misses", "stat": "near_misses", "target": 50, "inr": 250, "xp": 100, "gpgs": "CgkI_PLACEHOLDER_06"},
	"earn_10k": {"title": "Pocket Full of Rupees", "desc": "Earn ₹10,000 in fares", "stat": "earned", "target": 10000, "inr": 500, "xp": 150, "gpgs": "CgkI_PLACEHOLDER_07"},
	"monsoon_10": {"title": "Monsoon Warrior", "desc": "10 rides in the rain", "stat": "rain_rides", "target": 10, "inr": 300, "xp": 120, "gpgs": "CgkI_PLACEHOLDER_08"},
	"night_10": {"title": "Marina Night Rider", "desc": "10 rides after 7 PM", "stat": "night_rides", "target": 10, "inr": 300, "xp": 120, "gpgs": "CgkI_PLACEHOLDER_09"},
	"streak_7": {"title": "Every Day at the Stand", "desc": "Log in 7 days in a row", "stat": "best_streak", "target": 7, "inr": 300, "xp": 100, "gpgs": "CgkI_PLACEHOLDER_10"},
	"no_crash_5": {"title": "Clean Hands", "desc": "5 rides in a row without a crash", "stat": "clean_streak", "target": 5, "inr": 200, "xp": 80, "gpgs": "CgkI_PLACEHOLDER_11"},
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
		if not str(old["id"]).begins_with("ach:") and not str(old["id"]).begins_with("daily:"):
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
