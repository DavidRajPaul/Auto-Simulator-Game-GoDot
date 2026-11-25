# Daily reminder notifications

One local notification a day, Duolingo-style, to bring players (and closed testers) back.
No server, no Firebase, no data leaves the phone, so the Play Data Safety form is unaffected.

## Behaviour

- **Leaving the game** (`NOTIFICATION_APPLICATION_PAUSED` / close) schedules one reminder at **7 PM**
  for **7 days** (ids 1–7), starting today if the game is left before 7 PM, otherwise tomorrow. **Coming back** cancels them all.
- **7 PM is the phone's own local time**, in every country: the plugin computes it with `java.util.Calendar`
  in the device time zone, adding calendar days, so a daylight-saving change still lands on 7 PM.
  It is fixed when the player leaves the game; if they then fly to another time zone, that week's reminders
  keep the old moment until they next open the game (which reschedules them).
  A player who stays in the game at reminder time never sees one; someone who stops gets one a day for a week, the last
  one saying "we'll stop here", then nothing.
- **Future-day streak message** follows the 7-day login calendar (`RewardsEngine`): "Keep your 3-day streak! Day 4 bonus ₹125…",
  or the day-7 jackpot. If today's bonus wasn't claimed, or on later days (streak already broken), it
  offers a fresh ₹50 streak or rotates Chennai lines (passengers in Mylapore, tea kadai, Marina rush).
- Messages are `tr()` keys `REM_T_*` / `REM_B_*` in `translations/ui.csv`, so they follow the game language.
- Tapping a reminder opens the game (the daily-bonus popup then greets the player).

## Look (game-style card, Nov 25)

Plain text reminders looked like a system message (owner device test). Like the reward pushes of
Candy Crush, Coin Master or Clash of Clans, each reminder is now a colourful card with art, a reward tag and a
button, drawn in the notification's content area with `NotificationCompat.DecoratedCustomViewStyle`
(the system keeps its header, small icon and action row, so it stays within Android's rules):

![Notification cards](images/notification_preview.png)

| Look | Used for | Art | Chip | Button |
|---|---|---|---|---|
| `bonus` | fresh ₹50 daily bonus | coin pile on a sunburst, purple → orange | ₹50 | Claim ₹50 |
| `streak` | tomorrow's streak tile | coin stack + star, red → orange | DAY n | Claim ₹n |
| `jackpot` | day-7 jackpot | gift + gold badge, magenta → gold | ₹500 | Claim ₹500 |
| `street` | passengers / auto / Marina / last | the loading-screen night street with the auto | — | Drive now |

- Collapsed (≈48 dp): round badge, yellow title, one body line, reward chip. Expanded (168 dp): gradient,
  art in the right half (`fitEnd`, so phones and the OnePlus Pad both show it whole), title, body, a yellow
  "Claim" pill and the red chip. The system action button under the card opens the game, same as a tap.
- Text colours are fixed on our own background, so light and dark notification shades read the same.
  Title and body are still set on the builder for the lock screen and accessibility.
- `DailyReminder.build_reminders()` returns `look`, `chip` and `action` with each reminder (`LOOKS`;
  strings `REM_ACT_CLAIM`, `REM_ACT_DRIVE`, `REM_CHIP_DAY`). An unknown look shows the street card.
- Art: `tools/art/make_notification_art.py` builds `res/drawable-nodpi/namma_notif_{art,icon}_<look>.webp`
  from `assets/ui/rewards.png`, `assets/ui/loading_bg.jpg` and the app icon, and renders the preview above.
  Gradients/pills are XML drawables (`res/drawable/namma_notif_*`); keep `GRADIENTS` in the script in step.
- Layouts (`res/layout/namma_notif_*.xml`) may only use RemoteViews classes (FrameLayout, LinearLayout,
  TextView, ImageView…): a plain `<View>` makes the whole notification fail to inflate. The reminder suite checks it.

## Permission (Android 13+)

Never asked at launch. The "Daily reminder?" card shows once, after the first ride (tutorial finished)
or after a daily-bonus claim, whichever comes first. "Yes" opens the system dialog; if Android won't show
it again (denied twice) the app's notification settings open instead. Android 12 and older allow
notifications by default, so no card. Settings (main menu and pause menu) has a **Daily reminder ON/OFF** toggle.
The permission prompt does not promise a specific time because WorkManager delivery may be delayed. Debug builds also get **Test reminder in 1 min** in main-menu Settings: tap it, press Home, wait.

## Code

| Part | Path |
|---|---|
| Game logic, prompt, toggle state | `autoloads/DailyReminder.gd` |
| Android plugin (Kotlin, same AGP/Kotlin as Godot's template, WorkManager one-shot jobs, channel "Daily reminder") | `android_plugins/namma_reminder/` |
| Export addon (adds the AAR + AndroidX deps to Gradle exports) | `addons/namma_reminder/` |
| Tests (schedule, messages, Tamil, no-plugin safety, packaging) | `tests/run_reminder_tests.gd` |

Plugin API (`Engine.get_singleton("NammaReminder")`): `scheduleAt(id, days_ahead, hour, title, body, look, chip, action)`,
`schedule(id, delay_seconds, title, body, look, chip, action)` (debug test, shows the bonus card),
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
