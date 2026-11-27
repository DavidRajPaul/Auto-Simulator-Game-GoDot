"""Writes data/missions/side_quests/sq_001.tres, data/missions/stories/sq_001_story.tres,
docs/voice/SQ01_Wedding_Gold_Voice_Script.md and the SQ01 / VO_SQ01 rows of translations/ui.csv.

"The Wedding Gold" (v4, Nov 27 owner report: "zero dialogues or very short, the cut scenes are very
fast, no NPCs talking the dialog"). Rebuilt as a story quest like the Red Kite and Paati: voiced
cutscenes with the people in the world, stops beside real people, no button moves it forward.

Story: at a wedding hall on Ponnambalam Vathiyar Street the organiser Sundaram found a gold pouch at
the gate. Kavya (the bride's cousin) says her Kamala aunty gave it to her; Revathi says she left her
jewellery at the gate. Only Kavya knows what is inside. The receipt in the pouch has a blue lotus
stamp from M.R. Flowers on East Tank Square Street. Muthu the flower seller remembers Kamala amma
buying it for her niece, and also hands you the red pouch a lady in a violet saree forgot on his
counter this morning. Back at the hall you choose who gets the gold.

LINES is the one source for every voiced line: this script writes the voice script (the Generate
quest voices workflow voices any line without a file) and the subtitles. Until the voices exist,
a line stays up as long as it takes to read (QuestStory.reading_seconds).
Run from the repo root: python3 tools/quests/build_sq01_story.py
"""
import csv
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from story_tres import NONE, PEOPLE, PSA, ROOT, V2, V3, write_mission, write_story  # noqa: E402

START = V3((1145.6, 0, 1621.0))  # North Mada Street (anchors.json)
# The wedding hall on Ponnambalam Vathiyar Street: the west kerb is open ground in front of it.
HALL_ROAD = V3((1238.6, 0, 1664.1))
HALL_PLACE = V3((1232.4, 0, 1664.6))
ORGANISER = V3((1234.9, 0, 1662.6))
KAVYA_WAIT = V3((1234.7, 0, 1666.6))
REVATHI_WAIT = V3((1234.6, 0, 1659.4))
# M.R. Flowers on East Tank Square Street (east kerb, in front of the shop row).
FLOWER_ROAD = V3((1127.8, 0, 1719.4))
FLOWER_PLACE = V3((1134.6, 0, 1723.4))
MUTHU = V3((1133.6, 0, 1722.2))

