"""Writes data/missions/side_quests/sq_003.tres, data/missions/stories/sq_003_story.tres,
docs/voice/SQ03_Margazhi_Voice_Script.md and the SQ03 / VO_SQ03 rows of translations/ui.csv.

"Margazhi Missing Beat" (v3, Nov 27 owner request: "we have not added any cutscenes or dialogues
for the Margazhi quest"). Rebuilt as a voiced story quest like Paati and the Wedding Gold.

Story: it is the Margazhi music season in Mylapore. Sankaran, a mridangam player, has a concert at
the sabha in an hour, and his mridangam is still at Ganesan's music shop, where it got new straps.
He rides in the back (QuestRider, musician.glb). Ganesan brings the drum out and warns: drive
gently, and the sabha secretary said artists and instruments go in by the BACK gate. The drive to
the hall is timed and capped at 32 km/h, and bumps hurt the drum (quality "instrument"). At the
packed front gate a volunteer asks which way: the player has to remember Ganesan's words (back
gate), or gets sent round. At the back gate Lalitha, the sabha secretary, takes them in; Sankaran
tests the drum, and the player chooses: take the fare, or stay for the concert (respect XP).

LINES is the one source for every voiced line: this script writes the voice script (the Generate
quest voices workflow voices any line without a file) and the subtitles. Until the voices exist,
a line stays up as long as it takes to read (QuestStory.reading_seconds).
Run from the repo root: python3 tools/quests/build_sq03_story.py
"""
import csv
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from story_tres import NONE, PEOPLE, PSA, ROOT, V2, V3, write_mission, write_story  # noqa: E402

START = V3((1021.0, 0, 1599.5))  # anchors.json: Sankaran waits on a ledge here
# Ganesan's music shop: the road runs north-south, the shop is on its west side.
SHOP_ROAD = V3((968.1, 0, 1557.4))
SHOP_PLACE = V3((959.7, 0, 1556.7))
GANESAN = V3((962.8, 0, 1554.6))  # in front of the shop, clear of its shopkeeper figures
# The sabha (music hall): the road runs east-west, the hall's front gate is on its south side.
HALL_ROAD = V3((1058.0, 0, 1534.6))
HALL_PLACE = V3((1057.7, 0, 1539.2))
VOLUNTEER = V3((1057.6, 0, 1538.0))
# Rasikas queueing along the pavement east of the gate, facing it.
QUEUE = [V3((1060.3, 0, 1538.4)), V3((1062.2, 0, 1538.8)), V3((1064.2, 0, 1539.2)), V3((1066.2, 0, 1539.6)),
         V3((1068.2, 0, 1540.0))]
QUEUE_FACE = V3((1050.0, 0, 1537.0))
# The hall's back gate, round the corner (east-west road, gate on the south side).
BACK_ROAD = V3((1105.4, 0, 1614.1))
BACK_PLACE = V3((1104.6, 0, 1618.6))
LALITHA = V3((1102.6, 0, 1617.1))  # beside the gate, clear of the car parked at it

