class_name PassengerHUD
extends CanvasLayer
## Savari-mode UI in the "Namma Auto Arcade" style (UIKit): wallet / rating / rank chips,
## the haggle card (4G), the live ride card, the ride-complete fare screen (4F), the level-up
## celebration (4H), toasts and the mini-map. Reads SignalBus only; haggle choices go back out
## as SignalBus.haggle_choice_made. Everything is built once and reused (no nodes per ride).

const OFFER_TONES: Array[UIKit.Tone] = [UIKit.Tone.GREEN, UIKit.Tone.YELLOW, UIKit.Tone.RED]
const OFFER_CAPTION: PackedStringArray = ["RIDE FARE", "COUNTER", "DEMAND"]
const OFFER_TAGS: PackedStringArray = ["safe", "bargain", "greedy"]
const OFFER_SHORT: PackedStringArray = ["Correct Meter", "Meter Mela", "Fixed Rate"]
const OFFER_TAMIL: PackedStringArray = ["ஏற்றுக்கொள்", "பேரம்", "ஒரே ரேட்"]
const MINIMAP_SIZE: float = 170.0
const FARE_SECONDS: float = 8.0
const LEVEL_UP_SECONDS: float = 7.0

var _root: Control
var _wallet: Label
var _rating: Label
var _level: Label
var _level_icon: TextureRect
var _xp_bar: ProgressBar
var _chips: HBoxContainer
var _ride_card: PanelContainer
var _ride_text: Label
var _comfort_bar: ProgressBar
# Haggle (4G)
var _haggle: PanelContainer
var _haggle_title: Label
var _haggle_line: Label
var _haggle_name: Label
var _haggle_portrait: TextureRect
var _haggle_ring: CountdownRing
var _haggle_buttons: Array[Button] = []
var _offer_price: Array[Label] = []
var _offer_title: Array[Label] = []
var _offer_bar: Array[ProgressBar] = []
var _offer_chance: Array[Label] = []
var _haggle_time: float = 0.0
var _haggle_total: float = 5.0
# Fare result (4F)
var _fare_card: PanelContainer
var _fare_text: Label
var _fare_stars: Array[TextureRect] = []
var _fare_route: Label
var _fare_portrait: TextureRect
var _fare_quote: Label
var _fare_rows: VBoxContainer
var _fare_total: Label
var _fare_xp: ProgressBar
var _fare_timer: float = 0.0
# Level-up (4H)
var _level_up: Control
var _rays: Rays
var _medal: TextureRect
var _level_title: Label
var _level_rewards: HBoxContainer
var _level_timer: float = 0.0
var _rays_spin: Tween
var _toast: Label
var _toast_timer: float = 0.0
var minimap: MiniMap
var _hint: Label
var _hint_timer: float = 0.0
var nav_banner: NavBanner
var full_map: FullMap
var _double_btn: Button
var _last_ride: Dictionary = {}
var _warning_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _guidance_distance: Label

## 5-second haggle timer ring with the seconds in the middle (4G "0s" badge).
class CountdownRing:
	extends Control
	var value: float = 1.0
	var seconds: float = 5.0
	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 4.0
		draw_circle(c, r + 3.0, UIKit.PLUM)
		draw_circle(c, r, Color("120c16"))
		var col: Color = UIKit.GREEN if value > 0.5 else (UIKit.YELLOW if value > 0.25 else UIKit.RED)
		draw_arc(c, r - 5.0, -PI * 0.5, -PI * 0.5 + TAU * value, 40, col, 7.0, true)
		var f: Font = UIKit.title_font()
		var txt: String = "%ds" % ceili(value * seconds)
		var w: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string(f, c + Vector2(-w * 0.5, 9.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UIKit.JASMINE)

## Rotating sun rays behind the level-up medal (4H "rotate-slow").
class Rays:
	extends Control
	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = maxf(size.x, size.y)
		for i: int in 16:
			var a: float = TAU * float(i) / 16.0
			var w: float = 0.09
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a - w), sin(a - w)) * r, c + Vector2(cos(a + w), sin(a + w)) * r]),
				Color(1.0, 0.62, 0.15, 0.22 if i % 2 == 0 else 0.12))
		draw_circle(c, r * 0.16, Color(1.0, 0.75, 0.3, 0.25))

