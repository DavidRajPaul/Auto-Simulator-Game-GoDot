"""Writes data/missions/side_quests/sq_007.tres and data/missions/stories/sq_007_story.tres.

"The Little Red Kite" (v3, Nov 2026 owner request: side quests that play in the world, with voiced
cutscenes, like RDR2). Positions are real Santhome / Marina spots read off data/world; the voice
lines come from docs/voice/SQ07_Red_Kite_Voice_Script.md (assets/audio/voice/sq07).
Run from the repo root: python3 tools/quests/build_sq07_story.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class V3(tuple):
    pass


class V2(tuple):
    pass


class Col(tuple):
    pass


class PSA(list):
    pass


def g(v):
    """Python value -> Godot text resource variant."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, V3):
        return "Vector3(%s, %s, %s)" % tuple(num(x) for x in v)
    if isinstance(v, V2):
        return "Vector2(%s, %s)" % tuple(num(x) for x in v)
    if isinstance(v, Col):
        return "Color(%s, %s, %s, %s)" % tuple(num(x) for x in v)
    if isinstance(v, PSA):
        return "PackedStringArray(%s)" % ", ".join('"%s"' % x for x in v)
    if isinstance(v, (int, float)):
        return num(v)
    if isinstance(v, str):
        return '"%s"' % v.replace("\\", "\\\\").replace('"', '\\"')
    if isinstance(v, dict):
        if not v:
            return "{}"
        return "{\n" + ",\n".join('"%s": %s' % (k, g(x)) for k, x in v.items()) + "\n}"
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(g(x) for x in v) + "]"
    raise TypeError(v)


def num(x):
    if isinstance(x, bool):
        raise TypeError(x)
    if isinstance(x, int):
        return str(x)
    s = repr(float(x))
    return s


BLUE = Col((0.12, 0.27, 0.68, 1.0))
NONE = Col((0.0, 0.0, 0.0, 0.0))
PEOPLE = "res://assets/models/people/"

# Real places (data/world): Santhome High Road tea stall, Sullivan Street EB wire, the sand off
# Foreshore Estate Link, a house in the lanes behind the beach.
START = V3((2094.1, 0, 634.8))
TEA_ROAD = V3((2044.8, 0, 1440.0))
TEA_PLACE = V3((2053.2, 0, 1441.6))
CHURCH_ROAD = V3((2003.0, 0, 1744.8))
CHURCH_PLACE = V3((2011.0, 0, 1741.8))
# On the Sullivan Street EB wire, at the point farthest from the street trees (they line the
# other kerb), hanging over the road edge so a boy on the auto's roof can reach it.
KITE = V3((1943.8, 3.7, 1827.3))
KITE_HANG = V3((1943.6, 7.5, 1829.5))
DECOY_KITE = V3((1950.9, 4.6, 1716.0))
DECOY_HANG = V3((1950.7, 7.5, 1718.4))
UNDER_KITE = V3((1944.1, 0, 1826.0))
UNDER_PLACE = V3((1943.9, 0, 1828.0))
BEACH_ROAD = V3((2229.6, 0, 1843.9))
BEACH_PLACE = V3((2236.6, 0, 1844.6))
KARTHIK = V3((2250.5, 0, 1846.0))  # on the sand, 6 m past the beach fence
HOME_ROAD = V3((2205.3, 0, 1797.0))
HOME_PLACE = V3((2204.6, 0, 1802.5))

