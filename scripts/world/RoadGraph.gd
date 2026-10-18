class_name RoadGraph
extends RefCounted
## Drivable road network shared by AI traffic (and GPS routing in Phase 3).
## Built from data/world/road_graph.json (OSM pipeline) or programmatically (greybox).
##
## Each edge is a polyline from node `a` to node `b`. Traffic travels "forward" (a→b,
## dir = +1) or "back" (b→a, dir = -1). India drives on the LEFT: each direction's
## carriageway is the left half of the road relative to its heading (whole road if one-way).
## Every lane is split into 3 sub-lanes (0 = LeftEdge/kerb, 1 = Center, 2 = RightOvertake).

const SUB_LANES_PER_LANE: int = 3

class Edge:
	var a: int
	var b: int
	var points: PackedVector3Array
	var cum: PackedFloat32Array # cumulative length at each point
	var length: float
	var width: float
	var lanes_fwd: int
	var lanes_back: int
	var road_class: String
	var road_name: String

var nodes: PackedVector3Array = PackedVector3Array()
var edges: Array[Edge] = []
var node_edges: Array[PackedInt32Array] = []

# --- Construction ------------------------------------------------------------

static func from_json_file(path: String) -> RoadGraph:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("RoadGraph: cannot open " + path)
		return null
	var data: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	var g: RoadGraph = RoadGraph.new()
	for n: Array in data["nodes"]:
		g.nodes.append(Vector3(float(n[0]), 0.0, float(n[1])))
	for e: Dictionary in data["edges"]:
		var pts: PackedVector3Array = PackedVector3Array()
		for p: Array in e["pts"]:
			pts.append(Vector3(float(p[0]), 0.0, float(p[1])))
		g.add_edge(int(e["a"]), int(e["b"]), pts, float(e["w"]), int(e["lf"]), int(e["lb"]), str(e["c"]), str(e.get("n", "")))
	return g

func add_node(pos: Vector3) -> int:
	nodes.append(pos)
	return nodes.size() - 1

func add_edge(a: int, b: int, pts: PackedVector3Array, width: float, lanes_fwd: int, lanes_back: int,
		road_class: String = "primary", road_name: String = "") -> int:
	var e: Edge = Edge.new()
	e.a = a
	e.b = b
	e.points = pts
	e.width = width
	e.lanes_fwd = maxi(lanes_fwd, 0)
	e.lanes_back = maxi(lanes_back, 0)
	e.road_class = road_class
	e.road_name = road_name
	e.cum = PackedFloat32Array()
	e.cum.resize(pts.size())
	var total: float = 0.0
	for i: int in pts.size():
		if i > 0:
			total += pts[i].distance_to(pts[i - 1])
		e.cum[i] = total
	e.length = total
	edges.append(e)
	var idx: int = edges.size() - 1
	while node_edges.size() < nodes.size():
		node_edges.append(PackedInt32Array())
	node_edges[a].append(idx)
	node_edges[b].append(idx)
	return idx

# --- Queries -----------------------------------------------------------------

func lanes_in_dir(edge_idx: int, dir: int) -> int:
	var e: Edge = edges[edge_idx]
	return e.lanes_fwd if dir > 0 else e.lanes_back

func sub_lane_count(edge_idx: int, dir: int) -> int:
	return lanes_in_dir(edge_idx, dir) * SUB_LANES_PER_LANE

func is_one_way(edge_idx: int) -> bool:
	var e: Edge = edges[edge_idx]
	return e.lanes_fwd == 0 or e.lanes_back == 0

## Lateral offset (metres, positive = to the LEFT of the travel direction) of a sub-lane centre.
func sub_lane_offset(edge_idx: int, dir: int, sub_lane: int) -> float:
	var e: Edge = edges[edge_idx]
	var count: int = maxi(sub_lane_count(edge_idx, dir), 1)
	var half: float = e.width * 0.5
	var carriage: float = e.width if is_one_way(edge_idx) else half
	var sub_w: float = carriage / float(count)
	# Sub-lane 0 hugs the left kerb; the last one is nearest the centre line (overtake).
	var from_left_kerb: float = (float(sub_lane) + 0.5) * sub_w
	return half - from_left_kerb

## Position and unit travel direction at distance `s` from node a, travelling in `dir`.
func sample(edge_idx: int, s: float, dir: int) -> Array[Vector3]:
	var e: Edge = edges[edge_idx]
	var dist: float = clampf(s, 0.0, e.length)
	var i: int = e.cum.bsearch(dist)
	i = clampi(i, 1, e.points.size() - 1)
	var p0: Vector3 = e.points[i - 1]
	var p1: Vector3 = e.points[i]
	var seg: float = maxf(e.cum[i] - e.cum[i - 1], 0.0001)
	var pos: Vector3 = p0.lerp(p1, (dist - e.cum[i - 1]) / seg)
	var fwd: Vector3 = (p1 - p0).normalized() * float(dir)
	return [pos, fwd]

