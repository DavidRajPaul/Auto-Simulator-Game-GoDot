class_name FullMap
extends Control
## Full-screen north-up Chennai map, opened by tapping the mini-map (or M). Real OSM streets
## with their names (English, Tamil underneath on main roads), water/parks/sea, the GPS route,
## waiting passengers, auto stands, LPG/EV bunks, garages and landmarks. Drag to pan, pinch or
## the +/− buttons to zoom, ◎ to re-centre. The game pauses while it is open.
##
## Drawing is cached: everything is redrawn only when the view changes, not every frame.

const BG: Color = Color("2a2030") # night plum: the painted map's ground
const ROAD_STYLE: Dictionary = { # class -> [colour, metres-width multiplier, min px]
	"trunk": [Color("e8b65a"), 1.0, 3.0], "primary": [Color("d9c39a"), 1.0, 2.5],
	"secondary": [Color("bfb29a"), 1.0, 2.0], "tertiary": [Color("9d9385"), 1.0, 1.6],
}
const MINOR: Color = Color("6b5f70")
const AREA_COLOURS: Dictionary = {"sea": Color("1f5f78"), "water": Color("2e7f86"), "park": Color("3f7a3a"), "beach": Color("a88f5a")}
const CLOSED_ROAD: Color = Color("e8392e")
const LEGEND_ITEMS: Array[String] = ["player", "route", "destination", "pin", "hail", "quest", "quest_group",
	"quest_done", "landmark", "stand", "lpg", "ev", "garage", "main_road", "closed", "water", "park", "sea"]
## Layout, shared by drawing and hit-testing.
const TOP_BANNER_Y: float = 14.0
const TOP_BANNER_SIDE: float = 270.0
const BAR_BOTTOM_GAP: float = 90.0
const JOURNAL_TOP: float = 150.0
const JOURNAL_HEAD: float = 44.0
const JOURNAL_ROW_H: float = 72.0
const JOURNAL_PAGER_H: float = 62.0
const MIN_SCALE: float = 0.05 # px per metre (whole city)
const MAX_SCALE: float = 3.0
const LABEL_CELL_PX: float = 170.0
const QUEST_START_NEAR_M: float = 12.0

var graph: RoadGraph
var scale_px: float = 0.6
var centre: Vector2 = Vector2.ZERO # world (x, z) at the screen centre
var _player: Vector3 = Vector3.ZERO
var _heading: Vector3 = Vector3.FORWARD
var _route: PackedVector3Array = PackedVector3Array()
var _hails: Array = []
var _areas: Dictionary = {}
var _pois: Array[Dictionary] = [] # {name, kind, pos: Vector2}
var _touches: Dictionary = {} # index -> Vector2
var _pinch_d: float = 0.0
var _font: Font
var _labels: Array[Dictionary] = [] # per named road: {name, ta, cls, a, b, len}
var _close_rect: Rect2
var _plus_rect: Rect2
var _minus_rect: Rect2
var _select_mode: int = 0 # 0 pan, 2 drop/drag destination pin
var _dragging_pin: bool = false
var _custom_destination: Vector3 = Vector3.ZERO
var _has_custom_destination: bool = false
var _destination_rect: Rect2
var _navigate_rect: Rect2
var _clear_rect: Rect2
var _press_at: Dictionary = {}
var _me_rect: Rect2
var _quest_rows: Array[Dictionary] = []
var _quest_hits: Array[Dictionary] = []
var _journal_open: bool = false
var _journal_page: int = 0
var _quest_selected: String = ""
var _journal_rect: Rect2
var _journal_back: Rect2
var _journal_next: Rect2
var _track_rect: Rect2
var _start_rect: Rect2
var _journal_panel: Rect2
var _card_rect: Rect2
var _card_close_rect: Rect2
var _legend_open: bool = false
var _legend_rect: Rect2
var _title: Font
var _body: Font
var _legend_panel: Rect2
var _toast_text: String = ""
var _toast_until_ms: int = 0
const JOURNAL_ROWS: int = 5

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_font = UIKit.body_font()
	_body = _font
	_title = UIKit.title_font()
	SignalBus.road_graph_ready.connect(_set_graph)
	if SignalBus.current_road_graph != null:
		_set_graph(SignalBus.current_road_graph)
	SignalBus.player_pose_updated.connect(func(p: Vector3, f: Vector3) -> void:
		_player = p
		_heading = f)
	SignalBus.route_updated.connect(func(pts: PackedVector3Array) -> void:
		_route = pts
		queue_redraw())
	# The HUD's hint strip sits under this full-screen map, so map actions answer here too.
	SignalBus.hint_requested.connect(func(text: String, seconds: float) -> void:
		if visible:
			_toast_text = text
			_toast_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)
			queue_redraw())
	SignalBus.hails_updated.connect(func(h: Array) -> void: _hails = h)
	SignalBus.full_map_requested.connect(set_open)
	SignalBus.custom_navigation_state_changed.connect(_on_custom_state)
	SignalBus.quest_catalogue_changed.connect(_refresh_quests)
	SignalBus.quest_tracking_changed.connect(func(_id: String) -> void: _refresh_quests())
	SignalBus.mission_finished.connect(func(_id: String, _status: String, _reason: String) -> void: _refresh_quests())
	_refresh_quests()
	_load_world_extras()
	get_viewport().size_changed.connect(func() -> void:
		size = get_viewport().get_visible_rect().size
		queue_redraw())

func set_open(open: bool) -> void:
	if open == visible:
		return
	visible = open
	get_tree().paused = open
	# Fingers are tracked only from presses the map itself saw. A finger already down when the map
	# opened (e.g. holding the gas pedal while someone taps the mini-map) must never count.
	_touches.clear()
	_press_at.clear()
	_pinch_d = 0.0
	_dragging_pin = false
	_journal_open = false
	_legend_open = false
	_toast_text = ""
	SignalBus.full_map_state_changed.emit(open)
	if open:
		_refresh_quests()
		position = Vector2.ZERO
		size = get_viewport().get_visible_rect().size
		centre = Vector2(_player.x, _player.z)
		scale_px = 0.6
		queue_redraw()

