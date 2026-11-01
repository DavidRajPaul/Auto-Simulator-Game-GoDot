# Crash Reporting (Sentry) — setup & AI fix loop

Namma Auto reports crashes, GDScript errors and Android ANRs to **Sentry** using the official
Sentry Godot SDK. An AI agent (Claude Code, locally or in CI) reads those reports through the
**Sentry MCP server**, reproduces the crash with a headless test, fixes it and opens a PR.

```
Phone crash ──► Sentry (stack trace + breadcrumbs + tags + log + scene tree)
                   │
                   ▼  Sentry MCP
           Claude Code /fix-crash ──► failing headless test ──► fix ──► all suites ──► PR "Fixes NAMMA-AUTO-1A"
```

## Status

| Piece | Where | State |
|---|---|---|
| Engine on Godot 4.5.1 (Sentry 1.x/2.x minimum) | `android-build.yml`, `project.godot` | Done — all 11 suites pass on 4.5.1 |
| `CrashReporter` autoload (breadcrumbs, tags, player context) | `autoloads/CrashReporter.gd` | Done |
| Addon install (pinned 2.4.0, git-ignored) | `tools/sentry/install_sentry_addon.sh` | Done — CI runs it |
| DSN / release / environment stamped at export | `tools/sentry/stamp_sentry_settings.py` | Done — **waits for secret `SENTRY_DSN`** |
| Gradle build + INTERNET permission on both Android presets | `export_presets.cfg` | Done |
| Tests (work with and without the addon) | `tests/run_crash_reporter_tests.tscn` | Done — 15 checks |
| Sentry release + suspect commits | `android-build.yml` | **Waits for `SENTRY_AUTH_TOKEN`** (optional) |
| Claude Code local loop | `.mcp.json`, `.claude/commands/fix-crash.md` | **Waits for your Sentry sign-in** |
| Nightly AI triage in CI | `.github/workflows/crash-triage.yml` | Off — **waits for secrets + `ENABLE_CRASH_TRIAGE`** (optional) |

## Owner steps (placeholders to fill)

### Step 1 — Create the Sentry project (5 min)
1. Sign up at https://sentry.io (free Developer plan is enough to start).
2. Create a project: platform **Godot Engine**, name **`namma-auto`**.
3. Copy the **DSN** (Project Settings → Client Keys). It looks like
   `https://<PUBLIC_KEY>@o<ORG_ID>.ingest.<region>.sentry.io/<PROJECT_ID>`.

### Step 2 — Give CI the DSN
GitHub repo → Settings → Secrets and variables → Actions → **New repository secret**

| Name | Value |
|---|---|
| `SENTRY_DSN` | `<PASTE_DSN_HERE>` |

Never paste the DSN into `project.godot`; `tests/run_crash_reporter_tests` fails if you do.

### Step 3 — Prove it works
1. Actions → **Android Build** → *Run workflow* → tick **sentry_smoke_test**.
2. Install that run's debug APK on your phone and open the game once (with internet on).
3. Sentry → Issues should show **"Namma Auto Sentry smoke test (0.5.0)"** with tags
   `vehicle`, `graphics_preset`, `scene`.
4. Now reproduce your real crash on that build; it shows up as its own issue.

### Step 4 — Connect Claude Code to Sentry (local)
The repo's `.mcp.json` already declares the hosted Sentry MCP server. In a terminal in the repo:
```bash
claude            # approve the "sentry" MCP server from .mcp.json when asked
/mcp              # pick sentry → Authenticate → sign in to Sentry in the browser
/fix-crash        # or: /fix-crash NAMMA-AUTO-1A
```

### Step 5 — (Optional) suspect commits + nightly AI triage
| Kind | Name | Value |
|---|---|---|
| Secret | `SENTRY_AUTH_TOKEN` | Sentry → Settings → Auth Tokens (scopes `project:releases`, `org:read`, `project:read`, `event:read`) |
| Variable | `SENTRY_ORG` | `<your-org-slug>` |
| Variable | `SENTRY_PROJECT` | `namma-auto` |
| Secret | `ANTHROPIC_API_KEY` | only for the nightly triage workflow |
| Variable | `ENABLE_CRASH_TRIAGE` | `true` to turn the nightly triage on |

With these set, every main/tag build creates a Sentry release linked to its commits, and
**Crash Triage (AI)** opens at most one fix PR per night. It never merges.

### Step 6 — Play Store compliance (before Phase 11)
Data Safety form: declare **Crash logs** and **Diagnostics** (collected, not shared, not used
for tracking, for app functionality/analytics). `send_default_pii=false`, so no IP-linked
user data, names or save contents are sent.

## How it works

* The Sentry addon is a GDExtension that auto-initialises from `[sentry]` in `project.godot`
  before any autoload. With an empty DSN it stays disabled — that is the state of git, the
  editor and every test run.
* `autoloads/CrashReporter.gd` adds context only, listening on `SignalBus`:
  * **Breadcrumbs** (`category: message`): `vehicle` (stall, restart, LPG empty, impacts ≥ 6 m/s,
    tow, teleport, gears), `savari` (haggle, boarding, ride, shift end), `world` (zone change),
    `weather`, `ui` (modal, pause, back), `ads`, `tutorial`, `navigation` (scene change).
  * **Tags**: `app_version`, `vehicle`, `zone`, `scene`, `graphics_preset`, `language`,
    `raining`, `camera`, `renderer`, `debug_build`.
  * **Context `player`** every 5 s: position, speed, shift day/minute, zone, session time.
* Release = `namma-auto@<version/name>+<CI run number>`, dist = run number, environment =
  `production` (tags `v*`), `main`, or `pr`.
* Native Android crashes come through Android tombstones / NDK; GDScript errors arrive with
  script stack traces; ANRs are on by default.

## Running locally without CI
```bash
tools/sentry/install_sentry_addon.sh          # needs Godot 4.5+
SENTRY_DSN=<dsn> godot --path .               # the SDK also reads SENTRY_DSN from the environment
```
On a phone there is no environment variable, so device builds always get the DSN from CI.