func _ready() -> void:
	_warning_rng.randomize()
	layer = 11
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UIKit.theme()
	add_child(_root)
	minimap = MiniMap.new()
	minimap.name = "MiniMap"
	minimap.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	minimap.position = Vector2(16.0, 16.0)
	_root.add_child(minimap)
	SignalBus.tutorial_highlight.connect(func(id: String) -> void:
		if id == "minimap":
			SignalBus.tutorial_spotlight.emit(minimap.get_global_rect()))
	_build_chips()
	_guidance_distance = UIKit.label("", 26, Color.WHITE, true, 6)
	_guidance_distance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guidance_distance.visible = false
	_root.add_child(_guidance_distance)
	SignalBus.guidance_distance_updated.connect(func(value: String) -> void:
		_guidance_distance.text = value
		_guidance_distance.visible = value != "")
	nav_banner = NavBanner.new()
	nav_banner.name = "NavBanner"
	_root.add_child(nav_banner)
	_build_ride_card()
	_build_haggle()
	_build_fare_card()
	_build_level_up()
	_toast = UIKit.label("", 28, UIKit.YELLOW, true, 8)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_toast)
	_hint = UIKit.label("", 22, Color(0.75, 1.0, 0.8), false, 6)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_hint)
	# Full-screen map on its own layer above every HUD (opened by tapping the mini-map).
	var map_layer: CanvasLayer = CanvasLayer.new()
	map_layer.name = "FullMapLayer"
	map_layer.layer = 40
	map_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(map_layer)
	full_map = FullMap.new()
	full_map.name = "FullMap"
	map_layer.add_child(full_map)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh_wallet()
	SignalBus.wallet_balance_changed.connect(func(_b: int, _d: int) -> void: _refresh_wallet())
	SignalBus.stand_respect_changed.connect(func(_xp: int, _r: float) -> void: _refresh_wallet())
	SignalBus.haggle_started.connect(_on_haggle_started)
	SignalBus.haggle_resolved.connect(_on_haggle_resolved)
	SignalBus.ride_updated.connect(_on_ride_updated)
	SignalBus.ride_completed.connect(_on_ride_completed)
	SignalBus.hint_requested.connect(func(text: String, seconds: float) -> void:
		_hint.text = text
		_hint_timer = seconds)
	SignalBus.near_miss.connect(func(_c: float) -> void: toast("Gap-la Gethu!", 1.2))
	SignalBus.pedestrian_startled.connect(func(_p: Vector3) -> void:
		if _toast_timer <= 0.0:
			toast(_watch_out_line(), 1.2))
	SignalBus.driver_xp_changed.connect(func(_x: int, _l: int, _p: float) -> void: _refresh_level())
	SignalBus.driver_level_up.connect(_on_level_up)
	SignalBus.goal_completed.connect(func(g: Dictionary) -> void:
		toast("%s: %s  +₹%d" % [tr("GOAL_DONE"), goal_text(g), DriverProgress.GOAL_INR], 3.0))
	SignalBus.all_goals_completed.connect(func(bonus: int) -> void: toast("%s  +₹%d" % [tr("ALL_GOALS_DONE"), bonus], 4.0))
	SignalBus.achievement_unlocked.connect(func(_id: String, a: Dictionary) -> void:
		toast("%s — %s  +₹%d" % [str(a["title"]), str(a["desc"]), int(a["inr"])], 4.5))
	SignalBus.reward_granted.connect(func(source: String, inr: int, _xp: int) -> void:
		if source == "ad_double_fare" and inr > 0:
			toast("2× fare!  +₹%d" % inr, 3.0)
			_fare_card.visible = false)
	SignalBus.rewarded_ad_failed.connect(func(p: String, _why: String) -> void:
		if p == "ad_double_fare" and _double_btn != null:
			_double_btn.disabled = false)
	_refresh_level()
	SignalBus.ui_modal_changed.connect(func(open: bool) -> void: _root.visible = not open)

