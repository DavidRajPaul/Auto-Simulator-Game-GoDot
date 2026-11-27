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
@export var rewarded_enabled_placements: PackedStringArray = ["ad_double_fare", "ad_fuel_rescue", "ad_tow", "ad_test_drive", "ad_wreck_repair",
	"ad_daily_double", "ad_paint_trial", "ad_quest_double"]

@export_group("Banners")
## Banners only on calm screens, never over the driving view (AdMob: no banners on a game play
## screen). The full map pauses the game, so it counts as a calm screen.
@export var banner_screens: PackedStringArray = ["main_menu", "garage", "pause", "full_map", "shift_summary"]

@export_group("Provider")
## "mock" = on-screen placeholder; "admob" = the godot-sdk-integrations AdMob plugin v5.3
## (addons/AdmobPlugin, MIT). "admob" falls back to "mock" by itself wherever the plugin's
## Android singleton is absent (editor, desktop, headless tests).
@export_enum("mock", "admob", "applovin") var provider: String = "admob"
## true = Google's official TEST app id and ad units (safe to tap; no earnings, no policy risk).
## Set false only when the real ids below are filled in, together with
## addons/AdmobPlugin/android_export.cfg is_real=true (run_ads_tests checks they agree).
@export var use_test_ads: bool = true
## Real ids from the AdMob console (Apps -> Namma Auto -> Ad units). Empty until approval.
@export var admob_app_id: String = ""
@export var rewarded_unit_id: String = ""
@export var interstitial_unit_id: String = ""
@export var banner_unit_id: String = ""
## Ad content ceiling: "G", "PG", "T" or "MA". PG fits a city driving game for all ages.
@export var max_ad_content_rating: String = "PG"
## Placeholder ad length (mock provider) — short so playtests aren't annoying.
@export var mock_rewarded_s: float = 3.0
@export var mock_interstitial_s: float = 2.0