# id, speaker (cast.json), emotion tags, English, Tamil.
LINES = [
    # Intro: Sankaran stops the auto and gets in
    ("sq03_s01", "Sankaran", "[calling out, hurried]", "Auto! Thambi, please stop! I have a concert at the sabha in one hour!",
     "ஆட்டோ! தம்பி, கொஞ்சம் நிறுத்துப்பா! இன்னும் ஒரு மணி நேரத்துல சபாவுல எனக்குக் கச்சேரி!"),
    ("sq03_d01", "Driver", "[friendly]", "Margazhi season, sir? Everyone in Mylapore is running to some sabha!",
     "மார்கழி சீசனா சார்? மைலாப்பூர்ல எல்லாரும் ஏதோ ஒரு சபாவுக்குத்தான் ஓடறாங்க!"),
    ("sq03_s02", "Sankaran", "[worried]", "I am Sankaran, I play the mridangam. And I left my mridangam at Ganesan's shop for new straps!",
     "நான் சங்கரன், மிருதங்கம் வாசிக்கிறேன். புது வார் போடறதுக்கு என் மிருதங்கத்தை கணேசன் கடையில விட்டுட்டு வந்துட்டேன்!"),
    ("sq03_d02", "Driver", "[surprised, amused]", "A mridangam player without his mridangam? That's like an auto without a meter!",
     "மிருதங்கம் இல்லாத மிருதங்க வித்வானா? மீட்டர் இல்லாத ஆட்டோ மாதிரி!"),
    ("sq03_s03", "Sankaran", "[laughs, then serious]", "Exactly! The shop is just round the corner. We pick it up, then straight to the sabha.",
     "அதேதான்! கடை இங்க பக்கத்துலதான். அதை எடுத்துக்கிட்டு நேரா சபாவுக்கு."),
    ("sq03_s04", "Sankaran", "[warning, gentle]", "But listen, thambi. A freshly tuned mridangam is like a newborn baby. No bumps, no sudden brakes.",
     "ஆனா கேளு தம்பி. புதுசா சுருதி சேர்த்த மிருதங்கம் பச்சைக் குழந்தை மாதிரி. குலுக்கல் கூடாது, திடீர் பிரேக் கூடாது."),
    ("sq03_d03", "Driver", "[confident]", "Don't worry, sir. Get in. I'll drive like I'm carrying eggs.",
     "கவலைப்படாதீங்க சார். ஏறுங்க. முட்டை கொண்டு போற மாதிரி ஓட்டுவேன்."),
    # Driving to the shop
    ("sq03_s05", "Sankaran", "[pointing the way]", "Ganesan's music shop is just ahead. He has made mridangams for forty years.",
     "கணேசன் இசைக் கடை இதோ முன்னாடி. நாப்பது வருஷமா மிருதங்கம் செய்யறாரு."),
    ("sq03_s06", "Sankaran", "[dreamy]", "Every December the whole city sings. Even the auto horns sound in tune!",
     "டிசம்பர் வந்தா ஊரே பாடும். ஆட்டோ ஹாரன்கூட சுருதியில கேக்கும்!"),
    ("sq03_s07", "Sankaran", "[fond, remembering]", "My first concert was in this very season, thirty years ago.",
     "என் முதல் கச்சேரி இதே மார்கழியிலதான், முப்பது வருஷத்துக்கு முன்னாடி."),
    ("sq03_s08", "Sankaran", "[startled, half joking]", "Careful! If you shake me like this, imagine what you'll do to the drum!",
     "பார்த்து! என்னையே இப்படிக் குலுக்கினா, மிருதங்கத்தை என்ன பண்ணுவே!"),
    # At the music shop
    ("sq03_g01", "Ganesan", "[cheerful, calling out]", "Sankaran sir! I knew you'd come running. Your mridangam is ready!",
     "சங்கரன் சார்! ஓடி வருவீங்கன்னு தெரியும். உங்க மிருதங்கம் தயார்!"),
    ("sq03_s09", "Sankaran", "[relieved]", "Ganesa, you've saved my life. Did you tighten the straps?",
     "கணேசா, என் உயிரைக் காப்பாத்திட்டே. வாரை இறுக்கினியா?"),
    ("sq03_g02", "Ganesan", "[proud]", "New leather straps, and fresh black paste on the right side. It rings like a temple bell now!",
     "புது தோல் வார், வலது பக்கம் புதுசா சோறு போட்டேன். இப்ப கோயில் மணி மாதிரி ஒலிக்குது!"),
    ("sq03_d04", "Driver", "[curious]", "Brother, is it heavy? Shall I help you carry it?",
     "அண்ணா, கனமா இருக்கா? தூக்க உதவி பண்ணட்டுமா?"),
    ("sq03_g03", "Ganesan", "[careful]", "Carry it like your own child. Flat on the seat, with the cloth under it.",
     "உன் சொந்தக் குழந்தை மாதிரி தூக்கு. சீட்டுல படுக்க வச்சு, கீழ துணி போட்டு."),
    ("sq03_g04", "Ganesan", "[remembering, important]", "And sir, the sabha secretary called. The front gate is full of people. Artists and instruments go in by the back gate.",
     "அப்புறம் சார், சபா செயலாளர் போன் பண்ணாங்க. முன் வாசல்ல கூட்டம் நிரம்பி இருக்கு. கலைஞர்களும் வாத்தியங்களும் பின் வாசல் வழியாதான் போகணும்."),
    ("sq03_d05", "Driver", "[noting it]", "The back gate. Got it, brother.", "பின் வாசல். புரிஞ்சுது அண்ணா."),
    ("sq03_g05", "Ganesan", "[warm, blessing]", "Go slowly, thambi. Under thirty. One big bump and the tuning is gone. Play well, sir!",
     "மெதுவா போ தம்பி. முப்பதுக்குள்ள. ஒரு பெரிய குலுக்கல் போதும், சுருதி போயிடும். நல்லா வாசிங்க சார்!"),
    # Driving to the sabha
    ("sq03_s10", "Sankaran", "[holding the drum, tense]", "Slowly now, thambi. Below thirty, please.", "இப்ப மெதுவா தம்பி. முப்பதுக்குக் கீழ, ப்ளீஸ்."),
    ("sq03_s11", "Sankaran", "[humming, playful]", "Feel that? Even the road has a rhythm. Tha ka dhi mi, tha ka dhi mi…",
     "கேக்குதா? ரோட்டுக்கும் ஒரு தாளம் இருக்கு. தக திமி, தக திமி…"),
    ("sq03_s12", "Sankaran", "[checking the time]", "The violinist will be tuning by now. We still have time.",
     "வயலின்காரர் இப்ப சுருதி சேர்த்துக்கிட்டு இருப்பாரு. இன்னும் நேரம் இருக்கு."),
    ("sq03_s13", "Sankaran", "[alarmed]", "Ayyo! My mridangam! Thambi, gently!", "ஐயோ! என் மிருதங்கம்! தம்பி, மெதுவா!"),
    ("sq03_s14", "Sankaran", "[pleading]", "Easy on the brakes, please!", "பிரேக்கை மெதுவா போடுப்பா!"),
    # The front gate
    ("sq03_v01", "Volunteer", "[busy, calling out]", "Tickets only, please! The queue starts at the corner! Sir, are you coming in?",
     "டிக்கெட் இருந்தா மட்டும்! வரிசை அந்த மூலையில இருந்து! சார், நீங்க உள்ள வர்றீங்களா?"),
    ("sq03_s15", "Sankaran", "[polite]", "I am the mridangam artist for the four o'clock concert, thambi.",
     "நாலு மணி கச்சேரிக்கு நான்தான் மிருதங்கம் வாசிக்கிறேன் தம்பி."),
    ("sq03_v02", "Volunteer", "[flustered]", "Sir! Sorry, sir! It's so crowded today. Which way are you taking the mridangam?",
     "சார்! மன்னிச்சுக்கோங்க சார்! இன்னிக்கு ரொம்பக் கூட்டம். மிருதங்கத்தை எந்த வழியா கொண்டு போறீங்க?"),
    ("sq03_s16", "Sankaran", "[thinking, to the driver]", "Thambi, Ganesan said something about the gate. Do you remember?",
     "தம்பி, கணேசன் வாசலைப் பத்தி ஏதோ சொன்னாரே. ஞாபகம் இருக்கா?"),
    # Wrong answer: the front gate
    ("sq03_d06", "Driver", "[unsure]", "The front gate, sir. It's right here.", "முன் வாசல்தான் சார். இதோ இங்கேயே இருக்கு."),
    ("sq03_v03", "Volunteer", "[alarmed]", "No, no! A mridangam can't go through this crowd! Artists go in by the back gate, round the corner.",
     "இல்ல இல்ல! இந்தக் கூட்டத்துல மிருதங்கம் போக முடியாது! கலைஞர்கள் பின் வாசல் வழியா, அந்தத் திருப்பத்துல."),
    ("sq03_s17", "Sankaran", "[sighs, kindly]", "Ganesan told us that, thambi. Never mind. The back gate, quickly!",
     "அதை கணேசன் சொன்னாரே தம்பி. பரவாயில்ல. பின் வாசல், சீக்கிரம்!"),
    # Right answer: the back gate
    ("sq03_d07", "Driver", "[confident]", "Ganesan said artists and instruments go in by the back gate, sir.",
     "கலைஞர்களும் வாத்தியங்களும் பின் வாசல் வழியான்னு கணேசன் சொன்னாரு சார்."),
    ("sq03_s18", "Sankaran", "[pleased]", "Good memory, thambi! You'd make a fine accompanist.",
     "நல்ல ஞாபக சக்தி தம்பி! நீ நல்ல பக்கவாத்தியக்காரன் ஆவே."),
    ("sq03_v04", "Volunteer", "[relieved, pointing]", "Yes sir, the back gate, just round the corner! They're waiting for you.",
     "ஆமா சார், பின் வாசல், அந்தத் திருப்பத்துலதான்! உங்களுக்காகக் காத்திருக்காங்க."),
    ("sq03_d08", "Driver", "[focused]", "Round the corner to the back gate. Hold on to it, sir.",
     "திருப்பத்துல பின் வாசலுக்கு. நல்லா புடிச்சுக்கோங்க சார்."),
    # The back gate
    ("sq03_l01", "Lalitha", "[anxious, then relieved]", "Sankaran sir! Thank God! The singer is already on the stage.",
     "சங்கரன் சார்! கடவுளுக்கு நன்றி! பாடகர் ஏற்கனவே மேடையில இருக்காரு."),
    ("sq03_s19", "Sankaran", "[calm, proud]", "Lalitha amma, the mridangam is here, and not a scratch on it.",
     "லலிதா அம்மா, மிருதங்கம் வந்தாச்சு, ஒரு கீறல்கூட இல்ல."),
    ("sq03_l02", "Lalitha", "[teasing]", "Let me hear it first. Last year you blamed the rain for the tuning!",
     "முதல்ல கேக்கட்டும். போன வருஷம் சுருதி சரியில்லைன்னு மழை மேல பழி போட்டீங்க!"),
    ("sq03_s20", "Sankaran", "[taps the drum, proud]", "Listen. Tham! Tha dhi! Perfect. Thambi drove the way a veena is played: gently.",
     "கேளுங்க. தொம்! த தி! அருமை. வீணை வாசிக்கிற மாதிரி மெதுவா ஓட்டினான் தம்பி."),
    ("sq03_l03", "Lalitha", "[warm]", "Thank you, thambi. There is an empty chair at the back of the hall, if you want to stay and listen.",
     "நன்றி தம்பி. கூடத்துக்குப் பின்னாடி ஒரு நாற்காலி காலியா இருக்கு, இருந்து கேக்கணும்னா."),
    ("sq03_s21", "Sankaran", "[smiling]", "Stay, thambi. Or take your fare. Either way, you've earned it.",
     "இருந்து கேளு தம்பி. இல்லைன்னா உன் சவாரிக் காசை வாங்கிக்கோ. எப்படியும் நீ சம்பாதிச்சதுதான்."),
    # Ending: take the fare
    ("sq03_s22", "Sankaran", "[grateful]", "Here, thambi, your fare, and a little extra for the careful driving.",
     "இந்தா தம்பி, உன் காசு, கவனமா ஓட்டினதுக்கு கொஞ்சம் கூடவே."),
    ("sq03_d09", "Driver", "[cheerful]", "Thank you, sir. Play well tonight!", "நன்றி சார். இன்னிக்கு நல்லா வாசிங்க!"),
    # Ending: stay for the concert
    ("sq03_d10", "Driver", "[delighted]", "A real Margazhi concert, from inside the hall? I'll stay, sir!",
     "கூடத்துக்குள்ள இருந்து நிஜ மார்கழி கச்சேரியா? நான் இருக்கேன் சார்!"),
    ("sq03_l04", "Lalitha", "[warm, a little strict]", "Come, I'll show you your seat. Sit quietly during the mridangam solo!",
     "வா, உன் இடத்தைக் காட்டறேன். தனி ஆவர்த்தனம் நடக்கும்போது அமைதியா உக்காரு!"),
    ("sq03_s23", "Sankaran", "[happy, heading in]", "Wish me luck, thambi. Margazhi comes only once a year!",
     "வாழ்த்து சொல்லு தம்பி. மார்கழி வருஷத்துக்கு ஒரு தடவைதான்!"),
]

