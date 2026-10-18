extends Node
## Global Player Economy, Auto Stand Reputation & Shift State Singleton.

var wallet_inr: int = 500
var stand_respect_xp: int = 100
var star_rating: float = 4.5
var completed_savaris: int = 0

func add_inr(amount: int) -> void:
	wallet_inr = maxi(0, wallet_inr + amount)
	var bus: Node = get_node_or_null("/root/SignalBus")
	if bus != null:
		bus.emit_signal("wallet_balance_changed", wallet_inr, amount)

func calculate_meter_fare(distance_km: float, is_night_or_monsoon: bool = false) -> int:
	var extra_km: float = maxf(0.0, distance_km - 1.8)
	var raw_fare: float = 35.0 + (extra_km * 18.0)
	if is_night_or_monsoon:
		raw_fare *= 1.5
	return int(roundf(raw_fare / 5.0) * 5.0)