# id, speaker (cast.json), emotion tags, English, Tamil. English says "brother" for "anna".
LINES = [
    # Scene 1: the hall
    ("sq01_o01", "Sundaram", "[relieved, calling out]", "Auto! Auto thambi, stop here please!", "ஆட்டோ! ஆட்டோ தம்பி, இங்க கொஞ்சம் நிறுத்துப்பா!"),
    ("sq01_d01", "Driver", "[friendly]", "What happened, sir? Is everything all right at the wedding?", "என்ன ஆச்சு சார்? கல்யாணத்துல எல்லாம் சரியா இருக்கா?"),
    ("sq01_o02", "Sundaram", "[worried, fast]", "Nothing is all right! I found a gold pouch at the hall gate. Two ladies say it is theirs, and the muhurtham is in one hour!",
     "எதுவுமே சரியில்ல! மண்டப வாசல்ல ஒரு நகைப் பை கிடந்தது. ரெண்டு பேர் அது தங்களோடதுன்னு சொல்றாங்க. முகூர்த்தம் இன்னும் ஒரு மணி நேரத்துல!"),
    ("sq01_k01", "Kavya", "[upset, out of breath]", "Sir, it is mine! My Kamala aunty gave it to me this morning. It has a blue lotus on it.",
     "சார், அது என்னோடது! காலைல கமலா அத்தை எனக்குக் கொடுத்தாங்க. அதுல நீலத் தாமரை இருக்கு."),
    ("sq01_r01", "Revathi", "[firm, a little proud]", "No, no. I kept my jewellery near the gate when I went to wash my hands. That pouch is mine.",
     "இல்ல இல்ல. கை கழுவப் போனப்ப வாசல்கிட்ட என் நகையை வச்சேன். அந்தப் பை என்னோடதுதான்."),
    ("sq01_d02", "Driver", "[calm]", "Madam, what is inside your pouch?", "மேடம், உங்க பையில என்ன இருக்கு?"),
    ("sq01_r02", "Revathi", "[hesitant]", "Inside? A chain… some bangles… I packed in a hurry, I don't remember.",
     "உள்ளயா? ஒரு செயின்… சில வளையல்… அவசரமா கட்டினேன், ஞாபகம் இல்ல."),
    ("sq01_k02", "Kavya", "[pleading]", "One gold chain with a mango design, and two thin bangles. I can tell you with my eyes closed!",
     "மாங்காய் டிசைன் போட்ட ஒரு தங்கச் செயின், ரெண்டு மெல்லிய வளையல். கண்ணை மூடிக்கிட்டே சொல்லுவேன்!"),
    ("sq01_o03", "Sundaram", "[thinking]", "There was a small receipt in the pouch. M.R. Flowers, with a blue lotus stamp. That is the flower stall on East Tank Square Street.",
     "பையில ஒரு சின்ன ரசீது இருந்தது. எம்.ஆர். ஃப்ளவர்ஸ், நீலத் தாமரை முத்திரையோட. அது கிழக்கு குளக்கரைத் தெரு பூக்கடை."),
    ("sq01_d03", "Driver", "[confident]", "Then I'll ask the flower seller who bought that gift. Keep the pouch safe, sir.",
     "அப்போ அந்தப் பரிசை யார் வாங்கினாங்கன்னு பூக்காரர்கிட்ட கேக்கறேன். பையைப் பத்திரமா வச்சுக்கோங்க சார்."),
    ("sq01_o04", "Sundaram", "[grateful, then whispering]", "Go quickly, thambi. And please, don't tell the bride's mother!",
     "சீக்கிரம் போ தம்பி. தயவுசெஞ்சு பொண்ணோட அம்மாகிட்ட மட்டும் சொல்லிடாதே!"),
    # Driving to the flower stall
    ("sq01_d04", "Driver", "[to himself, amused]", "A wedding in Mylapore, and now I'm a detective!", "மைலாப்பூர் கல்யாணம், இப்ப நான் டிடெக்டிவ்!"),
    ("sq01_d05", "Driver", "[muttering, thinking]", "Blue lotus… M.R. Flowers… East Tank Square Street.", "நீலத் தாமரை… எம்.ஆர். ஃப்ளவர்ஸ்… கிழக்கு குளக்கரைத் தெரு."),
    ("sq01_d06", "Driver", "[to himself]", "One hour to the muhurtham. No time for tea today.", "முகூர்த்தத்துக்கு ஒரு மணி நேரம்தான். இன்னிக்கு டீக்குக்கூட நேரமில்ல."),
    # Scene 2: M.R. Flowers
    ("sq01_f01", "Muthu", "[cheerful, calling out]", "Vaanga, vaanga! Jasmine, rose, marigold, what do you need?", "வாங்க வாங்க! மல்லி, ரோஜா, சாமந்தி, என்ன வேணும்?"),
    ("sq01_d07", "Driver", "[polite]", "Brother, a quick question. A gift pouch with your blue lotus stamp. Who bought it?",
     "அண்ணா, ஒரு சின்னக் கேள்வி. உங்க கடையோட நீலத் தாமரை முத்திரை போட்ட பரிசுப் பை. அதை யார் வாங்கினாங்க?"),
    ("sq01_f02", "Muthu", "[remembering]", "Blue lotus? I make only five of those a week. Kamala amma bought one yesterday, for her niece's wedding.",
     "நீலத் தாமரையா? வாரத்துக்கு அஞ்சுதான் செய்வேன். நேத்து கமலா அம்மா ஒண்ணு வாங்கினாங்க, அவங்க அண்ணன் பொண்ணு கல்யாணத்துக்கு."),
    ("sq01_d08", "Driver", "[interested]", "Her niece… is that Kavya?", "அண்ணன் பொண்ணு… கவ்யாவா?"),
    ("sq01_f03", "Muthu", "[nodding, proud]", "Yes, Kavya! Good girl. M.R. is me, Muthu Ramasamy. I wrote that receipt myself!",
     "ஆமா, கவ்யாதான்! நல்ல பொண்ணு. எம்.ஆர்.ன்னா நான்தான், முத்து ராமசாமி. அந்த ரசீதை நானே எழுதினேன்!"),
    ("sq01_f04", "Muthu", "[suddenly remembering, laughing]", "Wait! A lady in a violet saree left this red pouch on my counter this morning. Is she at the same wedding?",
     "இருங்க! காலைல வயலட் புடவை கட்டின ஒரு அம்மா இந்தச் சிவப்புப் பையை என் கடையில மறந்து வச்சிட்டுப் போனாங்க. அவங்களும் அதே கல்யாணமா?"),
    ("sq01_d09", "Driver", "[laughing]", "I think I know exactly who she is. Give it to me, I'll take it to her.",
     "அவங்க யாருன்னு எனக்கு நல்லாவே தெரியும். குடுங்க, நான் கொண்டு போய் குடுக்கறேன்."),
    ("sq01_f05", "Muthu", "[warm]", "Take it. And tell the couple, Muthu wishes them a long and happy life!",
     "எடுத்துக்கோ. ஜோடிக்கு முத்து நீண்ட நாள் சந்தோஷமா வாழ வாழ்த்தினான்னு சொல்லு!"),
    # Driving back
    ("sq01_d10", "Driver", "[to himself, pleased]", "One blue pouch, one red pouch. This wedding may have a happy ending after all.",
     "ஒரு நீலப் பை, ஒரு சிவப்புப் பை. இந்தக் கல்யாணத்துக்கு நல்ல முடிவுதான் போல."),
    # Scene 3: the verdict
    ("sq01_o05", "Sundaram", "[anxious]", "Thambi, you're back! Ten minutes to the muhurtham. Tell me, whose pouch is it?",
     "தம்பி, வந்துட்டியா! முகூர்த்தத்துக்கு இன்னும் பத்து நிமிஷம். சொல்லு, பை யாரோடது?"),
    ("sq01_k03", "Kavya", "[hopeful, soft]", "Please, brother. That gift is from my aunty. It means everything to me.",
     "ப்ளீஸ் அண்ணா. அந்தப் பரிசு என் அத்தை கொடுத்தது. எனக்கு அது ரொம்ப முக்கியம்."),
    ("sq01_r03", "Revathi", "[defensive]", "I am not lying! My pouch was right here. Where else could it go?",
     "நான் பொய் சொல்லல! என் பை இங்கதான் இருந்துச்சு. வேற எங்க போயிருக்கும்?"),
    ("sq01_d11", "Driver", "[thoughtful]", "The flower seller told me who bought the blue lotus pouch.",
     "நீலத் தாமரைப் பையை யார் வாங்கினாங்கன்னு பூக்காரர் சொன்னாரு."),
    # Ending: Kavya
    ("sq01_d12", "Driver", "[warm]", "Kavya, this is yours. Kamala aunty bought it at M.R. Flowers yesterday.",
     "கவ்யா, இது உங்களோடது. நேத்து கமலா அத்தை எம்.ஆர். ஃப்ளவர்ஸ்ல வாங்கினாங்க."),
    ("sq01_k04", "Kavya", "[overjoyed, tearful]", "Thank you, brother! I was so scared I had lost it!",
     "ரொம்ப நன்றி அண்ணா! தொலைச்சிட்டேன்னு பயந்தே போயிட்டேன்!"),
    ("sq01_d13", "Driver", "[teasing, kind]", "And madam, the flower seller sent this. A red pouch, left on his counter this morning.",
     "மேடம், இதை பூக்காரர் அனுப்பினாரு. காலைல அவர் கடையில விட்டுட்டுப் போன சிவப்புப் பை."),
    ("sq01_r04", "Revathi", "[embarrassed, laughing]", "Ayyo! My pouch! I bought jasmine there and forgot it. Sorry, Kavya, sorry!",
     "ஐயோ! என் பைதான்! அங்க மல்லிப்பூ வாங்கிட்டு மறந்துட்டேன். மன்னிச்சுக்கோ கவ்யா!"),
    ("sq01_o06", "Sundaram", "[relieved, happy]", "Both pouches found, and the muhurtham is saved! Thambi, eat at the feast before you go.",
     "ரெண்டு பையும் கிடைச்சாச்சு, முகூர்த்தமும் காப்பாத்தியாச்சு! தம்பி, போறதுக்கு முன்னாடி பந்தியில சாப்பிட்டுட்டுப் போ."),
    # Ending: Revathi
    ("sq01_d14", "Driver", "[unsure]", "Revathi madam, take it. I think it is yours.", "ரேவதி மேடம், எடுத்துக்கோங்க. உங்களோடதுன்னு நினைக்கிறேன்."),
    ("sq01_r05", "Revathi", "[opens it, confused]", "Wait… a mango chain? This is not mine. My chain has a peacock on it.",
     "இருங்க… மாங்காய் செயினா? இது என்னோடது இல்ல. என் செயின்ல மயில் இருக்கும்."),
    ("sq01_k05", "Kavya", "[hurt]", "I told you! That is my aunty's gift!", "நான் சொன்னேன்ல! அது என் அத்தையோட பரிசு!"),
    ("sq01_o07", "Sundaram", "[sighs]", "Thambi, the flower seller told you the truth. Next time, trust what you found out.",
     "தம்பி, பூக்காரர் உண்மையைச் சொன்னாரு. அடுத்த முறை நீ கண்டுபிடிச்சதை நம்பு."),
    ("sq01_d15", "Driver", "[sheepish]", "Sorry, Kavya. And madam, here is your red pouch, from the flower stall.",
     "மன்னிச்சுக்கோங்க கவ்யா. மேடம், இதோ உங்க சிவப்புப் பை, பூக்கடையில இருந்தது."),
]