func _process(delta: float) -> void:
	if _haggle.visible:
		_haggle_time -= delta
		_haggle_ring.value = maxf(_haggle_time, 0.0) / _haggle_total
		_haggle_ring.queue_redraw()
		if _haggle_time <= 0.0:
			_haggle.visible = false
	if _fare_card.visible:
		_fare_timer -= delta
		if _fare_timer <= 0.0:
			_fare_card.visible = false
			# Natural break: the policy decides (usually "no" — cooldowns, grace, ride spacing).
			AdMonetizationManager.maybe_show_interstitial("after_fare_summary")
	if _level_up.visible:
		_level_timer -= delta
		if _level_timer <= 0.0:
			_close_level_up()
	var card_up: bool = _haggle.visible or _fare_card.visible or _level_up.visible
	_hint.visible = not card_up
	_toast.visible = not card_up
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			_hint.text = ""
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast.text = ""

func _watch_out_line() -> String:
	var lines: PackedStringArray = [tr("WATCH_OUT"), tr("WATCH_OUT_2"), tr("WATCH_OUT_3"), tr("WATCH_OUT_4"), tr("WATCH_OUT_5"), tr("WATCH_OUT_6")]
	return lines[_warning_rng.randi_range(0, lines.size() - 1)]

# --- Building ------------------------------------------------------------------

func _build_chips() -> void:
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 16)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_chips)
	var coin: HBoxContainer = UIKit.chip("coin", "₹500", 20)
	_chips.add_child(coin)
	_wallet = UIKit.chip_value(coin)
	var star: HBoxContainer = UIKit.chip("star", "4.5", 20)
	_chips.add_child(star)
	_rating = UIKit.chip_value(star)
	var rank: HBoxContainer = UIKit.chip("badge_bronze", "", 18)
	_root.add_child(rank)
	rank.name = "RankChip"
	_level_icon = rank.get_child(0) as TextureRect
	_level = UIKit.chip_value(rank)
	_xp_bar = UIKit.bar(0.0, UIKit.GREEN, 160, 10)
	_root.add_child(_xp_bar)

func _build_ride_card() -> void:
	_ride_card = UIKit.card()
	_ride_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ride_card.visible = false
	_root.add_child(_ride_card)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_ride_card.add_child(v)
	_ride_text = UIKit.label("", 19, UIKit.JASMINE)
	v.add_child(_ride_text)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	row.add_child(UIKit.label(tr("COMFORT_CUP"), 16, UIKit.YELLOW, true))
	_comfort_bar = UIKit.bar(1.0, UIKit.GREEN, 180, 14)
	row.add_child(_comfort_bar)

func _build_haggle() -> void:
	_haggle = UIKit.card()
	_haggle.mouse_filter = Control.MOUSE_FILTER_STOP
	_haggle.visible = false
	_root.add_child(_haggle)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_haggle.add_child(v)
	# Header: countdown ring · FARE NEGOTIATION · route
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	_haggle_ring = CountdownRing.new()
	_haggle_ring.custom_minimum_size = Vector2(64, 64)
	head.add_child(_haggle_ring)
	var ht: VBoxContainer = VBoxContainer.new()
	ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(ht)
	ht.add_child(UIKit.label(tr("FARE_NEGOTIATION"), 30, UIKit.YELLOW, true, 6))
	_haggle_title = UIKit.label("", 18, UIKit.MUTED)
	ht.add_child(_haggle_title)
	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	v.add_child(body)
	# Left: the rider.
	var left: PanelContainer = PanelContainer.new()
	left.add_theme_stylebox_override("panel", UIKit.card_box(UIKit.SURFACE, 18))
	left.custom_minimum_size = Vector2(260, 0)
	body.add_child(left)
	var lv: VBoxContainer = VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	_haggle_name = UIKit.label("", 22, UIKit.JASMINE, true)
	lv.add_child(_haggle_name)
	_haggle_portrait = UIKit.portrait("it_commuter", 150)
	lv.add_child(_haggle_portrait)
	var bubble: PanelContainer = PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", UIKit.card_box(UIKit.JASMINE, 14))
	lv.add_child(bubble)
	_haggle_line = UIKit.label("", 16, UIKit.PLUM)
	_haggle_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_haggle_line.custom_minimum_size = Vector2(220, 0)
	bubble.add_child(_haggle_line)
	# Right: three offer rows.
	var right: VBoxContainer = VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	for i: int in 3:
		var b: Button = UIKit.button("", OFFER_TONES[i], Callable(), 20)
		b.custom_minimum_size = Vector2(0, 100)
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var offer: int = i
		b.pressed.connect(func() -> void: _choose(offer))
		right.add_child(b)
		_haggle_buttons.append(b)
		var row: HBoxContainer = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 14.0
		row.offset_right = -14.0
		row.offset_top = 10.0
		row.offset_bottom = -12.0
		row.add_theme_constant_override("separation", 14)
		b.add_child(row)
		var tag: PanelContainer = PanelContainer.new()
		tag.add_theme_stylebox_override("panel", UIKit.card_box(UIKit.PLUM, 14))
		tag.custom_minimum_size = Vector2(110, 0)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tag)
		var tv: VBoxContainer = VBoxContainer.new()
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_child(tv)
		var cap: Label = UIKit.label(OFFER_CAPTION[i], 12, (UIKit.TONES[i] as Array)[0] as Color, true)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tv.add_child(cap)
		var price: Label = UIKit.label("₹0", 32, UIKit.JASMINE, true)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tv.add_child(price)
		_offer_price.append(price)
		var info: VBoxContainer = VBoxContainer.new()
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(info)
		var text_col: Color = (UIKit.TONES[int(OFFER_TONES[i])] as Array)[2] as Color
		var title: Label = UIKit.label("", 22, text_col, true)
		info.add_child(title)
		_offer_title.append(title)
		var chance_row: HBoxContainer = HBoxContainer.new()
		chance_row.add_theme_constant_override("separation", 8)
		chance_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(chance_row)
		var chance: Label = UIKit.label("", 14, text_col, true)
		chance_row.add_child(chance)
		_offer_chance.append(chance)
		var pb: ProgressBar = UIKit.bar(0.5, UIKit.JASMINE, 160, 12)
		chance_row.add_child(pb)
		_offer_bar.append(pb)

