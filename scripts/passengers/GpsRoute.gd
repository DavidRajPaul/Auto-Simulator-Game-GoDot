class_name GpsRoute
extends RefCounted
## Turns a RoadGraph.find_route() result into what a sat-nav shows (pure maths, unit-tested):
##   • `path`      — the guide line: offset into the LEFT lane (India drives on the left), resampled
##                   every RESAMPLE_M and corner-rounded, so it reads like a real nav ribbon instead
##                   of a zig-zag on the road's centre line.
##   • `cum`       — distance along `path` at each point.
##   • `maneuvers` — turn-by-turn: [{s, turn, road, road_ta}] where turn is one of TURN_*.
## Like the guide lines in Bus Simulator Indonesia / Truckers of Europe / Google Maps driving mode.

enum Turn { STRAIGHT, SLIGHT_LEFT, LEFT, SHARP_LEFT, SLIGHT_RIGHT, RIGHT, SHARP_RIGHT, U_TURN, ARRIVE }

const RESAMPLE_M: float = 2.0
const SMOOTH_PASSES: int = 2
## Heading change (deg) that counts as a turn worth announcing.
const SLIGHT_DEG: float = 22.0
const TURN_DEG: float = 50.0
const SHARP_DEG: float = 120.0
const U_TURN_DEG: float = 160.0
const HEADING_WINDOW_M: float = 10.0

var path: PackedVector3Array = PackedVector3Array()
var cum: PackedFloat32Array = PackedFloat32Array()
var maneuvers: Array[Dictionary] = []
var length: float = 0.0

static func build(graph: RoadGraph, route: Dictionary) -> GpsRoute:
	var g: GpsRoute = GpsRoute.new()
	if not bool(route.get("ok", false)):
		return g
	var raw: PackedVector3Array = route["points"]
	var steps: Array = route.get("steps", [])
	var starts: PackedInt32Array = route.get("step_starts", PackedInt32Array([0]))
	if raw.size() < 2:
		return g
	# 1. Left-lane offset per raw point (step owning that point decides the lane).
	var offs: PackedVector3Array = PackedVector3Array()
	var step_of: PackedInt32Array = PackedInt32Array()
	var si: int = 0
	for i: int in raw.size():
		while si + 1 < starts.size() and i >= starts[si + 1]:
			si += 1
		step_of.append(si)
		var prev: Vector3 = raw[maxi(i - 1, 0)]
		var nxt: Vector3 = raw[mini(i + 1, raw.size() - 1)]
		var fwd: Vector3 = Vector3(nxt.x - prev.x, 0.0, nxt.z - prev.z)
		if fwd.length_squared() < 0.0001:
			offs.append(raw[i])
			continue
		fwd = fwd.normalized()
		var left: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
		var lat: float = 0.0
		if si < steps.size() and graph != null:
			var ei: int = int(steps[si][0])
			var d: int = int(steps[si][1])
			# Middle sub-lane of the left-most lane: where an auto actually drives.
			lat = graph.sub_lane_offset(ei, d, mini(1, maxi(graph.sub_lane_count(ei, d) - 1, 0)))
		offs.append(raw[i] + left * lat)
	# 2. Resample evenly, then round corners (Chaikin).
	var res: PackedVector3Array = _resample(offs, RESAMPLE_M)
	for k: int in SMOOTH_PASSES:
		res = _chaikin(res)
	# Keep the exact start/end.
	g.path = res
	g._rebuild_cum()
	# 3. Maneuvers at step boundaries where the heading really changes.
	if graph != null:
		for k: int in range(1, starts.size()):
			var at: Vector3 = raw[clampi(starts[k], 0, raw.size() - 1)]
			var s_at: float = g.distance_at(at)
			var turn: Turn = g._turn_at(s_at)
			if turn == Turn.STRAIGHT:
				continue
			var e: RoadGraph.Edge = graph.edges[int(steps[k][0])]
			g.maneuvers.append({"s": s_at, "turn": turn, "road": e.road_name, "road_ta": e.road_name_ta})
		# Merge maneuvers closer than 15 m (complex junctions): keep the stronger one.
		var merged: Array[Dictionary] = []
		for m: Dictionary in g.maneuvers:
			if not merged.is_empty() and float(m["s"]) - float(merged[-1]["s"]) < 15.0:
				if _strength(m["turn"]) > _strength(merged[-1]["turn"]):
					merged[-1] = m
				continue
			merged.append(m)
		g.maneuvers = merged
	g.maneuvers.append({"s": g.length, "turn": Turn.ARRIVE, "road": "", "road_ta": ""})
	return g

