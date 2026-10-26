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
	var road_name_ta: String = ""

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
		var ei: int = g.add_edge(int(e["a"]), int(e["b"]), pts, float(e["w"]), int(e["lf"]), int(e["lb"]), str(e["c"]), str(e.get("n", "")))
		g.edges[ei].road_name_ta = str(e.get("nt", ""))
	g._build_seg_grid() # once, behind the loading screen
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
	_seg_grid_built = false
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

## Closest point on the network: {edge, s, dist}. Uses a segment grid (was a scan of all
## ~30k segments: ~10 ms on desktop, a 60 ms+ hitch on a budget phone at every haggle/reroute).
const SEG_CELL_M: float = 40.0
var _seg_grid: Dictionary = {} # Vector2i -> PackedInt32Array of (edge << 12 | segment)
var _seg_grid_built: bool = false

func closest_point(pos: Vector3) -> Dictionary:
	if not _seg_grid_built:
		_build_seg_grid()
	var best: Dictionary = {"edge": -1, "s": 0.0, "dist": INF}
	var c: Vector2i = Vector2i(floori(pos.x / SEG_CELL_M), floori(pos.z / SEG_CELL_M))
	var seen: Dictionary = {}
	# Grow rings until something is found and the ring is farther than the best hit.
	for ring: int in 40:
		if float(best["dist"]) < float(ring - 1) * SEG_CELL_M:
			break
		for dx: int in range(-ring, ring + 1):
			for dz: int in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				for code: int in _seg_grid.get(c + Vector2i(dx, dz), PackedInt32Array()):
					if seen.has(code):
						continue
					seen[code] = true
					var ei: int = code >> 12
					var i: int = code & 4095
					var e: Edge = edges[ei]
					var q: Vector3 = Geometry3D.get_closest_point_to_segment(pos, e.points[i - 1], e.points[i])
					var d: float = Vector2(q.x - pos.x, q.z - pos.z).length()
					if d < float(best["dist"]):
						best = {"edge": ei, "s": e.cum[i - 1] + q.distance_to(e.points[i - 1]), "dist": d}
	if int(best["edge"]) < 0:
		return _closest_point_scan(pos) # far outside the network
	return best

func _build_seg_grid() -> void:
	_seg_grid_built = true
	_seg_grid.clear()
	for ei: int in edges.size():
		var e: Edge = edges[ei]
		for i: int in range(1, mini(e.points.size(), 4096)):
			var a: Vector3 = e.points[i - 1]
			var b: Vector3 = e.points[i]
			var x0: int = floori(minf(a.x, b.x) / SEG_CELL_M)
			var x1: int = floori(maxf(a.x, b.x) / SEG_CELL_M)
			var z0: int = floori(minf(a.z, b.z) / SEG_CELL_M)
			var z1: int = floori(maxf(a.z, b.z) / SEG_CELL_M)
			for gx: int in range(x0, x1 + 1):
				for gz: int in range(z0, z1 + 1):
					var k: Vector2i = Vector2i(gx, gz)
					var arr: PackedInt32Array = _seg_grid.get(k, PackedInt32Array())
					arr.append((ei << 12) | i)
					_seg_grid[k] = arr

func _closest_point_scan(pos: Vector3) -> Dictionary:
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

# --- GPS routing (Phase 3) ------------------------------------------------------

## Edges you may leave `node` by, as [edge, dir, to_node].
func _out_moves(node: int) -> Array[Array]:
	var out: Array[Array] = []
	for ei: int in node_edges[node]:
		var e: Edge = edges[ei]
		if e.a == node and e.lanes_fwd > 0:
			out.append([ei, 1, e.b])
		if e.b == node and e.lanes_back > 0:
			out.append([ei, -1, e.a])
	return out

