"""Writes data/missions/side_quests/sq_002.tres, data/missions/stories/sq_002_story.tres,
docs/voice/SQ02_Filter_Coffee_Voice_Script.md and the SQ02 / VO_SQ02 rows of translations/ui.csv.

"Filter Coffee, No Spill" (v3, Nov 28 owner request: "add the cut scenes and dialogues … interesting,
funny and witty … NPC characters unique only for this quest … the shops must be easily identifiable
with the name board and look realistic").

Story: Kaapi Kannan runs Kannan Degree Coffee at a Luz junction and treats every tumbler like a
concert. Three regulars wait for theirs: Selvam the tailor (wedding season, the groom keeps growing),
Mohana Teacher at her book house (a retired Tamil teacher who corrects everyone and sells nothing),
and Murugan of Murugan Tea Stall, whose board says NO COFFEE. The driver picks the first shop, then
carries the coffee to all three against the clock while bumps and hard braking spill it (quality
"coffee", the old skill rules). At the tea stall the joke lands: the tea master drinks filter coffee in
secret. The player keeps his secret (respect XP) or teases him in front of the street (he pays ₹20
extra "for your acting").

The shops are QuestPlaceKit "coffee_bar", "tailors", "bookhouse", "tea_kadai" with painted boards
(tools/art/make_quest_signs.py). Each shopkeeper wears QuestWear items, so the street models read as
these people: Kannan carries a brass davara, Selvam has a tape round his neck and a pencil behind his
ear, Mohana wears spectacles and jasmine and holds a book, Murugan has a towel on his shoulder and a
steel glass.

LINES is the one source for every voiced line (subtitles + voice script; the Generate quest voices
workflow voices any line without a file). Run from the repo root: python3 tools/quests/build_sq02_story.py
"""
import csv
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from story_tres import NONE, PEOPLE, PSA, ROOT, V2, V3, write_mission, write_story  # noqa: E402
START = V3((634.3, 0, 1487.9))  # anchors.json: the Luz junction
# Kannan's coffee bar on the north corner of the junction, facing it.
COFFEE_PLACE = V3((634.3, 0, 1482.2))
KANNAN = V3((631.9, 0, 1483.4))
COFFEE_CUSTOMER = V3((636.9, 0, 1483.4))
# The three stops (unchanged from v2, so the routes and the validator stay as they were).
TAILOR_ROAD = V3((621.2, 0, 1592.8))
TAILOR_PLACE = V3((615.3, 0, 1593.3))
SELVAM = V3((616.9, 0, 1595.0))
BOOKS_ROAD = V3((742.3, 0, 1423.6))
BOOKS_PLACE = V3((743.3, 0, 1419.1))
MOHANA = V3((744.7, 0, 1421.0))
TEA_ROAD = V3((729.3, 0, 1297.6))
TEA_PLACE = V3((725.7, 0, 1301.0))
MURUGAN = V3((727.9, 0, 1301.1))
TEA_CUSTOMER = V3((725.0, 0, 1303.0))

