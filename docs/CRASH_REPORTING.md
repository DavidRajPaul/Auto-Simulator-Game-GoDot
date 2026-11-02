# Crash Reporting (GlitchTip) and the AI fix loop

Namma Auto reports crashes, GDScript errors and Android ANRs to **GlitchTip**, an open-source
(MIT) error tracker that accepts the Sentry protocol. The game uses the official Sentry Godot SDK
addon, so switching hosts later is a DSN change. An AI agent reads the reports through the
**GlitchTip MCP server**, reproduces each crash with a headless test, fixes it and opens a PR.

```
Phone crash ──► GlitchTip (stack trace + breadcrumbs + tags + player context + log)
                   │
                   ▼  glitchtip MCP
           Claude /fix-crash ──► failing headless test ──► fix ──► all suites ──► PR "GlitchTip issue 1234"
                                                                                       │
                                                       after merge + release: resolve in GlitchTip
```

## Status

| Piece | Where | State |
|---|---|---|
| Godot 4.5.1 (Sentry SDK 1.x/2.x minimum) | `android-build.yml`, `project.godot` | Done, all suites pass |
| `CrashReporter` autoload (breadcrumbs, tags, player context) | `autoloads/CrashReporter.gd` | Done |
| SDK addon, pinned 2.4.0, git-ignored | `tools/sentry/install_sentry_addon.sh` | Done, CI installs it |
| DSN stamped at export from the secret | `tools/sentry/stamp_sentry_settings.py` | Done, **waits for `GLITCHTIP_DSN`** |
| Gradle build + INTERNET on both Android presets | `export_presets.cfg` | Done |
| Tests, pass with or without the addon | `tests/run_crash_reporter_tests.tscn` | Done, 15 checks |
| Claude Code local loop | `.mcp.json`, `.claude/commands/fix-crash.md` | **Waits for your GlitchTip token** |
| Nightly AI triage in CI | `.github/workflows/crash-triage.yml` | Off, **waits for secrets + `ENABLE_CRASH_TRIAGE`** |

## Phone-only setup (no laptop needed)

Everything below works in a phone browser. Use "Desktop site" in the browser menu for GitHub
settings pages if the mobile layout hides a button.

1. **Create the GlitchTip project.** Sign up at glitchtip.com (free cloud tier). Create an
   organization, then a project named `namma-auto` with platform **Godot** (or any Sentry SDK
   platform). Open the project's **Client Keys (DSN)** page and copy the DSN.
2. **Add the DSN to GitHub.** github.com → repo → Settings → Secrets and variables → Actions →
   **New repository secret**: name `GLITCHTIP_DSN`, value = the DSN.
3. **Merge PR #71** once its checks are green (Actions tab, tap the PR).
4. **Get a test build.** Actions → **Android Build** → *Run workflow* → tick
   `sentry_smoke_test` → Run. When the run finishes, open it, download the `NammaAuto-android-…`
   artifact, and install the APK on your phone. Your phone must allow installs from your browser
   (Android Settings → Apps → Special access → Install unknown apps).
5. **Check it arrived.** Open the game once with internet on. A GlitchTip issue titled
   "Namma Auto Sentry smoke test" should appear within a minute.
6. **Reproduce the real crash** on that build. It shows up as its own GlitchTip issue.

## Laptop or cloud Claude setup (later, optional)

1. Create a GlitchTip API token (GlitchTip → profile → Auth Tokens). Give it project read and
   issue write access.
2. For local Claude Code, export `GLITCHTIP_AUTH_TOKEN`, `GLITCHTIP_API_URL`,
   `GLITCHTIP_ORGANIZATION` and `GLITCHTIP_PROJECT` in your shell profile, then run `claude`,
   approve the `glitchtip` server from `.mcp.json`, and use `/fix-crash`. Set
   `GLITCHTIP_API_URL` to the API base URL shown in your GlitchTip instance's docs (it ends with
   a slash).
3. For cloud Claude sessions, set the same four values in the environment settings.

## Nightly AI triage (optional, CI)

Add these, then the triage runs at 03:00 IST and opens at most one fix PR a night. It never merges.

| Kind | Name | Value |
|---|---|---|
| Secret | `GLITCHTIP_AUTH_TOKEN` | the API token from step 1 above |
| Secret | `ANTHROPIC_API_KEY` | your Anthropic API key |
| Variable | `GLITCHTIP_API_URL` | GlitchTip API base URL, ends with `/` |
| Variable | `GLITCHTIP_ORGANIZATION` | your organization slug |
| Variable | `GLITCHTIP_PROJECT` | `namma-auto` |
| Variable | `ENABLE_CRASH_TRIAGE` | `true` |

## Before Play launch

Data Safety form: declare **Crash logs** and **Diagnostics**, collected, not shared, not used for
tracking. `send_default_pii=false`, so names, save contents and IP-linked user data are not sent.

## How it works

* The SDK addon initialises from `[sentry]` in `project.godot` before any autoload. With an empty
  DSN it stays off, which is the state of git, the editor and every test run. The `sentry/...`
  names are the Sentry SDK's own settings and stay as they are.
* `autoloads/CrashReporter.gd` adds context only, from `SignalBus`:
  * **Breadcrumbs** (`category: message`): `vehicle` (stalls, restarts, LPG empty, impacts at
    6 m/s or more, tow, teleport, gears), `savari` (haggle, boarding, ride, shift end), `world`
    (zone change), `weather`, `ui`, `ads`, `tutorial`, `navigation` (scene change).
  * **Tags:** `app_version`, `vehicle`, `zone`, `scene`, `graphics_preset`, `language`, `raining`,
    `camera`, `renderer`, `debug_build`.
  * **Context `player`** every 5 seconds: position, speed, shift day and minute, zone, session time.
* Release is `namma-auto@<version>+<CI run>`, dist is the CI run number, and environment is
  `production` (tags `v*`), `main`, or `pr`.
* Native Android crashes come through tombstones and the NDK. GDScript errors arrive with script
  stack traces. ANR detection is on.

## Known differences from Sentry

* GlitchTip supports only part of the Sentry event format. Events that use unsupported features
  are accepted and then silently dropped. Smoke-test each build before relying on it.
* No suspect-commit tracking, so the agent finds the likely commit from the release tags.
* Alerts are email and webhook only.
