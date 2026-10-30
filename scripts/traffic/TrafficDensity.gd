class_name TrafficDensity
extends RefCounted
## Time-of-day × zone traffic model for Chennai. Pure maths, no scene access (unit-tested).
##
## Source: TomTom Traffic Index 2025, Chennai city area — typical 10 km travel time by hour.
## Free flow ≈ 19 min (4 AM). Weekday: 8 AM ≈ 31.5, noon ≈ 32.5, 6 PM ≈ 41 (worst, 154 %
## congestion), 8 PM ≈ 33, 10 PM ≈ 25. Saturday midday/evening heavier than Saturday morning;
## Sunday noticeably lighter. Evening rush average speed 14.6 km/h, morning 17.7 km/h.
## Congestion here = travel_time / free_flow − 1 (TomTom's definition), so 6 PM ≈ 1.1.

const FREE_FLOW_MIN: float = 19.3
## [hour, weekday minutes, saturday minutes, sunday minutes] per 10 km. Anchors from TomTom
## (4, 8, 12, 18, 20, 22 h); the in-between hours are interpolated on the same curve shape.
const PROFILE: Array[Vector4] = [
	Vector4(0.0, 20.5, 21.5, 21.0),
	Vector4(4.0, 19.0, 19.3, 19.3),
	Vector4(6.0, 22.5, 21.0, 20.0),
	Vector4(8.0, 31.5, 27.3, 24.5),
	Vector4(10.0, 33.5, 31.5, 27.0),
	Vector4(12.0, 32.5, 36.0, 29.2),
	Vector4(15.0, 33.0, 36.5, 29.5),
	Vector4(17.0, 38.0, 40.0, 31.5),
	Vector4(18.0, 41.0, 42.3, 32.3),
	Vector4(19.0, 38.0, 39.5, 31.0),
	Vector4(20.0, 33.0, 34.7, 29.2),
	Vector4(22.0, 25.0, 26.7, 23.5),
	Vector4(24.0, 20.5, 21.5, 21.0),
]
## Zone weight (manifest zone ids): T. Nagar and Mount Road are the city's choke points,
## Mylapore's narrow tank streets fill up at temple/market times, Marina is open boulevard
## that only gets busy with the evening beach crowd.
const ZONE_WEIGHT: Dictionary = {
	"t_nagar": 1.25, "anna_salai": 1.2, "mylapore": 1.0, "marina": 0.75,
	# Station approaches have high peak-hour pressure, but still respect the fixed 18-car pool.
	"central": 1.35, "ripon": 1.25, "egmore": 1.18
}
const MARINA_EVENING_BOOST: float = 0.35 # 4:30–8:30 PM beach crowd
const STATION_MORNING_BOOST: float = 0.18
const STATION_EVENING_BOOST: float = 0.16

## Minutes per 10 km for this time (minute of day 0–1440) and weekday (0 Mon … 6 Sun).
static func travel_minutes(minute_of_day: float, weekday: int) -> float:
	var h: float = fposmod(minute_of_day, 1440.0) / 60.0
	for i: int in PROFILE.size() - 1:
		var a: Vector4 = PROFILE[i]
		var b: Vector4 = PROFILE[i + 1]
		if h >= a.x and h <= b.x:
			var t: float = smoothstep(0.0, 1.0, (h - a.x) / maxf(b.x - a.x, 0.001))
			return lerpf(_col(a, weekday), _col(b, weekday), t)
	return FREE_FLOW_MIN

## TomTom-style congestion (0 = free flow, 1.1 = Chennai at 6 PM on a weekday).
static func congestion(minute_of_day: float, weekday: int) -> float:
	return maxf(0.0, travel_minutes(minute_of_day, weekday) / FREE_FLOW_MIN - 1.0)

## 0–1 how busy this place is right now (1 ≈ T. Nagar at the 6 PM peak).
static func density(minute_of_day: float, weekday: int, zone_id: String) -> float:
	var w: float = float(ZONE_WEIGHT.get(zone_id, 0.9))
	var m: float = fposmod(minute_of_day, 1440.0)
	if zone_id == "marina" and m >= 990.0 and m <= 1230.0:
		w += MARINA_EVENING_BOOST
	# Transit hubs are busy around office/commuter arrival and departure hours.
	# This is a gameplay tuning heuristic, not measured street-by-street traffic data.
	if zone_id in ["central", "ripon", "egmore"] and weekday != 6:
		if m >= 420.0 and m <= 630.0:
			w += STATION_MORNING_BOOST
		elif m >= 990.0 and m <= 1200.0:
			w += STATION_EVENING_BOOST
	return clampf(congestion(minute_of_day, weekday) / 1.15 * w, 0.0, 1.0)

## Active AI vehicles around the player for a density (pool cap is 18, AGENTS.md).
static func active_vehicles(d: float, pool_max: int) -> int:
	return clampi(roundi(lerpf(5.0, float(pool_max), clampf(d, 0.0, 1.0))), 3, pool_max)

## Multiplier on AI cruise speed: free flow 1.0 → ~0.5 at the evening peak
## (TomTom: 14.6 km/h evening average vs ~31 km/h free-flow city average).
static func speed_factor(minute_of_day: float, weekday: int, d: float) -> float:
	var base: float = FREE_FLOW_MIN / travel_minutes(minute_of_day, weekday)
	return clampf(lerpf(1.0, base, 0.6 + 0.4 * d), 0.45, 1.0)

## Rider demand for autos (feeds haggling): peak hours and rain mean riders need you more.
static func rider_demand(d: float, raining: bool) -> float:
	return clampf(d * 0.85 + (0.3 if raining else 0.0), 0.0, 1.0)

static func is_peak(minute_of_day: float, weekday: int) -> bool:
	return congestion(minute_of_day, weekday) >= 0.7

static func _col(v: Vector4, weekday: int) -> float:
	if weekday == 5:
		return v.z
	if weekday == 6:
		return v.w
	return v.y