SPEAKER_KEYS = {"s": "VO_SPK_SANKARAN", "d": "VO_SPK_DRIVER", "g": "VO_SPK_GANESAN", "v": "VO_SPK_VOLUNTEER",
                "l": "VO_SPK_LALITHA"}
SPEAKER_NAMES = {"VO_SPK_SANKARAN": ("Sankaran (mridangam)", "சங்கரன் (மிருதங்கம்)"),
                 "VO_SPK_GANESAN": ("Ganesan (music shop)", "கணேசன் (இசைக் கடை)"),
                 "VO_SPK_VOLUNTEER": ("Sabha volunteer", "சபா தன்னார்வலர்"),
                 "VO_SPK_LALITHA": ("Lalitha (sabha secretary)", "லலிதா (சபா செயலாளர்)")}

STRINGS = {
    "SQ03_TITLE": ("Margazhi Missing Beat", "மார்கழியின் தவறிய தாளம்"),
    "SQ03_RIDER": ("Sankaran (mridangam)", "சங்கரன் (மிருதங்கம்)"),
    "SQ03_DESC": ("A mridangam player left his drum at the music shop. Get it to the sabha before his Margazhi concert.",
                  "மிருதங்க வித்வான் தன் மிருதங்கத்தை இசைக் கடையில் விட்டுவிட்டார். மார்கழிக் கச்சேரிக்கு முன் சபாவுக்குக் கொண்டு சேர்."),
    "SQ03_JOB": ("1. Pick up Sankaran sir.\\n2. Stop beside Ganesan at the music shop for the drum.\\n3. Drive to the music hall under 32 km/h. Bumps and crashes hurt the drum.\\n4. Take it in by the right gate.",
                 "1. சங்கரன் சாரை ஏற்றிக்கொள்.\\n2. மிருதங்கத்துக்காக இசைக் கடையில் கணேசன் அருகே நிறுத்து.\\n3. 32 கி.மீ/மணிக்குள் சபாவுக்கு ஓட்டு. குலுக்கலும் மோதலும் மிருதங்கத்தைச் சேதப்படுத்தும்.\\n4. சரியான வாசல் வழியாகக் கொண்டு போ."),
    "SQ03_INTRO": ("Sankaran sir needs a ride.", "சங்கரன் சாருக்கு சவாரி வேண்டும்."),
    "SQ03_ASK_SHOP": ("Drive to the music shop and stop beside Ganesan.", "இசைக் கடைக்குப் போய் கணேசன் அருகே நிறுத்து."),
    "SQ03_SHOP": ("Ganesan brings the mridangam.", "கணேசன் மிருதங்கத்தைக் கொண்டு வருகிறார்."),
    "SQ03_APPROACH": ("Drive slowly to the music hall. Don't shake the drum!", "சபாவுக்கு மெதுவா ஓட்டு. மிருதங்கத்தைக் குலுக்காதே!"),
    "SQ03_HALL": ("The front gate is full of people.", "முன் வாசலில் கூட்டம் நிரம்பியிருக்கிறது."),
    "SQ03_GATE": ("Which gate takes the drum?", "மிருதங்கம் எந்த வாசல் வழியாகச் செல்லும்?"),
    "SQ03_REAR": ("Back gate", "பின்னாடி கேட்"),
    "SQ03_FRONT": ("Front gate", "முன்னாடி கேட்"),
    "SQ03_FRONT_LINE": ("Not this gate.", "இந்த வாசல் இல்லை."),
    "SQ03_REAR_LINE": ("To the back gate.", "பின் வாசலுக்கு."),
    "SQ03_HANDOVER": ("Drive to the back gate and stop beside the secretary. Keep the drum safe.",
                      "பின் வாசலுக்குப் போய் செயலாளர் அருகே நிறுத்து. மிருதங்கம் பத்திரம்."),
    "SQ03_BACKSTAGE": ("Sankaran sir checks his drum.", "சங்கரன் சார் மிருதங்கத்தைச் சோதிக்கிறார்."),
    "SQ03_PAYOFF": ("There is an empty seat for you in the hall.", "கூடத்தில் உனக்கு ஒரு இருக்கை காலியாக இருக்கிறது."),
    "SQ03_TAKE_FARE": ("Take the fare", "சவாரிக் காசை வாங்கு"),
    "SQ03_STAY": ("Stay for the concert", "கச்சேரி கேட்க இரு"),
    "SQ03_THANKS": ("The concert begins.", "கச்சேரி தொடங்குகிறது."),
    "SQ03_P_SHOP": ("Music Shop", "இசைக் கடை"),
    "SQ03_P_HALL": ("Music Hall", "சபா மண்டபம்"),
    "SQ03_P_BACK": ("Hall Back Gate", "சபா பின்னாடி கேட்"),
}
# Strings of the old button quest that nothing uses any more.
RETIRED = ["SQ03_BRIEF", "SQ03_READY", "SQ03_CASE", "SQ03_VERIFY", "SQ03_P_NOTICE"]