SPEAKER_KEYS = {"o": "VO_SPK_ORGANISER", "k": "VO_SPK_KAVYA", "r": "VO_SPK_REVATHI", "f": "VO_SPK_MUTHU", "d": "VO_SPK_DRIVER"}
SPEAKER_NAMES = {"VO_SPK_ORGANISER": ("Sundaram (organiser)", "சுந்தரம் (ஏற்பாட்டாளர்)"),
                 "VO_SPK_KAVYA": ("Kavya", "கவ்யா"), "VO_SPK_REVATHI": ("Revathi", "ரேவதி"),
                 "VO_SPK_MUTHU": ("Muthu (flowers)", "முத்து (பூக்கடை)")}

STRINGS = {
    "SQ01_TITLE": ("The Wedding Gold", "கல்யாண நகை"),
    "SQ01_DESC": ("Two guests claim a missing gold pouch. Help the family find the truth before the muhurtham.",
                  "காணாம போன நகைப் பையை இரண்டு பேர் சொந்தம்னு சொல்றாங்க. முகூர்த்தத்துக்கு முன் உண்மையைக் கண்டுபிடி."),
    "SQ01_JOB": ("1. Stop beside the organiser at the wedding hall.\\n2. Hear both women.\\n3. Ask the flower seller about the blue lotus pouch.\\n4. Go back to the hall and give the gold to its owner.",
                 "1. கல்யாண மண்டபத்தில் ஏற்பாட்டாளர் அருகே நிறுத்து.\\n2. இரண்டு பேரிடமும் கேள்.\\n3. நீலத் தாமரைப் பையைப் பற்றி பூக்காரரிடம் கேள்.\\n4. மண்டபத்துக்குத் திரும்பி நகையை உரியவரிடம் கொடு."),
    "SQ01_HALL": ("Drive to the wedding hall and stop beside the organiser.", "கல்யாண மண்டபத்துக்குப் போய் ஏற்பாட்டாளர் அருகே நிறுத்து."),
    "SQ01_HALL_TALK": ("Hear the organiser and both women.", "ஏற்பாட்டாளரும் இரண்டு பெண்களும் சொல்வதைக் கேள்."),
    "SQ01_ASK_FLOWER": ("Drive to M.R. Flowers on East Tank Square Street and stop beside Muthu.", "கிழக்கு குளக்கரைத் தெரு எம்.ஆர். ஃப்ளவர்ஸுக்குப் போய் முத்து அருகே நிறுத்து."),
    "SQ01_FLOWER_TALK": ("Ask Muthu who bought the blue lotus pouch.", "நீலத் தாமரைப் பையை யார் வாங்கினாங்கன்னு முத்துவிடம் கேள்."),
    "SQ01_BACK": ("Go back to the wedding hall. Both women are waiting.", "கல்யாண மண்டபத்துக்குத் திரும்பு. இரண்டு பேரும் காத்திருக்கிறார்கள்."),
    "SQ01_VERDICT": ("Both women are here.", "இரண்டு பேரும் வந்தாச்சு."),
    "SQ01_DECISION": ("Who gets the gold pouch?", "நகைப் பை யாருக்கு?"),
    "SQ01_OWNER": ("Give it to Kavya", "கவ்யாவிடம் கொடு"),
    "SQ01_OTHER": ("Give it to Revathi", "ரேவதியிடம் கொடு"),
    "SQ01_ENDING": ("The gold goes home.", "நகை உரியவரிடம் போகிறது."),
    "SQ01_P_HALL": ("Wedding Hall", "திருமண மண்டபம்"),
    "SQ01_P_FLOWER": ("M.R. Flowers", "எம்.ஆர். ஃப்ளவர்ஸ்"),
}
# Strings of the old button quest that nothing uses any more.
RETIRED = ["SQ01_RECEIPT", "SQ01_CLAIMANT", "SQ01_VERIFY", "SQ01_ASK", "SQ01_CHECK_RECEIPT", "SQ01_HANDOVER", "SQ01_THANKS",
           "SQ01_P_DESK", "SQ01_ORGANISER", "SQ01_LISTEN", "SQ01_MEENA_STATEMENT", "SQ01_ASK_OTHER", "SQ01_OTHER_STATEMENT",
           "SQ01_LOOK_RECEIPT", "SQ01_VIEW_RECEIPT", "SQ01_RECEIPT_CLUE", "SQ01_VISIT_FLOWER", "SQ01_SELLER",
           "SQ01_RETURN_TO_HALL", "SQ01_RESOLVED_RIGHT", "SQ01_RESOLVED_WRONG"]