stages = [
    dict(id="intro", kind="cutscene", objective_key="SQ07_INTRO", cutscene_id="intro", duration_s=30.0),
    dict(id="ask_tea", kind="ask", objective_key="SQ07_ASK", target=TEA_ROAD, radius_m=9.0, place_key="SQ07_P_TEA", place_pos=TEA_PLACE),
    dict(id="tea", kind="cutscene", objective_key="SQ07_TEA", cutscene_id="tea", duration_s=12.0),
    dict(id="spot_kite", kind="spot", objective_key="SQ07_FIND_KITE", target=CHURCH_ROAD, radius_m=130.0,
         spot_pos=KITE, spot_range_m=40.0, spot_max_kmh=15.0, shrink_after_s=75.0, shrink_radius_m=45.0,
         place_key="SQ07_P_CHURCH", place_pos=CHURCH_PLACE),
    dict(id="kids", kind="cutscene", objective_key="SQ07_KIDS", cutscene_id="kids", duration_s=14.0),
    dict(id="spot_boy", kind="spot", objective_key="SQ07_FIND_BOY", target=BEACH_ROAD, radius_m=110.0,
         spot_pos=V3((KARTHIK[0], 0.8, KARTHIK[2])), spot_range_m=48.0, spot_max_kmh=15.0, shrink_after_s=70.0,
         shrink_radius_m=40.0, place_key="SQ07_P_BEACH", place_pos=BEACH_PLACE),
    dict(id="reunion", kind="cutscene", objective_key="SQ07_REUNION", cutscene_id="reunion", duration_s=20.0),
    dict(id="choice", kind="dialogue", objective_key="SQ07_CHOICE", choices=PSA(["SQ07_CHOICE_HOME", "SQ07_CHOICE_KITE"]),
         next_by_choice={"SQ07_CHOICE_HOME": "home_line", "SQ07_CHOICE_KITE": "promise"}),
    dict(id="promise", kind="cutscene", objective_key="SQ07_PROMISE", cutscene_id="promise", duration_s=8.0),
    dict(id="rescue", kind="goto", objective_key="SQ07_RESCUE", target=UNDER_KITE, radius_m=2.4, arrival_speed_kmh=2.0,
         place_key="SQ07_P_KITE", place_pos=UNDER_PLACE),
    dict(id="climb", kind="cutscene", objective_key="SQ07_CLIMB", cutscene_id="climb", duration_s=10.0, next_id="ride_home"),
    dict(id="home_line", kind="cutscene", objective_key="SQ07_HOME_LINE", cutscene_id="home_line", duration_s=6.0),
    dict(id="ride_home", kind="goto", objective_key="SQ07_RIDE", target=HOME_ROAD, radius_m=8.0, quality_key="comfort",
         place_key="SQ07_P_HOME", place_pos=HOME_PLACE),
    dict(id="home", kind="cutscene", objective_key="SQ07_HOME", cutscene_id="home", duration_s=12.0),
    dict(id="payoff", kind="dialogue", objective_key="SQ07_PAYOFF", choices=PSA(["SQ07_TAKE_FARE", "SQ07_REFUSE_FARE"])),
    dict(id="thanks", kind="cutscene", objective_key="SQ07_THANKS", cutscene_id="thanks", duration_s=10.0),
]

FRONT = [2.1, 1.4, 7.2]          # front three-quarter of the auto, driver in view
FRONT_TO = [1.6, 1.35, 6.6]
AUTO_LOOK = [0.0, 1.05, 0.4]
BOARD_CAM = [-5.6, 1.6, 1.8]
KID_CLOSE = [-3.5, 0.95, 4.7]

