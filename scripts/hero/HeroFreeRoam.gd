class_name HeroFreeRoam
extends CanvasLayer
## On-foot mode: the auto remains in the world, the camera and streamed city follow the hero.
## Optional art: place the licensed GLB at res://assets/models/hero/namma_auto_hero.glb.

const HERO_MODEL: String = "res://assets/models/hero/namma_auto_hero.glb"
const WALK_SPEED: float = 3.3
const RUN_SPEED: float = 5.8
const ENTER_RADIUS: float = 4.0
const EXIT_MAX_KMH: float = 2.0
const GRAVITY: float = 18.0
const JUMP_SPEED: float = 5.2

var _auto: RigidBody3D
var _hero: CharacterBody3D
var _visual: Node3D
var _animation: AnimationPlayer
var _camera_rig: CameraRig
var _world: Node
var _hud: TouchHUD
var _overlay: Control
var _exit: Button
var _enter: Button
var _run: Button
var _jump: Button
var _joystick: Control
var _joystick_touch: int = -1
var _joystick_origin: Vector2 = Vector2.ZERO
var _axis: Vector2 = Vector2.ZERO
var _running: bool = false
var _on_foot: bool = false
var _vehicle_frozen: bool = false

func _ready() -> void:
	layer = 12
	_auto = get_parent().get_node("AutoRickshaw") as RigidBody3D
	_camera_rig = get_parent().get_node("CameraRig") as CameraRig
	_world = get_parent().get_node("World")
	_hud = get_parent().get_node("TouchHUD") as TouchHUD
	_create_hero()
	_create_ui()
	get_viewport().size_changed.connect(_layout)
	_layout()

func _create_hero() -> void:
	_hero = CharacterBody3D.new()
	_hero.name = "HeroDriver"
	_hero.collision_layer = 2
	_hero.collision_mask = 1
	_hero.floor_snap_length = 0.3
	var collider: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.75
	collider.shape = capsule
	collider.position.y = 0.88
	_hero.add_child(collider)
	_visual = Node3D.new()
	_visual.name = "CharacterVisual"
	_hero.add_child(_visual)
	if ResourceLoader.exists(HERO_MODEL):
		var scene: PackedScene = load(HERO_MODEL) as PackedScene
		if scene != null:
			var model: Node3D = scene.instantiate() as Node3D
			if model != null:
				_visual.add_child(model)
				_animation = _find_animation_player(model)
	if _visual.get_child_count() == 0:
		# Visible fallback until the binary character asset is checked into GitHub.
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var shape: CapsuleMesh = CapsuleMesh.new()
		shape.radius = 0.3
		shape.height = 1.7
		mesh.mesh = shape
		mesh.position.y = 0.85
		_visual.add_child(mesh)
	get_parent().add_child.call_deferred(_hero)
	_hero.visible = false
	_hero.set_physics_process(false)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null

func _create_ui() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_exit = _button("EXIT AUTO", _exit_auto)
	_enter = _button("ENTER AUTO", _enter_auto)
	_run = _button("RUN", _toggle_run)
	_jump = _button("JUMP", _jump_now)
	_joystick = Control.new()
	_joystick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_joystick)
	_joystick.draw.connect(_draw_joystick)
	_enter.visible = false
	_run.visible = false
	_jump.visible = false
	_joystick.visible = false

