---
description: Pull the top unresolved Namma Auto crash from GlitchTip, reproduce it, fix it, open a PR
argument-hint: "[optional GlitchTip issue id, e.g. 1234]"
---

Fix one crash from GlitchTip, end to end. Follow AGENTS.md (especially Rule 6, "Crash reporting").

1. **Pick the issue.** If `$ARGUMENTS` names an issue id, use it. Otherwise call
   `get_glitchtip_issues` (status unresolved) for the project in `GLITCHTIP_PROJECT` and pick the
   one with the most events or users. Skip any issue that already has an open PR (search open PRs
   for its id).
2. **Read everything GlitchTip has** with `get_glitchtip_issue`: the stack trace (GDScript frames
   map to `res://` paths in this repo), the breadcrumbs (CrashReporter categories: vehicle, savari,
   world, ui, ads, tutorial, weather, navigation), the tags (`vehicle`, `zone`, `scene`,
   `graphics_preset`, `raining`, `camera`), the `player` context (position, speed, shift clock),
   and the release (`namma-auto@<version>+<CI run>`). GlitchTip has no suspect-commit tracking, so
   find the likely commit with `git log` between the release tags. Check whether related issues
   share the root cause.
3. **Reproduce headless first.** Write a failing check in the closest `tests/run_phaseN_tests.gd`
   (or `tests/run_crash_reporter_tests.gd` for reporting bugs) that recreates the breadcrumb
   sequence and player context. Run it with `timeout` and confirm it fails for the right reason.
   If it only happens on a device (renderer, Android plugin, memory), say so in the PR and explain
   the evidence instead of guessing.
4. **Fix the root cause**, not the symptom. Respect the non-negotiable rules and "Lessons recorded".
   Never hide an error with a bare null check; if a guard is right, also report it with
   `CrashReporter.capture_message()`.
5. **Run the verification protocol** (AGENTS.md section 4): import, boot, every suite, and the
   perf probe if you touched rendering or traffic.
6. **Add a Lessons line** to AGENTS.md if the crash came from an engine, Jolt or Android gotcha.
7. **Open a PR** titled `fix(crash): <one line>`. The body has the GlitchTip issue id and link,
   the root cause in two sentences, and the regression check you added. Do not resolve the issue
   yet; it is resolved with `resolve_glitchtip_issue` after the fix is merged and released.

Stop after one issue. Never resolve or ignore a GlitchTip issue without a merged fix.
