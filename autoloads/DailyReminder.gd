extends Node
## Daily reminder notifications, Duolingo-style but local only (no server, no Firebase).
##
## Whenever the game goes to the background it schedules one reminder at REMIND_HOUR on each of
## the next DAYS days; coming back cancels them. So a player who drives every day never gets one,
## and a player who stops gets one a day for a week, the last one saying we'll stop, then silence.
## Day 1's message is about the daily login streak (RewardsEngine), the rest rotate Chennai lines.
##
## Android only, through the NammaReminder plugin (android_plugins/namma_reminder, packed by
## addons/namma_reminder). In the editor, tests and desktop builds every call is a no-op.
## Android 13+ needs the notification permission: asked once after the first ride (or after the
## first daily-bonus claim), never at launch; Settings has an on/off toggle.

## Emitted when the on/off state may have changed (permission answer, back from system settings).
signal changed

const PLUGIN: String = "NammaReminder"
## 7 PM in the phone's own time zone, wherever the player is (the plugin computes it with
## java.util.Calendar, so daylight-saving changes still land on 7 PM).
const REMIND_HOUR: int = 19 # after work / college, before dinner
const DAYS: int = 7
const TEST_ID: int = 99
const TEST_DELAY_S: int = 60
## Ask after the first ride's "All done" coach card (TutorialOverlay.DONE_SHOW_S = 2.5 s) has shown.
const ASK_DELAY_S: float = 3.5

var _plugin: Object = null
var _modal_open: bool = false
var _dialog: CanvasLayer = null
var _was_paused: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.has_singleton(PLUGIN):
		_plugin = Engine.get_singleton(PLUGIN)
		_plugin.connect("permission_result", _on_permission_result)
	SignalBus.ui_modal_changed.connect(func(open: bool) -> void: _modal_open = open)
	SignalBus.tutorial_finished.connect(_on_tutorial_finished)
	cancel_all() # the player is here: nothing pending should fire now

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		reschedule()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		cancel_all()
		changed.emit() # may be back from Android's notification settings

# --- State ----------------------------------------------------------------------------------

## The plugin is in this build (Android export with the AAR).
func is_supported() -> bool:
	return _plugin != null

## Android lets us post (permission granted on 13+, app notifications not switched off).
func notifications_allowed() -> bool:
	return _plugin != null and bool(_plugin.call("notificationsEnabled"))

## What the Settings toggle shows: the player wants reminders AND Android allows them.
func is_on() -> bool:
	return bool(GameState.settings.get("daily_reminder", true)) and notifications_allowed()

func set_enabled(on: bool) -> void:
	GameState.settings["reminder_asked"] = true
	GameState.set_setting("daily_reminder", on)
	if not on:
		cancel_all()
	elif not notifications_allowed():
		request_permission()

func request_permission() -> void:
	if _plugin != null:
		_plugin.call("requestPermission")

func _on_permission_result(granted: bool) -> void:
	if granted:
		GameState.set_setting("daily_reminder", true)
	changed.emit()

# --- Scheduling -----------------------------------------------------------------------------

func cancel_all() -> void:
	if _plugin != null:
		_plugin.call("cancelAll")

## Replaces the week of reminders (ids 1..DAYS) from now. Called when the app goes to the background.
func reschedule() -> void:
	if _plugin == null:
		return
	if not is_on():
		cancel_all()
		return
	for r: Dictionary in build_reminders(GameState.daily_reward_status()):
		_plugin.call("scheduleAt", int(r["id"]), int(r["days_ahead"]), int(r["hour"]), str(r["title"]), str(r["body"]))

## Debug builds: one reminder in a minute (press Home and wait).
func send_test() -> void:
	if _plugin == null:
		return
	if not notifications_allowed():
		request_permission()
	_plugin.call("schedule", TEST_ID, TEST_DELAY_S, tr("REM_T_PASSENGERS"), tr("REM_B_PASSENGERS"))