stages = [
    dict(id="intro", kind="cutscene", objective_key="SQ03_INTRO", cutscene_id="intro", duration_s=40.0),
    dict(id="ask_shop", kind="ask", objective_key="SQ03_ASK_SHOP", target=SHOP_ROAD, radius_m=9.0,
         place_key="SQ03_P_SHOP", place_pos=SHOP_PLACE),
    dict(id="shop", kind="cutscene", objective_key="SQ03_SHOP", cutscene_id="shop", duration_s=40.0),
    # The drum is in the auto from here on: timed, speed-capped, and every bump costs it.
    dict(id="approach", kind="goto", objective_key="SQ03_APPROACH", target=HALL_ROAD, radius_m=9.0, deadline_s=200.0,
         max_speed_kmh=32.0, quality_floor=15.0, quality_key="instrument", place_key="SQ03_P_HALL", place_pos=HALL_PLACE),
    dict(id="hall", kind="cutscene", objective_key="SQ03_HALL", cutscene_id="hall", duration_s=24.0),
    dict(id="gate", kind="dialogue", objective_key="SQ03_GATE", choices=PSA(["SQ03_REAR", "SQ03_FRONT"]),
         next_by_choice={"SQ03_REAR": "rear_line", "SQ03_FRONT": "front_line"}),
    dict(id="front_line", kind="cutscene", objective_key="SQ03_FRONT_LINE", cutscene_id="front_line", duration_s=14.0,
         next_id="to_back"),
    dict(id="rear_line", kind="cutscene", objective_key="SQ03_REAR_LINE", cutscene_id="rear_line", duration_s=12.0),
    dict(id="to_back", kind="ask", objective_key="SQ03_HANDOVER", target=BACK_ROAD, radius_m=9.0, quality_floor=15.0,
         quality_key="instrument", place_key="SQ03_P_BACK", place_pos=BACK_PLACE),
    dict(id="backstage", kind="cutscene", objective_key="SQ03_BACKSTAGE", cutscene_id="backstage", duration_s=34.0),
    dict(id="payoff", kind="dialogue", objective_key="SQ03_PAYOFF", choices=PSA(["SQ03_TAKE_FARE", "SQ03_STAY"])),
    dict(id="thanks", kind="cutscene", objective_key="SQ03_THANKS", cutscene_id="thanks", duration_s=16.0),
]