# (id, speaker, voice tags, English, Tamil). Letters after "sq02_": k Kannan, d driver, s Selvam,
# m Mohana, r Murugan.
LINES = [
    # Intro at the coffee bar.
    ("sq02_k01", "Kannan", "[theatrical, delighted]", "Stop, stop! Thambi, you have been chosen.",
     "நில்லு நில்லு! தம்பி, உன்னைத் தேர்ந்தெடுத்தாச்சு."),
    ("sq02_d01", "Driver", "[wary]", "Chosen for what, anna? Last time someone said that, I paid for his petrol.",
     "எதுக்கு அண்ணா? போன தடவை இப்படிச் சொன்னவருக்கு நான்தான் பெட்ரோல் போட்டேன்."),
    ("sq02_k02", "Kannan", "[proud]", "Three filter coffees, three shops. Hot, with the foam on top, exactly as I made them.",
     "மூணு ஃபில்டர் காபி, மூணு கடை. சூடா, மேல நுரையோட, நான் போட்ட மாதிரியே போய்ச் சேரணும்."),
    ("sq02_k03", "Kannan", "[solemn, slow]", "Brake hard, the foam dies. Hit a pothole, the coffee dies. Spill it, and I die.",
     "திடீர்னு பிரேக் போட்டா நுரை போயிடும். பள்ளத்துல விட்டா காபி போயிடும். சிந்தினா, நானே போயிடுவேன்."),
    ("sq02_d02", "Driver", "[dry]", "Anna, it's coffee. Not a kidney transplant.",
     "அண்ணா, இது காபிதான். கிட்னி ஆபரேஷன் இல்ல."),
    ("sq02_k04", "Kannan", "[offended]", "Forty years of decoction, thambi. To me, both are the same.",
     "நாப்பது வருஷ டிகாக்ஷன், தம்பி. எனக்கு ரெண்டும் ஒண்ணுதான்."),
    ("sq02_k05", "Kannan", "[listing on his fingers]", "Selvam the tailor, Mohana Teacher at the book house, and Murugan at the tea stall.",
     "டெய்லர் செல்வம், புக் ஹவுஸ் மோகனா டீச்சர், டீக்கடை முருகன்."),
    ("sq02_d03", "Driver", "[confused]", "Wait. The tea stall orders coffee from you?",
     "இருங்க. டீக்கடைக்காரர் உங்ககிட்ட காபி வாங்குறாரா?"),
    ("sq02_k06", "Kannan", "[sly, quiet]", "Every single day. Ask no questions. Him last, always. Now, who gets theirs first?",
     "தினமும். கேள்வி கேக்காத. அவருக்கு எப்பவுமே கடைசி. சரி, முதல்ல யாருக்கு?"),
    # Driving barks (the driver talks to the coffee).
    ("sq02_d04", "Driver", "[to the coffee, soothing]", "Okay coffee, no drama. Sit tight.",
     "சரி காபி, டிராமா வேண்டாம். அமைதியா இரு."),
    ("sq02_d05", "Driver", "[concentrating]", "Smooth, smooth. I'm driving like there's an egg under the pedal.",
     "மெதுவா, மெதுவா. ஆக்ஸிலேட்டர் கீழ முட்டை வெச்ச மாதிரி ஓட்டுறேன்."),
    ("sq02_d06", "Driver", "[grumbling]", "Whoever invented speed breakers never carried filter coffee.",
     "ஸ்பீட் பிரேக்கர் கண்டுபிடிச்சவன் ஒருநாளும் ஃபில்டர் காபி தூக்கிட்டுப் போனதில்ல."),
    ("sq02_d07", "Driver", "[alarmed]", "Ayyo, the foam! Kannan anna felt that, I'm sure.",
     "அய்யோ, நுரை! கண்ணன் அண்ணனுக்கு இது தெரிஞ்சிருக்கும்."),
    ("sq02_d08", "Driver", "[apologetic]", "Sorry coffee, sorry coffee!",
     "சாரி காபி, சாரி காபி!"),
    ("sq02_d17", "Driver", "[encouraging]", "One down, two to go. Stay strong, coffee.",
     "ஒண்ணு முடிஞ்சுது, இன்னும் ரெண்டு. தைரியமா இரு, காபி."),
    ("sq02_d18", "Driver", "[amused]", "Coffee to a tea stall. Like taking a cricket bat to a football match.",
     "டீக்கடைக்கு காபி. ஃபுட்பால் மேட்சுக்கு கிரிக்கெட் பேட் எடுத்துட்டுப் போற மாதிரி."),
    # Selvam Tailors.
    ("sq02_s01", "Selvam", "[frantic, fast]", "Coffee! Finally! The wedding is tomorrow, the groom's shirt is today, and the groom just put on five kilos.",
     "காபி! கடைசியா! கல்யாணம் நாளைக்கு, மாப்பிள்ளை சட்டை இன்னைக்கு, மாப்பிள்ளை இப்போ அஞ்சு கிலோ ஏறிட்டாரு."),
    ("sq02_d09", "Driver", "[surprised]", "Five kilos in one week?",
     "ஒரே வாரத்துல அஞ்சு கிலோவா?"),
    ("sq02_s02", "Selvam", "[exasperated]", "Engagement sweets. Every relative brought a box, and he finished every box.",
     "நிச்சயதார்த்த ஸ்வீட். ஒவ்வொரு சொந்தக்காரரும் ஒரு பெட்டி கொண்டு வந்தாங்க. அவர் எல்லாப் பெட்டியையும் முடிச்சிட்டாரு."),
    ("sq02_s03", "Selvam", "[sips, calmer]", "Ahh, Kannan's coffee. My hands are steady again. Let him grow, I'll let out the seams.",
     "ஆஹா, கண்ணன் காபி. கை நடுக்கம் நின்னுடுச்சு. அவர் எவ்வளவு வேணா ஏறட்டும், நான் தையலை விட்டுக் கொடுக்கறேன்."),
    ("sq02_s04", "Selvam", "[waving you off]", "Go, go! And if you see a round groom on the road, drive the other way.",
     "போ போ! வழியில உருண்டையா ஒரு மாப்பிள்ளையைப் பார்த்தா, வேற பக்கம் ஓட்டு."),
    # Mohana Book House.
    ("sq02_m01", "Mohana", "[strict, schoolteacher]", "You are four minutes late. In my class, that meant standing outside.",
     "நாலு நிமிஷம் லேட். என் கிளாஸ்ல இருந்தா வெளியே நிக்க வேண்டியதுதான்."),
    ("sq02_d10", "Driver", "[sheepish]", "Sorry teacher. Traffic was very heavy-ah.",
     "சாரி டீச்சர். டிராஃபிக் ரொம்ப ஹெவியா இருந்துச்சு."),
    ("sq02_m02", "Mohana", "[correcting, precise]", "Heavy-ah? Say it properly. The traffic was heavy. Now give me my coffee.",
     "ஹெவியா? ஒழுங்கா சொல்லு. போக்குவரத்து நெரிசலா இருந்தது. சரி, என் காபியைக் கொடு."),
    ("sq02_d11", "Driver", "[curious]", "Teacher, how much for that book on the table?",
     "டீச்சர், டேபிள் மேல இருக்கிற அந்தப் புத்தகம் என்ன விலை?"),
    ("sq02_m03", "Mohana", "[as if it were obvious]", "That one? Not for sale. Nothing here is for sale. They are my books.",
     "அதுவா? விற்பனைக்கு இல்ல. இங்க எதுவுமே விற்பனைக்கு இல்ல. எல்லாம் என் புத்தகம்."),
    ("sq02_d12", "Driver", "[baffled]", "Then why is it a book shop?",
     "அப்புறம் இது ஏன் புத்தகக் கடை?"),
    ("sq02_m04", "Mohana", "[sipping, pleased]", "So people come and talk to me. Like you. Now go. Drive properly, and speak properly.",
     "ஆளுங்க வந்து என்கிட்ட பேசுவாங்கல்ல. உன்னை மாதிரி. சரி கிளம்பு. ஒழுங்கா ஓட்டு, ஒழுங்கா பேசு."),
    # Murugan Tea Stall.
    ("sq02_r01", "Murugan", "[loud, for the customers]", "Coffee? Here? Who ordered coffee at MY tea stall?",
     "காபியா? இங்கேயா? என் டீக்கடைக்கு யார் காபி ஆர்டர் பண்ணது?"),
    ("sq02_d13", "Driver", "[innocent]", "Kannan anna said… you did. Every day.",
     "கண்ணன் அண்ணன் சொன்னாரு… நீங்கதான்னு. தினமும்."),
    ("sq02_r02", "Murugan", "[urgent whisper]", "Shh! Lower your voice! For thirty years I've told this street tea is the only drink.",
     "ஷ்ஷ்! மெதுவா பேசு! முப்பது வருஷமா இந்தத் தெருவுக்கே டீதான் ஒரே பானம்னு சொல்லிட்டு இருக்கேன்."),
    ("sq02_r03", "Murugan", "[guilty, whispering]", "Tea is my job. Coffee is my weakness. One tumbler a day, behind the boiler.",
     "டீ என் தொழில். காபி என் பலவீனம். ஒரு நாளைக்கு ஒரு டம்ளர், பாய்லருக்குப் பின்னாடி."),
    ("sq02_r04", "Murugan", "[pleading]", "If this gets out, my customers will riot. You'll keep quiet, no?",
     "இது வெளியே தெரிஞ்சா என் கஸ்டமர்ஸ் கலவரம் பண்ணுவாங்க. நீ வாயை மூடிக்குவ, இல்ல?"),
    # Endings.
    ("sq02_d14", "Driver", "[deadpan]", "What coffee? I only saw a tea stall.",
     "என்ன காபி? நான் ஒரு டீக்கடையைத்தான் பார்த்தேன்."),
    ("sq02_r05", "Murugan", "[relieved, emotional]", "Thambi, you are a gentleman. Free tea for you, any day, for life.",
     "தம்பி, நீ ஒரு ஜென்டில்மேன். உனக்கு வாழ்நாள் முழுக்க டீ ஃப்ரீ."),
    ("sq02_d15", "Driver", "[loud, teasing, to the street]", "Everyone listen! Murugan anna's tea is… the best tea in Mylapore!",
     "எல்லாரும் கேளுங்க! முருகன் அண்ணனோட டீதான்… மயிலாப்பூரிலேயே பெஸ்ட் டீ!"),
    ("sq02_r06", "Murugan", "[laughing, wiping sweat]", "Ayyo, you nearly killed me! Here, twenty rupees extra. Not for the coffee. For your acting.",
     "அய்யோ, உயிரே போயிடுச்சு! இந்தா இருபது ரூபா எக்ஸ்ட்ரா. காபிக்கு இல்ல. உன் நடிப்புக்கு."),
    ("sq02_r07", "Murugan", "[sips, blissful]", "Ahh. Don't tell Kannan I said this, but… the man is a genius.",
     "ஆஹா. கண்ணன்கிட்ட நான் சொன்னேன்னு சொல்லாத, ஆனா… அந்த ஆள் ஒரு மேதை."),
    ("sq02_d16", "Driver", "[satisfied]", "Three coffees, three shops, one secret. Kannan anna might put my photo up beside his filter.",
     "மூணு காபி, மூணு கடை, ஒரு ரகசியம். கண்ணன் அண்ணன் அவரு ஃபில்டர் பக்கத்துல என் போட்டோவை மாட்டினாலும் மாட்டுவாரு."),
]