stages = [
    dict(id="ask_hall", kind="ask", objective_key="SQ01_HALL", target=HALL_ROAD, radius_m=9.0,
         place_key="SQ01_P_HALL", place_pos=HALL_PLACE),
    dict(id="hall", kind="cutscene", objective_key="SQ01_HALL_TALK", cutscene_id="hall", duration_s=60.0),
    dict(id="ask_flower", kind="ask", objective_key="SQ01_ASK_FLOWER", target=FLOWER_ROAD, radius_m=9.0,
         place_key="SQ01_P_FLOWER", place_pos=FLOWER_PLACE),
    dict(id="flower", kind="cutscene", objective_key="SQ01_FLOWER_TALK", cutscene_id="flower", duration_s=40.0),
    dict(id="back_hall", kind="ask", objective_key="SQ01_BACK", target=HALL_ROAD, radius_m=9.0,
         place_key="SQ01_P_HALL", place_pos=HALL_PLACE),
    dict(id="verdict", kind="cutscene", objective_key="SQ01_VERDICT", cutscene_id="verdict", duration_s=24.0),
    dict(id="decision", kind="dialogue", objective_key="SQ01_DECISION", choices=PSA(["SQ01_OWNER", "SQ01_OTHER"])),
    dict(id="ending", kind="cutscene", objective_key="SQ01_ENDING", cutscene_id="ending", duration_s=30.0),
]