# Camera marks relative to the auto ([right, up, forward]; the kerb is on the left), the same ones
# the Paati quest proved: nothing framed "from" a person standing beside the auto.
FRONT = [2.1, 1.4, 7.2]          # front three-quarter of the auto, driver in view
FRONT_TO = [1.6, 1.35, 6.6]
AUTO_LOOK = [0.0, 1.05, 0.4]
BOARD_CAM = [-5.6, 1.6, 1.8]
SEAT_CAM = [2.3, 1.3, 0.4]       # Sankaran in the back seat, filmed through the road-side opening
SEAT_CAM_TO = [2.1, 1.28, 0.2]
DOOR_CAM = [0.9, 1.55, 4.0]      # in the road ahead, looking back at the kerb-side door
DOOR_CAM_TO = [0.7, 1.52, 3.6]
AT_DOOR = [-1.9, 0, -0.9]        # someone talking to the passenger at the back of the auto
RIDER_OUT = [-1.9, 0, 0.9]
OUT_FRONT = [-4.2, 1.35, 4.2]
OUT_FRONT_TO = [-3.9, 1.35, 3.8]
OUT_BACK = [-1.4, 1.55, -2.3]
OUT_SIDE = [-4.3, 1.35, -0.6]
# Shots framed on people where they stand ({"from": person} puts the lens between them and the auto).
VOL_SHOT = {"from": "role:volunteer", "dist": 3.4, "up": 1.55, "side": 1.2}
VOL_WIDE = {"from": "role:volunteer", "dist": 5.2, "up": 1.7, "side": -1.8}

