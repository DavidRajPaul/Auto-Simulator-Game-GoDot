class_name MeshKit
extends RefCounted
## Tiny procedural-modelling kit for low-poly vehicles and props. Everything is emitted
## into a SurfaceTool with vertex colours, so a whole model can share one material
## (= one draw call). Smooth groups: lofts/lathes are smoothed, boxes stay faceted.

static var _next_smooth_group: int = 1

static func begin() -> SurfaceTool:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

static func finish(st: SurfaceTool, material: Material, into: ArrayMesh = null) -> ArrayMesh:
	st.generate_normals()
	var mesh: ArrayMesh = st.commit(into)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color, smooth: bool = false) -> void:
	st.set_color(colour)
	st.set_smooth_group(0 if smooth else -1)
	# a-b-c-d counter-clockwise when seen from the outside (Godot front face = clockwise
	# in screen space, so emit a, c, b order).
	_tri(st, a, c, b)
	_tri(st, a, d, c)

## Axis-aligned box (optionally rotated by `basis` around `center`).
static func box(st: SurfaceTool, center: Vector3, size: Vector3, colour: Color, basis: Basis = Basis.IDENTITY) -> void:
	var h: Vector3 = size * 0.5
	var c: Array[Vector3] = []
	for i: int in 8:
		var p: Vector3 = Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
		c.append(center + basis * p)
	# faces: -x, +x, -y, +y, -z, +z
	quad(st, c[0], c[4], c[6], c[2], colour)
	quad(st, c[1], c[3], c[7], c[5], colour)
	quad(st, c[0], c[1], c[5], c[4], colour)
	quad(st, c[2], c[6], c[7], c[3], colour)
	quad(st, c[0], c[2], c[3], c[1], colour)
	quad(st, c[4], c[5], c[7], c[6], colour)

## Rounded-rectangle cross-section in the XY plane at depth z (CCW seen from -Z).
static func rounded_ring(z: float, width: float, y_bottom: float, y_top: float, radius: float, segs_per_corner: int = 3) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var r: float = minf(radius, minf(width, y_top - y_bottom) * 0.5 - 0.001)
	var hw: float = width * 0.5
	var centres: Array[Vector2] = [Vector2(hw - r, y_bottom + r), Vector2(hw - r, y_top - r), Vector2(-hw + r, y_top - r), Vector2(-hw + r, y_bottom + r)]
	var start_angles: Array[float] = [-PI * 0.5, 0.0, PI * 0.5, PI]
	for k: int in 4:
		for s: int in segs_per_corner + 1:
			var a: float = start_angles[k] + (PI * 0.5) * float(s) / float(segs_per_corner)
			out.append(Vector3(centres[k].x + cos(a) * r, centres[k].y + sin(a) * r, z))
	return out

## Join consecutive rings (same point count) into a smooth skin; optional end caps.
static func loft(st: SurfaceTool, rings: Array[PackedVector3Array], colour: Color, closed_ring: bool = true, cap_start: bool = false, cap_end: bool = false, flip: bool = false) -> void:
	var group: int = _next_smooth_group
	_next_smooth_group += 1
	st.set_color(colour)
	for r: int in range(1, rings.size()):
		var a: PackedVector3Array = rings[r - 1]
		var b: PackedVector3Array = rings[r]
		var n: int = a.size()
		var limit: int = n if closed_ring else n - 1
		for i: int in limit:
			var j: int = (i + 1) % n
			st.set_smooth_group(group)
			if flip:
				_tri(st, a[i], a[j], b[i])
				_tri(st, a[j], b[j], b[i])
			else:
				_tri(st, a[i], b[i], a[j])
				_tri(st, a[j], b[i], b[j])
	if cap_start:
		_cap(st, rings[0], colour, not flip)
	if cap_end:
		_cap(st, rings[rings.size() - 1], colour, flip)

static func _cap(st: SurfaceTool, ring: PackedVector3Array, colour: Color, reverse: bool) -> void:
	var c: Vector3 = Vector3.ZERO
	for p: Vector3 in ring:
		c += p
	c /= float(ring.size())
	st.set_color(colour)
	st.set_smooth_group(-1)
	for i: int in ring.size():
		var j: int = (i + 1) % ring.size()
		if reverse:
			_tri(st, c, ring[j], ring[i])
		else:
			_tri(st, c, ring[i], ring[j])

## Revolve a 2D profile (x = radius, y = position along axis) around the local X axis.
static func lathe_x(st: SurfaceTool, center: Vector3, profile: PackedVector2Array, segments: int, colour: Color) -> void:
	var rings: Array[PackedVector3Array] = []
	for p: Vector2 in profile:
		var ring: PackedVector3Array = PackedVector3Array()
		for s: int in segments:
			var a: float = TAU * float(s) / float(segments)
			ring.append(center + Vector3(p.y, cos(a) * p.x, sin(a) * p.x))
		rings.append(ring)
	loft(st, rings, colour, true)

## Cylinder between two points.
static func tube(st: SurfaceTool, from: Vector3, to: Vector3, radius: float, colour: Color, segments: int = 8) -> void:
	var axis: Vector3 = (to - from).normalized()
	var ref: Vector3 = Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u: Vector3 = axis.cross(ref).normalized()
	var v: Vector3 = axis.cross(u).normalized()
	var ra: PackedVector3Array = PackedVector3Array()
	var rb: PackedVector3Array = PackedVector3Array()
	for s: int in segments:
		var a: float = TAU * float(s) / float(segments)
		var off: Vector3 = (u * cos(a) + v * sin(a)) * radius
		ra.append(from + off)
		rb.append(to + off)
	loft(st, [ra, rb], colour, true, true, true)

## Flat disc facing `normal`.
static func disc(st: SurfaceTool, center: Vector3, normal: Vector3, radius: float, colour: Color, segments: int = 12) -> void:
	var n: Vector3 = normal.normalized()
	var ref: Vector3 = Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var u: Vector3 = n.cross(ref).normalized()
	var v: Vector3 = n.cross(u).normalized()
	st.set_color(colour)
	st.set_smooth_group(-1)
	for s: int in segments:
		var a0: float = TAU * float(s) / float(segments)
		var a1: float = TAU * float(s + 1) / float(segments)
		_tri(st, center, center + (u * cos(a1) + v * sin(a1)) * radius, center + (u * cos(a0) + v * sin(a0)) * radius)

## Curved shell (mudguard) around the X axis: arc from angle a0 to a1 (radians, 0 = +Z).
static func arc_shell(st: SurfaceTool, center: Vector3, radius: float, width: float, a0: float, a1: float, colour: Color, segments: int = 8) -> void:
	var left: PackedVector3Array = PackedVector3Array()
	var right: PackedVector3Array = PackedVector3Array()
	for s: int in segments + 1:
		var a: float = lerpf(a0, a1, float(s) / float(segments))
		var p: Vector3 = Vector3(0.0, sin(a) * radius, cos(a) * radius)
		left.append(center + p + Vector3(-width * 0.5, 0, 0))
		right.append(center + p + Vector3(width * 0.5, 0, 0))
	var group: int = _next_smooth_group
	_next_smooth_group += 1
	st.set_color(colour)
	for i: int in segments:
		st.set_smooth_group(group)
		# double-sided: both windings
		_tri(st, left[i], right[i], left[i + 1])
		_tri(st, left[i + 1], right[i], right[i + 1])
		_tri(st, left[i], left[i + 1], right[i])
		_tri(st, left[i + 1], right[i + 1], right[i])