## Pure: the reminders to schedule, given today's daily-bonus status (GameState.daily_reward_status()).
## Each: {id, days_ahead, hour, title, body}. Reminder k fires at REMIND_HOUR local time k calendar
## days after today: never today, because the player is playing today.
func build_reminders(status: Dictionary) -> Array[Dictionary]:
	var claimed_today: bool = not bool(status.get("available", true))
	var streak: int = int(status.get("streak", 0))
	var out: Array[Dictionary] = []
	for day: int in range(1, DAYS + 1):
		var msg: PackedStringArray = _message(day, claimed_today, streak)
		out.append({"id": day, "days_ahead": day, "hour": REMIND_HOUR, "title": msg[0], "body": msg[1]})
	return out

func _message(day: int, claimed_today: bool, streak: int) -> PackedStringArray:
	if day == 1 and claimed_today and streak > 0:
		# Tomorrow's calendar tile keeps the streak alive (RewardsEngine.daily_status).
		var idx: int = streak % RewardsEngine.DAILY_INR.size()
		if idx == RewardsEngine.DAILY_INR.size() - 1:
			return PackedStringArray([tr("REM_T_JACKPOT"), tr("REM_B_JACKPOT") % RewardsEngine.DAILY_INR[idx]])
		return PackedStringArray([tr("REM_T_STREAK") % streak, tr("REM_B_STREAK") % [idx + 1, RewardsEngine.DAILY_INR[idx]]])
	# Streak unclaimed today, or already broken: a fresh streak starts at the day-1 bonus.
	var fresh: int = RewardsEngine.DAILY_INR[0]
	match day:
		1, 3:
			return PackedStringArray([tr("REM_T_BONUS"), tr("REM_B_BONUS") % fresh])
		2, 6:
			return PackedStringArray([tr("REM_T_PASSENGERS"), tr("REM_B_PASSENGERS")])
		4:
			return PackedStringArray([tr("REM_T_AUTO"), tr("REM_B_AUTO")])
		5:
			return PackedStringArray([tr("REM_T_MARINA"), tr("REM_B_MARINA")])
	return PackedStringArray([tr("REM_T_LAST"), tr("REM_B_LAST")])

# --- Asking once ----------------------------------------------------------------------------

## Shows the "Daily reminder?" card once, if Android still needs the player's permission.
## Android 12 and older allow notifications by default, so there is nothing to ask.
func maybe_ask() -> void:
	if _plugin == null or _dialog != null or bool(GameState.settings.get("reminder_asked", false)):
		return
	if notifications_allowed():
		GameState.settings["reminder_asked"] = true
		return
	_show_dialog()

func _on_tutorial_finished(_skipped: bool) -> void:
	if _plugin == null:
		return
	await get_tree().create_timer(ASK_DELAY_S).timeout
	while _modal_open:
		await SignalBus.ui_modal_changed
	maybe_ask()

func _show_dialog() -> void:
	_dialog = CanvasLayer.new()
	_dialog.name = "ReminderAsk"
	_dialog.layer = 40
	_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UIKit.theme()
	_dialog.add_child(root)
	var dim: ColorRect = UIKit.backdrop()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var card: PanelContainer = UIKit.card()
	center.add_child(card)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	card.add_child(col)
	var title: Label = UIKit.label(tr("REMINDER_ASK_TITLE"), 32, UIKit.YELLOW, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var body: Label = UIKit.label(tr("REMINDER_ASK_BODY"), 22)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(560, 0)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(body)
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var no: Button = UIKit.button(tr("REMINDER_NO"), UIKit.Tone.PURPLE, _answer.bind(false), 22)
	no.custom_minimum_size = Vector2(200, 64)
	row.add_child(no)
	var yes: Button = UIKit.button(tr("REMINDER_YES"), UIKit.Tone.GREEN, _answer.bind(true), 24)
	yes.custom_minimum_size = Vector2(260, 64)
	row.add_child(yes)
	col.add_child(row)
	add_child(_dialog)
	_was_paused = get_tree().paused
	get_tree().paused = true
	SignalBus.ui_modal_changed.emit(true)
	UIKit.pop_in(card, 0.0, 0.25)

func _answer(yes: bool) -> void:
	GameState.settings["reminder_asked"] = true
	GameState.set_setting("daily_reminder", yes)
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null
	get_tree().paused = _was_paused
	SignalBus.ui_modal_changed.emit(false)
	if yes:
		request_permission()
	changed.emit()