FRONT = [2.1, 1.4, 7.2]          # front three-quarter of the auto, driver in view
FRONT_TO = [1.6, 1.35, 6.6]
AUTO_LOOK = [0.0, 1.05, 0.4]
# Everyone stands on the kerb in a row facing the auto: Revathi behind the door, Sundaram ahead
# of it, Kavya further ahead. Cameras stand in the road (or behind the auto), so faces show and the
# hall stays behind them; none is ever framed "from" a person beside the auto (lens in the canopy).
REVATHI_AT = [-2.1, 0, -0.5]
SUNDARAM_AT = [-2.1, 0, 1.7]
KAVYA_AT = [-2.1, 0, 3.8]
GROUP_CAM = [1.3, 1.85, 8.8]
GROUP_LOOK = [-2.1, 1.2, 1.6]
REV_CAM = [-0.2, 1.55, -3.9]
ORG_CAM = [0.5, 1.5, 5.0]
ORG_CAM_TO = [0.4, 1.5, 4.7]
KAV_CAM = [0.7, 1.5, 7.4]
KAV_CAM_TO = [0.6, 1.48, 7.1]
SELLER_AT = [-2.1, 0, 2.2]
SELLER_CAM = [0.5, 1.5, 5.4]
SELLER_CAM_TO = [0.4, 1.5, 5.0]

