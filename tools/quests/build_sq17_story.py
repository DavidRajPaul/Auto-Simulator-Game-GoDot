"""Writes data/missions/side_quests/sq_017.tres, data/missions/stories/sq_017_story.tres,
docs/voice/SQ17_Monsoon_Voice_Script.md and the SQ17 / VO_SQ17 rows of translations/ui.csv.

"The Monsoon Supply Run" (v3, Nov 28 owner request: more side quests with cutscenes and dialogue).

Story: the rain has not stopped, the relief lorry is stuck in water up to its axle, and Vasanthi
Madam at the relief store has three bundles (rice, water cans, biscuits) and one auto. Rafiq loads
them ("who packs the biscuits in a rice sack?"). Jeyaraj the flood watchman reads the flood sign for
the driver in his own units (his own knee) and warns that the junction is chest deep, whatever the
forwards say. Then the driver chooses who gets the bundles first: Maragatham Paati's shelter (forty
people, one stove, one rule: everyone gets a share, nobody gets two) or Pooja at the relief desk
(three hundred people took biscuits, two filled the form, and signing the rice receipt makes you a
volunteer).

The drive is unchanged: cargo that gets wet loses quality in the rain (weather loss), the flooded
junction fails the run, the shelter takes two bundles and the desk one, in the order the player picks
(205 Rs + 20 XP). Everyone wears QuestWear items (specs and clipboard, a steel glass, an umbrella and
a towel, jasmine, a pencil) so they read as themselves.

LINES is the one source for every voiced line (subtitles + voice script; the Generate quest voices
workflow voices any line without a file). Run from the repo root: python3 tools/quests/build_sq17_story.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from story_common import (back_to, check_lines, driver, hold_on, street, talk, two, update_ui_csv,  # noqa: E402
                          voice_script, walk_up)
import build_flood  # noqa: E402
from story_tres import NONE, PEOPLE, PSA, V2, V3, write_mission, write_story  # noqa: E402

START = V3((394.4, 0, -190.8))   # the relief store, Goudia Mutt Road
STORE_PLACE = V3((399.3, 0, -197.0))
SIGN = V3((360.9, 0, -146.9))
SIGN_PLACE = V3((364.5, 0, -145.7))
SHELTER = V3((327.4, 0, -202.5))
SHELTER_PLACE = V3((327.0, 0, -198.4))
DESK = V3((476.1, 0, -209.0))
DESK_PLACE = V3((479.0, 0, -213.5))
AVOID = V3((412.8, 0, -253.6))   # the flooded junction
# Where the people stand: clear kerb spots checked against the buildings and the road edge.
VASANTHI = V3((400.1, 0, -195.7))
RAFIQ = V3((395.2, 0, -194.9))
JEYARAJ = V3((365.5, 0, -147.4))   # beside the flood board, not behind it (the board has no collider)
MARAGATHAM = V3((328.5, 0, -198.4))
POOJA = V3((480.5, 0, -213.5))
# The flood (build_flood.py): circles (x, z, radius) round every place and the streets between
# them, and the deep water at the junction the quest tells you to avoid (x, z, radius, depth).
FLOOD_AREAS = [(394.4, -190.8, 70.0), (360.9, -146.9, 50.0), (327.4, -202.5, 60.0), (476.1, -209.0, 65.0),
               (412.8, -253.6, 45.0), (360.0, -196.0, 50.0), (435.0, -200.0, 55.0), (403.0, -222.0, 45.0)]
FLOOD_BASINS = [(412.8, -253.6, 13.0, 0.42)]
FLOOD_FILE = "res://data/missions/floods/sq_017.json"

SHELTER_C, DESK_C = "SQ17_SHELTER", "SQ17_DESK"

# (id, speaker, voice tags, English, Tamil). Letters after "sq17_": v Vasanthi, r Rafiq, j Jeyaraj,
# m Maragatham, p Pooja, d driver.
LINES = [
    # Intro at the relief store.
    ("sq17_v01", "Vasanthi", "[relieved, brisk]", "An auto! Thank God. The lorry is stuck in water up to its axle, and the people cannot wait.",
     "ஆட்டோ! கடவுளே. லாரி அச்சு வரைக்கும் தண்ணியில மாட்டிக்கிச்சு, மக்கள் காத்திருக்க முடியாது."),
    ("sq17_d01", "Driver", "[ready]", "Madam, what do you need me to carry?",
     "மேடம், நான் என்ன எடுத்துட்டுப் போகணும்?"),
    ("sq17_v02", "Vasanthi", "[clear, businesslike]", "Three bundles of rice, water cans and biscuits. Two for the shelter, one for the relief desk. You decide which goes first.",
     "அரிசி, தண்ணி கேன், பிஸ்கட்னு மூணு மூட்டை. ரெண்டு முகாமுக்கு, ஒண்ணு உதவி மேசைக்கு. எது முதல்லன்னு நீ முடிவு பண்ணு."),
    ("sq17_r01", "Rafiq", "[shouting from the store, cheerful]", "Madam, who packed the biscuits in a rice sack? Now I don't know which sack is which!",
     "மேடம், பிஸ்கட்டை அரிசிச் சாக்குல யார் அடைச்சது? இப்போ எந்தச் சாக்கு எதுன்னே தெரியல!"),
    ("sq17_v03", "Vasanthi", "[patient, dry]", "Rafiq, the one that rattles is the biscuits.",
     "ரஃபீக், சத்தம் போடறது பிஸ்கட்."),
    ("sq17_d02", "Driver", "[concerned]", "Madam, is the road flooded?",
     "மேடம், ரோடு தண்ணியில மூழ்கியிருக்கா?"),
    ("sq17_v04", "Vasanthi", "[serious]", "Near the junction, yes. The watchman will show you. Keep the bundles dry. Wet rice is not rice, it is porridge.",
     "ஜங்ஷன் பக்கம் ஆமா. வாட்ச்மேன் காட்டுவாரு. மூட்டை நனையாம பாத்துக்கோ. நனைஞ்ச அரிசி அரிசி இல்ல, கஞ்சி."),
    ("sq17_d03", "Driver", "[dry]", "And wet biscuits are not biscuits either.",
     "நனைஞ்ச பிஸ்கட்டும் பிஸ்கட் இல்ல."),
    ("sq17_v05", "Vasanthi", "[heartfelt]", "Wet biscuits are a tragedy. Go carefully, thambi.",
     "நனைஞ்ச பிஸ்கட் ஒரு சோகம். கவனமாப் போ தம்பி."),
    # Driving barks.
    ("sq17_d04", "Driver", "[amused, to the cargo]", "Rice on the left, biscuits on the right. Nobody fight.",
     "அரிசி இடது பக்கம், பிஸ்கட் வலது பக்கம். யாரும் சண்டை போடாதீங்க."),
    ("sq17_d05", "Driver", "[focused]", "Slow and steady. Wet road, dry biscuits.",
     "மெதுவா நிதானமா. ஈர ரோடு, காய்ஞ்ச பிஸ்கட்."),
    ("sq17_d06", "Driver", "[wry]", "Water everywhere. Chennai turns into a swimming pool by four o'clock.",
     "எங்க பாத்தாலும் தண்ணி. சென்னை நாலு மணிக்குள்ள நீச்சல் குளமாயிடும்."),
    ("sq17_d07", "Driver", "[pleading]", "Please don't rattle, biscuits. We are almost there.",
     "பிஸ்கட்டுகளே சத்தம் போடாதீங்க. கிட்டத்தட்ட வந்துட்டோம்."),
    ("sq17_d08", "Driver", "[alarmed]", "Ayyo, the bundles! Sorry, sorry!",
     "அய்யோ, மூட்டை! சாரி, சாரி!"),
    ("sq17_d09", "Driver", "[reading ahead]", "A flood sign ahead. Let me read it before the road reads me.",
     "முன்னால வெள்ளப் பலகை. ரோடு என்னைப் படிக்கறதுக்கு முன்னாடி நான் அதைப் படிக்கறேன்."),
    # The flood watchman at the sign.
    ("sq17_j01", "Jeyaraj", "[calling out through the rain]", "Stop, thambi, stop! Don't squint at the board, I will tell you. Water, knee deep. My knee, not yours. Mine is lower.",
     "நில்லு தம்பி நில்லு! பலகையைப் பாத்து கண்ணைச் சுருக்காத, நான் சொல்றேன். தண்ணி, முழங்கால் அளவு. என் முழங்கால், உன்னது இல்ல. என்னோடது கொஞ்சம் குட்டை."),
    ("sq17_d10", "Driver", "[serious]", "Sir, is the road closed?",
     "சார், ரோடு மூடியிருக்கா?"),
    ("sq17_j02", "Jeyaraj", "[dry, solemn]", "Closed for the lorry, open for the brave. But a bundle of rice drowns faster than a hero. Do not be brave today.",
     "லாரிக்கு மூடியிருக்கு, தைரியசாலிக்குத் திறந்திருக்கு. ஆனா ஒரு அரிசி மூட்டை ஹீரோவை விட வேகமா மூழ்கும். இன்னைக்கு தைரியம் காட்டாத."),
    ("sq17_d11", "Driver", "[practical]", "So which way do I go?",
     "அப்போ எந்தப் பக்கம் போறது?"),
    ("sq17_j03", "Jeyaraj", "[firm, then amused]", "Follow the route on your map and keep far from the junction. Chest deep there. Don't trust the forwards; they say neck deep. Forwards always exaggerate.",
     "உன் மேப்புல இருக்கற வழியில போ, ஜங்ஷன்கிட்ட போகாத. அங்கே மார்பளவு தண்ணி. ஃபார்வர்டுகளை நம்பாத, அவங்க கழுத்தளவுன்னு சொல்லுவாங்க. ஃபார்வர்டு எப்பவுமே பெருசாத்தான் சொல்லும்."),
    ("sq17_j04", "Jeyaraj", "[reminiscing]", "Thirty years I have watched this junction. When it rains four times, it floods three. The fourth time it floods out of habit.",
     "முப்பது வருஷமா இந்த ஜங்ஷனைப் பாக்கறேன். நாலு தடவை மழை பெஞ்சா மூணு தடவை தண்ணி நிக்கும். நாலாவது தடவை பழக்கத்துக்காக நிக்கும்."),
    ("sq17_d12", "Driver", "[smiling]", "Sir, you are very reassuring.",
     "சார், நீங்க ரொம்ப ஆறுதலா பேசறீங்க."),
    ("sq17_j05", "Jeyaraj", "[kind, resigned]", "I am a watchman. My job is worrying. Go, and come back dry.",
     "நான் வாட்ச்மேன். கவலைப்படறதுதான் என் வேலை. போ, காஞ்சு திரும்பி வா."),
    # The shelter: Maragatham Paati.
    ("sq17_m01", "Maragatham", "[commanding, warm]", "The auto has come! Vasanthi rang to say supplies were on the way. I told her, I have forty people and one stove. Everything is on the way.",
     "ஆட்டோ வந்துடுச்சு! சப்ளை வருதுன்னு வசந்தி போன் பண்ணா. நான் சொன்னேன், என்கிட்ட நாப்பது பேரு, ஒரு அடுப்பு. எல்லாமே வழியில தான் இருக்கு."),
    ("sq17_d13", "Driver", "[handing over]", "Paati, here are the bundles. Rice, water and biscuits.",
     "பாட்டி, இந்தாங்க மூட்டை. அரிசி, தண்ணி, பிஸ்கட்."),
    ("sq17_m02", "Maragatham", "[delighted]", "Rice, finally! And biscuits. The children have been fighting since morning over which kind would come.",
     "அரிசி, கடைசியா! பிஸ்கட்டும். எந்த வகை வரும்னு காலையில இருந்து புள்ளைங்க சண்டை போடுதுங்க."),
    ("sq17_m03", "Maragatham", "[stern]", "In this shelter I have one rule. Everyone gets a share, nobody gets two. Even the driver. Take a biscuit.",
     "இந்த முகாமுல எனக்கு ஒரே விதி. எல்லாருக்கும் ஒரு பங்கு, யாருக்கும் ரெண்டு இல்ல. டிரைவருக்கும்தான். ஒரு பிஸ்கட் எடுத்துக்கோ."),
    ("sq17_d14", "Driver", "[polite]", "Paati, I am on duty. I cannot.",
     "பாட்டி, நான் டியூட்டியில இருக்கேன். முடியாது."),
    ("sq17_m04", "Maragatham", "[firm]", "Rules are rules. Eat.",
     "விதின்னா விதிதான். சாப்பிடு."),
    ("sq17_d15", "Driver", "[mouth full, surprised]", "... Paati, this is very good.",
     "... பாட்டி, இது ரொம்ப நல்லா இருக்கு."),
    ("sq17_m05", "Maragatham", "[smiling, waving him on]", "Go on, thambi. Other people are waiting for you. And thank you, truly.",
     "போ தம்பி. மத்தவங்களும் உனக்காகக் காத்திருக்காங்க. உண்மையிலேயே நன்றி."),
    # The relief desk: Pooja.
    ("sq17_p01", "Pooja", "[flustered, fast]", "Auto, auto! Supplies! One second, where is the form? It is under the biscuits. The biscuits are under the form.",
     "ஆட்டோ, ஆட்டோ! சப்ளை! ஒரு நிமிஷம், ஃபார்ம் எங்கே? பிஸ்கட்டுக்குக் கீழ இருக்கு. பிஸ்கட் ஃபார்முக்குக் கீழ இருக்கு."),
    ("sq17_d16", "Driver", "[calm]", "Madam, one bundle, as promised.",
     "மேடம், ஒரு மூட்டை, சொன்ன மாதிரி."),
    ("sq17_p02", "Pooja", "[exhausted, funny]", "Thank you, thank you! Do you know how many came for relief today? Three hundred. How many filled the form? Two. How many took biscuits? Three hundred.",
     "நன்றி, நன்றி! இன்னைக்கு எத்தனை பேரு நிவாரணத்துக்கு வந்தாங்கன்னு தெரியுமா? முந்நூறு பேரு. எத்தனை பேரு ஃபார்ம் நிரப்பினாங்க? ரெண்டு பேரு. எத்தனை பேரு பிஸ்கட் எடுத்தாங்க? முந்நூறு பேரு."),
    ("sq17_p03", "Pooja", "[quick]", "Sign here. Here. Not there, that is the volunteer sheet. Oh no. Now you are a volunteer.",
     "இங்க கையெழுத்துப் போடுங்க. இங்க. அங்க இல்ல, அது வாலண்டியர் ஷீட். அய்யோ. இப்போ நீங்களும் வாலண்டியர்."),
    ("sq17_d17", "Driver", "[amused]", "Madam, I only signed for the rice.",
     "மேடம், நான் அரிசிக்குத்தான் கையெழுத்துப் போட்டேன்."),
    ("sq17_p04", "Pooja", "[grinning]", "Volunteer. Congratulations. There is no pay, but there is tea.",
     "வாலண்டியர். வாழ்த்துகள். சம்பளம் இல்ல, ஆனா டீ இருக்கு."),
    ("sq17_p05", "Pooja", "[grateful, warm]", "Go, go. Tell Vasanthi madam we are fine. And thank you, really.",
     "போங்க போங்க. வசந்தி மேடத்துக்குச் சொல்லுங்க, நாங்க நல்லா இருக்கோம்னு. உண்மையிலேயே நன்றி."),
    # Ending.
    ("sq17_d18", "Driver", "[quiet, proud]", "Three bundles, forty people, one stove, one rule. Chennai does not need a lorry. It needs a stubborn auto. And the biscuits did not rattle once.",
     "மூணு மூட்டை, நாப்பது பேரு, ஒரு அடுப்பு, ஒரு விதி. சென்னைக்கு லாரி வேணாம். பிடிவாதமான ஒரு ஆட்டோ போதும். பிஸ்கட் ஒரு தடவை கூட சத்தம் போடல."),
]

SPEAKER_KEYS = {"v": "VO_SPK_VASANTHI", "r": "VO_SPK_RAFIQ", "j": "VO_SPK_JEYARAJ", "m": "VO_SPK_MARAGATHAM",
                "p": "VO_SPK_POOJA", "d": "VO_SPK_DRIVER"}
SPEAKER_NAMES = {"VO_SPK_VASANTHI": ("Vasanthi Madam", "வசந்தி மேடம்"),
                 "VO_SPK_RAFIQ": ("Rafiq (volunteer)", "ரஃபீக் (தன்னார்வலர்)"),
                 "VO_SPK_JEYARAJ": ("Jeyaraj (flood watchman)", "ஜெயராஜ் (வெள்ள வாட்ச்மேன்)"),
                 "VO_SPK_MARAGATHAM": ("Maragatham Paati", "மரகதம் பாட்டி"),
                 "VO_SPK_POOJA": ("Pooja (relief desk)", "பூஜா (உதவி மேசை)")}

STRINGS = {
    "SQ17_INTRO": ("Vasanthi Madam at the relief store needs an auto.", "நிவாரணக் கிடங்கில் வசந்தி மேடத்துக்கு ஆட்டோ வேணும்."),
    "SQ17_WATCH": ("The flood watchman has a warning.", "வெள்ள வாட்ச்மேன் ஒரு எச்சரிக்கை சொல்கிறார்."),
    "SQ17_HANDOVER": ("Supplies handed over.", "பொருட்கள் சேர்ந்தன."),
}
RETIRED = []

def drive(stage_id, objective, first):
    """One of the two deliveries, exactly as v2 had them (the order the player picks decides which)."""
    shelter, desk = (SHELTER, DESK) if first else (DESK, SHELTER)
    shelter_p, desk_p = (SHELTER_PLACE, DESK_PLACE) if first else (DESK_PLACE, SHELTER_PLACE)
    st = dict(id=stage_id, kind="cargo", objective_key=objective, target=shelter, radius_m=9.0, target_choice_stage="order",
              target_options={SHELTER_C: shelter, DESK_C: desk}, cargo_delta=-2 if first else -1,
              cargo_delta_options={SHELTER_C: -2 if first else -1, DESK_C: -1 if first else -2}, deadline_s=250.0,
              quality_floor=15.0, weather_loss_per_s=0.25, quality_key="supplies",
              place_key="SQ17_P_SHELTER" if first else "SQ17_P_DESK", place_pos=shelter_p,
              place_options={SHELTER_C: "SQ17_P_SHELTER" if first else "SQ17_P_DESK",
                             DESK_C: "SQ17_P_DESK" if first else "SQ17_P_SHELTER"},
              place_pos_options={SHELTER_C: shelter_p, DESK_C: desk_p}, action_key="QUEST_ACT_GIVE")
    if first:
        st["avoid_center"] = AVOID
        st["avoid_radius_m"] = 8.0
    return st


stages = [
    dict(id="intro", kind="cutscene", objective_key="SQ17_INTRO", target=START, cutscene_id="intro", duration_s=60.0),
    dict(id="load", kind="cargo", objective_key="SQ17_LOAD", target=START, radius_m=9.0, cargo_delta=3,
         place_key="SQ17_P_STORE", place_pos=STORE_PLACE, action_key="QUEST_ACT_LOAD"),
    dict(id="warning", kind="inspect", objective_key="SQ17_WARNING", target=SIGN, radius_m=9.0, place_key="SQ17_P_SIGN",
         place_pos=SIGN_PLACE, action_key="QUEST_ACT_READ"),
    dict(id="watch", kind="cutscene", objective_key="SQ17_WATCH", cutscene_id="watch", duration_s=70.0),
    dict(id="order", kind="dialogue", objective_key="SQ17_ORDER", choices=PSA([SHELTER_C, DESK_C])),
    drive("first", "SQ17_FIRST", True),
    dict(id="first_drop", kind="cutscene", objective_key="SQ17_HANDOVER", cutscene_id="first_drop", duration_s=60.0),
    drive("second", "SQ17_SECOND", False),
    dict(id="second_drop", kind="cutscene", objective_key="SQ17_HANDOVER", cutscene_id="second_drop", duration_s=75.0),
]


def only_if(beats, cond):
    for b in beats:
        b["if_choice"] = ["order", cond]
    return beats


def shelter_scene(cond):
    return only_if(walk_up("maragatham", "sq17_m01", 0.5) + [
        driver("sq17_d13"),
        talk("maragatham", "sq17_m02", 36),
        talk("maragatham", "sq17_m03", 38),
        driver("sq17_d14"),
        talk("maragatham", "sq17_m04", 36, "drink"),
        driver("sq17_d15"),
        two("maragatham", "sq17_m05", 48, "wave"),
        back_to("maragatham", MARAGATHAM),
    ], cond)


def desk_scene(cond):
    return only_if(walk_up("pooja", "sq17_p01", 0.5) + [
        driver("sq17_d16"),
        talk("pooja", "sq17_p02", 36),
        talk("pooja", "sq17_p03", 38),
        driver("sq17_d17"),
        talk("pooja", "sq17_p04", 36),
        two("pooja", "sq17_p05", 48, "wave"),
        back_to("pooja", POOJA),
    ], cond)


cutscenes = {
    # Vasanthi at the store: three bundles, one auto, Rafiq calling from inside.
    "intro": walk_up("vasanthi", "sq17_v01", 0.5) + [
        driver("sq17_d01"),
        talk("vasanthi", "sq17_v02", 38),
        {"cam": street("rafiq", 54), "act": {"rafiq": {"face": "auto", "anim": "wave"}}, "line": "sq17_r01"},
        talk("vasanthi", "sq17_v03", 36),
        driver("sq17_d02"),
        talk("vasanthi", "sq17_v04", 38),
        driver("sq17_d03"),
        dict(two("vasanthi", "sq17_v05", 46), fade_out=0.8),
    ],
    # Jeyaraj reads the flood sign out loud, in his own knees. Ends held on the order choice.
    "watch": walk_up("jeyaraj", "sq17_j01", 0.5) + [
        driver("sq17_d10"),
        talk("jeyaraj", "sq17_j02", 38),
        driver("sq17_d11"),
        talk("jeyaraj", "sq17_j03", 36),
        talk("jeyaraj", "sq17_j04", 36),
        driver("sq17_d12"),
        two("jeyaraj", "sq17_j05", 46),
        hold_on("jeyaraj", 46),
    ],
    "first_drop": shelter_scene(SHELTER_C) + desk_scene(DESK_C),
    "second_drop": desk_scene(SHELTER_C) + shelter_scene(DESK_C) + [
        {"cam": {"eye": [2.1, 1.4, 7.2], "eye_to": [1.6, 1.35, 6.6], "look": [0.0, 1.05, 0.4], "fov": 48},
         "line": "sq17_d18", "fade_out": 0.8},
    ],
}

AT_STORE = ["intro", "load"]
AT_SIGN = ["warning", "watch", "order"]
AT_DROPS = ["first", "first_drop", "second", "second_drop"]

cast = {
    "vasanthi": {"model": PEOPLE + "woman_saree_kanchi.glb", "scale": 1.0, "world": VASANTHI, "face": START, "anim": "idle",
                 "wear": PSA(["specs", "clipboard"]), "stages": PSA(AT_STORE)},
    "rafiq": {"model": PEOPLE + "young_man.glb", "scale": 1.0, "world": RAFIQ, "face": START, "anim": "idle",
              "wear": PSA(["glass"]), "stages": PSA(AT_STORE)},
    "jeyaraj": {"model": PEOPLE + "old_man_veshti.glb", "scale": 0.97, "world": JEYARAJ, "face": SIGN, "anim": "idle",
                "wear": PSA(["umbrella", "towel"]), "stages": PSA(AT_SIGN)},
    "maragatham": {"model": PEOPLE + "woman_saree_green.glb", "scale": 0.96, "world": MARAGATHAM, "face": SHELTER, "anim": "idle",
                   "wear": PSA(["glass", "jasmine"]), "stages": PSA(AT_DROPS)},
    "pooja": {"model": PEOPLE + "girl_churidar.glb", "scale": 1.0, "world": POOJA, "face": DESK, "anim": "idle",
              "wear": PSA(["pencil", "clipboard"]), "stages": PSA(AT_DROPS)},
}
for c in cast.values():
    c["paint"] = NONE

barks = {
    "load": {"enter": ["sq17_d04"], "idle": ["sq17_d05", "sq17_d06"], "idle_s": V2((24.0, 38.0)), "impact": "sq17_d08",
             "jolt": "sq17_d08"},
    "warning": {"enter": ["sq17_d09"], "idle": ["sq17_d06", "sq17_d05"], "idle_s": V2((24.0, 38.0)), "impact": "sq17_d08",
                "jolt": "sq17_d08"},
    "first": {"enter": ["sq17_d05"], "idle": ["sq17_d06", "sq17_d07", "sq17_d04"], "idle_s": V2((22.0, 36.0)),
              "impact": "sq17_d08", "jolt": "sq17_d08"},
    "second": {"enter": ["sq17_d07"], "idle": ["sq17_d06", "sq17_d05", "sq17_d04"], "idle_s": V2((24.0, 38.0)),
               "impact": "sq17_d08", "jolt": "sq17_d08"},
}

check_lines(LINES, cutscenes, barks)

CAST_NOTES = [
    "- Vasanthi (Vasanthi Madam): runs the relief store, 50s, brisk, dry and kind.",
    "- Rafiq: a young volunteer loading bundles, cheerful, shouts from inside the store.",
    "- Jeyaraj: the flood watchman, 60s, gravelly, measures floods in his own knees, secretly a worrier.",
    "- Maragatham (Maragatham Paati): runs the shelter, 70s, commanding and warm, one rule for all.",
    "- Pooja: a young volunteer at the relief desk, 20s, flustered, fast and funny.",
    "- Driver (hero): the same locked voice as every quest.",
]

if __name__ == "__main__":
    write_story("sq_017", "res://assets/audio/voice/sq17", dict(SPEAKER_KEYS), cast, {}, cutscenes, barks)
    write_mission("sq_017", stages, [
        ("content_version", 3), ("title_key", "SQ17_TITLE"), ("description_key", "SQ17_DESC"), ("job_key", "SQ17_JOB"),
        ("discoverable", True), ("start_anchor", START), ("estimated_minutes", 8), ("category", "community"),
        ("reward_inr", 205), ("reward_xp", 20), ("scenario_weather", "rain"), ("scenario_flood", FLOOD_FILE)])
    build_flood.build("sq_017", FLOOD_AREAS, FLOOD_BASINS)
    voice_script("SQ17_Monsoon_Voice_Script.md", "The Monsoon Supply Run", "17", "build_sq17_story.py", CAST_NOTES, LINES)
    update_ui_csv(STRINGS, SPEAKER_NAMES, LINES, RETIRED)
    print("wrote sq_017.tres, sq_017_story.tres, the SQ17 voice script and ui.csv rows")