func _button(label: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(110.0, 54.0)
	button.pressed.connect(callback)
	_overlay.add_child(button)
	return button

func _layout() -> void:
	if _overlay == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_overlay.size = vp
	_exit.position = Vector2(vp.x - 160.0, 24.0)
	_enter.position = _exit.position
	_run.position = Vector2(vp.x - 145.0, vp.y - 185.0)
	_jump.position = Vector2(vp.x - 145.0, vp.y - 115.0)
	_joystick.position = Vector2(25.0, vp.y - 215.0)
	_joystick.size = Vector2(190.0, 190.0)

func _exit_auto() -> void:
	if _on_foot or _auto == null or _auto.linear_velocity.length() * 3.6 > EXIT_MAX_KMH:
		SignalBus.hint_requested.emit("Stop the auto before getting out", 2.0)
		return
	_on_foot = true
	_hero.global_position = _auto.global_position + _auto.global_basis.x * 1.8 - Vector3.UP * 0.6
	_hero.global_rotation.y = _auto.global_rotation.y
	_hero.velocity = Vector3.ZERO
	_hero.visible = true
	_hero.set_physics_process(true)
	_auto.linear_velocity = Vector3.ZERO
	_auto.angular_velocity = Vector3.ZERO
	_auto.freeze = true
	_vehicle_frozen = true
	_camera_rig._target = _hero
	_camera_rig.mode = CameraRig.Mode.CHASE
	_camera_rig._snap()
	_world.set("player_path", NodePath("../HeroDriver"))
	_hud._root.visible = false
	_hud.release_all()
	_exit.visible = false
	_enter.visible = true
	_run.visible = true
	_jump.visible = true
	_joystick.visible = true
	SignalBus.on_foot_changed.emit(true)
	SignalBus.parked_auto_position_changed.emit(_auto.global_position)

func _enter_auto() -> void:
	if not _on_foot:
		return
	if _hero.global_position.distance_to(_auto.global_position) > ENTER_RADIUS:
		SignalBus.hint_requested.emit("Walk closer to your auto", 2.0)
		return
	_on_foot = false
	_axis = Vector2.ZERO
	_joystick_touch = -1
	_hero.visible = false
	_hero.set_physics_process(false)
	_camera_rig._target = _auto
	_camera_rig._snap()
	_world.set("player_path", NodePath("../AutoRickshaw"))
	if _vehicle_frozen:
		_auto.freeze = false
		_vehicle_frozen = false
	_hud._root.visible = true
	_exit.visible = true
	_enter.visible = false
	_run.visible = false
	_jump.visible = false
	_joystick.visible = false
	SignalBus.on_foot_changed.emit(false)

func _toggle_run() -> void:
	_running = not _running
	_run.text = "WALK" if _running else "RUN"

func _jump_now() -> void:
	if _on_foot and _hero.is_on_floor():
		_hero.velocity.y = JUMP_SPEED

func _input(event: InputEvent) -> void:
	if not _on_foot:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed and _joystick_touch < 0 and _joystick.get_global_rect().has_point(touch.position):
			_joystick_touch = touch.index
			_joystick_origin = _joystick.get_global_rect().get_center()
			_update_axis(touch.position)
		elif not touch.pressed and touch.index == _joystick_touch:
			_joystick_touch = -1
			_axis = Vector2.ZERO
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == _joystick_touch:
			_update_axis(drag.position)

func _update_axis(position: Vector2) -> void:
	_axis = ((position - _joystick_origin) / 70.0).limit_length(1.0)
	_joystick.queue_redraw()

func _draw_joystick() -> void:
	var c: Vector2 = _joystick.size * 0.5
	_joystick.draw_circle(c, 76.0, Color(0.1, 0.12, 0.15, 0.55))
	_joystick.draw_arc(c, 76.0, 0.0, TAU, 48, Color(1.0, 0.72, 0.1), 3.0)
	_joystick.draw_circle(c + _axis * 62.0, 29.0, Color(1.0, 0.72, 0.1, 0.9))

func _physics_process(delta: float) -> void:
	if not _on_foot or not is_instance_valid(_hero):
		return
	var keyboard: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var input_axis: Vector2 = _axis if _axis.length_squared() > 0.001 else keyboard
	var forward: Vector3 = -_camera_rig._camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = _camera_rig._camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	var direction: Vector3 = (right * input_axis.x + forward * -input_axis.y).normalized()
	var speed: float = RUN_SPEED if _running else WALK_SPEED
	_hero.velocity.x = direction.x * speed
	_hero.velocity.z = direction.z * speed
	if not _hero.is_on_floor():
		_hero.velocity.y -= GRAVITY * delta
	elif _hero.velocity.y < 0.0:
		_hero.velocity.y = 0.0
	_hero.move_and_slide()
	if direction.length_squared() > 0.01:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(direction.x, direction.z), minf(1.0, delta * 10.0))
	_play_animation("jump" if not _hero.is_on_floor() else ("run" if _running and direction.length_squared() > 0.01 else ("walk" if direction.length_squared() > 0.01 else "standing_relax")))
	SignalBus.player_pose_updated.emit(_hero.global_position, direction if direction.length_squared() > 0.01 else -_hero.global_basis.z)
	_enter.disabled = _hero.global_position.distance_to(_auto.global_position) > ENTER_RADIUS

func _play_animation(name: String) -> void:
	if _animation == null:
		return
	var target: String = ""
	for entry: StringName in _animation.get_animation_list():
		if str(entry) == name or str(entry).ends_with("/" + name):
			target = str(entry)
			break
	if target != "" and _animation.current_animation != target:
		_animation.play(target)