func _build_fare_card() -> void:
	_fare_card = UIKit.card()
	_fare_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_fare_card.visible = false
	_root.add_child(_fare_card)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_fare_card.add_child(v)
	var stars: HBoxContainer = HBoxContainer.new()
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	stars.add_theme_constant_override("separation", 6)
	v.add_child(stars)
	for i: int in 5:
		var s: TextureRect = UIKit.reward_icon("star", 54 if i != 2 else 70)
		stars.add_child(s)
		_fare_stars.append(s)
	var title: Label = UIKit.label(tr("SAVARI_COMPLETE"), 40, UIKit.YELLOW, true, 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_fare_route = UIKit.label("", 20, UIKit.JASMINE, true)
	_fare_route.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_fare_route)
	var mid: HBoxContainer = HBoxContainer.new()
	mid.add_theme_constant_override("separation", 14)
	v.add_child(mid)
	_fare_portrait = UIKit.portrait("tourist", 96)
	mid.add_child(_fare_portrait)
	var bubble: PanelContainer = PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", UIKit.card_box(UIKit.JASMINE, 14))
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(bubble)
	_fare_quote = UIKit.label("", 17, UIKit.PLUM)
	_fare_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.add_child(_fare_quote)
	# Receipt + total.
	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	v.add_child(bottom)
	var receipt: PanelContainer = PanelContainer.new()
	receipt.add_theme_stylebox_override("panel", UIKit.card_box(UIKit.JASMINE, 14))
	receipt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(receipt)
	_fare_rows = VBoxContainer.new()
	_fare_rows.add_theme_constant_override("separation", 4)
	receipt.add_child(_fare_rows)
	var total_box: PanelContainer = PanelContainer.new()
	total_box.add_theme_stylebox_override("panel", UIKit.card_box(UIKit.SURFACE, 14))
	total_box.custom_minimum_size = Vector2(230, 0)
	bottom.add_child(total_box)
	var tv: VBoxContainer = VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	total_box.add_child(tv)
	var tl: Label = UIKit.label(tr("TOTAL_EARNED"), 14, UIKit.MUTED, true)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(tl)
	var trow: HBoxContainer = HBoxContainer.new()
	trow.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(trow)
	trow.add_child(UIKit.reward_icon("coins", 44))
	_fare_total = UIKit.label("₹0", 44, UIKit.YELLOW, true, 6)
	trow.add_child(_fare_total)
	_fare_text = UIKit.label("", 14, UIKit.MUTED)
	_fare_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(_fare_text)
	var foot: HBoxContainer = HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	v.add_child(foot)
	var xpv: VBoxContainer = VBoxContainer.new()
	xpv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(xpv)
	xpv.add_child(UIKit.label(tr("DRIVER_XP"), 14, UIKit.MUTED, true))
	_fare_xp = UIKit.bar(0.0, UIKit.GREEN, 260, 14)
	xpv.add_child(_fare_xp)
	var next: Button = UIKit.button(tr("NEXT_SAVARI") + "  ▶▶", UIKit.Tone.GREEN, func() -> void: _fare_card.visible = false, 26)
	next.custom_minimum_size = Vector2(300, 76)
	foot.add_child(next)
	# Opt-in rewarded video: double this fare. Never forced, hidden when no ad is ready.
	_double_btn = UIKit.button(tr("DOUBLE_FARE"), UIKit.Tone.YELLOW, func() -> void:
		_double_btn.disabled = true
		AdMonetizationManager.show_rewarded("ad_double_fare", {"ride_id": str(_last_ride.get("ride_id", "")), "inr": int(_last_ride.get("total", 0))}), 22, "coins")
	_double_btn.custom_minimum_size = Vector2(240, 76)
	_double_btn.visible = false
	foot.add_child(_double_btn)
	foot.move_child(_double_btn, foot.get_child_count() - 2)