# The back gate: Sankaran by the door, Lalitha 2 m ahead, both facing the auto; cameras in the road
# ahead, so the hall is behind them.
BACK_SANKARAN = [-2.0, 0, 0.0]
BACK_LALITHA = [-2.0, 0, 2.0]
BACK_MID = [-2.0, 1.3, 1.0]
BACK_TWO = [0.9, 1.55, 6.2]
BACK_TWO_TO = [0.7, 1.5, 5.8]
BACK_S_CAM = [0.2, 1.5, 4.2]
BACK_L_CAM = [0.4, 1.5, 5.4]

cutscenes = {
    # He gets up from the ledge, walks to the kerb-side door and talks; he gets in after "get in".
    "intro": [
        {"fade_in": 0.6, "cam": {"eye": {"from": "rider", "dist": 4.6, "up": 1.45, "side": 1.8}, "look": "rider", "fov": 44},
         "rider": {"out": RIDER_OUT, "face": "auto"}, "line": "sq03_s01", "line_at": 0.5},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq03_d01"},
        {"cam": {"eye": OUT_FRONT, "eye_to": OUT_FRONT_TO, "look": "rider", "fov": 44}, "line": "sq03_s02"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 46}, "line": "sq03_d02"},
        {"cam": {"eye": OUT_BACK, "look": "rider", "fov": 42}, "line": "sq03_s03"},
        {"cam": {"eye": OUT_SIDE, "look": "rider", "fov": 40}, "line": "sq03_s04"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq03_d03"},
        {"cam": {"eye": BOARD_CAM, "look": "rider", "fov": 50}, "rider": {"in": True}, "wait": "rider", "min_s": 1.2, "max_s": 20.0},
        {"cam": {"eye": BOARD_CAM, "look": AUTO_LOOK, "fov": 50}, "min_s": 0.8, "fade_out": 0.5},
    ],
    # Ganesan comes out of his shop to the auto with the drum.
    "shop": [
        {"cam": {"cockpit": True, "look": "role:ganesan", "fov": 58}, "act": {"ganesan": {"face": "auto", "anim": "wave"}},
         "line": "sq03_g01", "line_at": 0.3, "min_s": 1.6},
        # Through the windscreen while he walks round to the door (from the road ahead the auto would
        # stand between the lens and him).
        {"cam": {"cockpit": True, "look": "role:ganesan", "fov": 62},
         "act": {"ganesan": {"to": AT_DOOR, "gait": "walk", "then": "idle", "face": "rider"}}, "wait": "ganesan", "min_s": 1.2, "max_s": 8.0},
        {"cam": {"eye": SEAT_CAM, "eye_to": SEAT_CAM_TO, "look": "rider", "fov": 42}, "line": "sq03_s09"},
        {"cam": {"eye": DOOR_CAM, "look": "role:ganesan", "fov": 42}, "act": {"ganesan": {"anim": "talk", "face": "rider"}}, "line": "sq03_g02"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 46}, "line": "sq03_d04"},
        {"cam": {"eye": DOOR_CAM, "look": "role:ganesan", "fov": 40}, "act": {"ganesan": {"anim": "talk", "face": "auto"}}, "line": "sq03_g03"},
        {"cam": {"eye": DOOR_CAM, "look": "role:ganesan", "fov": 38}, "act": {"ganesan": {"anim": "talk", "face": "rider"}}, "line": "sq03_g04"},
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 48}, "line": "sq03_d05"},
        {"cam": {"eye": DOOR_CAM, "look": "role:ganesan", "fov": 42}, "act": {"ganesan": {"anim": "wave", "face": "auto"}}, "line": "sq03_g05"},
        {"cam": {"eye": SEAT_CAM, "look": "rider", "fov": 44}, "min_s": 1.0, "fade_out": 0.5},
    ],
    # The packed front gate: a volunteer and a queue of rasikas. The volunteer keeps his post at the
    # gate and every shot is framed on the people where they stand, so the scene reads the same from
    # whichever side of the road the auto stops (Nov 27 shots: walking him to an auto-relative mark
    # made him cross the road in front of the lens).
    "hall": [
        {"fade_in": 0.4, "cam": {"eye": {"from": "role:rasika_2", "dist": 6.0, "up": 1.8, "side": -2.5}, "look": "role:rasika_2", "fov": 58},
         "act": {"volunteer": {"face": "auto", "anim": "wave"}}, "line": "sq03_v01", "line_at": 0.5, "min_s": 2.0},
        {"cam": {"eye": SEAT_CAM, "eye_to": SEAT_CAM_TO, "look": "rider", "fov": 42}, "line": "sq03_s15"},
        {"cam": {"eye": VOL_SHOT, "look": "role:volunteer", "fov": 42}, "act": {"volunteer": {"anim": "talk", "face": "auto"}},
         "line": "sq03_v02"},
        {"cam": {"eye": SEAT_CAM, "look": "rider", "fov": 40}, "line": "sq03_s16"},
        {"cam": {"eye": VOL_WIDE, "look": "role:volunteer", "fov": 54}, "act": {"volunteer": {"anim": "idle"}}, "min_s": 0.6, "hold": True},
    ],
    "front_line": [
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 46}, "line": "sq03_d06"},
        {"cam": {"eye": VOL_SHOT, "look": "role:volunteer", "fov": 40}, "act": {"volunteer": {"anim": "talk", "face": "auto"}},
         "line": "sq03_v03"},
        {"cam": {"eye": SEAT_CAM, "look": "rider", "fov": 40}, "line": "sq03_s17"},
        {"cam": {"eye": VOL_WIDE, "look": "role:volunteer", "fov": 48}, "act": {"volunteer": {"anim": "wave"}}, "min_s": 1.0,
         "line": "sq03_d08", "fade_out": 0.4},
    ],
    "rear_line": [
        {"cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 46}, "line": "sq03_d07"},
        {"cam": {"eye": SEAT_CAM, "look": "rider", "fov": 40}, "line": "sq03_s18"},
        {"cam": {"eye": VOL_SHOT, "look": "role:volunteer", "fov": 44}, "act": {"volunteer": {"anim": "wave", "face": "auto"}},
         "line": "sq03_v04", "fade_out": 0.4},
    ],
    # The back gate: Sankaran gets out with his drum, Lalitha comes to meet him. Ends held on the
    # fare choice with both in frame.
    "backstage": [
        {"fade_in": 0.5, "rider": {"out": BACK_SANKARAN, "face": "auto"},
         "act": {"lalitha": {"to": BACK_LALITHA, "gait": "walk", "then": "talk", "face": "auto"}},
         "cam": {"eye": BACK_TWO, "eye_to": BACK_TWO_TO, "look": BACK_MID, "fov": 52}, "line": "sq03_l01", "line_at": 0.6},
        {"cam": {"eye": BACK_S_CAM, "look": "rider", "fov": 42}, "wait": "rider", "max_s": 6.0, "line": "sq03_s19"},
        {"cam": {"eye": BACK_L_CAM, "look": "role:lalitha", "fov": 42}, "act": {"lalitha": {"anim": "talk", "face": "rider"}},
         "wait": "lalitha", "max_s": 6.0, "line": "sq03_l02"},
        {"cam": {"eye": BACK_S_CAM, "look": "rider", "fov": 40}, "rider": {"face": "role:lalitha"}, "line": "sq03_s20"},
        {"cam": {"eye": BACK_L_CAM, "look": "role:lalitha", "fov": 42}, "act": {"lalitha": {"anim": "talk", "face": "auto"}},
         "line": "sq03_l03"},
        {"cam": {"eye": BACK_S_CAM, "look": "rider", "fov": 40}, "rider": {"face": "auto"}, "line": "sq03_s21"},
        {"cam": {"eye": BACK_TWO, "look": BACK_MID, "fov": 52}, "act": {"lalitha": {"anim": "idle", "face": "auto"}},
         "min_s": 0.6, "hold": True},
    ],
    "thanks": [
        {"if_choice": ["payoff", "SQ03_TAKE_FARE"], "cam": {"eye": BACK_S_CAM, "look": "rider", "fov": 40}, "line": "sq03_s22"},
        {"if_choice": ["payoff", "SQ03_TAKE_FARE"], "cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 46},
         "line": "sq03_d09"},
        {"if_choice": ["payoff", "SQ03_STAY"], "cam": {"eye": FRONT, "eye_to": FRONT_TO, "look": AUTO_LOOK, "fov": 46},
         "line": "sq03_d10"},
        {"if_choice": ["payoff", "SQ03_STAY"], "cam": {"eye": BACK_L_CAM, "look": "role:lalitha", "fov": 42},
         "act": {"lalitha": {"anim": "talk", "face": "auto"}}, "line": "sq03_l04"},
        {"cam": {"eye": BACK_S_CAM, "look": "rider", "fov": 40}, "line": "sq03_s23"},
        {"cam": {"eye": BACK_TWO, "look": BACK_MID, "fov": 54},
         "rider": {"walk": "place:to_back", "face": "auto"}, "act": {"lalitha": {"to": "place:to_back", "gait": "walk"}},
         "min_s": 3.4, "fade_out": 0.6},
        {"rider": {"show": False}, "act": {"lalitha": {"show": False}}, "min_s": 0.1},
    ],
}

