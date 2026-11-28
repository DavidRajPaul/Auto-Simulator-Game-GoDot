# Dev tools (DEV ONLY, `main` branch only)

**Never in a release or production build.** Rules: `AGENTS.md` Rule 7.

## What it is
A developer panel for testing on a phone or PC. In a debug build of the game scene a small orange **DEV**
button sits top centre; tap it to open the panel on the right (scrolls).

| Section | Options |
|---|---|
| Weather | Auto (the day's own roll), Dry, Rain, Storm + lightning, Flood on/off (the Monsoon Supply Run flood) |
| Time of day | Dawn 6:00, 9 AM, Noon, 4 PM, Dusk 6:30, Night 8 PM |
| Clock | Freeze, Normal, Fast x8 (never ends the shift by itself) |
| Player | Refuel, Repair, +5,000 rupees |

A storm is centred on "now", so it is at its strongest straight away. Jumping the time keeps the chosen weather.
The status lines at the top show the clock, rain, storm, clock mode and flood.

## Where it lives
* `scripts/devtools/DevTools.gd`: the whole thing (logic + panel, built in code).
* `tests/run_devtools_tests.*`, `tests/shot_devtools.*`: its tests and a panel screenshot (`SHOT_OUT`).
* Hook: three lines marked `DEVTOOLS-HOOK` in `autoloads/FrameGuard.gd`. Nothing else may mention it.
* Add new dev options inside `DevTools.gd` only (and a check in `run_devtools_tests.gd`).

## Branches and releases
* `main` has the dev tools.
* Release branches are `release/<major>.<minor>`, e.g. `release/1.1`. Cut one from `main`, then make the
  FIRST commit:

```bash
git checkout -b release/1.1 main
python3 tools/release/strip_devtools.py     # deletes the folder, tests and hook lines, then verifies
git add -A && git commit -m "release/1.1: remove dev tools"
git push -u origin release/1.1
```

* After merging `main` into a release branch, run the strip script again.
* Never cherry-pick or merge a dev-tools change into a release branch.

## What stops a leak
1. The panel loads only when `OS.is_debug_build()` and the folder exists (a release export is not a debug build).
2. **Release Guard** workflow (and the Android Build test job): `check_no_devtools.py --strict` fails any
   `release/*` branch, PR into one, or `v*` tag that still contains it. On other branches it fails if
   anything outside the hook mentions it.
3. **Android Build** exports the debug APK (panel kept, for testers), then strips before the signed release
   APK and the AAB; `check_package_clean.py` fails the job if the packages still hold it.
4. Repository setting (do once, GitHub UI): branch protection on `release/**` requiring the
   **Dev tools guard** and **Tests + perf budget** checks.

Local checks: `python3 tools/release/check_no_devtools.py [--strict]`, `python3 tools/release/strip_devtools.py --dry`.