cutscenes = {
    "hall": [
        {"fade_in": 0.6, "cam": {"cockpit": True, "look": "role:sundaram", "fov": 58},
         "act": {"sundaram": {"face": "auto", "anim": "wave"}}, "line": "sq01_o01", "line_at": 0.4, "min_s": 2.2},
        {"cam": {"eye": ORG_CAM, "eye_to": ORG_CAM_TO, "look": "role:sundaram", "fov": 46},
         "act": {"sundaram": {"to": SUNDARAM_AT, "gait": "walk", "then": "idle", "face": "auto"}},
         "wait": "sundaram", "min_s": 1.6, "max_s": 7.0},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq01_d01"},
        {"cam": {"eye": ORG_CAM, "look": "role:sundaram", "fov": 42}, "act": {"sundaram": {"anim": "talk", "face": "auto"}},
         "line": "sq01_o02"},
        # Kavya runs up from ahead; Revathi follows from behind.
        {"cam": {"eye": KAV_CAM, "eye_to": KAV_CAM_TO, "look": "role:kavya", "fov": 46},
         "act": {"kavya": {"at": [-3.2, 0, 13.0], "to": KAVYA_AT, "gait": "run", "then": "talk", "face": "auto"},
                 "revathi": {"at": [-3.0, 0, -10.0], "to": REVATHI_AT, "gait": "walk", "then": "idle", "face": "auto"}},
         "wait": "kavya", "min_s": 1.5, "max_s": 7.0},
        {"cam": {"eye": KAV_CAM, "look": "role:kavya", "fov": 40}, "act": {"kavya": {"anim": "talk", "face": "auto"}},
         "line": "sq01_k01"},
        {"cam": {"eye": REV_CAM, "look": "role:revathi", "fov": 40}, "act": {"revathi": {"anim": "talk", "face": "auto"}},
         "line": "sq01_r01", "wait": "revathi", "max_s": 12.0},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 46}, "line": "sq01_d02"},
        {"cam": {"eye": REV_CAM, "look": "role:revathi", "fov": 38}, "act": {"revathi": {"anim": "talk"}}, "line": "sq01_r02"},
        {"cam": {"eye": KAV_CAM, "look": "role:kavya", "fov": 38}, "act": {"kavya": {"anim": "talk", "face": "role:revathi"}},
         "line": "sq01_k02"},
        {"cam": {"eye": GROUP_CAM, "look": GROUP_LOOK, "fov": 54}, "act": {"sundaram": {"anim": "talk"}, "kavya": {"anim": "idle", "face": "role:sundaram"},
                                                                   "revathi": {"anim": "idle", "face": "role:sundaram"}},
         "line": "sq01_o03"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq01_d03"},
        {"cam": {"eye": ORG_CAM, "look": "role:sundaram", "fov": 42}, "act": {"sundaram": {"anim": "talk", "face": "auto"}},
         "line": "sq01_o04", "min_s": 1.0},
        {"cam": {"eye": GROUP_CAM, "look": GROUP_LOOK, "fov": 54}, "act": {"sundaram": {"anim": "wave"}}, "min_s": 1.4, "fade_out": 0.6},
    ],
    "flower": [
        {"cam": {"cockpit": True, "look": "role:muthu", "fov": 58}, "act": {"muthu": {"face": "auto", "anim": "wave"}},
         "line": "sq01_f01", "line_at": 0.3, "min_s": 1.8},
        {"cam": {"eye": SELLER_CAM, "eye_to": SELLER_CAM_TO, "look": "role:muthu", "fov": 46},
         "act": {"muthu": {"to": SELLER_AT, "gait": "walk", "then": "idle", "face": "auto"}}, "wait": "muthu", "min_s": 1.2, "max_s": 8.0},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq01_d07"},
        {"cam": {"eye": SELLER_CAM, "look": "role:muthu", "fov": 42}, "act": {"muthu": {"anim": "talk", "face": "auto"}}, "line": "sq01_f02"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 46}, "line": "sq01_d08"},
        {"cam": {"eye": SELLER_CAM, "look": "role:muthu", "fov": 40}, "act": {"muthu": {"anim": "talk"}}, "line": "sq01_f03"},
        {"cam": {"eye": SELLER_CAM, "look": "role:muthu", "fov": 38}, "act": {"muthu": {"anim": "wave"}}, "line": "sq01_f04"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq01_d09"},
        {"cam": {"eye": SELLER_CAM, "look": "role:muthu", "fov": 42}, "act": {"muthu": {"anim": "talk"}}, "line": "sq01_f05", "min_s": 1.0},
        {"cam": {"eye": SELLER_CAM, "look": "role:muthu", "fov": 46}, "act": {"muthu": {"anim": "wave"}}, "min_s": 1.2, "fade_out": 0.5},
    ],
    "verdict": [
        {"fade_in": 0.5, "cam": {"eye": GROUP_CAM, "eye_to": [1.1, 1.8, 8.3], "look": GROUP_LOOK, "fov": 54},
         "act": {"sundaram": {"to": SUNDARAM_AT, "gait": "walk", "then": "talk", "face": "auto"},
                 "kavya": {"to": KAVYA_AT, "gait": "walk", "then": "idle", "face": "auto"},
                 "revathi": {"to": REVATHI_AT, "gait": "walk", "then": "idle", "face": "auto"}},
         "line": "sq01_o05", "line_at": 0.6, "min_s": 2.0},
        {"cam": {"eye": KAV_CAM, "look": "role:kavya", "fov": 40}, "act": {"kavya": {"anim": "talk", "face": "auto"}},
         "wait": "kavya", "max_s": 8.0, "line": "sq01_k03"},
        {"cam": {"eye": REV_CAM, "look": "role:revathi", "fov": 40}, "act": {"revathi": {"anim": "talk", "face": "auto"}},
         "wait": "revathi", "max_s": 8.0, "line": "sq01_r03"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq01_d11"},
        {"cam": {"eye": GROUP_CAM, "look": GROUP_LOOK, "fov": 54}, "act": {"sundaram": {"anim": "idle"}}, "min_s": 0.6, "hold": True},
    ],
    "ending": [
        {"if_choice": ["decision", "SQ01_OWNER"], "cam": {"eye": KAV_CAM, "look": "role:kavya", "fov": 42},
         "act": {"kavya": {"anim": "idle", "face": "auto"}}, "line": "sq01_d12"},
        {"if_choice": ["decision", "SQ01_OWNER"], "cam": {"eye": KAV_CAM, "look": "role:kavya", "fov": 38},
         "act": {"kavya": {"anim": "wave"}}, "line": "sq01_k04"},
        {"if_choice": ["decision", "SQ01_OWNER"], "cam": {"eye": REV_CAM, "look": "role:revathi", "fov": 40}, "line": "sq01_d13"},
        {"if_choice": ["decision", "SQ01_OWNER"], "cam": {"eye": REV_CAM, "look": "role:revathi", "fov": 38},
         "act": {"revathi": {"anim": "talk", "face": "role:kavya"}}, "line": "sq01_r04"},
        {"if_choice": ["decision", "SQ01_OWNER"], "cam": {"eye": GROUP_CAM, "look": GROUP_LOOK, "fov": 54},
         "act": {"sundaram": {"anim": "talk", "face": "auto"}, "kavya": {"anim": "idle", "face": "role:revathi"}}, "line": "sq01_o06"},
        {"if_choice": ["decision", "SQ01_OTHER"], "cam": {"eye": REV_CAM, "look": "role:revathi", "fov": 40}, "line": "sq01_d14"},
        {"if_choice": ["decision", "SQ01_OTHER"], "cam": {"eye": REV_CAM, "look": "role:revathi", "fov": 38},
         "act": {"revathi": {"anim": "talk"}}, "line": "sq01_r05"},
        {"if_choice": ["decision", "SQ01_OTHER"], "cam": {"eye": KAV_CAM, "look": "role:kavya", "fov": 40},
         "act": {"kavya": {"anim": "talk", "face": "role:revathi"}}, "line": "sq01_k05"},
        {"if_choice": ["decision", "SQ01_OTHER"], "cam": {"eye": ORG_CAM, "look": "role:sundaram", "fov": 42},
         "act": {"sundaram": {"anim": "talk", "face": "auto"}}, "line": "sq01_o07"},
        {"if_choice": ["decision", "SQ01_OTHER"], "cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq01_d15"},
        # Everyone heads back in to the wedding.
        {"cam": {"eye": GROUP_CAM, "look": GROUP_LOOK, "fov": 56},
         "act": {"sundaram": {"to": "place:back_hall", "gait": "walk"}, "kavya": {"to": "place:back_hall", "gait": "walk"},
                 "revathi": {"to": "place:back_hall", "gait": "walk"}}, "min_s": 3.2, "fade_out": 0.6},
        {"act": {"sundaram": {"show": False}, "kavya": {"show": False}, "revathi": {"show": False}}, "min_s": 0.1},
    ],
}