cutscenes = {
    "intro": [
        {"fade_in": 0.8, "cam": {"cockpit": True, "look": "prop:swoop", "fov": 72},
         # Across the windscreen from the sea side, then away ahead-left over the houses: the
         # driver's eye follows it through the screen, never up into the canopy.
         "prop": {"swoop": {"path": [[10, 8, 24], [4.5, 3.4, 10], [0.8, 1.7, 3.6], [-2.2, 2.0, 3.4], [-7, 4.0, 9], [-15, 8, 18], [-26, 13, 28]],
                            "secs": 4.2, "show": True}},
         "line": "sq07_d01", "line_at": 1.3, "min_s": 2.6},
        {"cam": {"cockpit": True, "look": "prop:swoop", "fov": 56}, "min_s": 1.8},
        {"cam": {"cockpit": True, "look": [-2.2, 1.4, 9], "fov": 70}, "prop": {"swoop": {"show": False}},
         "act": {"lakshmi": {"at": [-5.5, 0, 18], "to": [-1.9, 0, 3.4], "gait": "run", "then": "wave", "face": "auto"}},
         "line": "sq07_l01", "line_at": 0.9, "wait": "lakshmi", "max_s": 7.0},
        {"cam": {"eye": [-4.6, 1.25, 6.2], "eye_to": [-4.2, 1.3, 5.6], "look": "role:lakshmi", "fov": 50},
         "act": {"lakshmi": {"anim": "talk", "face": "auto"}}, "line": "sq07_l02"},
        {"cam": {"eye": [-1.5, 1.55, -1.8], "look": "role:lakshmi", "fov": 44}, "line": "sq07_l03"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq07_d02"},
        {"cam": {"eye": BOARD_CAM, "look": "role:lakshmi", "fov": 50}, "act": {"lakshmi": {"to": "door", "gait": "run"}},
         "wait": "lakshmi", "min_s": 1.0, "max_s": 4.0},
        {"cam": {"eye": BOARD_CAM, "look": AUTO_LOOK, "fov": 50}, "act": {"lakshmi": {"show": False}}, "min_s": 0.9, "fade_out": 0.5},
    ],
    "tea": [
        {"cam": {"cockpit": True, "look": "role:tea_anna", "fov": 58}, "act": {"tea_anna": {"face": "auto", "anim": "wave"}}, "min_s": 1.3},
        {"cam": {"eye": {"from": "role:tea_anna", "dist": 4.2, "up": 1.5, "side": 1.6}, "look": "role:tea_anna", "fov": 42},
         "act": {"tea_anna": {"anim": "talk", "face": "auto"}}, "line": "sq07_t01"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq07_l04", "fade_out": 0.4},
    ],
    "kids": [
        {"fade_in": 0.4, "cam": {"eye": {"from": "prop:kite", "dist": 5.0, "up": -1.6, "side": 1.2}, "look": "prop:kite", "fov": 44},
         "line": "sq07_l09"},
        {"cam": {"eye": [-5.0, 1.1, 7.6], "look": "role:priya", "fov": 46},
         "act": {"priya": {"at": [-3.5, 0, 12], "to": [-2.0, 0, 3.2], "gait": "run", "then": "talk", "face": "auto"},
                 "kid2": {"at": [-4.6, 0, 13.5], "to": [-2.7, 0, 4.3], "gait": "run", "then": "idle", "face": "auto"}},
         "line": "sq07_k01", "line_at": 1.0, "wait": "priya", "max_s": 7.0},
        {"cam": {"eye": [-3.7, 1.0, 2.3], "look": "role:kid2", "fov": 42}, "act": {"kid2": {"anim": "wave", "face": KARTHIK}},
         "line": "sq07_k02"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq07_l11", "fade_out": 0.4},
    ],
    "reunion": [
        {"fade_in": 0.4, "cam": {"eye": {"from": "role:karthik", "dist": 5.5, "up": 1.3, "side": -1.5}, "look": "role:karthik", "fov": 40},
         "line": "sq07_l15"},
        {"min_s": 0.7, "fade_out": 0.5},
        {"fade_in": 0.7,
         "act": {"lakshmi": {"at": [-2.6, 0, 2.3], "anim": "talk"}, "karthik": {"at": [-2.2, 0, 3.4], "anim": "idle", "face": "role:lakshmi"}},
         "cam": {"eye": [-5.3, 1.3, 4.4], "eye_to": [-4.8, 1.3, 3.9], "look": "role:karthik", "fov": 46}, "line": "sq07_l16"},
        {"act": {"lakshmi": {"face": "role:karthik"}}, "cam": {"eye": KID_CLOSE, "look": "role:karthik", "fov": 38}, "line": "sq07_b01"},
        {"cam": {"eye": [-1.8, 1.45, 4.3], "look": "role:lakshmi", "fov": 40}, "line": "sq07_l17"},
        {"act": {"karthik": {"anim": "talk"}}, "cam": {"eye": KID_CLOSE, "look": "role:karthik", "fov": 38}, "line": "sq07_b02", "hold": True},
    ],
    "promise": [
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 46}, "line": "sq07_d04"},
        {"cam": {"eye": KID_CLOSE, "look": "role:karthik", "fov": 40}, "act": {"karthik": {"anim": "wave", "face": "auto"}}, "line": "sq07_b03"},
        {"cam": {"eye": BOARD_CAM, "look": AUTO_LOOK, "fov": 50},
         "act": {"lakshmi": {"to": "door", "gait": "walk"}, "karthik": {"to": "door", "gait": "run"}}, "wait": "karthik", "min_s": 1.2, "max_s": 4.0},
        {"act": {"lakshmi": {"show": False}, "karthik": {"show": False}}, "cam": {"eye": BOARD_CAM, "look": AUTO_LOOK, "fov": 50}, "min_s": 0.7, "fade_out": 0.4},
    ],
    "home_line": [
        {"cam": {"eye": KID_CLOSE, "look": "role:karthik", "fov": 40}, "act": {"karthik": {"anim": "idle", "face": "auto"}}, "line": "sq07_d03"},
        {"cam": {"eye": BOARD_CAM, "look": AUTO_LOOK, "fov": 50},
         "act": {"lakshmi": {"to": "door", "gait": "walk"}, "karthik": {"to": "door", "gait": "walk"}}, "wait": "lakshmi", "min_s": 1.2, "max_s": 4.0},
        {"act": {"lakshmi": {"show": False}, "karthik": {"show": False}}, "cam": {"eye": BOARD_CAM, "look": AUTO_LOOK, "fov": 50}, "min_s": 0.7, "fade_out": 0.4},
    ],
    "climb": [
        {"fade_in": 0.5,
         "act": {"lakshmi": {"at": [-1.4, 0, 0.6], "face": "prop:kite", "anim": "talk"},
                 "karthik": {"roof": True, "at": [0.0, 0, 0.2], "face": "prop:kite", "anim": "idle", "show": True}},
         "cam": {"eye": {"from": "prop:kite", "dist": -4.0, "up": -1.6, "side": 2.5}, "look": "role:karthik", "fov": 50}, "line": "sq07_l19"},
        {"act": {"karthik": {"anim": "wave"}}, "prop": {"kite": {"to": "hand:karthik", "secs": 1.3}},
         "cam": {"eye": {"from": "prop:kite", "dist": -2.8, "up": -1.5, "side": -1.6}, "look": "prop:kite", "fov": 46},
         "line": "sq07_b05", "line_at": 1.3, "min_s": 2.8},
        {"cam": {"eye": {"from": "prop:kite", "dist": -2.8, "up": -1.5, "side": -1.6}, "look": "role:karthik", "fov": 46},
         "min_s": 0.8, "fade_out": 0.5},
        {"act": {"karthik": {"show": False, "roof": False}, "lakshmi": {"show": False}}, "min_s": 0.1},
    ],
    "home": [
        {"if_choice": ["choice", "SQ07_CHOICE_KITE"], "fade_in": 0.5,
         "act": {"lakshmi": {"at": "door", "to": [-2.8, 0, 1.0], "then": "talk", "face": "auto", "show": True},
                 "karthik": {"at": [-1.5, 0, -0.6], "to": [-3.4, 0, 1.9], "then": "idle", "face": "auto", "show": True, "kite": "kite"}},
         "cam": {"eye": [-5.4, 1.5, 4.8], "look": "role:lakshmi", "fov": 48}, "line": "sq07_l22", "line_at": 0.8},
        {"if_choice": ["choice", "SQ07_CHOICE_HOME"], "fade_in": 0.5,
         "act": {"lakshmi": {"at": "door", "to": [-2.8, 0, 1.0], "then": "talk", "face": "auto", "show": True},
                 "karthik": {"at": [-1.5, 0, -0.6], "to": [-3.4, 0, 1.9], "then": "idle", "face": "auto", "show": True}},
         "cam": {"eye": [-5.4, 1.5, 4.8], "look": "role:lakshmi", "fov": 48}, "line": "sq07_l22", "line_at": 0.8},
        {"cam": {"eye": [-4.1, 1.35, -0.2], "look": "role:lakshmi", "fov": 42}, "act": {"lakshmi": {"anim": "talk", "face": "auto"}},
         "line": "sq07_l23", "hold": True},
    ],
    "thanks": [
        {"if_choice": ["payoff", "SQ07_REFUSE_FARE"], "cam": {"eye": [-3.9, 1.35, 2.2], "look": "role:lakshmi", "fov": 42},
         "act": {"lakshmi": {"anim": "talk"}}, "line": "sq07_l24"},
        {"cam": {"eye": KID_CLOSE, "look": "role:karthik", "fov": 40}, "act": {"karthik": {"anim": "wave", "face": "auto"}}, "line": "sq07_b08"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": "role:karthik", "fov": 50},
         "act": {"lakshmi": {"to": "place:ride_home", "gait": "walk"}, "karthik": {"to": "place:ride_home", "gait": "walk"}},
         "min_s": 3.2, "fade_out": 0.6},
        {"act": {"lakshmi": {"show": False}, "karthik": {"show": False}}, "min_s": 0.1},
    ],
}

decoy = lambda model, scale, paint, at, kite=False, kite_colour=None: {
    "model": PEOPLE + model, "scale": scale, "paint": paint, "world": at, "face": BEACH_ROAD, "anim": "idle",
    "stages": PSA(["spot_boy"]), "decoy_for": "spot_boy", "kite": kite,
    **({"kite_colour": kite_colour} if kite_colour else {})}

cast = {
    "lakshmi": {"model": PEOPLE + "woman_saree_green.glb", "scale": 1.0, "paint": NONE},
    "karthik": {"model": PEOPLE + "man_casual.glb", "scale": 0.72, "paint": BLUE, "world": KARTHIK, "face": BEACH_ROAD,
                "anim": "idle", "stages": PSA(["spot_boy"]), "target_for": "spot_boy"},
    "tea_anna": {"model": PEOPLE + "old_man_veshti.glb", "scale": 1.0, "paint": NONE, "world": V3((2051.6, 0, 1441.3)),
                 "face": TEA_ROAD, "anim": "idle", "stages": PSA(["ask_tea", "tea", "spot_kite"])},
    "flower_akka": {"model": PEOPLE + "woman_saree_maroon.glb", "scale": 1.0, "paint": NONE, "world": V3((2064.8, 0, 1389.8)),
                    "face": V3((2058.2, 0, 1387.7)), "anim": "idle", "stages": PSA(["ask_tea"]), "line": "sq07_f01",
                    "reply": "sq07_l08", "near_m": 10.0, "stall": "flowers"},
    "priya": {"model": PEOPLE + "girl_pavadai.glb", "scale": 0.8, "paint": NONE},
    "kid2": {"model": PEOPLE + "man_casual.glb", "scale": 0.66, "paint": Col((0.93, 0.7, 0.16, 1.0))},
    # The crowd on the sand: Karthik is the only blue shirt without a kite.
    "boy_blue_kite": decoy("man_casual.glb", 0.72, BLUE, V3((2248.0, 0, 1833.0)), True, Col((0.95, 0.85, 0.15, 1.0))),
    "girl_kite": decoy("girl_pavadai.glb", 0.8, NONE, V3((2254.0, 0, 1828.0)), True, Col((0.2, 0.5, 0.95, 1.0))),
    "boy_white": decoy("man_casual.glb", 0.7, Col((0.92, 0.92, 0.9, 1.0)), V3((2256.0, 0, 1853.0))),
    "girl_churidar": decoy("girl_churidar.glb", 0.8, NONE, V3((2248.5, 0, 1860.0))),
    "boy_red_kite": decoy("man_casual.glb", 0.74, Col((0.78, 0.16, 0.14, 1.0)), V3((2258.0, 0, 1840.0)), True, Col((0.2, 0.75, 0.3, 1.0))),
}

props = {
    "kite": {"kind": "kite", "world": KITE, "hang": KITE_HANG, "target_for": "spot_kite",
             "stages": PSA(["spot_kite", "kids", "spot_boy", "reunion", "choice", "promise", "rescue", "climb"])},
    # Another kite caught on a wire one street away: blue, so a careful look tells them apart.
    "blue_kite": {"kind": "kite", "world": DECOY_KITE, "hang": DECOY_HANG, "decoy_for": "spot_kite",
                  "colour": Col((0.15, 0.4, 0.92, 1.0)), "stages": PSA(["spot_kite"])},
}

barks = {
    "ask_tea": {"enter": ["sq07_l07"], "idle": ["sq07_l05"], "idle_s": V2((30.0, 45.0))},
    "spot_kite": {"idle": ["sq07_l06", "sq07_l05"], "idle_s": V2((22.0, 34.0)), "hint": ["sq07_l04"], "hint_after_s": 50.0,
                  "wrong": "sq07_l10"},
    "spot_boy": {"enter": ["sq07_l12"], "idle": ["sq07_l05"], "idle_s": V2((26.0, 38.0)), "hint": ["sq07_l13"],
                 "hint_after_s": 40.0, "wrong": "sq07_l14"},
    "rescue": {"near": "sq07_l18", "near_m": 30.0, "miss": "sq07_b04", "miss_m": 9.0},
    "ride_home": {"enter": ["sq07_b06", "sq07_l20"], "impact": "sq07_l21", "jolt": "sq07_b07"},
}

speakers = {"l": "VO_SPK_LAKSHMI", "b": "VO_SPK_KARTHIK", "d": "VO_SPK_DRIVER", "t": "VO_SPK_TEA",
            "f": "VO_SPK_FLOWER", "k": "VO_SPK_PRIYA", "sq07_k02": "VO_SPK_KID"}

story = ['[gd_resource type="Resource" script_class="QuestStoryData" load_steps=2 format=3]',
         '[ext_resource type="Script" path="res://data/missions/QuestStoryData.gd" id="story"]',
         '[resource]', 'script = ExtResource("story")',
         'voice_dir = "res://assets/audio/voice/sq07"',
         'speakers = ' + g(speakers), 'cast = ' + g(cast), 'props = ' + g(props),
         'cutscenes = ' + g(cutscenes), 'barks = ' + g(barks)]
out = ROOT / "data/missions/stories/sq_007_story.tres"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text("\n".join(story) + "\n", encoding="utf-8")

ORDER = ["id", "kind", "objective_key", "target", "radius_m", "arrival_speed_kmh", "duration_s", "choices", "next_by_choice",
         "quality_key", "place_key", "place_pos", "cutscene_id", "spot_pos", "spot_range_m", "spot_max_kmh", "shrink_after_s",
         "shrink_radius_m", "next_id"]
lines = ['[gd_resource type="Resource" script_class="MissionDef" load_steps=%d format=3]' % (len(stages) + 4),
         '[ext_resource type="Script" path="res://data/missions/MissionDef.gd" id="def"]',
         '[ext_resource type="Script" path="res://data/missions/MissionStage.gd" id="stage"]',
         '[ext_resource type="Resource" path="res://data/missions/stories/sq_007_story.tres" id="story"]']
for st in stages:
    lines.append('[sub_resource type="Resource" id="%s"]' % st["id"])
    lines.append('script = ExtResource("stage")')
    for k in ORDER:
        if k in st:
            lines.append("%s = %s" % (k, g(st[k])))
lines += ['[resource]', 'script = ExtResource("def")', 'id = "sq_007"', 'content_version = 3', 'title_key = "SQ07_TITLE"',
          'description_key = "SQ07_DESC"', 'job_key = "SQ07_JOB"', 'discoverable = true', 'start_anchor = ' + g(START),
          'estimated_minutes = 12', 'category = "help"', 'reward_inr = 220', 'reward_xp = 25',
          'reward_choice_stage = "payoff"', 'reward_choice_inr = ' + g({"SQ07_TAKE_FARE": 220, "SQ07_REFUSE_FARE": 0}),
          'reward_choice_xp = ' + g({"SQ07_REFUSE_FARE": 40}), 'story = ExtResource("story")',
          'stages = Array[ExtResource("stage")]([%s])' % ", ".join('SubResource("%s")' % s["id"] for s in stages)]
(ROOT / "data/missions/side_quests/sq_007.tres").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("wrote sq_007.tres and sq_007_story.tres")
