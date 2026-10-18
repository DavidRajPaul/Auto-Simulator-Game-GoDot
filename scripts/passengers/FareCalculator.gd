class_name FareCalculator
extends RefCounted
## Pure fare / haggling / tip maths for the "Meter Podu vs. Bargain" loop (GDD §1).
## No scene access — unit-tested in tests/run_phase3_tests.

enum Offer { METER, METER_MELA, FIXED }

const OFFER_NAMES: PackedStringArray = ["Correct Meter", "Meter Mela +₹30", "Fixed ₹200 — Return Empty!"]
const METER_MELA_EXTRA_INR: int = 30
const FIXED_RATE_INR: int = 200
## The map is a 1 : 2.5 compression of Chennai, so fares use real-world-equivalent km.
const REAL_KM_PER_GAME_KM: float = 2.5
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

## Probability the rider accepts. Rain makes riders less picky; Alangaram prestige
## (0–1, cosmetic upgrades in Phase 4) sweetens the Meter Mela ask.
static func acceptance_chance(offer: Offer, rider: PassengerArchetype, raining: bool = false, prestige: float = 0.0) -> float:
	var p: float
	match offer:
		Offer.METER_MELA:
			p = rider.accept_meter_mela_chance + 0.1 * clampf(prestige, 0.0, 1.0)
		Offer.FIXED:
			p = rider.accept_fixed_rate_chance
		_:
			p = rider.accept_meter_chance
	if raining and offer != Offer.METER:
		p += 0.1
	return clampf(p, 0.0, 1.0)

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