AFTER_HALL = ["back_hall", "verdict", "decision", "ending"]
cast = {
    "sundaram": {"model": PEOPLE + "old_man_veshti.glb", "scale": 1.0, "paint": NONE, "world": ORGANISER, "face": HALL_ROAD,
                 "anim": "idle", "stages": PSA(["ask_hall", "hall"] + AFTER_HALL)},
    # Kavya and Revathi come out of the hall in the first scene, then wait at the gate.
    "kavya": {"model": PEOPLE + "woman_saree_kanchi.glb", "scale": 1.0, "paint": NONE, "world": KAVYA_WAIT, "face": HALL_ROAD,
              "anim": "idle", "stages": PSA(AFTER_HALL)},
    "revathi": {"model": PEOPLE + "woman_saree_violet.glb", "scale": 1.0, "paint": NONE, "world": REVATHI_WAIT, "face": HALL_ROAD,
                "anim": "idle", "stages": PSA(AFTER_HALL)},
    "muthu": {"model": PEOPLE + "man_casual.glb", "scale": 1.0, "paint": NONE, "world": MUTHU, "face": FLOWER_ROAD,
              "anim": "idle", "stages": PSA(["ask_flower", "flower"])},
}

barks = {
    "ask_flower": {"enter": ["sq01_d04"], "idle": ["sq01_d05", "sq01_d06"], "idle_s": V2((28.0, 42.0))},
    "back_hall": {"enter": ["sq01_d10"]},
}


