# Required GLB assets and Godot import verification

This project previously shipped with **four referenced GLBs absent from GitHub**.
To prevent new regressions, `tools/assets/check_required_assets.py` scans:

- quoted `res://assets/...` paths in Godot scripts, project settings, scenes and resources;
- dynamic `data/world/city_props.json` models (including a default city-model path);
- every actor model dynamically constructed from `assets/models/people/people.json`;
- explicit art required by `tools/assets/required_assets.json` even if gameplay has a fallback.

The **Required model assets** job runs for *every pull request and main push* via the Android Build workflow. It fails if any required source file is absent. The Android APK/AAB job depends on that check. This is intentional: **the check will stay red until missing assets are uploaded**; don't weaken it to keep unrelated PRs green.

## Existing six GLB files without .glb.import sidecars

Godot creates `.glb.import` metadata on asset import. The raw GLBs **are already in GitHub**. Avoid hand-writing or copying `.import` files: generated metadata may contain stale identifiers and version-specific options. After `godot --headless --path . --import`, the test `tests/check_imported_glbs.gd` loads all six as `PackedScene`. If any import fails, CI reports the exact path.

## Missing GLBs to upload

Extract `Namma_Auto_All_4_Missing_Models.zip` at the repo root (folder paths are included):

- `assets/models/city/ripon_building.glb`
- `assets/models/city/tea_kadai.glb`
- `assets/models/city/biryani_shop.glb`
- `assets/models/hero/namma_auto_hero.glb`

These source files were provided by the user. The first three are optimized derivatives and the hero remains the uploaded source. Confirm licensing and mobile rendering in the editor, especially the hero animations.

## Verification

Run `python3 tools/assets/check_required_assets.py`, then start Godot once with `godot --headless --path . --import`. Next run `godot --headless --path . --script res://tests/check_imported_glbs.gd`.

Godot import success doesn't guarantee animation correctness, collisions or visual quality. Perform an Android device pass after assets are restored.
