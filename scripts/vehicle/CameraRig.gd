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

var _target: Node3D
var _camera: Camera3D

func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.far = 400.0
	_camera.near = 0.1 # better depth precision for flat road layers
	add_child(_camera)
	_camera.make_current()
	top_level = true
	_snap()

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("camera_cycle"):
		cycle_mode()
	if _target == null:
		return
	var basis_flat: Basis = _flat_basis()
	var desired: Vector3
	match mode:
		Mode.COCKPIT:
			# Cockpit is rigid to the chassis so the handlebar view never lags.
			_camera.global_transform = _target.global_transform.translated_local(COCKPIT_OFFSET).rotated_local(Vector3.RIGHT, -0.16) # look down at bars & snout
			_camera.fov = 78.0
			return
		Mode.TOP_DOWN:
			desired = _target.global_position + basis_flat * TOP_DOWN_OFFSET
		_:
			desired = _target.global_position + basis_flat * CHASE_OFFSET
	var t: float = 1.0 - exp(-follow_sharpness * delta)
	_camera.global_position = _camera.global_position.lerp(desired, t)
	_camera.fov = 70.0
	var look_at_pt: Vector3 = _target.global_position + Vector3(0.0, 0.4, 0.0)
	if _camera.global_position.distance_to(look_at_pt) > 0.1:
		_camera.look_at(look_at_pt, Vector3.UP if mode != Mode.TOP_DOWN else -basis_flat.z)

func cycle_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode
	_snap()
	SignalBus.camera_mode_changed.emit(MODE_NAMES[mode])

func _flat_basis() -> Basis:
	var fwd: Vector3 = -_target.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return Basis.IDENTITY
	return Basis.looking_at(fwd.normalized(), Vector3.UP)

func _snap() -> void:
	if _target == null or _camera == null:
		return
	_camera.global_position = _target.global_position + _flat_basis() * (TOP_DOWN_OFFSET if mode == Mode.TOP_DOWN else CHASE_OFFSET)