## Shortest legal route (respects one-ways) between two world positions.
## Returns {ok, length, points: PackedVector3Array, steps: Array[[edge, dir]]}.
func find_route(from_pos: Vector3, to_pos: Vector3) -> Dictionary:
	var start: Dictionary = closest_point(from_pos)
	var goal: Dictionary = closest_point(to_pos)
	if int(start["edge"]) < 0 or int(goal["edge"]) < 0:
		return {"ok": false}
	var se: Edge = edges[int(start["edge"])]
	var ge: Edge = edges[int(goal["edge"])]
	var s0: float = float(start["s"])
	var g0: float = float(goal["s"])
	# Same edge and the travel direction is legal: no graph search needed.
	if int(start["edge"]) == int(goal["edge"]):
		var d: int = 1 if g0 >= s0 else -1
		if (d > 0 and se.lanes_fwd > 0) or (d < 0 and se.lanes_back > 0):
			return {"ok": true, "length": absf(g0 - s0), "steps": [[int(start["edge"]), d]],
				"points": _slice(int(start["edge"]), s0, g0), "step_starts": PackedInt32Array([0])}
	# Seed: leave the start edge toward whichever endpoint(s) are legal.
	var dist: Dictionary = {}
	var prev: Dictionary = {} # node -> [prev_node, edge, dir]
	var heap: Array[Array] = []
	if se.lanes_fwd > 0:
		_relax(se.b, se.length - s0, -1, int(start["edge"]), 1, dist, prev, heap, to_pos)
	if se.lanes_back > 0:
		_relax(se.a, s0, -1, int(start["edge"]), -1, dist, prev, heap, to_pos)
	# Goal: arriving at an endpoint from which the goal edge can be driven to g0.
	var goal_entry: Dictionary = {} # node -> [cost to finish, dir]
	if ge.lanes_fwd > 0:
		goal_entry[ge.a] = [g0, 1]
	if ge.lanes_back > 0:
		goal_entry[ge.b] = [ge.length - g0, -1]
	var best_total: float = INF
	var best_node: int = -1
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var node: int = int(top[1])
		var cost: float = float(dist[node])
		if float(top[0]) - nodes[node].distance_to(to_pos) > cost + 0.001:
			continue # stale entry
		if cost >= best_total:
			break
		if goal_entry.has(node):
			var total: float = cost + float(goal_entry[node][0])
			if total < best_total:
				best_total = total
				best_node = node
		for mv: Array in _out_moves(node):
			_relax(int(mv[2]), cost + edges[int(mv[0])].length, node, int(mv[0]), int(mv[1]), dist, prev, heap, to_pos)
	if best_node < 0:
		return {"ok": false}
	# Rebuild steps.
	var steps: Array = [[int(goal["edge"]), int(goal_entry[best_node][1])]]
	var n: int = best_node
	while prev.has(n):
		var p: Array = prev[n]
		steps.push_front([int(p[1]), int(p[2])])
		n = int(p[0])
		if n < 0:
			break
	# Polyline.
	var pts: PackedVector3Array = PackedVector3Array()
	var step_starts: PackedInt32Array = PackedInt32Array()
	for i: int in steps.size():
		step_starts.append(pts.size())
		var ei: int = int(steps[i][0])
		var d: int = int(steps[i][1])
		var e: Edge = edges[ei]
		var from_s: float = (s0 if i == 0 else (0.0 if d > 0 else e.length))
		var to_s: float = (g0 if i == steps.size() - 1 else (e.length if d > 0 else 0.0))
		pts.append_array(_slice(ei, from_s, to_s))
	return {"ok": true, "length": best_total, "steps": steps, "points": pts, "step_starts": step_starts}

func _relax(node: int, cost: float, from_node: int, edge_idx: int, dir: int, dist: Dictionary, prev: Dictionary, heap: Array[Array], target: Vector3) -> void:
	if dist.has(node) and float(dist[node]) <= cost:
		return
	dist[node] = cost
	prev[node] = [from_node, edge_idx, dir]
	_heap_push(heap, [cost + nodes[node].distance_to(target), node])

## Points along an edge between two s values (either order).
func _slice(edge_idx: int, s_from: float, s_to: float) -> PackedVector3Array:
	var e: Edge = edges[edge_idx]
	var out: PackedVector3Array = PackedVector3Array()
	out.append(sample(edge_idx, s_from, 1)[0])
	if s_to >= s_from:
		for i: int in e.points.size():
			if e.cum[i] > s_from and e.cum[i] < s_to:
				out.append(e.points[i])
	else:
		for i: int in range(e.points.size() - 1, -1, -1):
			if e.cum[i] < s_from and e.cum[i] > s_to:
				out.append(e.points[i])
	out.append(sample(edge_idx, s_to, 1)[0])
	return out

static func _heap_push(heap: Array[Array], item: Array) -> void:
	heap.append(item)
	var i: int = heap.size() - 1
	while i > 0:
		var parent: int = (i - 1) / 2
		if float(heap[parent][0]) <= float(heap[i][0]):
			break
		var tmp: Array = heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent

static func _heap_pop(heap: Array[Array]) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i: int = 0
		while true:
			var l: int = i * 2 + 1
			var r: int = l + 1
			var m: int = i
			if l < heap.size() and float(heap[l][0]) < float(heap[m][0]):
				m = l
			if r < heap.size() and float(heap[r][0]) < float(heap[m][0]):
				m = r
			if m == i:
				break
			var tmp: Array = heap[m]
			heap[m] = heap[i]
			heap[i] = tmp
			i = m
	return top
