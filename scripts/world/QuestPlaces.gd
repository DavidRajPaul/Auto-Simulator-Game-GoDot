class_name QuestPlaces
extends Node3D
## The named places of the side quests, standing in the city all the time, not only during a job.
## One shared mesh per kind, each instance drawn only nearby, and the two nearest get their name
## painted on the board (Label3D draw calls are pooled, like BusStops).
const VISIBLE_M: float = 120.0
const NAME_M: float = 60.0
const NAME_SLOTS: int = 2
const REFRESH_S: float = 0.5
const BOARD_Z: float = -0.27 # Just in front of a shop's painted board.
const BOARD_Z_BY_KIND: Dictionary = {"hall": 0.07, "school": -0.43}
## Which model stands for each named place.
const KINDS: Dictionary = {
	"SQ01_P_DESK": "tent", "SQ01_P_FLOWER": "stall", "SQ01_P_HALL": "hall",
	"SQ02_P_BOOKS": "books", "SQ02_P_TAILOR": "tailor", "SQ02_P_TEA": "tea",
	"SQ03_P_BACK": "gate", "SQ03_P_HALL": "hall", "SQ03_P_NOTICE": "notice", "SQ03_P_SHOP": "music",
	"SQ04_P_HOME": "house", "SQ04_P_STALL": "stall", "SQ04_P_STEPS": "notice",
	"SQ05_P_OUTER": "notice", "SQ05_P_SHOP": "lamps", "SQ05_P_SIGN": "closed", "SQ05_P_STORE": "store",
	"SQ06_P_SPOT1": "photo", "SQ06_P_SPOT2": "photo",
	"SQ07_P_GATE1": "notice", "SQ07_P_GATE2": "notice", "SQ07_P_GATE3": "notice", "SQ07_P_HELP": "tent",
	"SQ08_P_BOXES": "stall", "SQ08_P_PAPER": "stall", "SQ08_P_SHELTER": "tent",
	"SQ09_P_CLINIC": "clinic", "SQ09_P_CORNER": "notice",
	"SQ10_P_NORTH": "notice", "SQ10_P_SORT": "tent", "SQ10_P_SOUTH": "notice", "SQ10_P_WEST": "notice",
	"SQ12_P_DESK": "office", "SQ12_P_GATE": "gate", "SQ12_P_SHOP": "sports",
	"SQ14_P_GATE": "school", "SQ14_P_PRINT": "print", "SQ14_P_SCHOOL": "notice",
	"SQ15_P_CLINIC": "clinic", "SQ15_P_LIBRARY": "books", "SQ15_P_STOP": "notice",
	"SQ16_P_A": "notice", "SQ16_P_B": "notice", "SQ16_P_C": "notice",
	"SQ17_P_DESK": "tent", "SQ17_P_SHELTER": "tent", "SQ17_P_SIGN": "warning", "SQ17_P_STORE": "store",
	"SQ18_P_CHARGER": "phones", "SQ18_P_HOME1": "house", "SQ18_P_HOME2": "house", "SQ18_P_SHOP": "store",
	"SQ19_P_OFFICE": "office", "SQ19_P_PRINTER": "print", "SQ19_P_TAILOR": "tailor",
	"SQ20_P_BOX": "power", "SQ20_P_MARKET": "stall", "SQ20_P_ROAD": "notice", "SQ20_P_SIGN": "warning",
	"SQ21_P_HOME": "house", "SQ21_P_OFFICE": "office", "SQ21_P_PRINT": "print",
	"SQ23_P_OFFICE": "office", "SQ23_P_ROAD": "notice", "SQ23_P_SHOP": "glass", "SQ23_P_SIGN": "warning",
	"SQ24_P_AUTO": "auto", "SQ24_P_BOARD": "notice", "SQ24_P_SHOP": "store",
	"SQ25_P_CLOCK": "notice", "SQ25_P_STONE": "notice", "SQ25_P_VIEW": "photo", "SQ25_P_WALL": "notice",
	"SQ26_P_HALL": "hall", "SQ26_P_JASMINE": "flowers", "SQ26_P_ROSE": "flowers",
	"SQ27_P_HOUSE": "house", "SQ27_P_LANE": "notice", "SQ27_P_ROAD": "notice",
}
@export var pack: MissionPack = preload("res://data/missions/career_quests.tres")
var places: Array[Dictionary] = [] # {key, kind, node}
var _names: Array[Label3D] = []
var _player: Vector3 = Vector3.ZERO
var _elapsed: float = 0.0

func _ready() -> void:
	var seen: Dictionary = {}
	for quest: MissionDef in pack.missions:
		for stage: MissionStage in quest.stages:
			if stage.place_key != "" and stage.place_options.is_empty():
				_add(seen, stage.place_key, stage.place_pos, stage.target)
			for option: String in stage.place_options:
				_add(seen, str(stage.place_options[option]), stage.place_pos_options[option] as Vector3, stage.target_options[option] as Vector3)
	for i: int in NAME_SLOTS:
		var label: Label3D = Label3D.new()
		label.font = UIKit.title_font()
		label.font_size = 40
		label.pixel_size = 0.0075
		label.outline_size = 0
		label.modulate = Color(1.0, 0.92, 0.6)
		label.double_sided = false
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.visible = false
		add_child(label)
		_names.append(label)
	SignalBus.player_pose_updated.connect(func(p: Vector3, _f: Vector3) -> void: _player = p)

func _add(seen: Dictionary, key: String, at: Vector3, road: Vector3) -> void:
	if seen.has(key) or at == Vector3.ZERO:
		return
	seen[key] = true
	var kind: String = str(KINDS.get(key, "notice"))
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = QuestPlaceKit.mesh(kind)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = VISIBLE_M
	var yaw: float = atan2(road.x - at.x, road.z - at.z)
	add_child(node)
	node.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, 0.0, at.z))
	SignalBus.ground_snap_requested.emit(node)
	places.append({"key": key, "kind": kind, "node": node})

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < REFRESH_S:
		return
	_elapsed = 0.0
	var near: Array[Dictionary] = []
	for place: Dictionary in places:
		if QuestPlaceKit.has_board(str(place["kind"])):
			var d: float = (place["node"] as Node3D).global_position.distance_to(_player)
			if d <= NAME_M:
				near.append({"d": d, "place": place})
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	for i: int in NAME_SLOTS:
		_names[i].visible = i < near.size()
		if i < near.size():
			var place: Dictionary = near[i]["place"]
			var node: Node3D = place["node"]
			_names[i].text = tr(str(place["key"]))
			_names[i].global_transform = node.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, QuestPlaceKit.SIGN_Y, float(BOARD_Z_BY_KIND.get(place["kind"], BOARD_Z))))
