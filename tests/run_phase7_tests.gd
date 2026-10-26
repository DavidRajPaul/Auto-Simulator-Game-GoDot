extends Node
## Phase 7 (game UI screens, Stitch art 4A-5B) verification: UI kit, home screen, haggle card,
## ride-complete screen, level-up, pause / garage restyle, HUD hidden under menus.
## Run:  godot --headless --path . --fixed-fps 60 res://tests/run_phase7_tests.tscn

const MENU_SCENE: String = "res://scenes/main_menu.tscn"
const PASSENGER_HUD: String = "res://scenes/ui/passenger_hud.tscn"
const TOUCH_HUD: String = "res://scenes/ui/touch_hud.tscn"

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Phase 7 tests ===")
	GameState.reset_profile()
	_test_kit()
	await _test_menu()
	var phud: PassengerHUD = (load(PASSENGER_HUD) as PackedScene).instantiate() as PassengerHUD
	add_child(phud)
	var thud: TouchHUD = (load(TOUCH_HUD) as PackedScene).instantiate() as TouchHUD
	add_child(thud)
	var ui: GarageUI = GarageUI.new()
	add_child(ui)
	await _frames(3)
	await _test_haggle(phud)
	await _test_fare(phud)
	await _test_level_up(phud)
	_test_modals(ui, phud, thud)
	ui.queue_free()
	phud.queue_free()
	thud.queue_free()
	await _frames(2)
	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _test_kit() -> void:
	_check("Shared theme is built once and cached", UIKit.theme() == UIKit.theme())
	_check("Arcade buttons reuse cached styleboxes", UIKit.button_box(UIKit.Tone.YELLOW) == UIKit.button_box(UIKit.Tone.YELLOW))
	var pressed: StyleBoxFlat = UIKit.button_box(UIKit.Tone.GREEN, "pressed")
	var normal: StyleBoxFlat = UIKit.button_box(UIKit.Tone.GREEN, "normal")
	_check("Pressed buttons drop onto their shelf (content moves down 4 px)", pressed.content_margin_top - normal.content_margin_top == UIKit.PRESS_PX and pressed.shadow_offset.y < normal.shadow_offset.y)
	_check("Rewards atlas cells resolve (coin, gift, padlock)", UIKit.reward_cell("coin").atlas != null and UIKit.reward_cell("gift").region.position.x == 256.0 and UIKit.reward_cell("lock").region.position == Vector2(512, 512))
	_check("Rank badge by level: bronze 1, silver 5, gold 9, diamond 20", UIKit.badge_for_level(1) == "badge_bronze" and UIKit.badge_for_level(5) == "badge_silver"
		and UIKit.badge_for_level(9) == "badge_gold" and UIKit.badge_for_level(20) == "badge_diamond")
	_check("Indian rupee grouping", UIKit.inr(123456) == "1,23,456" and UIKit.inr(14850) == "14,850" and UIKit.inr(500) == "500")

func _test_menu() -> void:
	var menu: MainMenu = (load(MENU_SCENE) as PackedScene).instantiate() as MainMenu
	add_child(menu)
	await _frames(4)
	_check("Home screen: driver card, rank chips, vehicle card", menu._buttons.has("profile") and menu._top_chips.get_child_count() >= 4 and menu._stats_card != null)
	_check("Home screen PLAY uses the yellow arcade style", (menu._buttons["new"] as Button).get_theme_stylebox("normal") == UIKit.button_box(UIKit.Tone.YELLOW))
	menu.queue_free()
	await _frames(2)

func _test_haggle(h: PassengerHUD) -> void:
	SignalBus.haggle_started.emit({"archetype": "it_commuter", "name": "IT Commuter", "line": "Anna, podhuma?", "destination": "TIDEL Park",
		"distance_km": 6.2, "quotes": [80, 100, 120], "odds": [0.95, 0.65, 0.3], "offers": FareCalculator.OFFER_NAMES}, 5.0)
	await _frames(2)
	_check("Haggle card shows three priced offers with their odds", h._haggle.visible and h._offer_price[1].text == "₹100" and is_equal_approx(h._offer_bar[2].value, 0.3) and h._offer_chance[0].text.begins_with("95%"))
	_check("Countdown ring runs down", h._haggle_ring.value < 1.0 and h._haggle_ring.value > 0.9)
	_check("Hints and toasts stay hidden while a card is up", not h._hint.visible and not h._toast.visible)
	var got: Array[int] = []
	var on_choice: Callable = func(o: int) -> void: got.append(o)
	SignalBus.haggle_choice_made.connect(on_choice)
	h._haggle_buttons[1].pressed.emit()
	SignalBus.haggle_choice_made.disconnect(on_choice)
	_check("Tapping an offer sends it and locks the buttons", got == [1] and h._haggle_buttons[0].disabled)
	SignalBus.haggle_resolved.emit({"accepted": true, "line": "Sari", "fare": 100})

func _test_fare(h: PassengerHUD) -> void:
	SignalBus.ride_completed.emit({"stars": 4.0, "destination": "Marina Beach", "line": "Mass!", "archetype_name": "Tourist", "archetype": "tourist",
		"fare": 140, "comfort_tip": 35, "gethu_bonus": 65, "total": 240, "on_time": true})
	await _frames(90)
	_check("Ride-complete screen: 4 gold stars and 1 empty", h._fare_card.visible and h._fare_stars[3].texture == UIKit.reward_cell("star") and h._fare_stars[4].texture == UIKit.reward_cell("star_empty"))
	_check("Total rolls up to the fare", h._fare_total.text == "₹240", h._fare_total.text)
	_check("Receipt lists meter fare, comfort tip and Gethu bonus", h._fare_rows.get_child_count() == 4)

func _test_level_up(h: PassengerHUD) -> void:
	SignalBus.driver_level_up.emit(5, "Mylapore Regular", 250, "UNLOCK_EV")
	await _frames(2)
	_check("Level-up overlay: silver badge for Lv 5, cash + unlock rewards", h._level_up.visible and h._medal.texture == UIKit.reward_cell("badge_silver") and h._level_rewards.get_child_count() == 2)
	_check("Level-up replaces the fare card", not h._fare_card.visible)
	h._close_level_up()
	_check("COLLECT closes it and pauses the ray spin", not h._level_up.visible and not h._rays_spin.is_running())

func _test_modals(ui: GarageUI, h: PassengerHUD, t: TouchHUD) -> void:
	ui.open_pause()
	_check("Menus hide the driving HUD underneath (fewer draws)", not h._root.visible and not t._root.visible)
	_check("Pause has the big RESUME button and status chips", ui._modal_body.get_child_count() >= 6)
	ui.close_modal()
	_check("…and bring it back on close", h._root.visible and t._root.visible)
	ui.open_garage()
	_check("Garage items are tiles with arcade buttons", ui._modal_body.get_child(ui._modal_body.get_child_count() - 1) is PanelContainer)
	ui.close_modal()

func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  ", test_name, ("  (" + detail + ")") if detail != "" else "")
	else:
		_failed += 1
		printerr("  FAIL  ", test_name, ("  (" + detail + ")") if detail != "" else "")