func _build_level_up() -> void:
	_level_up = Control.new()
	_level_up.name = "LevelUp"
	_level_up.mouse_filter = Control.MOUSE_FILTER_STOP
	_level_up.visible = false
	_root.add_child(_level_up)
	var dim: ColorRect = UIKit.backdrop()
	dim.name = "Dim"
	_level_up.add_child(dim)
	_rays = Rays.new()
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_up.add_child(_rays)
	var col: VBoxContainer = VBoxContainer.new()
	col.name = "Column"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	_level_up.add_child(col)
	var ribbon: PanelContainer = UIKit.ribbon(tr("LEVEL_UP_TITLE"), UIKit.Tone.ORANGE, 40)
	ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ribbon)
	_medal = UIKit.reward_icon("badge_silver", 200)
	_medal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_medal)
	_level_title = UIKit.label("", 34, UIKit.YELLOW, true, 8)
	_level_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_level_title)
	_level_rewards = HBoxContainer.new()
	_level_rewards.alignment = BoxContainer.ALIGNMENT_CENTER
	_level_rewards.add_theme_constant_override("separation", 24)
	col.add_child(_level_rewards)
	var collect: Button = UIKit.button(tr("COLLECT"), UIKit.Tone.YELLOW, _close_level_up, 32, "tick")
	collect.custom_minimum_size = Vector2(340, 84)
	collect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(collect)

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# Bottom centre, between the TouchHUD speedometer and LPG dial.
	minimap.position = Vector2(vp.x * 0.5 - MINIMAP_SIZE * 0.5, vp.y - 22.0 - MINIMAP_SIZE)
	_chips.reset_size()
	_chips.position = Vector2(vp.x - 24.0 - _chips.get_combined_minimum_size().x, 100.0)
	_guidance_distance.position = Vector2(vp.x * 0.5 - 110.0, 72.0)
	_guidance_distance.size = Vector2(220.0, 42.0)
	var rank: Control = _root.get_node("RankChip") as Control
	rank.reset_size()
	rank.position = Vector2(vp.x - 24.0 - rank.get_combined_minimum_size().x, 146.0)
	_xp_bar.position = Vector2(vp.x - 24.0 - 160.0, 196.0)
	_xp_bar.size = Vector2(160.0, 10.0)
	_ride_card.custom_minimum_size = Vector2(420.0, 0.0)
	_ride_card.position = Vector2(vp.x * 0.5 - 210.0, 12.0)
	# Sat-nav turn prompt: left, under the top button row (clear of the ride card).
	nav_banner.position = Vector2(20.0, 118.0)
	var hw: float = minf(960.0, vp.x - 40.0)
	_haggle.custom_minimum_size = Vector2(hw, 0.0)
	_haggle.position = Vector2((vp.x - hw) * 0.5, vp.y * 0.08)
	var fw: float = minf(860.0, vp.x - 40.0)
	_fare_card.custom_minimum_size = Vector2(fw, 0.0)
	_fare_card.position = Vector2((vp.x - fw) * 0.5, 12.0)
	_level_up.position = Vector2.ZERO
	_level_up.size = vp
	(_level_up.get_node("Dim") as Control).size = vp
	var side: float = minf(vp.x, vp.y) * 1.3
	_rays.size = Vector2(side, side)
	_rays.position = Vector2(vp.x * 0.5 - side * 0.5, vp.y * 0.4 - side * 0.5)
	_rays.pivot_offset = _rays.size * 0.5
	var col: Control = _level_up.get_node("Column") as Control
	col.position = Vector2(0, 0)
	col.size = vp
	_toast.position = Vector2(vp.x * 0.1, vp.y * 0.25)
	_toast.size = Vector2(vp.x * 0.8, 40.0)
	_hint.position = Vector2(vp.x * 0.2, vp.y * 0.36)
	_hint.size = Vector2(vp.x * 0.6, 60.0)

