extends Node
## Dev-only: draws one wall with an AC outdoor unit through WorldChunkStreamer's own helpers and
## saves a PNG. SHOT_OUT = png path. The wall is the plane z = 0, facing +Z; the unit stands at y = 2.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var stage: Node3D = Node3D.new()
	add_child(stage)
	var streamer: WorldChunkStreamer = WorldChunkStreamer.new()
	var m: WorldChunkStreamer.MeshBuf = WorldChunkStreamer.MeshBuf.new()
	var wall: Array[Vector3] = [Vector3(-3.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0), Vector3(3.0, 4.0, 0.0), Vector3(-3.0, 4.0, 0.0)]
	streamer._face(m, wall, Vector3.BACK, Color(0.85, 0.82, 0.78))
	streamer._ac_unit(m, Vector2(0.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 0.0), 2.0)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = m.verts
	arr[Mesh.ARRAY_NORMAL] = m.norms
	arr[Mesh.ARRAY_COLOR] = m.cols
	arr[Mesh.ARRAY_TEX_UV] = m.uvs
	var am: ArrayMesh = ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = mat
	stage.add_child(mi)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	stage.add_child(sun)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.75, 0.95)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.62)
	stage.add_child(env)
	var cam: Camera3D = Camera3D.new()
	stage.add_child(cam)
	cam.global_position = Vector3(1.8, 2.9, 3.6)
	cam.look_at(Vector3(0.0, 1.9, 0.0), Vector3.UP)
	cam.current = true
	for i: int in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()
