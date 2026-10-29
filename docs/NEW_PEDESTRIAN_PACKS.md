# New Chennai pedestrian variations — October 2026

Source archives supplied by the game owner:

| Archive | Character ID | Author | Licence | Status |
|---|---|---|---|---|
| indian_man_in_dhoti.zip | man_dhoti_new | anandmohan662 | CC BY 4.0 | Source archive valid; rigged, requires visual QA of dhoti |
| indian_man_in_pattern_shirt.zip | man_pattern_shirt | Pixel_Monster | CC BY 4.0 | Source archive valid; source animation available |
| sareewoman.zip | woman_saree_new | dk8026854 | CC BY 4.0 | Source archive valid; source animation available |
| sareelady.zip | TBD | unknown | unverified | Corrupt ZIP: cannot inspect or license-check; re-export required |

Source attribution:
- [Indian Man In Dhoti](https://sketchfab.com/3d-models/indian-man-in-dhoti-54b9e050d0d6424b848a04bec02a85d0) by anandmohan662, CC BY 4.0
- [indian man in pattern shirt](https://sketchfab.com/3d-models/indian-man-in-pattern-shirt-13b46cdd311043d7a460245276c9771b) by Pixel_Monster, CC BY 4.0
- [Sareewoman](https://sketchfab.com/3d-models/sareewoman-c28105203127478b8e26ad0474083367) by dk8026854, CC BY 4.0

## Integration steps

The user-provided binary ZIPs are NOT stored in this PR. To generate the three game assets:

1. Copy valid ZIP archives into a local folder.
2. Run `python3 tools/assets/stage_new_people.py <folder>`. Remove the corrupted sareelady ZIP first or the staging command will return a nonzero status, despite staging valid files.
3. Install the documented dependencies of `process_people.py` (numpy, Pillow and gltf-transform).
4. Run `python3 tools/assets/process_people.py man_dhoti_new man_pattern_shirt woman_saree_new`.
5. Inspect the output in Godot. In particular, the dhoti cloth in earlier exports was malformed, so do not ship it without confirming the geometry and animation. Fix its skin binding in Blender if necessary.
6. Commit the generated `assets/models/people/*.glb`, `people.json`, and credits. Add creator credits to the in-game Credits UI before distribution.
7. Verify test suites, draw calls ≤150, offscreen animation cutoff, Android FPS and APK/AAB size.

## Crowd design
- Pool size increased from 24 to 30. New slots can use all three new archetypes once their GLBs are included.
- Pooled nodes are reused; no recurring instantiation.
- Nearest 2 pedestrians cast shadows; animation cutoff at 55 m.
- The code automatically skips missing model files, so the PR can build before binary upload. This is NOT equivalent to shipping the new character visuals.
