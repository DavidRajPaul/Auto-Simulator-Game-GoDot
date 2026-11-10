# Daily reminder notifications

One local notification a day, Duolingo-style, to bring players (and closed testers) back.
No server, no Firebase, no data leaves the phone, so the Play Data Safety form is unaffected.

## Behaviour

- **Leaving the game** (`NOTIFICATION_APPLICATION_PAUSED` / close) schedules one reminder at **7 PM**
  on each of the next **7 days** (ids 1–7). **Coming back** cancels them all.
- **7 PM is the phone's own local time**, in every country: the plugin computes it with `java.util.Calendar`
  in the device time zone, adding calendar days, so a daylight-saving change still lands on 7 PM.
  It is fixed when the player leaves the game; if they then fly to another time zone, that week's reminders
  keep the old moment until they next open the game (which reschedules them).
  A player who drives every day never sees one; someone who stops gets one a day for a week, the last
  one saying "we'll stop here", then nothing.
- **Day 1 message** follows the 7-day login calendar (`RewardsEngine`): "Keep your 3-day streak! Day 4 bonus ₹125…",
  or the day-7 jackpot. If today's bonus wasn't claimed, or on later days (streak already broken), it
  offers a fresh ₹50 streak or rotates Chennai lines (passengers in Mylapore, tea kadai, Marina rush).
- Messages are `tr()` keys `REM_T_*` / `REM_B_*` in `translations/ui.csv`, so they follow the game language.
- Tapping a reminder opens the game (the daily-bonus popup then greets the player).

## Permission (Android 13+)

Never asked at launch. The "Daily reminder?" card shows once, after the first ride (tutorial finished)
or after a daily-bonus claim, whichever comes first. "Yes" opens the system dialog; if Android won't show
it again (denied twice) the app's notification settings open instead. Android 12 and older allow
notifications by default, so no card. Settings (main menu and pause menu) has a **Daily reminder ON/OFF** toggle.
Debug builds also get **Test reminder in 1 min** in main-menu Settings: tap it, press Home, wait.

## Code

| Part | Path |
|---|---|
| Game logic, prompt, toggle state | `autoloads/DailyReminder.gd` |
| Android plugin (Kotlin, same AGP/Kotlin as Godot's template, WorkManager one-shot jobs, channel "Daily reminder") | `android_plugins/namma_reminder/` |
| Export addon (adds the AAR + AndroidX deps to Gradle exports) | `addons/namma_reminder/` |
| Tests (schedule, messages, Tamil, no-plugin safety, packaging) | `tests/run_reminder_tests.gd` |

Plugin API (`Engine.get_singleton("NammaReminder")`): `scheduleAt(id, days_ahead, hour, title, body)`,
`schedule(id, delay_seconds, title, body)` (debug test),
`cancelAll()`, `notificationsEnabled()`, `requestPermission()` → signal `permission_result(granted)`.

## Building the AAR

CI (`android-build.yml`) builds it before every Android export. Locally (Android SDK + JDK 17 + Gradle 8.9+):

```
gradle -p android_plugins/namma_reminder assembleRelease
mkdir -p addons/namma_reminder/bin
cp android_plugins/namma_reminder/build/outputs/aar/namma_reminder-release.aar addons/namma_reminder/bin/namma_reminder.aar
```

Without the AAR the export still succeeds, just without reminders (the export addon prints a warning).

## Device check (OnePlus Pad, Moto G40)

1. Fresh install → finish the first ride → the card appears → Yes → system dialog → Allow.
2. Settings shows Daily reminder ON. Debug build: Test reminder → Home → it arrives in ~1 min → tap opens the game.
3. Leave the game; `adb shell dumpsys jobscheduler | grep namma` (or WorkManager inspector) lists 7 pending jobs; reopen → they're gone.
4. Reboot with the game closed → the jobs are still pending.
5. Toggle OFF → leave → nothing pending. Deny twice → toggle ON opens Android's notification settings.
