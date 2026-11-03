class_name DamageFX
extends Node3D
## Engine smoke that builds with the damage, then fire (Nov 3 request): driven only by
## GameState.damage_severity() (1 - condition / 100), so it starts light and grows as the auto is
## hit, and a repair puts it out.
##   severity < SMOKE_FROM        nothing
##   SMOKE_FROM .. BLACK_FROM     thin, then denser grey wisps from the engine (rear, low)
##   BLACK_FROM .. FIRE_FROM      thick dark smoke
##   FIRE_FROM .. 1               flames under black smoke, an orange flickering light
##   wrecked (condition 0)        big fire; the engine is dead (AutoRickshawController)
## Emitter amounts only change between STAGES (changing CPUParticles3D.amount restarts it), colour
## and size ease every frame. Kenney CC0 textures (assets/fx) via CollisionFX's helpers.
## 0 draw calls when healthy; at most 2 emitters + 1 light while burning.

const SMOKE_FROM: float = 0.35
const BLACK_FROM: float = 0.8
const FIRE_FROM: float = 0.88
## Smoke particles per stage (0 = off): light, grey, dark, black + fire, wrecked.
const STAGE_SMOKE: Array[int] = [0, 4, 8, 14, 20, 28]
const STAGE_FIRE: Array[int] = [0, 0, 0, 0, 18, 40]
## Engine position on the auto (game space: the auto faces -Z, the engine sits at the back).
const ENGINE_POS: Vector3 = Vector3(0.0, -0.25, 0.95)

var smoke: CPUParticles3D
var fire: CPUParticles3D
var glow: OmniLight3D
var stage: int = 0
var severity: float = 0.0
var _t: float = 0.0

func _ready() -> void:
	position = ENGINE_POS
	smoke = _build_smoke()
	add_child(smoke)
	fire = _build_fire()
	fire.position = Vector3(0.0, 0.5, -0.05) # on top of the engine cover, under the canopy's tail
	add_child(fire)
	glow = OmniLight3D.new()
	glow.name = "FireGlow"
	glow.light_color = Color(1.0, 0.55, 0.2)
	glow.omni_range = 5.0
	glow.shadow_enabled = false
	glow.visible = false
	glow.position = Vector3(0.0, 0.6, 0.0)
	add_child(glow)
	SignalBus.condition_changed.connect(func(_c: float) -> void: refresh())
	SignalBus.damage_changed.connect(refresh)
	refresh()

## Stage for a severity 0..1 (pure; tests use it).
static func stage_for(sev: float, wrecked: bool) -> int:
	if wrecked:
		return 5
	if sev >= FIRE_FROM:
		return 4
	if sev >= BLACK_FROM:
		return 3
	if sev >= (SMOKE_FROM + BLACK_FROM) * 0.5:
		return 2
	if sev >= SMOKE_FROM:
		return 1
	return 0

func refresh() -> void:
	severity = GameState.damage_severity()
	var s: int = stage_for(severity, GameState.is_wrecked())
	if s == stage and smoke.emitting == (STAGE_SMOKE[s] > 0):
		return
	stage = s
	_set_amount(smoke, STAGE_SMOKE[s])
	_set_amount(fire, STAGE_FIRE[s])
	glow.visible = STAGE_FIRE[s] > 0

func _set_amount(e: CPUParticles3D, n: int) -> void:
	if n <= 0:
		e.emitting = false
		e.visible = false
		return
	if e.amount != n:
		e.amount = n
	e.visible = true
	e.emitting = true

func _process(delta: float) -> void:
	if stage == 0:
		return
	_t += delta
	# Grey -> black as it gets worse; bigger, faster, longer-lived puffs.
	var k: float = clampf((severity - SMOKE_FROM) / (1.0 - SMOKE_FROM), 0.0, 1.0)
	var grey: float = lerpf(0.62, 0.06, k)
	var col: Color = Color(grey, grey, grey, lerpf(0.22, 0.8, k))
	smoke.color_ramp = CollisionFX._fade(col, Color(grey, grey, grey, 0.0))
	smoke.scale_amount_min = lerpf(0.5, 1.4, k)
	smoke.scale_amount_max = lerpf(0.9, 2.6, k)
	smoke.initial_velocity_min = lerpf(0.5, 1.6, k)
	smoke.initial_velocity_max = lerpf(0.9, 2.6, k)
	if glow.visible:
		var burn: float = 1.0 if stage >= 5 else 0.6
		glow.light_energy = burn * (1.6 + 0.6 * sin(_t * 17.0) + 0.4 * sin(_t * 31.0 + 1.3))

static func _build_smoke() -> CPUParticles3D:
	var tex: Texture2D = CollisionFX._tex("smoke_a.png")
	var e: CPUParticles3D = CollisionFX._emitter("EngineSmoke", 2.2, Vector2(0.7, 0.7), CollisionFX._mat(tex, false))
	e.one_shot = false
	e.explosiveness = 0.0
	e.amount = 4
	e.local_coords = false # trails behind a moving auto
	e.direction = Vector3(0.0, 1.0, 0.25)
	e.spread = 18.0
	e.gravity = Vector3(0.0, 0.6, 0.0) # hot smoke rises
	e.damping_min = 0.4
	e.damping_max = 0.8
	e.angle_min = -180.0
	e.angle_max = 180.0
	e.angular_velocity_min = -30.0
	e.angular_velocity_max = 30.0
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 0.15
	var grow: Curve = Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.0))
	e.scale_amount_curve = grow
	return e

static func _build_fire() -> CPUParticles3D:
	var tex: Texture2D = CollisionFX._tex("flare.png")
	var e: CPUParticles3D = CollisionFX._emitter("EngineFire", 0.8, Vector2(1.0, 1.3), CollisionFX._mat(tex, true))
	e.one_shot = false
	e.explosiveness = 0.0
	e.amount = 10
	e.local_coords = false
	e.direction = Vector3.UP
	e.spread = 12.0
	e.initial_velocity_min = 1.2
	e.initial_velocity_max = 2.2
	e.gravity = Vector3(0.0, 2.0, 0.0)
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	e.emission_box_extents = Vector3(0.45, 0.08, 0.3)
	e.scale_amount_min = 0.8
	e.scale_amount_max = 1.6
	var shrink: Curve = Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.2))
	e.scale_amount_curve = shrink
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.45, 1.0))
	g.add_point(0.45, Color(1.0, 0.45, 0.08, 0.85))
	g.set_color(g.get_point_count() - 1, Color(0.5, 0.08, 0.02, 0.0))
	e.color_ramp = g
	return e
