class_name FareCalculator
extends RefCounted
## Pure fare / haggling / tip maths for the "Meter Podu vs. Bargain" loop (GDD §1).
## No scene access — unit-tested in tests/run_phase3_tests.

enum Offer { METER, METER_MELA, FIXED }

const OFFER_NAMES: PackedStringArray = ["Correct Meter", "Meter Mela +₹30", "Fixed ₹200 — Return Empty!"]
const METER_MELA_EXTRA_INR: int = 30
const FIXED_RATE_INR: int = 200
## Real km per game km. The world is built 1 : 1 from OSM since the MVP polish pass
## (Phases 2–4 used a 1 : 2.5 compressed map, where this was 2.5).
const REAL_KM_PER_GAME_KM: float = 1.0
## Respect XP per accepted offer, and for a rejection.
const RESPECT_XP: Array[int] = [10, 2, -3]
const RESPECT_XP_REJECTED: int = -1
const NEAR_MISS_BONUS_INR: int = 5

## Meter fare (₹35 for 1.8 km + ₹18/km, nearest ₹5) for a game-world distance.
static func meter_fare(game_km: float, surge: float = 1.0) -> int:
	var real_km: float = game_km * REAL_KM_PER_GAME_KM
	var raw: float = (GameState.METER_BASE_FARE_INR + maxf(0.0, real_km - GameState.METER_BASE_KM) * GameState.METER_PER_KM_INR) * surge
	return int(roundf(raw / 5.0) * 5.0)

static func quote(offer: Offer, game_km: float, rider: PassengerArchetype) -> int:
	var meter: int = meter_fare(game_km, rider.surge_multiplier)
	match offer:
		Offer.METER_MELA:
			return meter + METER_MELA_EXTRA_INR
		Offer.FIXED:
			return maxi(FIXED_RATE_INR, meter + METER_MELA_EXTRA_INR)
		_:
			return meter

## Context for a haggle beyond the rider's archetype odds (all optional, neutral defaults).
##   meter_inr    — the honest meter fare; markups are judged against it (₹30 extra on a ₹40
##                  hop is outrageous, on a ₹150 trip it's normal Chennai bargaining)
##   demand       — 0–1 from TrafficDensity.rider_demand: rush hour/rain → riders need you
##   stars        — the driver's stand rating; a 3★ auto doesn't get to ask for extra
##   greed_streak — recent greedy asks; word spreads at the stand
const STRICT_MARKUP_FREE: float = 0.2 # markup up to 20 % of the meter costs nothing extra
const STRICT_MARKUP_SLOPE: float = 0.9 # each +100 % markup beyond that removes 90 % of the odds
const GREED_PENALTY: float = 0.06
const MAX_GREED_STREAK: int = 5

## Probability the rider accepts. Strict by design (GDD Meter Mela 65–85 % was too easy):
## base odds come from the archetype .tres, then scale down with the markup ratio, the
## driver's rating and recent greed, and up a little with rain, rush-hour demand and
## Alangaram prestige (0–1). The honest meter is always accepted.
static func acceptance_chance(offer: Offer, rider: PassengerArchetype, raining: bool = false, prestige: float = 0.0,
		meter_inr: int = 0, demand: float = 0.5, stars: float = 4.5, greed_streak: int = 0) -> float:
	if offer == Offer.METER:
		return clampf(rider.accept_meter_chance, 0.0, 1.0)
	var p: float = rider.accept_meter_mela_chance + 0.08 * clampf(prestige, 0.0, 1.0) if offer == Offer.METER_MELA else rider.accept_fixed_rate_chance
	if meter_inr > 0:
		var asked: int = meter_inr + METER_MELA_EXTRA_INR if offer == Offer.METER_MELA else maxi(FIXED_RATE_INR, meter_inr + METER_MELA_EXTRA_INR)
		var markup: float = float(asked - meter_inr) / float(meter_inr)
		p *= clampf(1.0 - STRICT_MARKUP_SLOPE * maxf(0.0, markup - STRICT_MARKUP_FREE), 0.05, 1.0)
	if raining:
		p += 0.06
	p += 0.12 * (clampf(demand, 0.0, 1.0) - 0.5) # off-peak riders shop around, peak riders don't
	p *= clampf(0.55 + 0.1 * stars, 0.75, 1.0) # 4.5★ = 1.0, 3★ = 0.85, 2★ = 0.75
	p -= GREED_PENALTY * float(clampi(greed_streak, 0, MAX_GREED_STREAK))
	return clampf(p, 0.02, 0.95)

## Drive-time allowance for a route (m) at a realistic city pace plus the rider's slack.
static func ride_time_limit_s(route_m: float, rider: PassengerArchetype) -> float:
	return route_m / 7.0 + rider.timer_slack_s

## Final settlement shown on the fare breakdown screen.
## comfort: 0–1 tea-cup level at drop-off; near_misses: Gap-la Gethu count during the ride.
## tip_bonus: extra tip fraction (e.g. +0.25 green-ride bonus from IT riders in the EV).
static func settle(agreed_fare: int, rider: PassengerArchetype, comfort: float, on_time: bool, near_misses: int, tip_bonus: float = 0.0) -> Dictionary:
	var c: float = clampf(comfort, 0.0, 1.0)
	var tip: int = roundi(float(rider.max_tip_inr) * c * (1.0 + tip_bonus)) if on_time else 0
	var gethu: int = 0
	if rider.likes_fast_driving:
		gethu = near_misses * (NEAR_MISS_BONUS_INR + rider.near_miss_tip_inr)
	var stars: float = clampf(1.0 + 4.0 * c - (0.0 if on_time else 1.0), 1.0, 5.0)
	return {
		"fare": agreed_fare,
		"comfort_tip": tip,
		"gethu_bonus": gethu,
		"total": agreed_fare + tip + gethu,
		"stars": stars,
		"on_time": on_time,
	}