func _process(_delta: float) -> void:
	if _toast_text != "" and Time.get_ticks_msec() >= _toast_until_ms:
		_toast_text = ""
		queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and not k.echo and k.physical_keycode == KEY_M:
		set_open(not visible)
	elif visible and k != null and k.pressed and k.physical_keycode == KEY_ESCAPE:
		set_open(false)

func _set_graph(g: RoadGraph) -> void:
	graph = g
	_labels.clear()
	var by_name: Dictionary = {}
	for e: RoadGraph.Edge in g.edges:
		if e.road_name == "" or e.points.size() < 2:
			continue
		# Longest edge per (name, ~400 m cell) carries the label: one label per stretch.
		var mid: Vector3 = e.points[e.points.size() / 2]
		var key: String = "%s|%d|%d" % [e.road_name, floori(mid.x / 400.0), floori(mid.z / 400.0)]
		if not by_name.has(key) or (by_name[key] as RoadGraph.Edge).length < e.length:
			by_name[key] = e
	for key: String in by_name:
		var e: RoadGraph.Edge = by_name[key]
		_labels.append({"name": e.road_name, "ta": e.road_name_ta, "cls": e.road_class, "edge": e})
	# Big roads first so they win label placement.
	_labels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _rank(str(a["cls"])) > _rank(str(b["cls"])))

static func _rank(cls: String) -> int:
	return {"trunk": 5, "primary": 4, "secondary": 3, "tertiary": 2}.get(cls, 1)

func _load_world_extras() -> void:
	var f: FileAccess = FileAccess.open("res://data/world/areas.json", FileAccess.READ)
	if f != null:
		_areas = JSON.parse_string(f.get_as_text()) as Dictionary
	var mf: FileAccess = FileAccess.open("res://data/world/manifest.json", FileAccess.READ)
	if mf == null:
		return
	var m: Dictionary = JSON.parse_string(mf.get_as_text()) as Dictionary
	for l: Dictionary in m.get("landmarks", []):
		_pois.append({"name": str(l["name"]), "kind": "landmark", "pos": Vector2(float(l["x"]), float(l["z"]))})
	for s: Dictionary in m.get("auto_stands", []):
		_pois.append({"name": str(s["name"]), "kind": "stand", "pos": Vector2(float(s["x"]), float(s["z"]))})
	for s: Dictionary in m.get("services", []):
		_pois.append({"name": str(s["name"]), "kind": str(s["kind"]), "pos": Vector2(float(s["x"]), float(s["z"]))})
	# Real-world landmarks built from the city-props file, with their fixed OSM coordinates.
	var props_file: FileAccess = FileAccess.open("res://data/world/city_props.json", FileAccess.READ)
	if props_file != null:
		var city: Dictionary = JSON.parse_string(props_file.get_as_text()) as Dictionary
		for prop: Dictionary in city.get("props", []):
			if not bool(prop.get("landmark", false)) and not bool(prop.get("tea_cluster", false)):
				continue
			var label: String = "Tea Kadai"
			_pois.append({"name": label, "kind": "landmark",
				"pos": Vector2(float(prop["x"]), float(prop["z"]))})