def voice_script():
    cast_notes = [
        "- Sundaram: the wedding organiser, 60s, busy, kind, panicking about the muhurtham.",
        "- Kavya: the bride's cousin, about 24, honest, upset then overjoyed.",
        "- Revathi: a guest, about 45, proud and sure of herself, then embarrassed.",
        "- Muthu: M.R. Flowers on East Tank Square Street, 50s, cheerful.",
        "- Driver (hero): the same locked voice as every quest.",
    ]
    out = ['# SQ01 "The Wedding Gold": Voice Script', "",
           "Written by `tools/quests/build_sq01_story.py` (edit the lines there, not here). Generated by",
           "**Actions -> Generate quest voices** (Indic Parler-TTS, see `docs/voice/README.md`).",
           "Each bullet is one line: `id Speaker: [tags] Tamil / [tags] English`. Files land in",
           "`assets/audio/voice/sq01/<id>_<ta|en>.ogg`. Subtitles: `VO_SQ01_*` in `translations/ui.csv`.", "",
           "## Cast"] + cast_notes + ["", "## Lines"]
    for lid, spk, tags, en, ta in LINES:
        out.append(f"- {lid} {spk}: {tags} {ta} / {tags} {en}")
    (ROOT / "docs/voice/SQ01_Wedding_Gold_Voice_Script.md").write_text("\n".join(out) + "\n", encoding="utf-8")


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


speakers = dict(SPEAKER_KEYS)
write_story("sq_001", "res://assets/audio/voice/sq01", speakers, cast, {}, cutscenes, barks)
write_mission("sq_001", stages, [
    ("content_version", 4), ("title_key", "SQ01_TITLE"), ("description_key", "SQ01_DESC"), ("job_key", "SQ01_JOB"),
    ("discoverable", True), ("start_anchor", START), ("estimated_minutes", 10), ("category", "mystery"),
    ("reward_inr", 155), ("reward_xp", 15), ("reward_choice_stage", "decision"),
    ("reward_choice_inr", {"SQ01_OWNER": 155, "SQ01_OTHER": 45})])
voice_script()
update_ui_csv()
print("wrote sq_001.tres, sq_001_story.tres, the SQ01 voice script and ui.csv rows")