AT_HALL = ["approach", "hall", "gate", "front_line", "rear_line"]


def rasika(model, at, scale=1.0):
    return {"model": PEOPLE + model, "scale": scale, "paint": NONE, "world": at, "face": QUEUE_FACE, "anim": "idle",
            "stages": PSA(AT_HALL)}


cast = {
    "ganesan": {"model": PEOPLE + "old_man_veshti.glb", "scale": 1.0, "paint": NONE, "world": GANESAN, "face": SHOP_ROAD,
                "anim": "idle", "stages": PSA(["ask_shop", "shop"])},
    "volunteer": {"model": PEOPLE + "young_man.glb", "scale": 1.0, "paint": NONE, "world": VOLUNTEER, "face": HALL_ROAD,
                  "anim": "idle", "stages": PSA(AT_HALL)},
    # The queue at the front gate: why the drum can't go in that way.
    "rasika_1": rasika("woman_saree_kanchi.glb", QUEUE[0]),
    "rasika_2": rasika("man_casual.glb", QUEUE[1]),
    "rasika_3": rasika("woman_saree_green.glb", QUEUE[2]),
    "rasika_4": rasika("girl_pavadai.glb", QUEUE[3], 0.9),
    "rasika_5": rasika("woman_coat.glb", QUEUE[4]),
    "lalitha": {"model": PEOPLE + "woman_saree_maroon.glb", "scale": 1.0, "paint": NONE, "world": LALITHA, "face": BACK_ROAD,
                "anim": "idle", "stages": PSA(["to_back", "backstage", "payoff", "thanks"])},
}