SPEAKER_KEYS = {"k": "VO_SPK_KANNAN", "d": "VO_SPK_DRIVER", "s": "VO_SPK_SELVAM", "m": "VO_SPK_MOHANA",
                "r": "VO_SPK_MURUGAN"}
SPEAKER_NAMES = {"VO_SPK_KANNAN": ("Kaapi Kannan", "காபி கண்ணன்"),
                 "VO_SPK_SELVAM": ("Selvam (tailor)", "செல்வம் (டெய்லர்)"),
                 "VO_SPK_MOHANA": ("Mohana Teacher", "மோகனா டீச்சர்"),
                 "VO_SPK_MURUGAN": ("Murugan (tea stall)", "முருகன் (டீக்கடை)")}

STRINGS = {
    "SQ02_TITLE": ("Filter Coffee, No Spill", "சிந்தாத ஃபில்டர் காபி"),
    "SQ02_DESC": ("Kaapi Kannan needs three hot filter coffees delivered to three shops. Don't spill a drop.",
                  "காபி கண்ணனின் மூணு சூடான ஃபில்டர் காபியை மூணு கடைக்குக் கொண்டு சேர். ஒரு சொட்டு கூட சிந்தக்கூடாது."),
    "SQ02_JOB": ("1. Meet Kannan at his coffee bar.\\n2. Pick which shop gets coffee first.\\n3. Deliver to all three shops in time.\\n4. Bumps and hard braking spill the coffee, so drive smoothly.",
                 "1. கண்ணனை அவர் காபிக் கடையில் சந்தி.\\n2. முதலில் எந்தக் கடை என்று தேர்வு செய்.\\n3. மூன்று கடைகளுக்கும் நேரத்துக்குள் கொடு.\\n4. குலுக்கலும் திடீர் பிரேக்கும் காபியைச் சிந்தும். மெதுவா ஓட்டு."),
    "SQ02_INTRO": ("Kaapi Kannan has a job for you.", "காபி கண்ணனிடம் உனக்கு ஒரு வேலை இருக்கிறது."),
    "SQ02_ORDER": ("Which shop first?", "முதலில் எந்தக் கடை?"),
    "SQ02_LUZ_FIRST": ("Selvam Tailors", "செல்வம் டெய்லர்ஸ்"),
    "SQ02_GARDEN_FIRST": ("Mohana Book House", "மோகனா புக் ஹவுஸ்"),
    "SQ02_FIRST": ("Take coffee to the first shop. Drive smoothly!", "முதல் கடைக்குக் காபி கொண்டு போ. மெதுவா ஓட்டு!"),
    "SQ02_DROP": ("Coffee delivered.", "காபி சேர்ந்தது."),
    "SQ02_SECOND": ("Now the second shop. Don't spill!", "இப்போ இரண்டாவது கடை. சிந்தாதே!"),
    "SQ02_THIRD": ("Last one: Murugan Tea Stall.", "கடைசி: முருகன் டீ ஸ்டால்."),
    "SQ02_TEA": ("A coffee for the tea man.", "டீக்காரருக்கு ஒரு காபி."),
    "SQ02_SECRET": ("Murugan's secret is in your hands.", "முருகனின் ரகசியம் உன் கையில்."),
    "SQ02_KEEP": ("Keep his secret", "ரகசியத்தைக் காப்பாற்று"),
    "SQ02_TEASE": ("Tease him a little", "கொஞ்சம் கலாய்"),
    "SQ02_THANKS": ("All three coffees delivered.", "மூணு காபியும் சேர்ந்தது."),
    "SQ02_P_COFFEE": ("Kannan Degree Coffee", "கண்ணன் டிகிரி காபி"),
    "SQ02_P_TAILOR": ("Selvam Tailors", "செல்வம் டெய்லர்ஸ்"),
    "SQ02_P_BOOKS": ("Mohana Book House", "மோகனா புக் ஹவுஸ்"),
    "SQ02_P_TEA": ("Murugan Tea Stall", "முருகன் டீ ஸ்டால்"),
}
RETIRED = []

