# Ads (AdMob)

Real ads run through the **godot-sdk-integrations AdMob plugin v5.3** (MIT, built for Godot
4.5.1), committed in `addons/AdmobPlugin/`. `scripts/monetization/AdMobProvider.gd` drives it;
`autoloads/AdMonetizationManager.gd` keeps every rule it already had (8-minute first-session grace,
3-minute cooldown, at most 2 interstitials per 10 minutes and 3 per session, interstitials only on
fare / shift-end / menu screens and never while moving, rewarded ads only when the player taps).

## What happens on the phone

1. **Consent first.** Google's consent form (UMP) appears only where the law requires it (EEA,
   UK). In India the game goes straight on.
2. **Then the ads SDK starts**, and the first rewarded and interstitial ads load in the background.
   If there is no network, nothing waits: buttons that need an ad simply don't offer one.
3. **While an ad is on screen the game's sound is muted**, and comes back when it closes.
4. **After every ad the next one loads by itself.**

Off the phone (editor, desktop, headless tests) the plugin's Android singleton is absent, so the
on-screen placeholder ads (`MockAdProvider`) are used automatically.

## Test ads now, real ads after approval

Today the game uses **Google's official test app id and test ad units**. They are safe to tap and
earn nothing. Keep them until AdMob has approved the account, and **never tap your own real ads**.

To switch to real ads (after the AdMob account is approved):

1. In AdMob: **Apps → Add app → Android → "No, it isn't listed yet"** (link it to Play later) →
   name it *Namma Auto*. Copy the **App ID** (`ca-app-pub-…~…`).
2. **Ad units → Add ad unit**: one **Rewarded** (name `rewarded_main`), one **Interstitial**
   (name `interstitial_main`) and one **Banner** (name `banner_main`; refresh rate 60 s or
   "Google optimized"). Copy the ids (`ca-app-pub-…/…`).
3. Send the ids to Claude, or edit by hand:
   - `data/monetization/ad_config.tres`: `use_test_ads = false`, `admob_app_id`,
     `rewarded_unit_id`, `interstitial_unit_id`, `banner_unit_id`. Without a banner id, release
     builds simply show no banners (`AdMobProvider.banner_enabled`).
   - `addons/AdmobPlugin/android_export.cfg`: `is_real=true` and `[Release] app_id` = the same
     App ID.
4. `tests/run_ads_tests` fails if the two files disagree or an id is missing; CI's "Verify APK
   manifest" step fails if the APK lacks the AdMob app id (the SDK would crash at launch).
5. Before publishing: add **app-ads.txt** on your developer website (AdMob shows the exact line),
   and in Play Console declare **advertising ID** use in Data safety and "Contains ads" = Yes.

## Testing without risking the account

- **Debug APKs always show Google's demo ads**, even after real ads are switched on
  (`AdMobProvider.use_demo_ads`). The APKs from the Android Build workflow are debug builds, so
  tapping ads while testing them is always safe. Only the release AAB on Play shows real ads.
- To test the **Play Store build** itself, add each phone as a **test device** in AdMob
  (Settings → Test devices → Add test device → Android → advertising ID from the phone's
  Settings → Google → Ads, or Settings → Privacy → Ads). Real ad units then serve ads labelled
  **"Test Ad"** on that phone.
- **Only ever tap an ad that shows the "Test Ad" label.**

Ad content is capped at **PG** (`AdConfig.max_ad_content_rating`).

## Where ads appear

**Banners** (standard 320 × 50, bottom centre, inside the safe area) only on calm screens, listed in
`AdConfig.banner_screens`: garage, pause menu, full city map (it pauses the game) and the shift
summary. Not on the home screen (owner's call; easy to add back in that list). Never while driving, never on the loading screen or a traffic-fine notice, never in
the tutorial, never for No Ads buyers. AdMob's rules forbid banners on a game play screen and next
to buttons, so each screen moves its bottom row up by `AdMonetizationManager.banner_inset_px()`:
the banner plus a 24 px gap. One banner is loaded and then shown/hidden as screens change.

AdMob ads cannot be drawn on in-world billboards (they are native overlays). Real ads on 3D
hoardings need an intrinsic in-game ad network (Gadsme has a Godot SDK) — a later idea, once the
game has players.

**Rewarded** (always opt-in, marked ▶, paid only when AdMob confirms the reward; daily caps in
`RewardsEngine.DAILY_CAPS`):

| Placement | Where | Reward | Cap/day |
|---|---|---|---|
| `ad_double_fare` | fare card after a ride | the fare again | 12 |
| `ad_fuel_rescue` / `ad_tow` | out of fuel | half a tank / free tow | 4 / 4 |
| `ad_wreck_repair` | wrecked auto | free repair | 3 |
| `ad_test_drive` | garage Autos tab, main-menu auto card | drive an unowned auto (locked ones too) until the shift ends | 3 |
| `ad_paint_trial` | garage Paint tab | wear an unowned paint (and its Meter Mela bonus) until the shift ends | 3 |
| `ad_daily_double` | daily bonus calendar, after claiming | today's bonus again | 1 |
| `ad_quest_double` | 12 s offer after a side quest is completed | the quest's ₹ again (once per quest) | 5 |

A test drive parks your own auto exactly as it was (tank, condition) and hands the lent one back at
shift end, when you pick one of your own autos, or on a later day; buying it keeps it. Garage
upgrades can't be bought for a lent auto.

**Interstitials** (forced, rare): after a fare summary and at shift end. `back_to_menu` is allowed by
the rules but not triggered anywhere yet (left for later).