# --- Behaviour -----------------------------------------------------------------

## Tap the mini-map to open the full Chennai map (TouchHUD ignores that spot).
func _input(event: InputEvent) -> void:
	if full_map == null or full_map.visible or not _root.visible:
		return
	var tapped: bool = false
	var pos: Vector2 = Vector2.ZERO
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		pos = (event as InputEventScreenTouch).position
		tapped = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available():
		pos = (event as InputEventMouseButton).position
		tapped = true
	if tapped and minimap.get_global_rect().has_point(pos) and pos.distance_to(minimap.get_global_rect().get_center()) <= MINIMAP_SIZE * 0.5:
		SignalBus.full_map_requested.emit(true)
		get_viewport().set_input_as_handled()

func toast(text: String, seconds: float) -> void:
	_toast.text = text
	_toast_timer = seconds
	_toast.pivot_offset = _toast.size * 0.5
	_toast.scale = Vector2.ONE * 0.7
	create_tween().tween_property(_toast, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _refresh_level() -> void:
	var lvl: int = GameState.driver_level()
	_level.text = "%s %d · %s" % [tr("LV"), lvl, DriverProgress.title(lvl)]
	_level_icon.texture = UIKit.reward_cell(UIKit.badge_for_level(lvl))
	_xp_bar.value = GameState.progress.level_progress()
	if _chips != null:
		_layout()

## "Complete 3 rides (1/3)"
static func goal_text(g: Dictionary) -> String:
	return TranslationServer.translate(str(g["text"])) % int(g["target"])

func _refresh_wallet() -> void:
	_wallet.text = "₹" + UIKit.inr(GameState.wallet_inr)
	_rating.text = "%.1f" % GameState.star_rating

func _inr(v: int) -> String:
	return UIKit.inr(v)

func _on_haggle_started(info: Dictionary, seconds: float) -> void:
	_fare_card.visible = false
	_haggle_name.text = str(info["name"])
	_haggle_title.text = "→ %s  ·  %.1f km" % [info["destination"], float(info["distance_km"])]
	_haggle_line.text = "“%s”" % info["line"]
	UIKit.set_portrait(_haggle_portrait, str(info.get("archetype", "")))
	var quotes: Array = info["quotes"]
	var odds: Array = info.get("odds", [0.9, 0.6, 0.3])
	for i: int in 3:
		_offer_price[i].text = "₹%d" % int(quotes[i])
		_offer_title[i].text = "%s · %s" % [OFFER_SHORT[i].to_upper(), OFFER_TAMIL[i]]
		_offer_bar[i].value = float(odds[i])
		_offer_chance[i].text = "%d%% %s" % [roundi(float(odds[i]) * 100.0), tr("CHANCE")]
		_haggle_buttons[i].text = ""
		_haggle_buttons[i].disabled = false
		_haggle_buttons[i].tooltip_text = "%s\n₹%d\n%s" % [OFFER_SHORT[i], int(quotes[i]), OFFER_TAGS[i]]
	_haggle_time = seconds
	_haggle_total = seconds
	_haggle_ring.seconds = seconds
	_haggle.visible = true
	UIKit.pop_in(_haggle, 0.0, 0.25)

func _choose(offer: int) -> void:
	for b: Button in _haggle_buttons:
		b.disabled = true
	SignalBus.haggle_choice_made.emit(offer)

func _on_haggle_resolved(result: Dictionary) -> void:
	_haggle.visible = false
	if bool(result["accepted"]):
		toast("“%s”  Deal: ₹%d" % [result["line"], int(result["fare"])], 3.0)
		_ride_card.visible = true
	else:
		toast("“%s”" % result["line"], 3.0)

func _on_ride_updated(info: Dictionary) -> void:
	_ride_card.visible = true
	var t: float = float(info["time_left_s"])
	var clock: String = "%d:%02d" % [int(absf(t)) / 60, int(absf(t)) % 60]
	_ride_text.text = "%s → %s\n%.1f km   %s%s   ₹%d" % [info["archetype"], info["destination"],
		float(info["remaining_m"]) / 1000.0 * FareCalculator.REAL_KM_PER_GAME_KM, "-" if t < 0.0 else "", clock, int(info["fare"])]
	_ride_text.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if t < 0.0 else UIKit.JASMINE)
	_comfort_bar.value = float(info["comfort"])