LUZ, GARDEN = "SQ02_LUZ_FIRST", "SQ02_GARDEN_FIRST"
stages = [
    dict(id="intro", kind="cutscene", objective_key="SQ02_INTRO", target=START, cutscene_id="intro", duration_s=60.0,
         place_key="SQ02_P_COFFEE", place_pos=COFFEE_PLACE),
    dict(id="order", kind="dialogue", objective_key="SQ02_ORDER", choices=PSA([LUZ, GARDEN])),
    dict(id="first", kind="goto", objective_key="SQ02_FIRST", target=TAILOR_ROAD, target_choice_stage="order",
         target_options={LUZ: TAILOR_ROAD, GARDEN: BOOKS_ROAD}, radius_m=9.0, deadline_s=190.0, quality_key="coffee",
         quality_floor=20.0, quality_scale=1.0, place_key="SQ02_P_TAILOR", place_pos=TAILOR_PLACE,
         place_options={LUZ: "SQ02_P_TAILOR", GARDEN: "SQ02_P_BOOKS"},
         place_pos_options={LUZ: TAILOR_PLACE, GARDEN: BOOKS_PLACE}),
    dict(id="first_drop", kind="cutscene", objective_key="SQ02_DROP", cutscene_id="first_drop", duration_s=40.0),
    dict(id="second", kind="goto", objective_key="SQ02_SECOND", target=BOOKS_ROAD, target_choice_stage="order",
         target_options={LUZ: BOOKS_ROAD, GARDEN: TAILOR_ROAD}, radius_m=9.0, deadline_s=210.0, quality_key="coffee",
         quality_floor=20.0, place_key="SQ02_P_BOOKS", place_pos=BOOKS_PLACE,
         place_options={LUZ: "SQ02_P_BOOKS", GARDEN: "SQ02_P_TAILOR"},
         place_pos_options={LUZ: BOOKS_PLACE, GARDEN: TAILOR_PLACE}),
    dict(id="second_drop", kind="cutscene", objective_key="SQ02_DROP", cutscene_id="second_drop", duration_s=40.0),
    dict(id="third", kind="goto", objective_key="SQ02_THIRD", target=TEA_ROAD, radius_m=9.0, deadline_s=210.0,
         quality_key="coffee", quality_floor=20.0, place_key="SQ02_P_TEA", place_pos=TEA_PLACE),
    dict(id="tea", kind="cutscene", objective_key="SQ02_TEA", cutscene_id="tea", duration_s=36.0),
    dict(id="secret", kind="dialogue", objective_key="SQ02_SECRET", choices=PSA(["SQ02_KEEP", "SQ02_TEASE"])),
    dict(id="thanks", kind="cutscene", objective_key="SQ02_THANKS", cutscene_id="thanks", duration_s=24.0),
]

