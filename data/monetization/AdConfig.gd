class_name AdConfig
extends Resource
## Every ad-frequency number lives here (and can later be overridden by Firebase Remote
## Config), so balancing never touches code. Defaults follow the research docs:
## UndrAds 2026 — < 3 interstitials per session retains 27 % more players; CAS.AI — first-session
## grace and cooldowns; GDD — never interrupt driving.

@export_group("Interstitials (forced)")
## No forced ads in a brand-new install's first minutes (covers the first ~3 rides).
@export var first_session_grace_s: float = 480.0
## Minimum gap between two forced interstitials.
@export var interstitial_cooldown_s: float = 180.0
## Hard cap per rolling 10 minutes and per app session.
@export var max_per_10_min: int = 2
@export var max_per_session: int = 3
## Forced ads only at these natural breaks — never while the auto is moving.
@export var allowed_placements: PackedStringArray = ["after_fare_summary", "shift_end", "back_to_menu"]
## Only every Nth ride ends in an interstitial at all (on top of the cooldowns).
@export var rides_between_interstitials: int = 3
## Auto must be (nearly) stopped to show one.
@export var max_speed_kmh: float = 3.0

@export_group("Rewarded (opt-in)")
## Watching an opt-in rewarded video resets the interstitial cooldown (reward ad-free driving).
@export var rewarded_resets_cooldown: bool = true
@export var rewarded_enabled_placements: PackedStringArray = ["ad_double_fare", "ad_fuel_rescue", "ad_tow", "ad_test_drive"]

@export_group("Banners")
## Banners only on menu/garage/pause screens, never over the driving view.
@export var banner_screens: PackedStringArray = ["main_menu", "garage", "pause"]

@export_group("Provider")
## "mock" = on-screen placeholder (editor, tests, closed testing without ad units).
## "admob" = godot-admob plugin (poing-studios), "applovin" = AppLovin MAX plugin.
@export_enum("mock", "admob", "applovin") var provider: String = "mock"
## Use Google's official TEST ad unit ids until the Play Console app is approved.
@export var use_test_ads: bool = true
@export var admob_app_id: String = "ca-app-pub-3940256099942544~3347511713" # Google test app id
@export var rewarded_unit_id: String = "ca-app-pub-3940256099942544/5224354917" # Google test rewarded
@export var interstitial_unit_id: String = "ca-app-pub-3940256099942544/1033173712" # Google test interstitial
@export var banner_unit_id: String = "ca-app-pub-3940256099942544/6300978111" # Google test banner
## Placeholder ad length (mock provider) — short so playtests aren't annoying.
@export var mock_rewarded_s: float = 3.0
@export var mock_interstitial_s: float = 2.0
