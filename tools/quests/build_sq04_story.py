"""Writes data/missions/side_quests/sq_004.tres and data/missions/stories/sq_004_story.tres.

"Paati Knows the Way" (v3, Nov 2026 owner request: rework every side quest like the Red Kite, with
voiced cutscenes, people to talk to and things to find). Kamakshi Paati came from Kumbakonam to
her granddaughter Meena's new house in Mylapore, went to the temple and can't find her way back.
She has no phone and no address, only memories: the jasmine stall, the tank steps, the old sundal
seller. Paati is the quest's rider (QuestRider, paati.glb): she walks up to the auto, rides in
the back and gets out in the scenes ("rider" beats in QuestStory).

Positions are real Mylapore spots read off data/world: Venkatesa Agraharam Road, the
Kapaleeshwarar tank (South Mada Street, East Tank Square Street) and RK Mutt Road. Voice lines
come from docs/voice/SQ04_Paati_Voice_Script.md (assets/audio/voice/sq04).
Run from the repo root: python3 tools/quests/build_sq04_story.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from story_tres import NONE, PEOPLE, PSA, V2, V3, write_mission, write_story  # noqa: E402

START = V3((784.0, 0, 1795.6))  # Venkatesa Agraharam Road, by the Mylapore branch library
# The jasmine stall where Paati bought flowers this morning (and left her change).
FLOWER_ROAD = V3((674.7, 0, 1792.6))
FLOWER_PLACE = V3((675.0, 0, 1788.5))
VALLI = V3((677.0, 0, 1789.4))
# A building watchman on the way: "a hundred new flats on this road, Paati!"
WATCHMAN = V3((735.0, 0, 1794.4))
# South Mada Street, on the tank side: the sundal seller who saw her on the steps.
SUNDAL_ROAD = V3((1056.4, 0, 1825.8))
SUNDAL_PLACE = V3((1056.4, 0, 1821.8))
SUNDAL = V3((1058.2, 0, 1822.6))
# East Tank Square Street, the temple side: Meena is asking everyone for her Paati.
TEMPLE_ROAD = V3((1131.2, 0, 1705.3))
TEMPLE_PLACE = V3((1132.7, 0, 1717.9))
MEENA = V3((1132.7, 0, 1681.2))  # tank side: open sky and water behind her, no tree canopy
# Meena's new home on RK Mutt Road corner: the green gate, two minutes from the tank.
HOME_ROAD = V3((952.1, 0, 1806.6))
HOME_PLACE = V3((950.6, 0, 1810.2))

stages = [
    dict(id="intro", kind="cutscene", objective_key="SQ04_INTRO", cutscene_id="intro", duration_s=40.0),
    dict(id="ask_flower", kind="ask", objective_key="SQ04_ASK_FLOWER", target=FLOWER_ROAD, radius_m=9.0,
         place_key="SQ04_P_STALL", place_pos=FLOWER_PLACE),
    dict(id="flowers", kind="cutscene", objective_key="SQ04_FLOWERS", cutscene_id="flowers", duration_s=16.0),
    dict(id="guess", kind="dialogue", objective_key="SQ04_GUESS", choices=PSA(["SQ04_TANK", "SQ04_MARKET"]),
         next_by_choice={"SQ04_TANK": "tank_line", "SQ04_MARKET": "market_line"}),
    dict(id="market_line", kind="cutscene", objective_key="SQ04_MARKET_LINE", cutscene_id="market_line", duration_s=10.0,
         next_id="ask_sundal"),
    dict(id="tank_line", kind="cutscene", objective_key="SQ04_TANK_LINE", cutscene_id="tank_line", duration_s=8.0),
    dict(id="ask_sundal", kind="ask", objective_key="SQ04_ASK_SUNDAL", target=SUNDAL_ROAD, radius_m=9.0,
         place_key="SQ04_P_TANK", place_pos=SUNDAL_PLACE),
    dict(id="sundal", kind="cutscene", objective_key="SQ04_SUNDAL", cutscene_id="sundal", duration_s=16.0),
    dict(id="spot_meena", kind="spot", objective_key="SQ04_FIND_MEENA", target=TEMPLE_ROAD, radius_m=80.0,
         spot_pos=V3((MEENA[0], 0.8, MEENA[2])), spot_range_m=40.0, spot_max_kmh=15.0, shrink_after_s=70.0,
         shrink_radius_m=38.0, place_key="SQ04_P_TEMPLE", place_pos=TEMPLE_PLACE),
    dict(id="reunion", kind="cutscene", objective_key="SQ04_REUNION", cutscene_id="reunion", duration_s=30.0),
    dict(id="ride_home", kind="goto", objective_key="SQ04_HOME", target=HOME_ROAD, radius_m=8.0, quality_key="comfort",
         place_key="SQ04_P_HOME", place_pos=HOME_PLACE),
    dict(id="home", kind="cutscene", objective_key="SQ04_AT_HOME", cutscene_id="home", duration_s=12.0),
    dict(id="payoff", kind="dialogue", objective_key="SQ04_PAYOFF", choices=PSA(["SQ04_TAKE_FARE", "SQ04_REFUSE_FARE"])),
    dict(id="thanks", kind="cutscene", objective_key="SQ04_THANKS", cutscene_id="thanks", duration_s=14.0),
]

FRONT = [2.1, 1.4, 7.2]          # front three-quarter of the auto, driver in view
FRONT_TO = [1.6, 1.35, 6.6]
AUTO_LOOK = [0.0, 1.05, 0.4]
BOARD_CAM = [-5.6, 1.6, 1.8]
# Paati in the back seat. She sits right of centre (QuestRider.PASSENGER_HIP), so from the kerb
# side the driver hides her: film her through the road-side opening.
SEAT_CAM = [2.3, 1.3, 0.4]
SEAT_CAM_TO = [2.1, 1.28, 0.2]
# In front of the auto, a little out into the road, looking back at someone at the kerb-side door.
# (The flower stall's shop front fills the kerb, so no camera stands on the kerb there.)
DOOR_CAM = [0.9, 1.55, 4.0]
DOOR_CAM_TO = [0.7, 1.52, 3.6]
# Valli talks to Paati at the back of the auto, out of the seat shot.
VALLI_AT_AUTO = [-1.9, 0, -0.9]
# Paati standing on the kerb beside the auto, and shots of her there (never framed "from" her:
# from beside the auto that would put the lens inside the canopy).
PAATI_OUT = [-1.9, 0, 0.9]
OUT_FRONT = [-4.2, 1.35, 4.2]     # kerb, ahead of her, auto in frame
OUT_FRONT_TO = [-3.9, 1.35, 3.8]
OUT_BACK = [-1.4, 1.55, -2.3]     # over the auto's rear corner, looking forward at her
OUT_SIDE = [-4.3, 1.35, -0.6]
# At the green gate: Paati by the door, Meena 2 m ahead, both on the kerb facing the auto. Cameras
# stand in the road ahead of the auto, so both faces show and the house stays behind them.
HOME_PAATI = [-2.0, 0, 0.0]
HOME_MEENA = [-2.0, 0, 2.0]
HOME_MID = [-2.0, 1.3, 1.0]
HOME_TWO = [0.9, 1.55, 6.2]
HOME_TWO_TO = [0.7, 1.5, 5.8]
HOME_PAATI_CAM = [0.2, 1.5, 4.2]
HOME_MEENA_CAM = [0.4, 1.5, 5.4]

cutscenes = {
    # She gets up from her thinnai and walks to the auto (QuestRider boards her) while she talks.
    "intro": [
        {"fade_in": 0.6, "cam": {"eye": {"from": "rider", "dist": 4.6, "up": 1.45, "side": 1.8}, "look": "rider", "fov": 44},
         # She comes up to the kerb-side door and stands there to talk; she gets in after "hop in".
         "rider": {"out": PAATI_OUT, "face": "auto"}, "line": "sq04_p01", "line_at": 0.5},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq04_d01"},
        {"cam": {"eye": OUT_FRONT, "eye_to": OUT_FRONT_TO, "look": "rider", "fov": 44}, "line": "sq04_p02"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 46}, "line": "sq04_d02"},
        {"cam": {"eye": OUT_BACK, "look": "rider", "fov": 42}, "line": "sq04_p03"},
        {"cam": {"eye": OUT_SIDE, "look": "rider", "fov": 40}, "line": "sq04_p04"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq04_d03"},
        {"cam": {"eye": BOARD_CAM, "look": "rider", "fov": 50}, "rider": {"in": True}, "wait": "rider", "min_s": 1.2, "max_s": 20.0},
        {"cam": {"eye": BOARD_CAM, "look": AUTO_LOOK, "fov": 50}, "min_s": 0.8, "fade_out": 0.5},
    ],
    # Valli recognises her from the morning and comes over to the auto.
    "flowers": [
        {"cam": {"cockpit": True, "look": "role:valli", "fov": 60}, "act": {"valli": {"face": "auto", "anim": "wave"}}, "min_s": 1.3},
        {"cam": {"eye": DOOR_CAM, "eye_to": DOOR_CAM_TO, "look": "role:valli", "fov": 50},
         "act": {"valli": {"to": VALLI_AT_AUTO, "gait": "walk", "then": "talk", "face": "rider"}},
         "line": "sq04_v01", "line_at": 0.5, "wait": "valli", "max_s": 8.0},
        {"cam": {"eye": SEAT_CAM, "eye_to": SEAT_CAM_TO, "look": "rider", "fov": 42}, "line": "sq04_p09"},
        {"cam": {"eye": DOOR_CAM, "look": "role:valli", "fov": 42}, "act": {"valli": {"anim": "talk"}}, "line": "sq04_v02"},
        {"cam": {"eye": SEAT_CAM, "look": "rider", "fov": 40}, "line": "sq04_p10", "hold": True},
    ],
    "market_line": [
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 46}, "line": "sq04_d04"},
        {"cam": {"eye": SEAT_CAM, "eye_to": SEAT_CAM_TO, "look": "rider", "fov": 40}, "line": "sq04_p11"},
        {"cam": {"eye": DOOR_CAM, "look": "role:valli", "fov": 46}, "act": {"valli": {"anim": "wave", "face": "auto"}},
         "line": "sq04_v03", "fade_out": 0.4},
    ],
    "tank_line": [
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 46}, "line": "sq04_d05"},
        {"cam": {"eye": SEAT_CAM, "look": "rider", "fov": 40}, "line": "sq04_p12"},
        {"cam": {"eye": DOOR_CAM, "look": "role:valli", "fov": 46}, "act": {"valli": {"anim": "wave", "face": "auto"}},
         "line": "sq04_v03", "fade_out": 0.4},
    ],
    # The old sundal seller on the tank side: he saw her this morning, and Meena ten minutes ago.
    "sundal": [
        {"cam": {"cockpit": True, "look": "role:sundal", "fov": 58}, "act": {"sundal": {"face": "auto", "anim": "wave"}}, "min_s": 1.3},
        {"cam": {"eye": {"from": "role:sundal", "dist": 4.0, "up": 1.5, "side": 1.5}, "look": "role:sundal", "fov": 42},
         "act": {"sundal": {"anim": "talk", "face": "auto"}}, "line": "sq04_s01"},
        {"cam": {"eye": SEAT_CAM, "eye_to": SEAT_CAM_TO, "look": "rider", "fov": 40}, "line": "sq04_p15"},
        {"cam": {"eye": {"from": "role:sundal", "dist": 3.0, "up": 1.5, "side": -1.2}, "look": "role:sundal", "fov": 38},
         "act": {"sundal": {"anim": "talk"}}, "line": "sq04_s03"},
        {"cam": {"eye": SEAT_CAM, "look": "rider", "fov": 38}, "line": "sq04_p16", "fade_out": 0.4},
    ],
    # Meena sees the auto, and Paati gets out to meet her.
    "reunion": [
        # Through the windscreen: tree canopies have no collider, so a shot framed on her from the
        # street could end up inside one.
        {"fade_in": 0.4, "cam": {"cockpit": True, "look": "role:meena", "fov": 50},
         "act": {"meena": {"face": "auto", "anim": "wave"}}, "line": "sq04_m01", "line_at": 0.3, "min_s": 1.6},
        {"min_s": 0.6, "fade_out": 0.5},
        {"fade_in": 0.7,
         "rider": {"out": PAATI_OUT, "now": True, "face": "role:meena"},
         "act": {"meena": {"at": [-2.5, 0, 2.3], "anim": "talk", "face": "rider"}},
         "cam": {"eye": [-4.4, 1.35, 3.6], "eye_to": [-4.1, 1.35, 3.3], "look": "role:meena", "fov": 48}, "line": "sq04_m02"},
        {"cam": {"eye": OUT_BACK, "look": "rider", "fov": 42}, "line": "sq04_p21"},
        {"cam": {"eye": [-3.6, 1.45, 4.6], "look": "role:meena", "fov": 38}, "act": {"meena": {"anim": "talk"}}, "line": "sq04_m03"},
        {"cam": {"eye": OUT_SIDE, "look": "rider", "fov": 42}, "rider": {"face": "auto"}, "line": "sq04_p22"},
        {"cam": {"eye": [-3.6, 1.45, 4.6], "look": "role:meena", "fov": 38}, "act": {"meena": {"anim": "talk", "face": "auto"}}, "line": "sq04_m04"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq04_d06"},
        {"cam": {"eye": BOARD_CAM, "look": AUTO_LOOK, "fov": 50}, "rider": {"in": True},
         "act": {"meena": {"to": "door", "gait": "walk"}}, "wait": "rider", "min_s": 1.5, "max_s": 9.0},
        {"cam": {"eye": BOARD_CAM, "look": AUTO_LOOK, "fov": 50}, "act": {"meena": {"show": False}}, "min_s": 0.7, "fade_out": 0.4},
    ],
    # The green gate: both get out and stand side by side on the kerb, Paati by the door and Meena
    # two metres ahead of her, both facing the auto. Every shot here is from the road in front of
    # the auto, so the house and its compound wall are always BEHIND them (Nov 27 device report:
    # Meena stood behind the gate and the camera looked at the back of Paati's head).
    "home": [
        {"fade_in": 0.5, "rider": {"out": HOME_PAATI, "face": "auto"},
         "act": {"meena": {"at": "door", "to": HOME_MEENA, "then": "talk", "face": "auto", "show": True}},
         "cam": {"eye": HOME_TWO, "eye_to": HOME_TWO_TO, "look": HOME_MID, "fov": 52}, "line": "sq04_m06", "line_at": 0.8},
        {"cam": {"eye": HOME_PAATI_CAM, "look": "rider", "fov": 42}, "wait": "rider", "max_s": 6.0, "line": "sq04_p25"},
        {"cam": {"eye": HOME_MEENA_CAM, "look": "role:meena", "fov": 42}, "act": {"meena": {"anim": "talk", "face": "auto"}},
         "line": "sq04_m07"},
        # The fare choice: both of them in one frame.
        {"cam": {"eye": HOME_TWO, "look": HOME_MID, "fov": 52}, "rider": {"face": "auto"},
         "act": {"meena": {"anim": "idle", "face": "auto"}}, "min_s": 0.6, "hold": True},
    ],
    "thanks": [
        {"if_choice": ["payoff", "SQ04_REFUSE_FARE"], "cam": {"eye": HOME_PAATI_CAM, "look": "rider", "fov": 40},
         "line": "sq04_p26"},
        {"if_choice": ["payoff", "SQ04_TAKE_FARE"], "cam": {"eye": HOME_MEENA_CAM, "look": "role:meena", "fov": 42},
         "act": {"meena": {"anim": "talk"}}, "line": "sq04_m08"},
        {"cam": {"eye": HOME_PAATI_CAM, "look": "rider", "fov": 40}, "line": "sq04_p27"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 46}, "line": "sq04_d07"},
        {"cam": {"eye": HOME_TWO, "look": HOME_MID, "fov": 54},
         "rider": {"walk": "place:ride_home", "face": "auto"}, "act": {"meena": {"to": "place:ride_home", "gait": "walk"}},
         "min_s": 3.4, "fade_out": 0.6},
        {"rider": {"show": False}, "act": {"meena": {"show": False}}, "min_s": 0.1},
    ],
}

def decoy(model, at, scale=1.0, paint=NONE):
    return {"model": PEOPLE + model, "scale": scale, "paint": paint, "world": at, "face": TEMPLE_ROAD, "anim": "idle",
            "stages": PSA(["spot_meena"]), "decoy_for": "spot_meena"}


cast = {
    "valli": {"model": PEOPLE + "woman_saree_maroon.glb", "scale": 1.0, "paint": NONE, "world": VALLI, "face": FLOWER_ROAD,
              "anim": "idle", "stages": PSA(["ask_flower", "flowers", "guess", "market_line", "tank_line"])},
    "watchman": {"model": PEOPLE + "old_man_veshti.glb", "scale": 1.0, "paint": NONE, "world": WATCHMAN, "face": V3((735.0, 0, 1797.4)),
                 "anim": "idle", "stages": PSA(["ask_flower"]), "line": "sq04_w01", "reply": "sq04_p08", "near_m": 10.0},
    "sundal": {"model": PEOPLE + "old_man_veshti.glb", "scale": 1.0, "paint": NONE, "world": SUNDAL, "face": SUNDAL_ROAD,
               "anim": "idle", "stages": PSA(["ask_sundal", "sundal", "spot_meena"])},
    # Meena: the only rose-pink churidar in the city. Her own baked copy of the street model
    # (tools/assets/make_meena.py), not a PaintSwap: in the city the GL Compatibility renderer can
    # run out of instance-uniform slots and a repaint then silently shows the stock dress (Nov 20:
    # a "yellow" Meena rendered green, and green churidars walk every street).
    "meena": {"model": PEOPLE + "quest/meena.glb", "scale": 1.04, "paint": NONE, "world": MEENA, "face": TEMPLE_ROAD,
              "anim": "talk", "stages": PSA(["spot_meena"]), "target_for": "spot_meena"},
    # Look-alikes in their own colours: the street's green churidar, a girl in a pink pavadai, an
    # office coat and a violet saree.
    "green_churidar": decoy("girl_churidar.glb", V3((1135.8, 0, 1665.5))),
    "pavadai_girl": decoy("girl_pavadai.glb", V3((1130.4, 0, 1693.0)), 0.9),
    "office_coat": decoy("woman_coat.glb", V3((1135.0, 0, 1706.1))),
    "violet_saree": decoy("woman_saree_violet.glb", V3((1139.6, 0, 1682.6))),
}

barks = {
    "ask_flower": {"enter": ["sq04_p05"], "idle": ["sq04_p06", "sq04_p07"], "idle_s": V2((26.0, 40.0)), "impact": "sq04_p14"},
    "ask_sundal": {"enter": ["sq04_p13"], "idle": ["sq04_p06", "sq04_p07"], "idle_s": V2((26.0, 40.0)), "impact": "sq04_p14"},
    "spot_meena": {"enter": ["sq04_p28"], "idle": ["sq04_p18"], "idle_s": V2((24.0, 36.0)), "hint": ["sq04_p29"],
                   "hint_after_s": 40.0, "wrong": "sq04_p20"},
    "ride_home": {"enter": ["sq04_m05", "sq04_p23"], "impact": "sq04_p14", "jolt": "sq04_p24"},
}

speakers = {"p": "VO_SPK_PAATI", "d": "VO_SPK_DRIVER", "v": "VO_SPK_VALLI", "w": "VO_SPK_WATCHMAN",
            "s": "VO_SPK_SUNDAL", "m": "VO_SPK_MEENA"}

write_story("sq_004", "res://assets/audio/voice/sq04", speakers, cast, {}, cutscenes, barks)
write_mission("sq_004", stages, [
    ("content_version", 3), ("title_key", "SQ04_TITLE"), ("description_key", "SQ04_DESC"), ("job_key", "SQ04_JOB"),
    ("discoverable", True), ("start_anchor", START), ("estimated_minutes", 12), ("category", "exploration"),
    ("reward_inr", 180), ("reward_xp", 25), ("rider_model", "res://assets/models/people/quest/paati.glb"),
    ("rider_name_key", "SQ04_RIDER"), ("reward_choice_stage", "payoff"),
    ("reward_choice_inr", {"SQ04_TAKE_FARE": 180, "SQ04_REFUSE_FARE": 0}), ("reward_choice_xp", {"SQ04_REFUSE_FARE": 40})])
print("wrote sq_004.tres and sq_004_story.tres")