barks = {
    "ask_shop": {"enter": ["sq03_s05"], "idle": ["sq03_s06", "sq03_s07"], "idle_s": V2((26.0, 40.0)), "impact": "sq03_s08"},
    "approach": {"enter": ["sq03_s10"], "idle": ["sq03_s11", "sq03_s12"], "idle_s": V2((24.0, 36.0)), "impact": "sq03_s13",
                 "jolt": "sq03_s14"},
    "to_back": {"impact": "sq03_s13", "jolt": "sq03_s14"},
}


def voice_script():
    cast_notes = [
        "- Sankaran: a mridangam player, about 60, gentle and witty, nervous about his drum.",
        "- Ganesan: the music shop owner who makes mridangams, 60s, cheerful and fatherly.",
        "- Volunteer: a young sabha volunteer at the crowded front gate, flustered.",
        "- Lalitha: the sabha secretary, 40s, brisk, warm, teasing.",
        "- Driver (hero): the same locked voice as every quest.",
    ]
    out = ['# SQ03 "Margazhi Missing Beat": Voice Script', "",
           "Written by `tools/quests/build_sq03_story.py` (edit the lines there, not here). Generated by",
           "**Actions -> Generate quest voices** (Indic Parler-TTS, see `docs/voice/README.md`).",
           "Each bullet is one line: `id Speaker: [tags] Tamil / [tags] English`. Files land in",
           "`assets/audio/voice/sq03/<id>_<ta|en>.ogg`. Subtitles: `VO_SQ03_*` in `translations/ui.csv`.", "",
           "## Cast"] + cast_notes + ["", "## Lines"]
    for lid, spk, tags, en, ta in LINES:
        out.append(f"- {lid} {spk}: {tags} {ta} / {tags} {en}")
    (ROOT / "docs/voice/SQ03_Margazhi_Voice_Script.md").write_text("\n".join(out) + "\n", encoding="utf-8")


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


write_story("sq_003", "res://assets/audio/voice/sq03", dict(SPEAKER_KEYS), cast, {}, cutscenes, barks)
write_mission("sq_003", stages, [
    ("content_version", 3), ("title_key", "SQ03_TITLE"), ("description_key", "SQ03_DESC"), ("job_key", "SQ03_JOB"),
    ("discoverable", True), ("start_anchor", START), ("estimated_minutes", 10), ("category", "skill"),
    ("reward_inr", 155), ("reward_xp", 15), ("rider_model", "res://assets/models/people/quest/musician.glb"),
    ("rider_name_key", "SQ03_RIDER"), ("reward_choice_stage", "payoff"),
    ("reward_choice_inr", {"SQ03_TAKE_FARE": 155, "SQ03_STAY": 0}), ("reward_choice_xp", {"SQ03_STAY": 45})])
voice_script()
update_ui_csv()
print("wrote sq_003.tres, sq_003_story.tres, the SQ03 voice script and ui.csv rows")