# Camera marks relative to the auto ([right, up, forward]).
FRONT = [2.1, 1.4, 7.2]          # front three-quarter of the auto, driver in view
FRONT_TO = [1.6, 1.35, 6.6]
AUTO_LOOK = [0.0, 1.05, 0.4]
WIDE = [0.0, 2.4, 10.5]
WIDE_LOOK = [0.0, 1.2, 0.0]
DRIVER_FACE = [0.0, 0.0, 1.4]  # someone at the window looks at the driver, so the lens ahead sees their face


def two_shot(role, fov=50):
    """From ahead on the shopkeeper's side: the auto with them at the driver's window (never with
    the auto between the lens and them, whichever side of the auto they stand)."""
    return {"eye": {"from": "role:" + role, "dist": 1.0, "side": 4.4, "up": 1.7, "ahead": True}, "look": "role:" + role,
            "fov": fov}


def walking(role, fov=56):
    """Watching them walk from their shop to the auto, from off to the side of their path."""
    return {"eye": {"from": "role:" + role, "dist": 1.6, "side": 4.6, "up": 1.8, "ahead": True}, "look": "role:" + role,
            "fov": fov}


def close(role, fov=40, side=2.6, dist=0.6):
    """The shopkeeper standing by the driver, filmed from ahead of the auto on their side."""
    return {"eye": {"from": "role:" + role, "dist": dist, "side": side, "up": 1.55, "ahead": True}, "look": "role:" + role,
            "fov": fov}


