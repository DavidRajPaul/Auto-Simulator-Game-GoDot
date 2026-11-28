extends Node
## DEV ONLY (deleted on release/*): renders the dev panel open to $SHOT_OUT (default /tmp/devtools.png).
func _ready() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.35, 0.45, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var dev: DevTools = DevTools.new()
	dev.main_scene_name = get_tree().current_scene.name
	add_child(dev)
	for i: int in 4:
		await get_tree().process_frame
	dev.set_weather("storm")
	dev._on_toggle()
	for i: int in 4:
		await get_tree().process_frame
	var out: String = OS.get_environment("SHOT_OUT") if OS.has_environment("SHOT_OUT") else "/tmp/devtools.png"
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
