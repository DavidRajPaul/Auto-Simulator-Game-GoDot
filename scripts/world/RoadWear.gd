class_name RoadWear
## The potholes you can see are the potholes you can feel (Nov 14 owner question: "will the
## auto obey physics when going through potholes?").
##
## street_surface.gdshader paints potholes from WorldChunkStreamer.road_condition (UV.y) and a
## small value noise in world space. This is the SAME formula on the CPU, so a wheel ray can
## ask how deep the road is at its contact point. It only runs for the player's three wheels
## (a few hundred float operations a physics frame).
##
## Not reproduced: the shader's +-0.05 nudge from the detail texture and the repair patches
## (texture lookups the CPU can't make cheaply), so a hole's edge is a few cm off at most.
const MAX_DEPTH_M: float = 0.075
## Drawn asphalt height band (WorldChunkStreamer.ROAD_Y 0.06; footpaths are 0.08).
const ASPHALT_Y: Vector2 = Vector2(0.045, 0.072)

## How far below the road surface the ground is at (x, z): 0 off a pothole.
static func pothole_depth(x: float, z: float) -> float:
	var cond: float = WorldChunkStreamer.road_condition(x, z)
	if cond <= 0.6:
		return 0.0
	var broken: float = smoothstep(0.6, 0.7, cond)
	var n: float = _vnoise(x * 0.9, z * 0.9) * 0.7 + _vnoise(x * 2.3 + 7.0, z * 2.3 + 7.0) * 0.3
	var limit: float = 0.2 + 0.12 * broken
	var hole: float = 1.0 - smoothstep(limit - 0.035, limit, n)
	# Deeper towards the middle of a hole (n well under the limit).
	var bowl: float = clampf((limit - n) / 0.08, 0.0, 1.0)
	return hole * broken * MAX_DEPTH_M * (0.55 + 0.45 * bowl)

## True where (x, z) is drawn asphalt (potholes are never on footpaths, plots or bare ground).
static func on_asphalt(x: float, z: float) -> bool:
	var h: float = SignalBus.surface_height(x, z, -1.0)
	return h >= ASPHALT_Y.x and h <= ASPHALT_Y.y

## The shader's hash21 / vnoise, in the same order of operations.
static func _hash21(px: float, py: float) -> float:
	var x: float = _fract(px * 0.1031)
	var y: float = _fract(py * 0.1030)
	var d: float = x * (y + 33.33) + y * (x + 33.33)
	x += d
	y += d
	return _fract((x + y) * x)

static func _vnoise(px: float, py: float) -> float:
	var ix: float = floorf(px)
	var iy: float = floorf(py)
	var fx: float = px - ix
	var fy: float = py - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a: float = lerpf(_hash21(ix, iy), _hash21(ix + 1.0, iy), fx)
	var b: float = lerpf(_hash21(ix, iy + 1.0), _hash21(ix + 1.0, iy + 1.0), fx)
	return lerpf(a, b, fy)

static func _fract(v: float) -> float:
	return v - floorf(v)