# --- Input --------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			_touches[t.index] = t.position
			_press_at[t.index] = t.position
			if _touches.size() == 1 and _tap_button(t.position):
				_touches.erase(t.index)
				_press_at.erase(t.index) # Button press must not also drop a map pin on release
		elif not _touches.has(t.index):
			pass # release of a finger that went down before the map opened (or on a map button)
		else:
			if _dragging_pin:
				_select_point(t.position)
				_dragging_pin = false
			elif _press_at.has(t.index) and (t.position as Vector2).distance_to(_press_at[t.index] as Vector2) < 14.0:
				_tap_map(t.position)
			_press_at.erase(t.index)
			_touches.erase(t.index)
		_pinch_d = _pinch_distance()
		accept_event()
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		# Godot hands drags with no touch focus (a HUD finger pressed before the map opened) to the
		# control under them — this one. Adding them to _touches left a ghost finger that blocked
		# every later tap (the ✕ "did nothing"), so only fingers pressed on the map count.
		if not _touches.has(d.index):
			accept_event()
			return
		if _touches.size() >= 2:
			_touches[d.index] = d.position
			var nd: float = _pinch_distance()
			if _pinch_d > 1.0:
				_zoom_at(nd / _pinch_d, _pinch_mid())
			_pinch_d = nd
		else:
			_touches[d.index] = d.position
			if _select_mode == 2 or _dragging_pin:
				_dragging_pin = true
				_select_point(d.position)
			else:
				centre -= d.relative / scale_px
		queue_redraw()
		accept_event()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(1.15, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / 1.15, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available():
			if not _tap_button(mb.position):
				_tap_map(mb.position)
		accept_event()
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT and not DisplayServer.is_touchscreen_available():
		centre -= (event as InputEventMouseMotion).relative / scale_px
		queue_redraw()

func _tap_button(p: Vector2) -> bool:
	# Map chrome first: ✕, zoom and re-centre work whatever panel is open. The old order swallowed
	# every tap while the side-quest list was open, so the list could only close from its own button.
	if _close_rect.has_point(p):
		set_open(false)
	elif _plus_rect.has_point(p):
		_zoom_at(1.5, size * 0.5)
	elif _minus_rect.has_point(p):
		_zoom_at(1.0 / 1.5, size * 0.5)
	elif _me_rect.has_point(p):
		centre = Vector2(_player.x, _player.z)
		queue_redraw()
	elif _journal_rect.has_point(p):
		_journal_open = not _journal_open
		_legend_open = false
		if _journal_open:
			_quest_selected = ""
			_journal_page = clampi(_journal_page, 0, _journal_pages() - 1)
		queue_redraw()
	elif _legend_rect.has_point(p):
		_legend_open = not _legend_open
		_journal_open = false
		queue_redraw()
	elif _journal_open:
		if _journal_back.has_area() and _journal_back.has_point(p):
			_journal_page = maxi(0, _journal_page - 1)
		elif _journal_next.has_area() and _journal_next.has_point(p):
			_journal_page = mini(_journal_pages() - 1, _journal_page + 1)
		elif not _select_journal_row(p) and not _journal_panel.has_point(p):
			_journal_open = false # a tap on the map closes the list
		queue_redraw()
	elif _legend_open:
		_legend_open = false # any tap closes the key
		queue_redraw()
	elif _card_close_rect.has_area() and _card_close_rect.has_point(p):
		_quest_selected = ""
		queue_redraw()
	elif _track_rect.has_area() and _track_rect.has_point(p) and _quest_selected != "":
		_track_selected()
	elif _start_rect.has_area() and _start_rect.has_point(p) and _quest_selected != "":
		if SignalBus.quest_action_provider.is_valid() and bool(SignalBus.quest_action_provider.call("start", _quest_selected)):
			set_open(false)
		else:
			SignalBus.hint_requested.emit(tr("QUEST_STOP_AT_KERB"), 3.0)
	elif _card_rect.has_area() and _card_rect.has_point(p):
		pass # the card's body: never drop a pin through it
	elif _destination_rect.has_point(p):
		_select_mode = 2
		queue_redraw()
	elif _navigate_rect.has_point(p):
		if _has_custom_destination:
			SignalBus.custom_navigation_requested.emit(_player, _custom_destination)
			set_open(false)
		else:
			SignalBus.hint_requested.emit(tr("MAP_DROP_PIN_FIRST"), 2.0)
	elif _clear_rect.has_point(p):
		_has_custom_destination = false
		_select_mode = 0
		_quest_selected = ""
		SignalBus.custom_navigation_cleared.emit()
		queue_redraw()
	else:
		return false
	return true

## A tap on the map itself: a quest badge or garage selects it, a tap in pin mode places the pin,
## and any other tap closes the quest card (Nov 9: the card stayed up after "Clear route").
func _tap_map(p: Vector2) -> void:
	if _select_quest_at(p) or _select_garage_at(p):
		return
	if _select_mode != 0:
		_select_point(p)
	elif _quest_selected != "":
		_quest_selected = ""
		queue_redraw()

## "Go there" draws the route to the quest on both maps and closes the card; "Clear route" removes it.
func _track_selected() -> void:
	var selected: Dictionary = _selected_quest()
	var routing: bool = not bool(selected.get("tracked", false))
	if SignalBus.quest_action_provider.is_valid():
		SignalBus.quest_action_provider.call("track", _quest_selected if routing else "")
	_quest_selected = ""
	_refresh_quests()
	if routing and _route.size() >= 2 and not _ride_busy():
		_fit_route()

## Frame the auto and the whole route so the player sees where "Go there" leads.
func _fit_route() -> void:
	var box: Rect2 = Rect2(Vector2(_player.x, _player.z), Vector2.ZERO)
	for p: Vector3 in _route:
		box = box.expand(Vector2(p.x, p.z))
	centre = box.get_center()
	var room: Vector2 = Vector2(maxf(size.x - 220.0, 100.0), maxf(size.y - 300.0, 100.0))
	scale_px = clampf(minf(room.x / maxf(box.size.x, 1.0), room.y / maxf(box.size.y, 1.0)), MIN_SCALE, 1.2)
	queue_redraw()

func _journal_pages() -> int:
	return maxi(1, ceili(float(_quest_rows.size()) / float(JOURNAL_ROWS)))

func _ride_busy() -> bool:
	return SignalBus.savari_busy_provider.is_valid() and bool(SignalBus.savari_busy_provider.call())

func _refresh_quests() -> void:
	_quest_rows.clear()
	if SignalBus.quest_discovery_provider.is_valid():
		var rows: Array = SignalBus.quest_discovery_provider.call()
		for row: Dictionary in rows:
			_quest_rows.append(row)
	queue_redraw()

func _selected_quest() -> Dictionary:
	for quest: Dictionary in _quest_rows:
		if str(quest["id"]) == _quest_selected:
			return quest
	return {}

func _select_quest_at(p: Vector2) -> bool:
	for hit: Dictionary in _quest_hits:
		if (hit["rect"] as Rect2).has_point(p):
			var members: PackedStringArray = hit["members"]
			var index: int = members.find(_quest_selected)
			_quest_selected = members[(index + 1) % members.size()]
			_journal_open = false
			queue_redraw()
			return true
	return false

func _select_journal_row(p: Vector2) -> bool:
	var first: int = _journal_page * JOURNAL_ROWS
	for i: int in range(first, mini(first + JOURNAL_ROWS, _quest_rows.size())):
		if _journal_row_rect(i - first).has_point(p):
			_quest_selected = str(_quest_rows[i]["id"])
			_journal_open = false
			centre = Vector2((_quest_rows[i]["position"] as Vector3).x, (_quest_rows[i]["position"] as Vector3).z)
			return true
	return false

## Select a service point directly instead of requiring the player to drop a pin
## on the garage's tiny map symbol. The usual Set Route button starts navigation.
func _select_garage_at(screen_point: Vector2) -> bool:
	var nearest: Dictionary = {}
	var best_distance: float = 30.0
	for poi: Dictionary in _pois:
		if str(poi.get("kind", "")) != "garage":
			continue
		var position: Vector2 = poi["pos"]
		var distance: float = to_screen(position).distance_to(screen_point)
		if distance < best_distance:
			best_distance = distance
			nearest = poi
	if nearest.is_empty():
		return false
	var pos: Vector2 = nearest["pos"]
	_custom_destination = Vector3(pos.x, 0.0, pos.y)
	_has_custom_destination = true
	_select_mode = 0
	SignalBus.hint_requested.emit("%s selected — tap Set Route" % str(nearest["name"]), 3.0)
	queue_redraw()
	return true

func _select_point(screen_point: Vector2) -> void:
	var w: Vector2 = to_world(screen_point)
	var point: Vector3 = Vector3(w.x, 0.0, w.y)
	_custom_destination = point
	_has_custom_destination = true
	# Keep selection mode active so the pin can be dragged until Set Route.
	_select_mode = 2
	queue_redraw()

func _on_custom_state(active: bool, start: Vector3, destination: Vector3) -> void:
	if active:
		_custom_destination = destination
		_has_custom_destination = true
	else:
		_has_custom_destination = false
	queue_redraw()

func _zoom_at(factor: float, screen_pt: Vector2) -> void:
	var before: Vector2 = to_world(screen_pt)
	scale_px = clampf(scale_px * factor, MIN_SCALE, MAX_SCALE)
	centre += before - to_world(screen_pt)
	queue_redraw()

func _pinch_distance() -> float:
	var v: Array = _touches.values()
	return (v[0] as Vector2).distance_to(v[1] as Vector2) if v.size() >= 2 else 0.0

func _pinch_mid() -> Vector2:
	var v: Array = _touches.values()
	return ((v[0] as Vector2) + (v[1] as Vector2)) * 0.5 if v.size() >= 2 else size * 0.5

func to_screen(w: Vector2) -> Vector2:
	return size * 0.5 + (w - centre) * scale_px

func to_world(s: Vector2) -> Vector2:
	return centre + (s - size * 0.5) / scale_px

# --- Drawing ------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var view: Rect2 = Rect2(to_world(Vector2.ZERO), size / scale_px).grow(60.0)
	_draw_areas(view)
	if graph != null:
		_draw_roads(view)
	_draw_route()
	_draw_pois(view)
	if graph != null:
		_draw_labels(view)
	_draw_hails()
	_draw_custom_pins()
	_draw_quests(view)
	# Last of the world layer: a quest badge must never hide the player's own auto.
	_draw_player()
	_draw_chrome()
	_draw_quest_ui()
	_draw_toast()

## True where an open panel (quest list or map key) covers the map: nothing there can be seen or
## tapped, so it is not drawn or hit-tested. This is the saving that keeps the panels cheap.
func _under_panel(p: Vector2) -> bool:
	if _journal_open:
		return _journal_layout().has_point(p)
	if _legend_open:
		return _legend_panel.has_point(p)
	return false

func _draw_quests(view: Rect2) -> void:
	_quest_hits.clear()
	var clusters: Dictionary = {}
	for q: Dictionary in _quest_rows:
		var pos: Vector3 = q["position"]
		if not view.has_point(Vector2(pos.x, pos.z)):
			continue
		if bool(q["completed"]):
			_draw_done_badge(to_screen(Vector2(pos.x, pos.z)))
			continue
		var screen: Vector2 = to_screen(Vector2(pos.x, pos.z))
		if _under_panel(screen):
			continue
		var key: Vector2i = Vector2i(floori(screen.x / 52.0), floori(screen.y / 52.0))
		if not clusters.has(key):
			clusters[key] = {"point": screen, "members": PackedStringArray()}
		var cluster: Dictionary = clusters[key]
		var ids: PackedStringArray = cluster["members"]
		ids.append(str(q["id"]))
		cluster["members"] = ids
		clusters[key] = cluster
	for key: Vector2i in clusters:
		var cluster: Dictionary = clusters[key]
		var point: Vector2 = cluster["point"]
		var members: PackedStringArray = cluster["members"]
		var selected: bool = members.has(_quest_selected)
		_draw_quest_badge(point, str(members.size()) if members.size() > 1 else "!", selected)
		_quest_hits.append({"rect": Rect2(point - Vector2(24, 24), Vector2(48, 48)), "members": members})

## Quest card, journal and legend: the one panel open at a time, anchored above the bottom bar.
func _draw_quest_ui() -> void:
	_track_rect = Rect2()
	_start_rect = Rect2()
	_card_rect = Rect2()
	_card_close_rect = Rect2()
	_journal_back = Rect2()
	_journal_next = Rect2()
	_journal_panel = Rect2()
	if _legend_open:
		_draw_legend()
		return
	if _journal_open:
		_draw_journal()
		return
	var q: Dictionary = _selected_quest()
	if q.is_empty():
		return
	var width: float = minf(size.x - 32.0, 400.0)
	var body: String = "%s\n%s" % [str(q["description"]), str(q["job"])]
	var body_h: float = _body.get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, width - 52.0, 16).y
	var completed: bool = bool(q["completed"])
	var height: float = 50.0 + body_h + 40.0 + (0.0 if completed else 72.0) + 14.0
	var y: float = size.y - BAR_BOTTOM_GAP - 12.0 - height
	_card_rect = Rect2(Vector2(16.0, y), Vector2(width, height))
	MapChrome.panel(self, _card_rect)
	var title_w: float = minf(width - 130.0, _title.get_string_size(str(q["title"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 48.0)
	MapChrome.ribbon(self, Rect2(Vector2(30.0, y - 16.0), Vector2(title_w, 38.0)), str(q["title"]), _title, 20)
	_card_close_rect = Rect2(Vector2(16.0 + width - 60.0, y + 10.0), Vector2(46.0, 46.0))
	MapChrome.button(self, _card_close_rect, "✕", UIKit.Tone.RED, _title, false, 20)
	draw_multiline_string(_body, Vector2(30.0, y + 50.0), body, HORIZONTAL_ALIGNMENT_LEFT, width - 52.0, 16, -1, MapChrome.JASMINE)
	var reward_y: float = y + 50.0 + body_h + 4.0
	var status: String = tr("QUEST_DONE") if completed else tr("QUEST_REWARD") % [UIKit.inr(int(q["reward"])), int(q["minutes"])]
	var pill_w: float = minf(width - 52.0, _body.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 52.0)
	MapChrome.pill(self, Rect2(Vector2(30.0, reward_y), Vector2(pill_w, 30.0)), status,
			Color("3ddc84") if completed else MapChrome.MARIGOLD, _body, 15)
	if completed:
		return
	var at: Vector3 = q["position"]
	var near: bool = Vector2(at.x, at.z).distance_to(Vector2(_player.x, _player.z)) <= QUEST_START_NEAR_M
	var row_y: float = y + height - 70.0
	if near:
		_start_rect = Rect2(Vector2(30.0, row_y), Vector2(width - 52.0, 56.0))
		MapChrome.button(self, _start_rect, tr("QUEST_START"), UIKit.Tone.GREEN, _title, false, 22)
	else:
		_track_rect = Rect2(Vector2(30.0, row_y), Vector2(width - 52.0, 56.0))
		if bool(q["tracked"]):
			MapChrome.button(self, _track_rect, tr("QUEST_UNTRACK"), UIKit.Tone.ORANGE, _title, false, 22)
		else:
			MapChrome.button(self, _track_rect, tr("QUEST_TRACK"), UIKit.Tone.YELLOW, _title, false, 22)

## The journal's panel: five rows a page, each with two lines of description, so nothing is cut
## off mid-sentence. Hit-testing reads the same geometry, so the two can never drift apart.
func _journal_layout() -> Rect2:
	var w: float = minf(400.0, size.x - 32.0)
	return Rect2(Vector2(16.0, JOURNAL_TOP), Vector2(w, JOURNAL_HEAD + JOURNAL_ROWS * JOURNAL_ROW_H + JOURNAL_PAGER_H))

func _journal_row_rect(slot: int) -> Rect2:
	var panel: Rect2 = _journal_layout()
	return Rect2(panel.position + Vector2(12.0, JOURNAL_HEAD + slot * JOURNAL_ROW_H), Vector2(panel.size.x - 24.0, JOURNAL_ROW_H - 8.0))

func _draw_journal() -> void:
	var panel: Rect2 = _journal_layout()
	_journal_panel = panel
	# The list can shrink (a quest finished, a new game): never show a page past the last one.
	_journal_page = clampi(_journal_page, 0, _journal_pages() - 1)
	MapChrome.panel(self, panel)
	MapChrome.ribbon(self, Rect2(panel.position + Vector2(18.0, -16.0), Vector2(190.0, 38.0)), tr("QUEST_JOURNAL"), _title, 22)
	if _quest_rows.is_empty():
		draw_multiline_string(_body, panel.position + Vector2(20.0, 70.0), tr("QUEST_EMPTY"), HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 40.0, 17, -1, MapChrome.JASMINE)
	var first: int = _journal_page * JOURNAL_ROWS
	for i: int in range(first, mini(first + JOURNAL_ROWS, _quest_rows.size())):
		var q: Dictionary = _quest_rows[i]
		var rr: Rect2 = _journal_row_rect(i - first)
		var selected: bool = bool(q["tracked"])
		draw_style_box(MapChrome.box(Color(0.2, 0.14, 0.26, 1.0), MapChrome.MARIGOLD if selected else MapChrome.DUSK, 14, 3 if selected else 2), rr)
		draw_texture_rect(UIKit.reward_cell("coin"), Rect2(rr.position + Vector2(10.0, 10.0), Vector2(40.0, 40.0)), false)
		var status: String = _journal_status(q)
		var status_fill: Color = _journal_status_fill(q)
		var pill_w: float = _body.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 24.0
		MapChrome.pill(self, Rect2(rr.end - Vector2(pill_w + 10.0, rr.size.y - 14.0), Vector2(pill_w, 24.0)), status, status_fill, _body, 13)
		var text_x: float = rr.position.x + 62.0
		var text_w: float = rr.size.x - 62.0 - pill_w - 24.0
		draw_string(_title, Vector2(text_x, rr.position.y + 26.0), str(q["title"]), HORIZONTAL_ALIGNMENT_LEFT, text_w, 19, MapChrome.MARIGOLD)
		var line: String = str(q["description"]) if bool(q["unlocked"]) else str(q["locked_reason"])
		draw_multiline_string(_body, Vector2(text_x, rr.position.y + 44.0), line, HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 72.0, 14, 2, MapChrome.JASMINE)
	var pages: int = _journal_pages()
	var pager_y: float = panel.end.y - JOURNAL_PAGER_H + 8.0
	if pages > 1:
		draw_string(_title, Vector2(panel.position.x, pager_y + 30.0), "%d / %d" % [_journal_page + 1, pages], HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 18, MapChrome.JASMINE)
	if _journal_page > 0:
		_journal_back = Rect2(Vector2(panel.position.x + 14.0, pager_y), Vector2(84.0, 44.0))
		MapChrome.button(self, _journal_back, "", UIKit.Tone.PURPLE, _title)
		_draw_chevron(_journal_back.get_center(), -1.0)
	if _journal_page < pages - 1:
		_journal_next = Rect2(Vector2(panel.end.x - 98.0, pager_y), Vector2(84.0, 44.0))
		MapChrome.button(self, _journal_next, "", UIKit.Tone.PURPLE, _title)
		_draw_chevron(_journal_next.get_center(), 1.0)

## A pager chevron: -1 points left, 1 points right. Drawn, so it is the same at every font size.
func _draw_chevron(c: Vector2, dir: float) -> void:
	draw_polyline(PackedVector2Array([c + Vector2(-5.0 * dir, -9.0), c + Vector2(5.0 * dir, 0.0), c + Vector2(-5.0 * dir, 9.0)]), MapChrome.JASMINE, 4.5)

func _journal_status(q: Dictionary) -> String:
	if bool(q["completed"]):
		return tr("QUEST_DONE")
	if not bool(q["unlocked"]):
		return tr("QUEST_LOCKED")
	return tr("QUEST_TRACKED") if bool(q["tracked"]) else tr("QUEST_AVAILABLE")

func _journal_status_fill(q: Dictionary) -> Color:
	if bool(q["completed"]):
		return Color("3ddc84")
	if not bool(q["unlocked"]):
		return Color("8a8290")
	return MapChrome.MARIGOLD if bool(q["tracked"]) else MapChrome.GREEN

## Map key: every symbol the map draws, drawn by the same code as the map itself.
func _draw_legend() -> void:
	var rows: int = ceili(LEGEND_ITEMS.size() / 2.0)
	var width: float = minf(600.0, size.x - 120.0)
	var row_h: float = minf(42.0, (size.y - JOURNAL_TOP - BAR_BOTTOM_GAP - 80.0) / rows)
	var panel: Rect2 = Rect2(Vector2(16.0, JOURNAL_TOP), Vector2(width, 62.0 + rows * row_h + 14.0))
	_legend_panel = panel
	MapChrome.panel(self, panel)
	MapChrome.ribbon(self, Rect2(panel.position + Vector2(18.0, -16.0), Vector2(260.0, 38.0)), tr("MAP_LEGEND_TITLE"), _title, 20)
	var col_w: float = width * 0.5
	for i: int in LEGEND_ITEMS.size():
		var kind: String = LEGEND_ITEMS[i]
		var col: int = i / rows
		var row: int = i % rows
		var at: Vector2 = panel.position + Vector2(14.0 + col * col_w + 22.0, 62.0 + row * row_h + row_h * 0.5)
		_draw_legend_icon(kind, at)
		draw_string(_body, at + Vector2(28.0, 6.0), tr("MAP_KEY_" + kind.to_upper()), HORIZONTAL_ALIGNMENT_LEFT, col_w - 64.0, 15, MapChrome.JASMINE)

func _draw_legend_icon(kind: String, at: Vector2) -> void:
	match kind:
		"player":
			_draw_auto_arrow(at, Vector2(0, -1))
		"route":
			_draw_route_swatch(at)
		"destination":
			_draw_route_end(at)
		"pin":
			_draw_pin(at)
		"hail":
			_draw_hail(at)
		"quest":
			_draw_quest_badge(at, "!", false, 13.0)
		"quest_group":
			_draw_quest_badge(at, "3", false, 13.0)
		"quest_done":
			_draw_done_badge(at)
		"main_road":
			draw_line(at - Vector2(14, 0), at + Vector2(14, 0), ROAD_STYLE["trunk"][0] as Color, 6.0)
		"closed":
			draw_line(at - Vector2(14, 0), at + Vector2(14, 0), CLOSED_ROAD, 6.0)
		"water", "park", "sea":
			draw_style_box(MapChrome.box(AREA_COLOURS[kind] as Color, MapChrome.PLUM, 4, 2), Rect2(at - Vector2(13, 9), Vector2(26, 18)))
		_:
			_draw_poi_icon(at, kind)

func _draw_quest_badge(point: Vector2, label: String, selected: bool, radius: float = 20.0) -> void:
	MapChrome.token(self, point, radius, UIKit.Tone.YELLOW, label, _title, selected)

func _draw_done_badge(point: Vector2) -> void:
	MapChrome.token(self, point, 11.0, UIKit.Tone.GREEN, "", _title)
	draw_polyline(PackedVector2Array([point + Vector2(-4, 0), point + Vector2(-1, 4), point + Vector2(5, -4)]), MapChrome.JASMINE, 2.5)

## Waiting passenger: a green token with a head dot, so it never looks like a quest.
func _draw_hail(point: Vector2) -> void:
	MapChrome.token(self, point, 11.0, UIKit.Tone.GREEN, "", _title)
	draw_circle(point + Vector2(0.0, 1.0), 3.5, MapChrome.JASMINE)

## Route end: a jasmine disc with a green heart, so it reads as the finish of the trail.
func _draw_route_end(point: Vector2) -> void:
	draw_circle(point + Vector2(0.0, 3.0), 10.0, MapChrome.PLUM)
	draw_circle(point, 10.0, MapChrome.JASMINE)
	draw_circle(point, 6.0, MapChrome.GREEN)

func _draw_route_swatch(at: Vector2) -> void:
	draw_line(at - Vector2(14, 0), at + Vector2(14, 0), MapChrome.PLUM, 9.0)
	draw_line(at - Vector2(14, 0), at + Vector2(14, 0), MapChrome.GREEN, 5.0)

func _draw_toast() -> void:
	if _toast_text == "":
		return
	var fs: int = 18
	var w: float = minf(_title.get_string_size(_toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 52.0, size.x - TOP_BANNER_SIDE * 2.0)
	MapChrome.banner(self, Rect2(Vector2((size.x - w) * 0.5, TOP_BANNER_Y), Vector2(w, 50.0)), _toast_text, _title, fs)

## Areas are flat fills, one draw call per polygon, so the basemap stays cheap.
func _draw_areas(view: Rect2) -> void:
	for kind: String in ["sea", "beach", "park", "water"]:
		for poly: Array in _areas.get(kind, []):
			if poly.size() < 3:
				continue
			var pts: PackedVector2Array = PackedVector2Array()
			var bb: Rect2 = Rect2(Vector2(float(poly[0][0]), float(poly[0][1])), Vector2.ZERO)
			for p: Array in poly:
				var w: Vector2 = Vector2(float(p[0]), float(p[1]))
				bb = bb.expand(w)
				pts.append(to_screen(w))
			if not bb.intersects(view):
				continue
			if Geometry2D.triangulate_polygon(pts).is_empty():
				draw_polyline(pts, AREA_COLOURS[kind] as Color, 2.0) # rivers drawn as lines (non-simple polygons)
			else:
				draw_colored_polygon(pts, AREA_COLOURS[kind] as Color)

func _draw_roads(view: Rect2) -> void:
	var minor: PackedVector2Array = PackedVector2Array()
	var major: Dictionary = {}
	var closed: PackedVector2Array = PackedVector2Array()
	for e: RoadGraph.Edge in graph.edges:
		var a0: Vector3 = e.points[0]
		if not view.has_point(Vector2(a0.x, a0.z)) and not view.has_point(Vector2(e.points[e.points.size() - 1].x, e.points[e.points.size() - 1].z)):
			continue
		if e.closed:
			for i: int in range(1, e.points.size()):
				closed.append(to_screen(Vector2(e.points[i - 1].x, e.points[i - 1].z)))
				closed.append(to_screen(Vector2(e.points[i].x, e.points[i].z)))
		var target: PackedVector2Array = minor
		if ROAD_STYLE.has(e.road_class):
			if not major.has(e.road_class):
				major[e.road_class] = PackedVector2Array()
			target = major[e.road_class]
		elif scale_px < 0.12:
			continue # residential lanes vanish when zoomed far out
		for i: int in range(1, e.points.size()):
			target.append(to_screen(Vector2(e.points[i - 1].x, e.points[i - 1].z)))
			target.append(to_screen(Vector2(e.points[i].x, e.points[i].z)))
		if target != minor:
			major[e.road_class] = target
		else:
			minor = target
	if not minor.is_empty():
		draw_multiline(minor, MINOR, maxf(1.0, 6.0 * scale_px))
	# Main roads get a plum casing first, like a painted map's inked edge. One extra batch each.
	for cls: String in ["tertiary", "secondary", "primary", "trunk"]:
		if major.has(cls):
			var st: Array = ROAD_STYLE[cls]
			var w: float = maxf(float(st[2]), 12.0 * scale_px * float(st[1]))
			if cls == "trunk" or cls == "primary": # casing only on the big roads: it costs a batch each
				draw_multiline(major[cls], MapChrome.PLUM, w + 3.0)
			draw_multiline(major[cls], st[0] as Color, w)
	# Roads closed for works (RoadWorks): red on top, so the GPS detour makes sense.
	if not closed.is_empty():
		draw_multiline(closed, CLOSED_ROAD, maxf(3.0, 9.0 * scale_px))

## The GPS route: a plum casing under a green trail, finished with a route-end disc.
func _draw_route() -> void:
	if _route.size() < 2:
		return
	var pts: PackedVector2Array = PackedVector2Array()
	for p: Vector3 in _route:
		pts.append(to_screen(Vector2(p.x, p.z)))
	draw_polyline(pts, MapChrome.PLUM, maxf(9.0, 16.0 * scale_px))
	draw_polyline(pts, MapChrome.GREEN, maxf(5.0, 11.0 * scale_px))
	_draw_route_end(pts[pts.size() - 1])

## Points of interest are drawn shapes, not emoji: the game's font has no emoji glyphs, so the old
## fuel-pump and spanner icons rendered as empty boxes.
func _draw_poi_icon(s: Vector2, kind: String) -> void:
	draw_circle(s, 13.0, MapChrome.MARIGOLD.darkened(0.2))
	draw_circle(s, 11.0, MapChrome.PLUM)
	match kind:
		"landmark":
			var star: PackedVector2Array = PackedVector2Array()
			for i: int in 10:
				var r: float = 8.0 if i % 2 == 0 else 3.6
				var a: float = -PI * 0.5 + i * PI / 5.0
				star.append(s + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(star, MapChrome.MARIGOLD)
		"stand":
			draw_string(_title, s + Vector2(-6, 6), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MapChrome.MARIGOLD)
		"lpg":
			draw_rect(Rect2(s + Vector2(-5, -7), Vector2(10, 14)), ORANGE_ICON)
			draw_rect(Rect2(s + Vector2(-2, -9), Vector2(4, 2)), ORANGE_ICON)
		"ev":
			draw_colored_polygon(PackedVector2Array([s + Vector2(1, -8), s + Vector2(-5, 1), s + Vector2(0, 1), s + Vector2(-2, 8), s + Vector2(5, -2), s + Vector2(0, -2)]), MapChrome.GREEN)
		"garage":
			draw_rect(Rect2(s + Vector2(-6, -2), Vector2(12, 8)), MapChrome.JASMINE)
			draw_colored_polygon(PackedVector2Array([s + Vector2(-8, -2), s + Vector2(0, -9), s + Vector2(8, -2)]), MapChrome.JASMINE)
		_:
			draw_circle(s, 3.0, MapChrome.JASMINE)

const ORANGE_ICON: Color = Color("ff7a3d")

func _draw_pois(view: Rect2) -> void:
	for p: Dictionary in _pois:
		var w: Vector2 = p["pos"]
		if not view.has_point(w):
			continue
		var s: Vector2 = to_screen(w)
		if _under_panel(s):
			continue
		_draw_poi_icon(s, str(p["kind"]))
		if scale_px >= 0.25 or str(p["kind"]) == "landmark":
			draw_string_outline(_body, s + Vector2(16, 6), str(p["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, MapChrome.PLUM)
			draw_string(_body, s + Vector2(16, 6), str(p["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MapChrome.JASMINE)

## Street names along the roads, rotated to the road, decluttered on a screen grid.
func _draw_labels(view: Rect2) -> void:
	var used: Dictionary = {}
	var min_rank: int = 4 if scale_px < 0.15 else (3 if scale_px < 0.35 else (2 if scale_px < 0.8 else 1))
	for l: Dictionary in _labels:
		if _rank(str(l["cls"])) < min_rank:
			continue
		var e: RoadGraph.Edge = l["edge"]
		var mid_i: int = e.points.size() / 2
		var a: Vector3 = e.points[maxi(mid_i - 1, 0)]
		var b: Vector3 = e.points[mini(mid_i, e.points.size() - 1)]
		if a.is_equal_approx(b):
			b = e.points[e.points.size() - 1]
		var mid: Vector2 = Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
		if not view.has_point(mid) or e.length * scale_px < 60.0:
			continue
		var s: Vector2 = to_screen(mid)
		if _under_panel(s):
			continue
		var cell: Vector2i = Vector2i(floori(s.x / LABEL_CELL_PX), floori(s.y / (LABEL_CELL_PX * 0.4)))
		if used.has(cell):
			continue
		used[cell] = true
		var ang: float = atan2(b.z - a.z, b.x - a.x)
		if ang > PI * 0.5:
			ang -= PI
		elif ang < -PI * 0.5:
			ang += PI
		var name: String = str(l["name"])
		var fs: int = 15 if _rank(str(l["cls"])) >= 3 else 13
		var w: float = _body.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_set_transform(s, ang, Vector2.ONE)
		draw_string_outline(_body, Vector2(-w * 0.5, 5), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, MapChrome.PLUM)
		draw_string(_body, Vector2(-w * 0.5, 5), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, MapChrome.JASMINE)
		var ta: String = str(l["ta"])
		if ta != "" and scale_px >= 0.5:
			var tw: float = _body.get_string_size(ta, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2).x
			draw_string_outline(_body, Vector2(-tw * 0.5, 22), ta, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, 5, MapChrome.PLUM)
			draw_string(_body, Vector2(-tw * 0.5, 22), ta, HORIZONTAL_ALIGNMENT_LEFT, -1, fs - 2, MARIGOLD_TEXT)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

const MARIGOLD_TEXT: Color = Color("ffd35c")

func _draw_hails() -> void:
	for h: Dictionary in _hails:
		var p: Vector3 = h["position"]
		_draw_hail(to_screen(Vector2(p.x, p.z)))

func _draw_player() -> void:
	_draw_auto_arrow(to_screen(Vector2(_player.x, _player.z)), Vector2(_heading.x, _heading.z).normalized())

## The player's auto: a marigold arrow with a plum contour, on a soft halo.
func _draw_auto_arrow(s: Vector2, f: Vector2) -> void:
	if f == Vector2.ZERO:
		f = Vector2(0, -1)
	var r: Vector2 = Vector2(-f.y, f.x)
	draw_circle(s, 17.0, Color(1.0, 0.76, 0.1, 0.3))
	var tip: PackedVector2Array = PackedVector2Array([s + f * 15.0, s - f * 9.0 + r * 10.0, s - f * 4.0, s - f * 9.0 - r * 10.0, s + f * 15.0])
	draw_colored_polygon(tip, MapChrome.MARIGOLD)
	draw_polyline(tip, MapChrome.PLUM, 3.0)

func _draw_custom_pins() -> void:
	if not _has_custom_destination:
		return
	var screen: Vector2 = to_screen(Vector2(_custom_destination.x, _custom_destination.z))
	_draw_pin(screen)
	# Mid-ride the rider's route keeps the GPS: say when this pin's route will start.
	if _ride_busy():
		var label: String = tr("MAP_PIN_AFTER_RIDE")
		var w: float = _body.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 28.0
		MapChrome.banner(self, Rect2(screen + Vector2(20.0, -34.0), Vector2(w, 30.0)), label, _body, 14)

func _draw_pin(screen: Vector2) -> void:
	MapChrome.token(self, screen, 12.0, UIKit.Tone.ORANGE, "", _title)
	draw_circle(screen, 4.0, MapChrome.JASMINE)

## The top-left plate, the mode buttons and the bottom bar. Every rect is recomputed here, and
## _tap_button reads these same rects, so what you see is what answers a tap.
func _draw_chrome() -> void:
	var b: float = 64.0
	var rx: float = size.x - b - 20.0
	_close_rect = Rect2(Vector2(rx, 14.0), Vector2(b, b))
	_plus_rect = Rect2(Vector2(rx, size.y * 0.5 - 70.0), Vector2(b, b))
	_minus_rect = Rect2(Vector2(rx, size.y * 0.5 + 6.0), Vector2(b, b))
	_me_rect = Rect2(Vector2(rx, size.y * 0.5 + 82.0), Vector2(b, b))
	MapChrome.button(self, _close_rect, "✕", UIKit.Tone.RED, _title, false, 26)
	MapChrome.button(self, _plus_rect, "+", UIKit.Tone.YELLOW, _title, false, 30)
	MapChrome.button(self, _minus_rect, "−", UIKit.Tone.YELLOW, _title, false, 30)
	MapChrome.button(self, _me_rect, "◎", UIKit.Tone.GREEN, _title, false, 26)
	_draw_compass(Vector2(rx + b * 0.5, 116.0))
	MapChrome.ribbon(self, Rect2(Vector2(16.0, 14.0), Vector2(236.0, 52.0)), "CHENNAI", _title, 26)
	_journal_rect = Rect2(Vector2(16.0, 76.0), Vector2(176.0, 60.0))
	_legend_rect = Rect2(Vector2(200.0, 76.0), Vector2(150.0, 60.0))
	MapChrome.button(self, _journal_rect, tr("QUEST_JOURNAL"), UIKit.Tone.YELLOW, _title, _journal_open, 20)
	MapChrome.button(self, _legend_rect, tr("MAP_LEGEND"), UIKit.Tone.PURPLE, _title, _legend_open, 20)
	var bw: float = minf(200.0, (size.x - 40.0 - 16.0) / 3.0)
	var y: float = size.y - BAR_BOTTOM_GAP
	_destination_rect = Rect2(Vector2(16.0, y), Vector2(bw, 66.0))
	_navigate_rect = Rect2(Vector2(16.0 + bw + 8.0, y), Vector2(bw, 66.0))
	_clear_rect = Rect2(Vector2(16.0 + (bw + 8.0) * 2.0, y), Vector2(bw, 66.0))
	MapChrome.button(self, _destination_rect, tr("MAP_DROP_PIN"), UIKit.Tone.ORANGE, _title, _select_mode == 2, 20)
	MapChrome.button(self, _navigate_rect, tr("MAP_SET_ROUTE"), UIKit.Tone.GREEN, _title, false, 20)
	MapChrome.button(self, _clear_rect, tr("MAP_CLEAR"), UIKit.Tone.RED, _title, false, 20)
	if _select_mode != 0:
		var help: String = tr("MAP_PIN_HELP")
		var w: float = minf(_title.get_string_size(help, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 52.0, size.x - TOP_BANNER_SIDE * 2.0)
		MapChrome.banner(self, Rect2(Vector2((size.x - w) * 0.5, TOP_BANNER_Y), Vector2(w, 50.0)), help, _title, 18)
	draw_string(_body, Vector2(16.0, size.y - 6.0), "Map data © OpenStreetMap contributors", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))

## A marigold compass disc with a red needle pointing north.
func _draw_compass(c: Vector2) -> void:
	draw_circle(c, 30.0, MapChrome.MARIGOLD)
	draw_circle(c, 24.0, MapChrome.PLUM)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -20), c + Vector2(8, 6), c + Vector2(-8, 6)]), RED_NEEDLE)
	draw_string(_title, c + Vector2(-8, 36), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MapChrome.JASMINE)

const RED_NEEDLE: Color = Color("e8392e")
