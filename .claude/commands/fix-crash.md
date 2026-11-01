---
description: Pull the top unresolved Namma Auto crash from Sentry, reproduce it, fix it, open a PR
argument-hint: "[optional Sentry issue id or URL, e.g. NAMMA-AUTO-1A]"
---

Fix one crash from Sentry, end to end. Follow AGENTS.md (especially "Crash reporting").

1. **Pick the issue.** If `$ARGUMENTS` names an issue, use it. Otherwise use the Sentry MCP to
   list unresolved issues in project `namma-auto` from the last 7 days, environment `main` or
   `production`, sorted by users affected. Pick the top one that has no open PR (search open
   PRs for its short id).
2. **Read everything Sentry has:** stack trace (GDScript frames map to `res://` paths in this
   repo), breadcrumbs (CrashReporter's categories: vehicle, savari, world, ui, ads, tutorial,
   navigation), tags (`vehicle`, `zone`, `scene`, `graphics_preset`, `raining`, `camera`),
   the `player` context (position, speed, shift clock), the attached Godot log and scene tree,
   the release (`namma-auto@<version>+<CI run>`) and suspect commits. Check whether related
   issues share the root cause.
3. **Reproduce headless first.** Write a failing check in the closest `tests/run_phaseN_tests.gd`
   (or `tests/run_crash_reporter_tests.gd` for reporting bugs) that recreates the breadcrumb
   sequence and player context. Run it with `timeout` and confirm it fails for the right reason.
   If it only happens on a device (renderer, Android plugin, memory), say so in the PR and
   explain the evidence instead of guessing.
4. **Fix the root cause**, not the symptom. Respect the five non-negotiable rules and the
   "Lessons recorded". Never silence the error with a bare null check that hides a broken state;
   if a guard is right, also report it with `CrashReporter.capture_message()`.
5. **Run the verification protocol** (AGENTS.md §4): import, boot, every suite, perf probe if you
   touched rendering or traffic.
6. **Add a Lessons line** to AGENTS.md if the crash came from an engine/Jolt/Android gotcha.
7. **Open a PR** titled `fix(crash): <one line>` whose body has: the Sentry issue link and short
   id, root cause in two sentences, the regression check you added, and `Fixes <SHORT-ID>` so
   Sentry resolves it when the release ships. Then comment the PR link on the Sentry issue.

Stop after one issue. Never resolve or ignore a Sentry issue without a merged fix.