## Distance along the path of the point nearest `p` (full scan; call rarely).
func distance_at(p: Vector3) -> float:
	return progress_from(p, 0, path.size())[1]

## Nearest path point searching indices [from, from+window). Returns [index, s, lateral_dist].
func progress_from(p: Vector3, from: int, window: int) -> Array:
	var best: int = clampi(from, 0, maxi(path.size() - 1, 0))
	var best_d: float = INF
	var to: int = mini(path.size(), from + window)
	for i: int in range(maxi(from, 0), to):
		var d: float = Vector2(path[i].x - p.x, path[i].z - p.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return [best, cum[best] if best < cum.size() else 0.0, sqrt(best_d)]

## Next maneuver at or after distance `s`.
func next_maneuver(s: float) -> Dictionary:
	for m: Dictionary in maneuvers:
		if float(m["s"]) > s + 1.0:
			return m
	return maneuvers[-1] if not maneuvers.is_empty() else {}

static func turn_text(turn: Turn) -> String:
	match turn:
		Turn.SLIGHT_LEFT: return "Keep left"
		Turn.LEFT: return "Turn left"
		Turn.SHARP_LEFT: return "Sharp left"
		Turn.SLIGHT_RIGHT: return "Keep right"
		Turn.RIGHT: return "Turn right"
		Turn.SHARP_RIGHT: return "Sharp right"
		Turn.U_TURN: return "Make a U-turn"
		Turn.ARRIVE: return "Arrive at destination"
	return "Continue straight"

## Arrow glyph for the banner.
static func turn_glyph(turn: Turn) -> String:
	match turn:
		Turn.SLIGHT_LEFT: return "↖"
		Turn.LEFT, Turn.SHARP_LEFT: return "↰"
		Turn.SLIGHT_RIGHT: return "↗"
		Turn.RIGHT, Turn.SHARP_RIGHT: return "↱"
		Turn.U_TURN: return "↶"
		Turn.ARRIVE: return "◉"
	return "↑"

func _turn_at(s: float) -> Turn:
	var a: Vector3 = _dir_between(s - HEADING_WINDOW_M, s)
	var b: Vector3 = _dir_between(s, s + HEADING_WINDOW_M)
	if a == Vector3.ZERO or b == Vector3.ZERO:
		return Turn.STRAIGHT
	# Signed yaw: + = left turn (counter-clockwise seen from above, -Z north, +X east).
	var ang: float = rad_to_deg(atan2(a.x * b.z - a.z * b.x, a.x * b.x + a.z * b.z))
	var left: bool = ang < 0.0
	var mag: float = absf(ang)
	if mag >= U_TURN_DEG:
		return Turn.U_TURN
	if mag >= SHARP_DEG:
		return Turn.SHARP_LEFT if left else Turn.SHARP_RIGHT
	if mag >= TURN_DEG:
		return Turn.LEFT if left else Turn.RIGHT
	if mag >= SLIGHT_DEG:
		return Turn.SLIGHT_LEFT if left else Turn.SLIGHT_RIGHT
	return Turn.STRAIGHT

func _dir_between(s0: float, s1: float) -> Vector3:
	var p0: Vector3 = point_at(s0)
	var p1: Vector3 = point_at(s1)
	var d: Vector3 = Vector3(p1.x - p0.x, 0.0, p1.z - p0.z)
	return d.normalized() if d.length_squared() > 0.01 else Vector3.ZERO

func point_at(s: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	var d: float = clampf(s, 0.0, length)
	var i: int = clampi(cum.bsearch(d), 1, path.size() - 1)
	var seg: float = maxf(cum[i] - cum[i - 1], 0.0001)
	return path[i - 1].lerp(path[i], (d - cum[i - 1]) / seg)

func _rebuild_cum() -> void:
	cum.resize(path.size())
	var t: float = 0.0
	for i: int in path.size():
		if i > 0:
			t += path[i].distance_to(path[i - 1])
		cum[i] = t
	length = t

static func _strength(t: int) -> int:
	return [0, 1, 2, 3, 1, 2, 3, 4, 5][t]

static func _resample(pts: PackedVector3Array, step: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array([pts[0]])
	var carry: float = 0.0
	for i: int in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var seg: float = a.distance_to(b)
		var t: float = step - carry
		while t <= seg:
			out.append(a.lerp(b, t / seg))
			t += step
		carry = seg - (t - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > 0.2:
		out.append(pts[pts.size() - 1])
	return out

static func _chaikin(pts: PackedVector3Array) -> PackedVector3Array:
	if pts.size() < 3:
		return pts
	var out: PackedVector3Array = PackedVector3Array([pts[0]])
	for i: int in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	out.append(pts[pts.size() - 1])
	return out
