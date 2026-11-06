class_name FareCalculator
extends RefCounted
## Pure fare, bargaining and tip maths (GDD §1).
## No scene access — unit-tested in tests/run_phase3_tests.

enum Choice { ACCEPT, ASK_LOW, ASK_HIGH, LET_GO }

## Real km per game km. The world is built 1 : 1 from OSM since the MVP polish pass
## (Phases 2–4 used a 1 : 2.5 compressed map, where this was 2.5).
const REAL_KM_PER_GAME_KM: float = 1.0
## Respect XP for a fair deal, and when a rider leaves.
const RESPECT_XP_DEAL: int = 6
const RESPECT_XP_REJECTED: int = -1
const RESPECT_XP_INSULTED: int = -4
const NEAR_MISS_BONUS_INR: int = 5

## Meter fare (₹50 for 1.8 km + ₹25/km, nearest ₹5) for a game-world distance.
static func meter_fare(game_km: float, surge: float = 1.0) -> int:
	var real_km: float = game_km * REAL_KM_PER_GAME_KM
	var raw: float = (GameState.METER_BASE_FARE_INR + maxf(0.0, real_km - GameState.METER_BASE_KM) * GameState.METER_PER_KM_INR) * surge
	return int(roundf(raw / 5.0) * 5.0)

## --- Bargaining ---
## The rider opens with an offer and hides their top price. Clues on the card show which way it
## leans, so reading the rider is the skill: no percentages are shown. Each refused ask costs
## patience and a greedy ask costs double. When patience runs out the rider walks.
const CLUE_EFFECT: Dictionary = {"late": 0.16, "bags": 0.1, "rain": 0.13, "night": 0.12, "new": 0.12,
	"family": 0.08, "app": -0.12, "broke": -0.14, "bus": -0.08}
const GREED_PENALTY: float = 0.04
const MAX_GREED_STREAK: int = 5
const GREEDY_OVER: float = 0.22 # An ask this far past the top price is an insult.
const MIN_ASK_STEP_INR: int = 10
const HIGH_ASK_RATIO: float = 1.3
const COUNTER_SHARE: float = 0.6 # A counter moves this far toward the top price.
const STREAK_BONUS_INR: int = 5
const MAX_STREAK: int = 5
const OVERCHARGE_RATIO: float = 1.25 # Past this a rider pays, but tips half.

static func round5(v: float) -> int:
	return int(roundf(v / 5.0) * 5.0)

## The most this rider pays today. Never under the meter: an honest ask is always fair.
##   jitter — small per-rider randomness (±0.06), so a clue guides without giving the number.
static func rider_limit(meter: int, rider: PassengerArchetype, clues: PackedStringArray, prestige: float = 0.0,
		demand: float = 0.5, stars: float = 4.5, greed_streak: int = 0, jitter: float = 0.0) -> int:
	var ratio: float = rider.haggle_ceiling + jitter
	for clue: String in clues:
		ratio += float(CLUE_EFFECT.get(clue, 0.0))
	ratio += 0.05 * clampf(prestige, 0.0, 1.0)
	ratio += 0.16 * (clampf(demand, 0.0, 1.0) - 0.5) # Rush hour: fewer free autos.
	ratio += 0.06 * (clampf(stars, 1.0, 5.0) - 4.5)
	ratio -= GREED_PENALTY * float(clampi(greed_streak, 0, MAX_GREED_STREAK)) # Word spreads at the stand.
	return maxi(meter, round5(float(meter) * ratio))

static func opening_offer(meter: int, rider: PassengerArchetype, clues: PackedStringArray) -> int:
	var ratio: float = rider.haggle_open_ratio
	if clues.has("app") or clues.has("broke"):
		ratio -= 0.08
	return mini(meter, round5(float(meter) * ratio))

## The two prices a player can ask next. Low is at least the meter; high is a real gamble.
static func next_asks(offer: int, meter: int) -> Array[int]:
	var low: int = maxi(meter, offer + MIN_ASK_STEP_INR)
	return [low, maxi(low + MIN_ASK_STEP_INR, round5(float(low) * HIGH_ASK_RATIO))]

## One round: {accepted, walked, insulted, offer, patience}. Pure, so it is fully unit-tested.
static func respond(ask: int, limit: int, offer: int, patience: int) -> Dictionary:
	if ask <= limit:
		return {"accepted": true, "walked": false, "insulted": false, "offer": ask, "patience": patience}
	var insulted: bool = float(ask - limit) / float(limit) > GREEDY_OVER
	var left: int = patience - (2 if insulted else 1)
	var counter: int = mini(limit, maxi(offer + 5, round5(float(offer) + float(limit - offer) * COUNTER_SHARE)))
	return {"accepted": false, "walked": left <= 0, "insulted": insulted, "offer": counter, "patience": maxi(left, 0)}

## Drive-time allowance for a route (m) at a realistic city pace plus the rider's slack.
static func ride_time_limit_s(route_m: float, rider: PassengerArchetype) -> float:
	return route_m / 7.0 + rider.timer_slack_s

## Final settlement shown on the fare breakdown screen.
## comfort: 0–1 tea-cup level at drop-off; near_misses: Gap-la Gethu count during the ride.
## tip_bonus: extra tip fraction (e.g. +0.25 green-ride bonus from IT riders in the EV).
## meter_inr: a rider charged far over it tips half; deal_streak: fair deals in a row pay extra.
static func settle(agreed_fare: int, rider: PassengerArchetype, comfort: float, on_time: bool, near_misses: int, tip_bonus: float = 0.0, meter_inr: int = 0, deal_streak: int = 0) -> Dictionary:
	var c: float = clampf(comfort, 0.0, 1.0)
	var tip: int = roundi(float(rider.max_tip_inr) * c * (1.0 + tip_bonus)) if on_time else 0
	if meter_inr > 0 and float(agreed_fare) > float(meter_inr) * OVERCHARGE_RATIO:
		tip = tip / 2
	var streak_bonus: int = clampi(deal_streak, 0, MAX_STREAK) * STREAK_BONUS_INR if on_time else 0
	var gethu: int = 0
	if rider.likes_fast_driving:
		gethu = near_misses * (NEAR_MISS_BONUS_INR + rider.near_miss_tip_inr)
	var stars: float = clampf(1.0 + 4.0 * c - (0.0 if on_time else 1.0), 1.0, 5.0)
	return {
		"fare": agreed_fare,
		"comfort_tip": tip,
		"gethu_bonus": gethu,
		"streak_bonus": streak_bonus,
		"total": agreed_fare + tip + gethu + streak_bonus,
		"stars": stars,
		"on_time": on_time,
	}
