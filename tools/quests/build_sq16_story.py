"""Writes data/missions/side_quests/sq_016.tres, data/missions/stories/sq_016_story.tres,
docs/voice/SQ16_Ambulance_Voice_Script.md and the SQ16 / VO_SQ16 rows of translations/ui.csv.

"Room for an Ambulance" (v3, Nov 28 owner request: more side quests with cutscenes and dialogue).

Story: an ambulance is rushing a mother in labour through three bad roads of Royapettah. Constable
Pandian (22 years with a whistle that has stopped nothing) can't stand on all three, so he makes the
driver his "second constable": indicator on, pull to the kerb, stop on the marker. At each stop the
driver meets someone: Kanagu akka, whose brinjals rolled into the gutter; Sundar, a retired
ambulance driver who now drives an auto ("we never cut through, you open the road"); and Sister
Kavitha at the hospital gate, who says mother and baby are fine and that the family named the boy
after what the driver did: Indicator Kumar.

The drive is unchanged (three yield stages, indicator then stop on the marker, the pooled
ambulance, 170 Rs + 20 XP). Each person wears QuestWear items (whistle, basket, towel and specs,
stethoscope and clipboard) so they read as themselves.

LINES is the one source for every voiced line (subtitles + voice script; the Generate quest voices
workflow voices any line without a file). Run from the repo root: python3 tools/quests/build_sq16_story.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from story_common import (back_to, check_lines, driver, hold_on, talk, two, update_ui_csv, voice_script,  # noqa: E402
                          walk_up)
from story_tres import NONE, PEOPLE, PSA, V2, V3, write_mission, write_story  # noqa: E402

START = V3((537.6, 0, -490.2))  # Royapettah High Road
# The three pull-over stops (unchanged from v2, so the routes and the validator stay as they were).
STOP_A = V3((602.6, 0, -769.1))   # Westcott Road
PLACE_A = V3((608.7, 0, -769.0))
STOP_B = V3((679.6, 0, -534.3))   # Peters Road
PLACE_B = V3((682.3, 0, -538.2))
STOP_C = V3((650.6, 0, -356.2))   # the hospital gate
PLACE_C = V3((647.6, 0, -352.9))
# Where the people stand: clear kerb spots checked against the buildings and the road edge.
PANDIAN = V3((541.6, 0, -490.2))
KANAGU = V3((609.1, 0, -767.6))
SUNDAR = V3((683.8, 0, -538.2))
KAVITHA = V3((648.9, 0, -352.1))

# (id, speaker, voice tags, English, Tamil). Letters after "sq16_": p Pandian, d driver, k Kanagu,
# s Sundar, n Nurse Kavitha.
LINES = [
    # Intro: the constable at the start.
    ("sq16_p01", "Pandian", "[calling, urgent]", "Stop, stop, thambi! Not for a challan. For a favour.",
     "நில்லு நில்லு தம்பி! சலான் போடல, ஒரு உதவி வேணும்."),
    ("sq16_d01", "Driver", "[surprised]", "Sir, a constable has never asked me for a favour before. Usually there is a number attached.",
     "சார், ஒரு கான்ஸ்டபிள் எங்கிட்ட உதவி கேட்டதே இல்ல. வழக்கமா ஒரு நம்பர் இருக்கும்."),
    ("sq16_p02", "Pandian", "[serious]", "An ambulance is rushing a mother to the hospital, and it has three bad roads to cross. I can't stand on all three. Today, you are my second constable.",
     "ஒரு ஆம்புலன்ஸ் ஒரு அம்மாவை ஆஸ்பத்திரிக்குக் கொண்டு போகுது, வழியில மூணு மோசமான ரோடு. மூணு ரோட்டுலயும் என்னால நிக்க முடியாது. இன்னைக்கு நீதான் என்னோட செகண்ட் கான்ஸ்டபிள்."),
    ("sq16_d02", "Driver", "[dry]", "Second constable? Sir, does the post come with a salary?",
     "செகண்ட் கான்ஸ்டபிளா? சார், அந்த வேலைக்குச் சம்பளம் உண்டா?"),
    ("sq16_p03", "Pandian", "[proud, firm]", "It comes with something better. Pride. Now listen: indicator on, pull to the kerb, stop on the marker, let the siren pass.",
     "அதைவிட நல்லது கிடைக்கும். பெருமை. இப்போ கேளு: இண்டிகேட்டர் போடு, ஓரமா ஒதுங்கு, குறியில நில்லு, சைரன் போகட்டும்."),
    ("sq16_d03", "Driver", "[doubtful]", "Indicator, sir? In Chennai the indicator is a decoration, like the garland on a new auto.",
     "இண்டிகேட்டரா சார்? சென்னையில இண்டிகேட்டர்னா அலங்காரம், புது ஆட்டோவுக்குப் போடற மாலை மாதிரி."),
    ("sq16_p04", "Pandian", "[a small smile]", "Today the decoration works. Show them what that little orange light is for.",
     "இன்னைக்கு அலங்காரம் வேலை செய்யும். அந்தச் சின்ன ஆரஞ்சு லைட் எதுக்குன்னு எல்லாருக்கும் காட்டு."),
    ("sq16_d04", "Driver", "[curious]", "Sir, how long have you been blowing that whistle?",
     "சார், எத்தனை வருஷமா அந்த விசிலை ஊதிட்டு இருக்கீங்க?"),
    ("sq16_p05", "Pandian", "[tired, funny]", "Twenty-two years. It has stopped nothing, thambi. Not one bus, not one lorry. Only me, when I run out of breath.",
     "இருபத்தி ரெண்டு வருஷம். இது எதையும் நிறுத்தினதில்ல தம்பி. ஒரு பஸ்ஸும் இல்ல, ஒரு லாரியும் இல்ல. மூச்சு வாங்கும்போது என்னை மட்டும்தான்."),
    ("sq16_p06", "Pandian", "[urgent]", "Westcott Road first. Go! Every second counts.",
     "முதல்ல வெஸ்ட்காட் ரோடு. போ! ஒவ்வொரு நிமிஷமும் முக்கியம்."),
    # Driving barks (the driver talks himself through it).
    ("sq16_d05", "Driver", "[muttering, focused]", "Indicator first, then kerb. Indicator first, then kerb.",
     "முதல்ல இண்டிகேட்டர், அப்புறம் ஓரம். முதல்ல இண்டிகேட்டர், அப்புறம் ஓரம்."),
    ("sq16_d06", "Driver", "[amused]", "Everyone is staring at me. For once I'm not the one blocking the road.",
     "எல்லாரும் என்னையே பாக்கறாங்க. ஒரு தடவையாவது ரோட்டை அடைக்கிறது நான் இல்ல."),
    ("sq16_d07", "Driver", "[tense]", "I can feel the siren all the way into my seat.",
     "சைரன் சத்தம் சீட்டு வரைக்கும் கேக்குது."),
    ("sq16_d08", "Driver", "[calm]", "Easy now. Kerb on the left, marker ahead.",
     "மெதுவா. இடது பக்கம் ஓரம், முன்னால குறி."),
    ("sq16_d09", "Driver", "[to the auto, soothing]", "Gently, auto. Today you are a gentleman.",
     "மெதுவா, ஆட்டோ. இன்னைக்கு நீ ஜென்டில்மேன்."),
    ("sq16_d10", "Driver", "[alarmed]", "Ayyo, not now! Sorry, sorry!",
     "அய்யோ, இப்போ வேணாம்! சாரி, சாரி!"),
    # Stop A: Westcott Road, Kanagu akka.
    ("sq16_k01", "Kanagu", "[loud, dramatic]", "Ayyo, my brinjals! That siren came and they rolled straight into the gutter. Look, they are swimming!",
     "அய்யோ, என் கத்திரிக்காய்! சைரன் வந்தது, எல்லாம் சாக்கடையில உருண்டு போச்சு. பாரு, நீச்சல் அடிக்குது!"),
    ("sq16_d11", "Driver", "[concerned]", "Akka, are you alright?",
     "அக்கா, உங்களுக்கு ஒண்ணும் இல்லையே?"),
    ("sq16_k02", "Kanagu", "[still shocked]", "Me? Fine! But thambi, thirty vehicles on this road and only you used an indicator. I almost fainted.",
     "நானா? நல்லாத்தான் இருக்கேன்! ஆனா தம்பி, இந்த ரோட்டுல முப்பது வண்டி, உன் ஒருத்தனுக்குத்தான் இண்டிகேட்டர் போட்டிருக்கு. எனக்கு மயக்கமே வந்துடுச்சு."),
    ("sq16_d12", "Driver", "[gentle]", "Akka, there is a mother in labour inside that ambulance. Everyone had to make way.",
     "அக்கா, அந்த ஆம்புலன்ஸ்ல ஒரு அம்மா பிரசவ வலியோட இருக்காங்க. எல்லாரும் வழி விடணும்ல."),
    ("sq16_k03", "Kanagu", "[softening, fast]", "Ayyo, a baby on the way? Then go, go! And tell Sister Kavitha at the gate, Kanagu akka sends greens for the new mother.",
     "அய்யோ, குழந்தை வரப்போகுதா? அப்போ போ, போ! கேட்ல இருக்கற சிஸ்டர் கவிதாகிட்ட சொல்லு, புது அம்மாவுக்குக் கனகு அக்கா கீரை அனுப்பினாங்கன்னு."),
    ("sq16_d13", "Driver", "[amused]", "Greens, akka? I am a driver, not a courier.",
     "கீரையா அக்கா? நான் டிரைவர், கூரியர் இல்ல."),
    ("sq16_k04", "Kanagu", "[waving him off]", "Today you are everything. Go!",
     "இன்னைக்கு நீ எல்லாமே. போ!"),
    # Stop B: Peters Road, Sundar the retired ambulance driver.
    ("sq16_s01", "Sundar", "[warm, impressed]", "Shabash! Indicator, kerb, marker. Twenty years on an ambulance, I never saw it done so cleanly.",
     "சபாஷ்! இண்டிகேட்டர், ஓரம், குறி. இருபது வருஷம் ஆம்புலன்ஸ் ஓட்டினேன், இவ்வளவு சுத்தமா யாரும் செஞ்சதில்ல."),
    ("sq16_d14", "Driver", "[surprised]", "You drove an ambulance, sir?",
     "நீங்க ஆம்புலன்ஸ் ஓட்டினீங்களா சார்?"),
    ("sq16_s02", "Sundar", "[wry]", "Twenty years, thambi. Now I drive an auto. Slower vehicle, same problem. Nobody listens.",
     "இருபது வருஷம் தம்பி. இப்போ ஆட்டோ ஓட்டறேன். வண்டி மெதுவு, பிரச்சனை அதே. யாரும் கேக்கறதில்ல."),
    ("sq16_d15", "Driver", "[curious]", "Sir, how does an ambulance get through all this traffic?",
     "சார், இவ்வளவு டிராஃபிக்ல ஆம்புலன்ஸுக்கு எப்படி வழி கிடைக்கும்?"),
    ("sq16_s03", "Sundar", "[quiet, wise]", "We never cut through. You open the road, thambi. The siren only asks.",
     "நாங்க வழி கிழிச்சுப் போறதில்ல. நீங்கதான் வழி திறக்கறீங்க தம்பி. சைரன் கேக்க மட்டும்தான் செய்யும்."),
    ("sq16_s04", "Sundar", "[stern, then smiling]", "And never follow an ambulance close to jump the traffic. That is not helping. That is cheating.",
     "ஆம்புலன்ஸ் பின்னாடியே போய் டிராஃபிக்கைத் தாண்டாத. அது உதவி இல்ல. ஏமாத்து."),
    ("sq16_d16", "Driver", "[guilty]", "Sir, I would never. ... I did it once. In 2019.",
     "சார், நான் அப்படிச் செய்யவே மாட்டேன். ... ஒரே ஒரு தடவை செஞ்சேன். 2019-ல."),
    ("sq16_s05", "Sundar", "[kind, serious]", "Hmm. Go. The last stop is the hospital gate. Gently, thambi, a mother is aboard.",
     "ம்ம். போ. கடைசி இடம் ஆஸ்பத்திரி கேட். மெதுவாப் போ தம்பி, ஒரு அம்மா உள்ள இருக்காங்க."),
    # Stop C: the hospital gate, Sister Kavitha.
    ("sq16_n01", "Kavitha", "[breathless, grateful]", "Thank you, thank you! The ambulance radioed ahead: a yellow auto with an indicator that works. We thought they were joking.",
     "நன்றி, நன்றி! ஆம்புலன்ஸ் ரேடியோவுல சொன்னாங்க: வேலை செய்யற இண்டிகேட்டரோட ஒரு மஞ்சள் ஆட்டோவாம். நாங்க கிண்டல்னு நெனச்சோம்."),
    ("sq16_d17", "Driver", "[anxious]", "Sister, is everything alright? The mother?",
     "சிஸ்டர், எல்லாம் நல்லா இருக்கா? அந்த அம்மா?"),
    ("sq16_n02", "Kavitha", "[smiling, warm]", "Mother and baby are both fine. A healthy boy, born just inside the gate.",
     "அம்மாவும் குழந்தையும் ரெண்டு பேரும் நல்லா இருக்காங்க. ஆரோக்கியமான ஆண் குழந்தை, கேட்டுக்குள்ள வந்ததும் பிறந்தான்."),
    ("sq16_d18", "Driver", "[delighted]", "A boy! That is wonderful!",
     "ஆண் குழந்தையா! சூப்பர்!"),
    ("sq16_n03", "Kavitha", "[teasing]", "The family asked who made way for them on the road. I said, an auto driver. They want to name the baby after you.",
     "ரோட்டுல வழி விட்டது யாருன்னு குடும்பம் கேட்டாங்க. ஆட்டோ டிரைவர்னு சொன்னேன். உங்க பேரையே குழந்தைக்கு வைக்கணும்னு சொல்றாங்க."),
    ("sq16_d19", "Driver", "[embarrassed]", "Ayyo, no need, Sister. My name is nothing special.",
     "அய்யோ, வேணாம் சிஸ்டர். என் பேர்ல ஒண்ணுமில்ல."),
    ("sq16_n04", "Kavitha", "[mischievous]", "You never told us your name. So they chose the next best thing. They named him after what you did.",
     "நீங்க பேரே சொல்லல. அதனால அடுத்த நல்ல விஷயத்தைத் தேர்ந்தெடுத்தாங்க. நீங்க செஞ்சதையே பேரா வெச்சிட்டாங்க."),
    ("sq16_d20", "Driver", "[puzzled]", "What did I do?",
     "நான் என்ன செஞ்சேன்?"),
    ("sq16_n05", "Kavitha", "[proud, straight-faced]", "Indicator. His name is Indicator Kumar.",
     "இண்டிகேட்டர். அவன் பேரு இண்டிகேட்டர் குமார்."),
    ("sq16_d21", "Driver", "[horrified, laughing]", "Sister, please tell me you are joking.",
     "சிஸ்டர், தயவு செஞ்சு இது ஜோக்குன்னு சொல்லுங்க."),
    ("sq16_n06", "Kavitha", "[laughing]", "The form is already filled, brother.",
     "ஃபார்ம் ஏற்கனவே நிரப்பியாச்சு அண்ணா."),
    ("sq16_d22", "Driver", "[amused, wondering]", "Indicator Kumar. One day that boy will be a constable, and all of Chennai will have to listen to him.",
     "இண்டிகேட்டர் குமார். ஒரு நாள் அந்தப் பையன் கான்ஸ்டபிள் ஆவான், சென்னையே அவன் பேச்சைக் கேக்கணும்."),
    ("sq16_n07", "Kavitha", "[warm, quiet]", "Go home, brother. Today Chennai gave way. Remember how it felt.",
     "வீட்டுக்குப் போங்க அண்ணா. இன்னைக்குச் சென்னை வழி விட்டுச்சு. அந்த உணர்வை நினைவு வெச்சுக்கோங்க."),
]

SPEAKER_KEYS = {"p": "VO_SPK_PANDIAN", "d": "VO_SPK_DRIVER", "k": "VO_SPK_KANAGU", "s": "VO_SPK_SUNDAR",
                "n": "VO_SPK_KAVITHA_NURSE"}
SPEAKER_NAMES = {"VO_SPK_PANDIAN": ("Constable Pandian", "கான்ஸ்டபிள் பாண்டியன்"),
                 "VO_SPK_KANAGU": ("Kanagu akka", "கனகு அக்கா"),
                 "VO_SPK_SUNDAR": ("Sundar (ex-ambulance)", "சுந்தர் (முன்னாள் ஆம்புலன்ஸ்)"),
                 "VO_SPK_KAVITHA_NURSE": ("Sister Kavitha", "சிஸ்டர் கவிதா")}

STRINGS = {
    "SQ16_INTRO": ("Constable Pandian needs your help.", "கான்ஸ்டபிள் பாண்டியனுக்கு உன் உதவி வேணும்."),
    "SQ16_PASSED": ("The ambulance is through.", "ஆம்புலன்ஸ் கடந்துடுச்சு."),
    "SQ16_GATE": ("The hospital gate.", "ஆஸ்பத்திரி கேட்."),
}
RETIRED = []

stages = [
    dict(id="intro", kind="cutscene", objective_key="SQ16_INTRO", target=START, cutscene_id="intro", duration_s=70.0),
    dict(id="brief", kind="dialogue", objective_key="SQ16_BRIEF", choices=PSA(["SQ16_READY"])),
    dict(id="yield_1", kind="yield", objective_key="SQ16_YIELD_1", target=STOP_A, radius_m=11.0, deadline_s=190.0,
         place_key="SQ16_P_A", place_pos=PLACE_A),
    dict(id="scene_a", kind="cutscene", objective_key="SQ16_PASSED", cutscene_id="scene_a", duration_s=50.0),
    dict(id="yield_2", kind="yield", objective_key="SQ16_YIELD_2", target=STOP_B, radius_m=11.0, deadline_s=190.0,
         place_key="SQ16_P_B", place_pos=PLACE_B),
    dict(id="scene_b", kind="cutscene", objective_key="SQ16_PASSED", cutscene_id="scene_b", duration_s=55.0),
    dict(id="yield_3", kind="yield", objective_key="SQ16_YIELD_3", target=STOP_C, radius_m=11.0, deadline_s=170.0,
         place_key="SQ16_P_C", place_pos=PLACE_C),
    dict(id="scene_c", kind="cutscene", objective_key="SQ16_GATE", cutscene_id="scene_c", duration_s=75.0),
]

cutscenes = {
    # The constable at the start waves the auto over and makes the driver his second constable.
    "intro": walk_up("pandian", "sq16_p01", 0.6, "wave") + [
        driver("sq16_d01"),
        talk("pandian", "sq16_p02", 36),
        driver("sq16_d02"),
        talk("pandian", "sq16_p03", 38),
        driver("sq16_d03"),
        talk("pandian", "sq16_p04", 36),
        driver("sq16_d04"),
        talk("pandian", "sq16_p05", 36),
        two("pandian", "sq16_p06", 48),
        hold_on("pandian", 46),
    ],
    "scene_a": walk_up("kanagu", "sq16_k01", 0.5) + [
        driver("sq16_d11"),
        talk("kanagu", "sq16_k02", 36),
        driver("sq16_d12"),
        talk("kanagu", "sq16_k03", 36),
        driver("sq16_d13"),
        two("kanagu", "sq16_k04", 48, "wave"),
        back_to("kanagu", KANAGU),
    ],
    "scene_b": walk_up("sundar", "sq16_s01", 0.5) + [
        driver("sq16_d14"),
        talk("sundar", "sq16_s02", 38),
        driver("sq16_d15"),
        talk("sundar", "sq16_s03", 34),
        talk("sundar", "sq16_s04", 38),
        driver("sq16_d16"),
        two("sundar", "sq16_s05", 48),
        back_to("sundar", SUNDAR),
    ],
    "scene_c": walk_up("nurse", "sq16_n01", 0.5) + [
        driver("sq16_d17"),
        talk("nurse", "sq16_n02", 38),
        driver("sq16_d18"),
        talk("nurse", "sq16_n03", 38),
        driver("sq16_d19"),
        talk("nurse", "sq16_n04", 38),
        driver("sq16_d20"),
        talk("nurse", "sq16_n05", 34),
        driver("sq16_d21"),
        talk("nurse", "sq16_n06", 36),
        driver("sq16_d22"),
        dict(two("nurse", "sq16_n07", 46), fade_out=0.8),
    ],
}

AT_START = ["intro", "brief"]
AT_A = ["yield_1", "scene_a"]
AT_B = ["yield_2", "scene_b"]
AT_C = ["yield_3", "scene_c"]

cast = {
    "pandian": {"model": PEOPLE + "police_m_ips.glb", "scale": 1.0, "world": PANDIAN, "face": START, "anim": "idle",
                "wear": PSA(["whistle"]), "stages": PSA(AT_START)},
    "kanagu": {"model": PEOPLE + "woman_saree_maroon.glb", "scale": 1.0, "world": KANAGU, "face": STOP_A, "anim": "idle",
               "wear": PSA(["basket", "jasmine"]), "stages": PSA(AT_A)},
    "sundar": {"model": PEOPLE + "old_man_veshti.glb", "scale": 1.0, "world": SUNDAR, "face": STOP_B, "anim": "idle",
               "wear": PSA(["towel", "specs"]), "stages": PSA(AT_B)},
    "nurse": {"model": PEOPLE + "woman_coat.glb", "scale": 1.0, "world": KAVITHA, "face": STOP_C, "anim": "idle",
              "wear": PSA(["stethoscope", "clipboard"]), "stages": PSA(AT_C)},
}
for c in cast.values():
    c["paint"] = NONE

# The driver talks himself through each pull-over; a knock or a jolt makes him yelp.
barks = {
    "yield_1": {"enter": ["sq16_d05"], "idle": ["sq16_d06", "sq16_d07", "sq16_d08"], "idle_s": V2((22.0, 36.0)),
                "impact": "sq16_d10", "jolt": "sq16_d10"},
    "yield_2": {"enter": ["sq16_d08"], "idle": ["sq16_d09", "sq16_d07", "sq16_d06"], "idle_s": V2((24.0, 38.0)),
                "impact": "sq16_d10", "jolt": "sq16_d10"},
    "yield_3": {"enter": ["sq16_d09"], "idle": ["sq16_d08", "sq16_d07", "sq16_d05"], "idle_s": V2((24.0, 38.0)),
                "impact": "sq16_d10", "jolt": "sq16_d10"},
}

check_lines(LINES, cutscenes, barks)

CAST_NOTES = [
    "- Pandian (Constable Pandian): traffic constable, about 45, tired and dry-funny, twenty-two years with a whistle that has stopped nothing.",
    "- Kanagu (Kanagu akka): a vegetable seller on Westcott Road, 50s, loud, dramatic and kind.",
    "- Sundar: a retired ambulance driver who now drives an auto, 60s, quiet and wise, a little wry.",
    "- Kavitha (Sister Kavitha): the nurse at the hospital gate, 30s, breathless, warm and teasing.",
    "- Driver (hero): the same locked voice as every quest.",
]

if __name__ == "__main__":
    write_story("sq_016", "res://assets/audio/voice/sq16", dict(SPEAKER_KEYS), cast, {}, cutscenes, barks)
    write_mission("sq_016", stages, [
        ("content_version", 3), ("title_key", "SQ16_TITLE"), ("description_key", "SQ16_DESC"), ("job_key", "SQ16_JOB"),
        ("discoverable", True), ("start_anchor", START), ("estimated_minutes", 7), ("category", "community"),
        ("reward_inr", 170), ("reward_xp", 20)])
    voice_script("SQ16_Ambulance_Voice_Script.md", "Room for an Ambulance", "16", "build_sq16_story.py", CAST_NOTES, LINES)
    update_ui_csv(STRINGS, SPEAKER_NAMES, LINES, RETIRED)
    print("wrote sq_016.tres, sq_016_story.tres, the SQ16 voice script and ui.csv rows")