## World position of a vehicle at (edge, s, dir, sub_lane).
func lane_position(edge_idx: int, s: float, dir: int, sub_lane: int) -> Array[Vector3]:
	var pd: Array[Vector3] = sample(edge_idx, s, dir)
	var left: Vector3 = Vector3(pd[1].z, 0.0, -pd[1].x)
	return [pd[0] + left * sub_lane_offset(edge_idx, dir, sub_lane), pd[1]]

## Pick a continuation at the node we arrive at. Avoids U-turns unless it's a dead end.
func next_edge(edge_idx: int, dir: int, rng: RandomNumberGenerator) -> Dictionary:
	var e: Edge = edges[edge_idx]
	var node: int = e.b if dir > 0 else e.a
	var options: Array[Dictionary] = []
	for other: int in node_edges[node]:
		if other == edge_idx:
			continue
		var o: Edge = edges[other]
		var out_dir: int = 1 if o.a == node else -1
		if lanes_in_dir(other, out_dir) > 0:
			options.append({"edge": other, "dir": out_dir})
	if options.is_empty():
		if lanes_in_dir(edge_idx, -dir) > 0:
			return {"edge": edge_idx, "dir": -dir}
		return {}
	return options[rng.randi() % options.size()]

## Closest point on the network: {edge, s, dist}.
func closest_point(pos: Vector3) -> Dictionary:
	var best: Dictionary = {"edge": -1, "s": 0.0, "dist": INF}
	for ei: int in edges.size():
		var e: Edge = edges[ei]
		for i: int in range(1, e.points.size()):
			var q: Vector3 = Geometry3D.get_closest_point_to_segment(pos, e.points[i - 1], e.points[i])
			var d: float = Vector2(q.x - pos.x, q.z - pos.z).length()
			if d < float(best["dist"]):
				best = {"edge": ei, "s": e.cum[i - 1] + q.distance_to(e.points[i - 1]), "dist": d}
	return best

## Spawn grid: road sample points bucketed by cell so spawning near the player
## doesn't scan every edge. Built lazily on first use.
const SPAWN_CELL_M: float = 50.0
const SPAWN_STEP_M: float = 16.0
var _spawn_grid: Dictionary = {} # Vector2i -> Array[Vector3] (x, z = pos, y = packed edge/s)
var _spawn_grid_built: bool = false

func _build_spawn_grid() -> void:
	_spawn_grid_built = true
	for ei: int in edges.size():
		var e: Edge = edges[ei]
		var s: float = minf(SPAWN_STEP_M * 0.5, e.length * 0.5)
		while s < e.length:
			var p: Vector3 = sample(ei, s, 1)[0]
			var key: Vector2i = Vector2i(floori(p.x / SPAWN_CELL_M), floori(p.z / SPAWN_CELL_M))
			if not _spawn_grid.has(key):
				_spawn_grid[key] = []
			(_spawn_grid[key] as Array).append([ei, s, p])
			s += SPAWN_STEP_M

## Candidate spawn spots between min_d and max_d from `origin`, in front of `heading`
## when possible. Returns Array of {edge, s, dir}.
func spawn_candidates(origin: Vector3, heading: Vector3, min_d: float, max_d: float) -> Array[Dictionary]:
	if not _spawn_grid_built:
		_build_spawn_grid()
	var out: Array[Dictionary] = []
	var behind: Array[Dictionary] = []
	var flat_heading: Vector3 = Vector3(heading.x, 0.0, heading.z).normalized()
	var r: int = ceili(max_d / SPAWN_CELL_M)
	var c: Vector2i = Vector2i(floori(origin.x / SPAWN_CELL_M), floori(origin.z / SPAWN_CELL_M))
	for dx: int in range(-r, r + 1):
		for dz: int in range(-r, r + 1):
			var bucket: Variant = _spawn_grid.get(c + Vector2i(dx, dz))
			if bucket == null:
				continue
			for item: Array in bucket:
				var p: Vector3 = item[2]
				var to_p: Vector3 = Vector3(p.x - origin.x, 0.0, p.z - origin.z)
				var d: float = to_p.length()
				if d < min_d or d > max_d:
					continue
				var ahead: bool = flat_heading == Vector3.ZERO or to_p.normalized().dot(flat_heading) > 0.2
				for dir: int in [1, -1]:
					if lanes_in_dir(int(item[0]), dir) > 0:
						(out if ahead else behind).append({"edge": int(item[0]), "s": float(item[1]), "dir": dir})
	return out if not out.is_empty() else behind
