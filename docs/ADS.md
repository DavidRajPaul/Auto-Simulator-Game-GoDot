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
2. **Ad units → Add ad unit**: one **Rewarded** (name `rewarded_main`) and one **Interstitial**
   (name `interstitial_main`). Copy both ids (`ca-app-pub-…/…`).
3. Send the three ids to Claude, or edit by hand:
   - `data/monetization/ad_config.tres`: `use_test_ads = false`, `admob_app_id`,
     `rewarded_unit_id`, `interstitial_unit_id`.
   - `addons/AdmobPlugin/android_export.cfg`: `is_real=true` and `[Release] app_id` = the same
     App ID.
4. `tests/run_ads_tests` fails if the two files disagree or an id is missing; CI's "Verify APK
   manifest" step fails if the APK lacks the AdMob app id (the SDK would crash at launch).
5. Before publishing: add **app-ads.txt** on your developer website (AdMob shows the exact line),
   and in Play Console declare **advertising ID** use in Data safety and "Contains ads" = Yes.

Ad content is capped at **PG** (`AdConfig.max_ad_content_rating`). Banners stay off for the first
release.