def street(role, fov=60):
    """The shopkeeper at their own shop, the painted board behind them (lens on the road side)."""
    return {"eye": {"from": "role:" + role, "dist": 3.8, "side": 2.2, "up": 1.9}, "look": "role:" + role, "fov": fov}


def walk_up(role, line, line_at=0.6):
    """They see the auto, call out and walk to the driver's side."""
    return [
        {"fade_in": 0.5, "cam": street(role), "act": {role: {"face": "auto", "anim": "wave"}}, "line": line,
         "line_at": line_at, "min_s": 1.6},
        {"cam": walking(role),
         "act": {role: {"to": "beside:" + role, "gait": "walk", "then": "talk", "face": DRIVER_FACE}},
         "wait": role, "min_s": 1.0, "max_s": 9.0},
    ]


def talk(role, line, fov=40, anim="talk"):
    return {"cam": close(role, fov), "act": {role: {"anim": anim, "face": DRIVER_FACE}}, "line": line}


def driver(line):
    return {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 46}, "line": line}


def back_to_shop(role, spot, last_line=None):
    beat = {"cam": {"eye": WIDE, "look": WIDE_LOOK, "fov": 54},
            "act": {role: {"to": spot, "gait": "walk", "then": "idle", "face": "auto"}}, "min_s": 1.8, "fade_out": 0.5}
    if last_line:
        beat["line"] = last_line
    return beat


def tailor_scene(cond):
    beats = walk_up("selvam", "sq02_s01") + [
        driver("sq02_d09"),
        talk("selvam", "sq02_s02"),
        dict(talk("selvam", "sq02_s03", 36, "drink")),
        {"cam": two_shot("selvam", 48), "act": {"selvam": {"anim": "wave", "face": DRIVER_FACE}}, "line": "sq02_s04"},
        back_to_shop("selvam", SELVAM),
    ]
    for b in beats:
        b["if_choice"] = ["order", cond]
    return beats


def books_scene(cond):
    beats = walk_up("mohana", "sq02_m01") + [
        driver("sq02_d10"),
        talk("mohana", "sq02_m02"),
        driver("sq02_d11"),
        talk("mohana", "sq02_m03", 38),
        driver("sq02_d12"),
        dict(talk("mohana", "sq02_m04", 36, "drink")),
        back_to_shop("mohana", MOHANA),
    ]
    for b in beats:
        b["if_choice"] = ["order", cond]
    return beats


