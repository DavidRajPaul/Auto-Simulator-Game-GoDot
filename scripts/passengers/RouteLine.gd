class_name RouteLine
extends MeshInstance3D
## In-world sat-nav guide line + turn-by-turn prompts (the "GPS" of the dashboard phone).
##
## Modelled on the guide lines of top driving sims (Bus Simulator Indonesia, Truckers of Europe,
## Google Maps driving mode): a continuous translucent ribbon in YOUR lane with bright chevrons
## that flow toward the destination, eaten up behind you as you drive, fading out close to the
## camera and far ahead so it never paints over the whole road. One mesh, one draw call; the
## chevrons, trimming and fades are all in the shader (no per-frame mesh rebuild).

const WIDTH_M: float = 1.8
const Y: float = 0.11
const NAV_UPDATE_S: float = 0.2
## Off-route distance (m) beyond which the line stops trimming (the reroute will replace it).
const OFF_ROUTE_M: float = 25.0

const SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 band_colour : source_color = vec4(0.16, 0.55, 1.0, 0.42);
uniform vec4 chevron_colour : source_color = vec4(1.0, 1.0, 1.0, 0.95);
uniform float progress_m = 0.0;
uniform float total_m = 1.0;
uniform float chevron_spacing = 5.0;
uniform float flow_speed = 6.0;
uniform float near_fade_m = 3.0;
uniform float far_fade_m = 140.0;
varying float v_s;
void vertex() { v_s = UV.y; }
void fragment() {
	float ahead = v_s - progress_m;
	if (ahead < -1.0) { discard; }
	float x = UV.x * 2.0 - 1.0;                 // -1 … 1 across the ribbon
	float edge = smoothstep(1.0, 0.75, abs(x));  // soft edges
	// Chevron ">" pointing along +s, scrolling forward.
	float t = fract((v_s - TIME * flow_speed) / chevron_spacing);
	float chev = abs(t - 0.5 + abs(x) * 0.28);
	float c = (1.0 - smoothstep(0.05, 0.11, chev)) * step(abs(x), 0.72);
	float fade = smoothstep(-1.0, near_fade_m, ahead) * (1.0 - smoothstep(far_fade_m * 0.7, far_fade_m, ahead));
	// Last 25 m before the drop-off glow green.
	vec4 band = mix(band_colour, vec4(0.2, 1.0, 0.45, 0.5), smoothstep(total_m - 25.0, total_m - 5.0, v_s));
	vec4 col = mix(band, chevron_colour, c);
	ALBEDO = col.rgb;
	ALPHA = col.a * edge * fade;
}
"""

var gps: GpsRoute
var progress_m: float = 0.0
var _progress_idx: int = 0
var _mat: ShaderMaterial
var _nav_timer: float = 0.0
var _player: Vector3 = Vector3.ZERO

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh: Shader = Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.render_priority = 1 # after the road surface: no z-fighting flicker
	material_override = _mat
	SignalBus.gps_route_changed.connect(_on_gps)
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void: _player = p)

func _on_gps(r: RefCounted) -> void:
	gps = r as GpsRoute
	progress_m = 0.0
	_progress_idx = 0
	if gps == null or gps.path.size() < 2:
		gps = null
		mesh = null
		SignalBus.nav_instruction.emit({})
		return
	mesh = _build_ribbon(gps)
	_mat.set_shader_parameter("total_m", gps.length)
	_mat.set_shader_parameter("progress_m", 0.0)
	_update_nav()

func _physics_process(delta: float) -> void:
	if gps == null:
		return
	_nav_timer += delta
	if _nav_timer >= NAV_UPDATE_S:
		_nav_timer = 0.0
		_update_nav()

func _update_nav() -> void:
	# Local search ahead of the last progress (and a little behind for wobble).
	var res: Array = gps.progress_from(_player, maxi(_progress_idx - 10, 0), 160)
	if float(res[2]) <= OFF_ROUTE_M:
		_progress_idx = int(res[0])
		progress_m = maxf(progress_m, float(res[1]))
		_mat.set_shader_parameter("progress_m", progress_m)
	var m: Dictionary = gps.next_maneuver(progress_m)
	if m.is_empty():
		return
	var dist: float = maxf(0.0, float(m["s"]) - progress_m)
	var turn: GpsRoute.Turn = m["turn"] as GpsRoute.Turn
	var text: String = GpsRoute.turn_text(turn)
	if turn != GpsRoute.Turn.ARRIVE and str(m["road"]) != "":
		text += " onto " + str(m["road"])
	SignalBus.nav_instruction.emit({
		"turn": turn, "text": text, "glyph": GpsRoute.turn_glyph(turn), "distance_m": dist,
		"road": m["road"], "road_ta": m["road_ta"], "remaining_m": maxf(0.0, gps.length - progress_m),
	})

## Mitred ribbon: one vertex pair per path point (no gaps or overlaps at corners).
## UV.x across (0–1), UV.y = metres along the route (drives chevrons and trimming).
static func _build_ribbon(r: GpsRoute) -> ArrayMesh:
	var pts: PackedVector3Array = r.path
	var n: int = pts.size()
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	var half: float = WIDTH_M * 0.5
	for i: int in n:
		var d_in: Vector3 = Vector3(pts[i].x - pts[maxi(i - 1, 0)].x, 0.0, pts[i].z - pts[maxi(i - 1, 0)].z)
		var d_out: Vector3 = Vector3(pts[mini(i + 1, n - 1)].x - pts[i].x, 0.0, pts[mini(i + 1, n - 1)].z - pts[i].z)
		if d_in.length_squared() < 1e-6:
			d_in = d_out
		if d_out.length_squared() < 1e-6:
			d_out = d_in
		var t: Vector3 = (d_in.normalized() + d_out.normalized())
		if t.length_squared() < 1e-6:
			t = d_out
		t = t.normalized()
		var left: Vector3 = Vector3(t.z, 0.0, -t.x)
		# Miter length, capped so hairpins don't spike.
		var cosv: float = maxf(left.dot(Vector3(d_out.normalized().z, 0.0, -d_out.normalized().x)), 0.5)
		var w: float = half / cosv
		var base: Vector3 = Vector3(pts[i].x, pts[i].y + Y, pts[i].z)
		verts.append(base + left * w)
		verts.append(base - left * w)
		uvs.append(Vector2(0.0, r.cum[i]))
		uvs.append(Vector2(1.0, r.cum[i]))
		if i > 0:
			var a: int = (i - 1) * 2
			idx.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
