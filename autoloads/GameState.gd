extends Node
## Player economy, Auto Stand reputation and shift state.

const METER_BASE_FARE_INR: float = 35.0
const METER_BASE_KM: float = 1.8
const METER_PER_KM_INR: float = 18.0
const SURGE_MULTIPLIER: float = 1.5

var wallet_inr: int = 500
var stand_respect_xp: int = 100
var star_rating: float = 4.5
var completed_savaris: int = 0

func add_inr(amount: int) -> void:
	wallet_inr = maxi(0, wallet_inr + amount)
	SignalBus.wallet_balance_changed.emit(wallet_inr, amount)

func add_respect(xp: int) -> void:
	stand_respect_xp = maxi(0, stand_respect_xp + xp)
	SignalBus.stand_respect_changed.emit(stand_respect_xp, star_rating)

## Chennai meter: ₹35 for the first 1.8 km, ₹18/km after, rounded to nearest ₹5.
func calculate_meter_fare(distance_km: float, is_night_or_monsoon: bool = false) -> int:
	var extra_km: float = maxf(0.0, distance_km - METER_BASE_KM)
	var raw_fare: float = METER_BASE_FARE_INR + extra_km * METER_PER_KM_INR
	if is_night_or_monsoon:
		raw_fare *= SURGE_MULTIPLIER
	return int(roundf(raw_fare / 5.0) * 5.0)
