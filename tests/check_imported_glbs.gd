extends SceneTree
## Run after: godot --headless --path . --import
## Verifies physical GLBs are loadable as PackedScene. Godot .import files
## are regenerated; don't commit hand-written stale import metadata.

const CANDIDATES: PackedStringArray = [
    "res://assets/models/city/barricade/roadside_barricade.glb",
    "res://assets/models/city/coconut_palm.glb",
    "res://assets/models/city/lighthouse/chennai_lighthouse.glb",
    "res://assets/models/traffic/maintenance_pack/maintenance_vehicle_pack.glb",
    "res://assets/models/traffic/police_car/svc_police_car.glb",
    "res://assets/models/traffic/two_wheeler_pack/two_wheeler_pack.glb",
]

func _initialize() -> void:
    var failed: int = 0
    for path: String in CANDIDATES:
        if not ResourceLoader.exists(path):
            push_error("Import verification: source not imported or unavailable: " + path)
            failed += 1
            continue
        var model: Resource = ResourceLoader.load(path)
        if not model is PackedScene:
            push_error("Import verification: GLB not a loadable scene: " + path)
            failed += 1
            continue
        print("PASS imported GLB: ", path)
    print("Import check: ", CANDIDATES.size() - failed, "/", CANDIDATES.size())
    quit(1 if failed > 0 else 0)