cutscenes = {
    # Kannan sees the auto, waves it over and briefs the driver at the window.
    "intro": [
        {"fade_in": 0.6, "cam": {"eye": {"from": "role:kannan", "dist": 6.5, "side": -2.0, "up": 2.0}, "look": "role:kannan", "fov": 54},
         "act": {"kannan": {"face": "auto", "anim": "wave"}}, "line": "sq02_k01", "line_at": 0.6, "min_s": 1.8},
        {"cam": walking("kannan"),
         "act": {"kannan": {"to": "beside:kannan", "gait": "walk", "then": "talk", "face": DRIVER_FACE}},
         "wait": "kannan", "min_s": 1.0, "max_s": 10.0},
        driver("sq02_d01"),
        talk("kannan", "sq02_k02"),
        talk("kannan", "sq02_k03", 34),
        driver("sq02_d02"),
        talk("kannan", "sq02_k04", 38),
        {"cam": two_shot("kannan", 50), "act": {"kannan": {"anim": "talk", "face": DRIVER_FACE}}, "line": "sq02_k05"},
        driver("sq02_d03"),
        talk("kannan", "sq02_k06", 36),
        {"cam": close("kannan", 46), "act": {"kannan": {"anim": "idle", "face": DRIVER_FACE}}, "min_s": 0.6, "hold": True},
    ],
    "first_drop": tailor_scene(LUZ) + books_scene(GARDEN),
    "second_drop": books_scene(LUZ) + tailor_scene(GARDEN),
    # The tea stall: loud for the customers, then a whisper at the auto. Ends held on the choice.
    "tea": walk_up("murugan", "sq02_r01", 0.4) + [
        driver("sq02_d13"),
        talk("murugan", "sq02_r02", 34),
        talk("murugan", "sq02_r03", 38),
        {"cam": two_shot("murugan", 46), "act": {"murugan": {"anim": "talk", "face": DRIVER_FACE}}, "line": "sq02_r04"},
        {"cam": close("murugan", 44), "act": {"murugan": {"anim": "idle", "face": DRIVER_FACE}}, "min_s": 0.6, "hold": True},
    ],
    "thanks": [
        dict(driver("sq02_d14"), if_choice=["secret", "SQ02_KEEP"]),
        dict(talk("murugan", "sq02_r05", 38), if_choice=["secret", "SQ02_KEEP"]),
        dict(driver("sq02_d15"), if_choice=["secret", "SQ02_TEASE"]),
        dict(talk("murugan", "sq02_r06", 38), if_choice=["secret", "SQ02_TEASE"]),
        {"cam": street("murugan", 46), "act": {"murugan": {"to": MURUGAN, "gait": "walk", "then": "drink", "face": "auto"}},
         "wait": "murugan", "max_s": 7.0, "line": "sq02_r07"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq02_d16", "fade_out": 0.6},
    ],
}

AT_COFFEE = ["intro", "order"]
AT_SHOPS = ["first", "first_drop", "second", "second_drop"]
AT_TEA = ["third", "tea", "secret", "thanks"]

cast = {
    "kannan": {"model": PEOPLE + "old_man_veshti.glb", "scale": 1.0, "world": KANNAN, "face": START, "anim": "idle",
               "wear": PSA(["davara"]), "stages": PSA(AT_COFFEE)},
    "coffee_customer": {"model": PEOPLE + "woman_saree_green.glb", "scale": 1.0, "world": COFFEE_CUSTOMER, "face": COFFEE_PLACE,
                        "anim": "drink", "stages": PSA(AT_COFFEE)},
    "selvam": {"model": PEOPLE + "young_man.glb", "scale": 1.0, "world": SELVAM, "face": TAILOR_ROAD, "anim": "idle",
               "wear": PSA(["tape", "pencil"]), "stages": PSA(AT_SHOPS)},
    "mohana": {"model": PEOPLE + "woman_saree_violet.glb", "scale": 1.0, "world": MOHANA, "face": BOOKS_ROAD, "anim": "idle",
               "wear": PSA(["specs", "jasmine", "book"]), "stages": PSA(AT_SHOPS)},
    "murugan": {"model": PEOPLE + "man_casual.glb", "scale": 1.0, "world": MURUGAN, "face": TEA_ROAD, "anim": "idle",
                "wear": PSA(["towel", "glass"]), "stages": PSA(AT_TEA)},
    "tea_customer": {"model": PEOPLE + "old_man_veshti.glb", "scale": 0.97, "world": TEA_CUSTOMER, "face": TEA_PLACE,
                     "anim": "drink", "wear": PSA(["glass"]), "stages": PSA(AT_TEA)},
}
for c in cast.values():
    c["paint"] = NONE

barks = {
    "first": {"enter": ["sq02_d04"], "idle": ["sq02_d05", "sq02_d06"], "idle_s": V2((24.0, 38.0)), "impact": "sq02_d07",
              "jolt": "sq02_d08"},
    "second": {"enter": ["sq02_d17"], "idle": ["sq02_d05", "sq02_d06"], "idle_s": V2((26.0, 40.0)), "impact": "sq02_d07",
               "jolt": "sq02_d08"},
    "third": {"enter": ["sq02_d18"], "idle": ["sq02_d06", "sq02_d05"], "idle_s": V2((26.0, 40.0)), "impact": "sq02_d07",
              "jolt": "sq02_d08"},
}


def voice_script():
    cast_notes = [
        "- Kannan (Kaapi Kannan): owner of Kannan Degree Coffee, about 65, theatrical and proud, treats coffee like a concert.",
        "- Selvam: a tailor in wedding season, 30s, frantic and fast, calms down with coffee.",
        "- Mohana Teacher: a retired Tamil teacher who runs a book house and sells nothing, 60s, strict, precise, secretly warm.",
        "- Murugan: the tea-stall master who drinks coffee in secret, 40s, loud for customers, whispers when caught.",
        "- Driver (hero): the same locked voice as every quest.",
    ]
    out = ['# SQ02 "Filter Coffee, No Spill": Voice Script', "",
           "Written by `tools/quests/build_sq02_story.py` (edit the lines there, not here). Generated by",
           "**Actions -> Generate quest voices** (Indic Parler-TTS, see `docs/voice/README.md`).",
           "Each bullet is one line: `id Speaker: [tags] Tamil / [tags] English`. Files land in",
           "`assets/audio/voice/sq02/<id>_<ta|en>.ogg`. Subtitles: `VO_SQ02_*` in `translations/ui.csv`.", "",
           "## Cast"] + cast_notes + ["", "## Lines"]
    for lid, spk, tags, en, ta in LINES:
        out.append(f"- {lid} {spk}: {tags} {ta} / {tags} {en}")
    (ROOT / "docs/voice/SQ02_Filter_Coffee_Voice_Script.md").write_text("\n".join(out) + "\n", encoding="utf-8")


def csv_row(key, en, ta):
    buf = io.StringIO()
    csv.writer(buf, lineterminator="").writerow([key, en, ta])
    return buf.getvalue()


def update_ui_csv():
    path = ROOT / "translations/ui.csv"
    rows = path.read_text(encoding="utf-8").split("\n")
    want = dict(STRINGS)
    for k, (en, ta) in SPEAKER_NAMES.items():
        want[k] = (en, ta)
    for lid, _spk, _tags, en, ta in LINES:
        want["VO_" + lid.upper()] = (en, ta)
    kept = []
    seen = set()
    for r in rows:
        key = r.split(",", 1)[0]
        if key in RETIRED:
            continue
        if key in want:
            if key in seen:
                continue
            seen.add(key)
            kept.append(csv_row(key, *want[key]))
            continue
        kept.append(r)
    while kept and kept[-1] == "":
        kept.pop()
    for key, (en, ta) in want.items():
        if key not in seen:
            kept.append(csv_row(key, en, ta))
    path.write_text("\n".join(kept) + "\n", encoding="utf-8")


ids = [line[0] for line in LINES]
assert len(ids) == len(set(ids)), "duplicate line id"
used = set()
for beats in cutscenes.values():
    for b in beats:
        if "line" in b:
            used.add(b["line"])
for bk in barks.values():
    for v in bk.values():
        used.update(v if isinstance(v, list) else [v] if isinstance(v, str) else [])
assert used <= set(ids), used - set(ids)
assert set(ids) <= used, set(ids) - used

write_story("sq_002", "res://assets/audio/voice/sq02", dict(SPEAKER_KEYS), cast, {}, cutscenes, barks)
write_mission("sq_002", stages, [
    ("content_version", 3), ("title_key", "SQ02_TITLE"), ("description_key", "SQ02_DESC"), ("job_key", "SQ02_JOB"),
    ("discoverable", True), ("start_anchor", START), ("estimated_minutes", 9), ("category", "skill"),
    ("reward_inr", 145), ("reward_xp", 15), ("reward_choice_stage", "secret"),
    ("reward_choice_inr", {"SQ02_KEEP": 145, "SQ02_TEASE": 165}), ("reward_choice_xp", {"SQ02_KEEP": 30})])
voice_script()
update_ui_csv()
print("wrote sq_002.tres, sq_002_story.tres, the SQ02 voice script and ui.csv rows")
