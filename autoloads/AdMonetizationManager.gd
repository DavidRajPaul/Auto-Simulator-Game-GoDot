extends Node
## Non-intrusive ad policy (AGENTS.md autoload). The rest of the game asks this service
## "may I show X here?" and never talks to an ad SDK directly.
##
## Rules (all numbers in data/monetization/ad_config.tres):
##   • Rewarded ads are always opt-in and pay only when the network confirms (RewardsEngine).
##   • Forced interstitials only at natural breaks (fare summary, shift end, back to menu), never
##     while moving, never in the first 8 minutes of a new install, ≥ 3 min apart, ≤ 2 per
##     10 minutes, ≤ 3 per session, only every 3rd ride — and never for "No Ads" buyers.
##   • A watched rewarded ad resets the interstitial cooldown.
##   • Nothing ever waits on an ad: if none is cached, the game just carries on.

const CONFIG_PATH: String = "res://data/monetization/ad_config.tres"

var config: AdConfig
var provider: AdProvider
var session_s: float = 0.0
var install_play_s: float = 0.0 # total play time on this install (saved via GameState settings)
var last_interstitial_s: float = -100000.0
var interstitials_this_session: int = 0
var _recent: Array[float] = [] # session times of recent interstitials
var _rides_since_interstitial: int = 0
var _speed_kmh: float = 0.0
var _pending: Dictionary = {} # placement -> context for an in-flight rewarded ad

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	config = load(CONFIG_PATH) as AdConfig if ResourceLoader.exists(CONFIG_PATH) else AdConfig.new()
	provider = _make_provider(config.provider)
	add_child(provider)
	provider.setup(config)
	provider.rewarded_earned.connect(_on_rewarded_earned)
	provider.rewarded_failed.connect(func(p: String, why: String) -> void:
		_pending.erase(p)
		SignalBus.rewarded_ad_failed.emit(p, why))
	provider.interstitial_closed.connect(func(p: String) -> void: SignalBus.interstitial_closed.emit(p))
	provider.load_rewarded()
	provider.load_interstitial()
	SignalBus.speed_updated.connect(func(k: float) -> void: _speed_kmh = k)
	SignalBus.ride_completed.connect(func(_b: Dictionary) -> void: _rides_since_interstitial += 1)
	install_play_s = float(GameState.settings.get("install_play_s", 0.0))

func _make_provider(kind: String) -> AdProvider:
	if kind == "admob" and AdMobProvider.plugin_available():
		return AdMobProvider.new()
	return MockAdProvider.new()

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	session_s += delta
	install_play_s += delta
	if int(session_s) % 30 == 0 and int(session_s - delta) % 30 != 0:
		GameState.settings["install_play_s"] = install_play_s

# --- Rewarded (opt-in) ----------------------------------------------------------

func can_offer_rewarded(placement: String) -> bool:
	return config.rewarded_enabled_placements.has(placement) and provider.is_rewarded_ready() \
		and GameState.rewards.remaining_today(placement, RewardsEngine.today_string()) > 0

## Show a rewarded ad. `context` is handed back with the confirmed reward (e.g. ride_id, inr).
func show_rewarded(placement: String, context: Dictionary = {}) -> bool:
	if not can_offer_rewarded(placement):
		SignalBus.rewarded_ad_failed.emit(placement, "unavailable")
		return false
	_pending[placement] = context
	if not provider.show_rewarded(placement):
		_pending.erase(placement)
		SignalBus.rewarded_ad_failed.emit(placement, "not_loaded")
		provider.load_rewarded()
		return false
	return true

func _on_rewarded_earned(placement: String) -> void:
	var ctx: Dictionary = _pending.get(placement, {})
	_pending.erase(placement)
	if config.rewarded_resets_cooldown:
		last_interstitial_s = session_s
	SignalBus.rewarded_ad_completed.emit(placement, ctx)
	provider.load_rewarded()

# --- Interstitials (forced, rare) ------------------------------------------------

## Why not (empty string = allowed). Exposed for the debug overlay and tests.
func interstitial_block_reason(placement: String) -> String:
	if GameState.no_ads:
		return "no_ads_purchased"
	if not config.allowed_placements.has(placement):
		return "placement_not_allowed"
	if GameState.tutorial_active:
		return "tutorial"
	if install_play_s < config.first_session_grace_s:
		return "first_session_grace"
	if _speed_kmh > config.max_speed_kmh:
		return "moving"
	if session_s - last_interstitial_s < config.interstitial_cooldown_s:
		return "cooldown"
	if interstitials_this_session >= config.max_per_session:
		return "session_cap"
	var in_window: int = 0
	for t: float in _recent:
		if session_s - t < 600.0:
			in_window += 1
	if in_window >= config.max_per_10_min:
		return "ten_minute_cap"
	if placement == "after_fare_summary" and _rides_since_interstitial < config.rides_between_interstitials:
		return "ride_spacing"
	if not provider.is_interstitial_ready():
		return "not_loaded"
	return ""

## Call at a natural break. Returns true if an ad is being shown.
func maybe_show_interstitial(placement: String) -> bool:
	if interstitial_block_reason(placement) != "":
		return false
	if not provider.show_interstitial(placement):
		provider.load_interstitial()
		return false
	last_interstitial_s = session_s
	interstitials_this_session += 1
	_recent.append(session_s)
	if _recent.size() > 8:
		_recent.pop_front()
	_rides_since_interstitial = 0
	provider.load_interstitial()
	SignalBus.ad_state_changed.emit({"interstitials": interstitials_this_session})
	return true

# --- Banners ------------------------------------------------------------------

## Screens call this when they open/close. Banners never show over driving.
func set_screen(screen: String) -> void:
	provider.show_banner(not GameState.no_ads and config.banner_screens.has(screen))

## Test helper: pretend this many seconds of play happened.
func debug_advance(seconds: float) -> void:
	session_s += seconds
	install_play_s += seconds