## 4F: stars pop in one by one, receipt rows, rolling total, XP bar, NEXT SAVARI.
func _on_ride_completed(b: Dictionary) -> void:
	_ride_card.visible = false
	var stars: int = roundi(float(b["stars"]))
	for i: int in 5:
		_fare_stars[i].texture = UIKit.reward_cell("star" if i < stars else "star_empty")
	_fare_route.text = "→ %s" % b["destination"]
	_fare_quote.text = "“%s”  — %s" % [b["line"], b.get("archetype_name", "")]
	UIKit.set_portrait(_fare_portrait, str(b.get("archetype", "")))
	for c: Node in _fare_rows.get_children():
		c.queue_free()
	_fare_rows.add_child(UIKit.label(tr("FARE_BILL"), 15, Color("8a5a00"), true))
	var lines: Array = [[tr("METER_FARE"), int(b["fare"]), false], [tr("COMFORT_TIP"), int(b["comfort_tip"]), true],
		[tr("GETHU_BONUS"), int(b["gethu_bonus"]), true]]
	for ln: Array in lines:
		var row: HBoxContainer = HBoxContainer.new()
		var l: Label = UIKit.label(str(ln[0]), 17, UIKit.PLUM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UIKit.label(("+₹%d" if bool(ln[2]) else "₹%d") % int(ln[1]), 17, Color("1b7c30") if bool(ln[2]) else UIKit.PLUM, true))
		_fare_rows.add_child(row)
	var total: int = int(b["total"])
	_fare_text.text = tr("ON_TIME") if bool(b["on_time"]) else tr("LATE")
	_fare_xp.value = GameState.progress.level_progress()
	_fare_card.visible = true
	_fare_timer = FARE_SECONDS
	_last_ride = b
	var can_double: bool = AdMonetizationManager.can_offer_rewarded("ad_double_fare") and total > 0
	_double_btn.visible = can_double
	_double_btn.disabled = false
	_double_btn.text = "%s  +₹%d" % [tr("DOUBLE_FARE"), total]
	if can_double:
		_fare_timer = FARE_SECONDS + 2.0 # a little longer to decide
	UIKit.pop_in(_fare_card, 0.0, 0.25)
	for i: int in 5:
		UIKit.pop_in(_fare_stars[i], 0.15 + i * 0.12, 0.3)
	UIKit.count_up(_fare_total, 0, total, "₹%d", 1.0)

## 4H: rays turn, the rank badge pops, rewards listed, COLLECT (or auto-close).
func _on_level_up(lvl: int, title: String, reward: int, unlock_key: String) -> void:
	_medal.texture = UIKit.reward_cell(UIKit.badge_for_level(lvl))
	_level_title.text = "%s %d · %s" % [tr("LV"), lvl, title]
	for c: Node in _level_rewards.get_children():
		c.queue_free()
	_level_rewards.add_child(UIKit.chip("coin_pile", "+₹%d" % reward, 24))
	if unlock_key != "":
		_level_rewards.add_child(UIKit.chip("gift", tr(unlock_key), 20))
	_fare_card.visible = false
	_level_up.visible = true
	_level_timer = LEVEL_UP_SECONDS
	_layout()
	UIKit.pop_in(_medal, 0.1, 0.45)
	if _rays_spin == null:
		_rays_spin = UIKit.spin(_rays, 22.0)
	_rays_spin.play()

func _close_level_up() -> void:
	_level_up.visible = false
	if _rays_spin != null:
		_rays_spin.pause() # nothing animates while the overlay is hidden
