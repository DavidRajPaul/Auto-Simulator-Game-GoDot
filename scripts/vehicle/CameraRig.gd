class_name CameraRig
extends Node3D
## Chase, Cockpit (handlebar) and Top-Down cameras. Cycles on the "camera_cycle" action.

enum Mode { CHASE, COCKPIT, TOP_DOWN }

const MODE_NAMES: PackedStringArray = ["Chase", "Cockpit", "Top-Down"]
const CHASE_OFFSET: Vector3 = Vector3(0.0, 2.4, 5.6)
## Driver eye ≈ 1.35 m above the road (chassis origin rides ~0.8 m up), behind the cowl.
const COCKPIT_OFFSET: Vector3 = Vector3(0.0, 0.58, -0.25)
const TOP_DOWN_OFFSET: Vector3 = Vector3(0.0, 24.0, 6.0)

@export var target_path: NodePath
@export var follow_sharpness: float = 6.0
@export var mode: Mode = Mode.CHASE
## Cockpit head stabilisation: how quickly the eye follows chassis pitch/roll (yaw stays tight).
## Real drivers' necks soak up suspension buzz; a rigid camera shows every physics micro-bump.
@export var cockpit_tilt_sharpness: float = 5.0
@export var cockpit_yaw_sharpness: float = 22.0
## Fraction of chassis pitch/roll the eye keeps (1 = rigid, 0 = horizon-locked).
@export var cockpit_tilt_follow: float = 0.45

var _target: Node3D
var _camera: Camera3D
var _cockpit_basis: Basis = Basis.IDENTITY
var _cockpit_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.far = 400.0
	_camera.near = 0.1 # better depth precision for flat road layers
	add_child(_camera)
	_camera.make_current()
	top_level = true
	# The rig is driven every rendered frame from the target's *interpolated* transform, so it
	# must not be interpolated a second time by the engine.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	SignalBus.teleport_requested.connect(func(_x: Transform3D) -> void: _snap.call_deferred())
	_snap()

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("camera_cycle"):
		cycle_mode()
	if _target == null:
		return
	# Interpolated pose: physics runs at 60 Hz but phones render at uneven 30–120 Hz; reading
	# the raw physics transform here is what made the auto judder on screen.
	var xf: Transform3D = _target_xform()
	var basis_flat: Basis = _flat_basis(xf)
	var desired: Vector3
	match mode:
		Mode.COCKPIT:
			_update_cockpit(xf, delta)
			return
		Mode.TOP_DOWN:
			desired = xf.origin + basis_flat * TOP_DOWN_OFFSET
		_:
			desired = xf.origin + basis_flat * CHASE_OFFSET
	var t: float = 1.0 - exp(-follow_sharpness * delta)
	_camera.global_position = _camera.global_position.lerp(desired, t)
	# A little wider with speed: reads as faster without needing more speed.
	var speed: float = (_target as RigidBody3D).linear_velocity.length() if _target is RigidBody3D else 0.0
	_camera.fov = lerpf(_camera.fov, 68.0 + clampf(speed * 0.45, 0.0, 9.0), 1.0 - exp(-3.0 * delta))
	var look_at_pt: Vector3 = xf.origin + Vector3(0.0, 0.4, 0.0)
	if _camera.global_position.distance_to(look_at_pt) > 0.1:
		_camera.look_at(look_at_pt, Vector3.UP if mode != Mode.TOP_DOWN else -basis_flat.z)

## Head-stabilised cockpit: yaw tracks the handlebar tightly, pitch/roll are partly
## levelled and low-pass filtered so road buzz and suspension bounce don't shake the view.
func _update_cockpit(xf: Transform3D, delta: float) -> void:
	var fwd: Vector3 = -xf.basis.z
	var flat: Vector3 = Vector3(fwd.x, 0.0, fwd.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	var level: Basis = Basis.looking_at(flat.normalized(), Vector3.UP)
	var chassis: Basis = xf.basis.orthonormalized()
	var target_q: Quaternion = Quaternion(level).slerp(Quaternion(chassis), cockpit_tilt_follow)
	var cur_q: Quaternion = Quaternion(_cockpit_basis.orthonormalized())
	# Yaw responsive, tilt soft: blend with two rates, then take the faster yaw back.
	var tilt_q: Quaternion = cur_q.slerp(target_q, 1.0 - exp(-cockpit_tilt_sharpness * delta))
	var yaw_err: float = angle_difference(Basis(tilt_q).get_euler().y, level.get_euler().y)
	tilt_q = Quaternion(Vector3.UP, yaw_err * (1.0 - exp(-cockpit_yaw_sharpness * delta))) * tilt_q
	_cockpit_basis = Basis(tilt_q.normalized())
	# Eye position follows the seat, with vertical bounce softened.
	var seat: Vector3 = xf * COCKPIT_OFFSET
	_cockpit_pos.x = seat.x
	_cockpit_pos.z = seat.z
	_cockpit_pos.y = lerpf(_cockpit_pos.y, seat.y, 1.0 - exp(-14.0 * delta))
	if _cockpit_pos.distance_squared_to(seat) > 1.0:
		_cockpit_pos = seat
	_camera.global_transform = Transform3D(_cockpit_basis, _cockpit_pos).rotated_local(Vector3.RIGHT, -0.16) # look down at bars & snout
	_camera.fov = 78.0

func _target_xform() -> Transform3D:
	if is_inside_tree() and get_tree().physics_interpolation:
		return _target.get_global_transform_interpolated()
	return _target.global_transform

func cycle_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode
	_snap()
	SignalBus.camera_mode_changed.emit(MODE_NAMES[mode])

func _flat_basis(xf: Transform3D) -> Basis:
	var fwd: Vector3 = -xf.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return Basis.IDENTITY
	return Basis.looking_at(fwd.normalized(), Vector3.UP)

func _snap() -> void:
	if _target == null or _camera == null:
		return
	var xf: Transform3D = _target.global_transform
	_camera.global_position = xf.origin + _flat_basis(xf) * (TOP_DOWN_OFFSET if mode == Mode.TOP_DOWN else CHASE_OFFSET)
	_cockpit_basis = xf.basis.orthonormalized()
	_cockpit_pos = xf * COCKPIT_OFFSET
