#!/usr/bin/env python3
"""Savari (street ride) dialogue: the one source for its strings and its voice script.

Nov 20 owner request: "In the Savari mode … some 10 variety of dialogues in English and Tamil
for each item, like a passenger calling auto, or saying the place to go (T. Nagar ponum) …
also voice dialogs for the bargain features."

Writes:
  translations/ui.csv            SAV_* keys (en, ta) — replaces any SAV_* rows already there
  docs/voice/SAV_Savari_Voice_Script.md   every voiced line, for Actions -> Generate quest voices
Usage: python3 tools/voice/savari_lines.py

Riders speak in one of four voices, picked from the character standing at the kerb (SavariManager
VOICE_OF): man, woman, elder, girl. Every rider line exists in all four. The elder says "தம்பி"
where the others say "அண்ணா" (he is older than the driver). Destination lines name the place:
each (place, voice) pair voices 4 of the 10 templates, rotating so that all 10 are heard
(dest_templates()). The hero "Driver" speaks his side of the bargain in his locked voice.
Voice files: assets/audio/voice/sav/<id>_<ta|en>.ogg.
"""
from __future__ import annotations

import csv
import io
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CSV = ROOT / "translations" / "ui.csv"
SCRIPT = ROOT / "docs" / "voice" / "SAV_Savari_Voice_Script.md"

VOICES = ["man", "woman", "elder", "girl"]
SPEAKER = {"man": "Rider Man", "woman": "Rider Woman", "elder": "Rider Elder", "girl": "Rider Girl"}
DEST_PER_VOICE = 4

# Places a rider names. The game maps every destination (manifest landmarks, stands, zones) to
# one of these by name (SavariManager.PLACE_OF); "near" is a road-name destination nearby.
PLACES = {
    "tnagar": ("T. Nagar", "டி. நகர்"),
    "mylapore_tank": ("Mylapore tank", "மயிலாப்பூர் குளம்"),
    "kapali": ("Kapaleeshwarar temple", "கபாலீஸ்வரர் கோயில்"),
    "lighthouse": ("the Lighthouse", "லைட்ஹவுஸ்"),
    "marina": ("Marina Beach", "மெரினா பீச்"),
    "mount_road": ("Mount Road", "மவுண்ட் ரோடு"),
    "napier": ("Napier Bridge", "நேப்பியர் பாலம்"),
    "vivekananda": ("Vivekananda House", "விவேகானந்தர் இல்லம்"),
    "lic": ("the LIC building", "எல்.ஐ.சி. பில்டிங்"),
    "gemini": ("the Gemini flyover", "ஜெமினி பாலம்"),
    "panagal": ("Panagal Park", "பனகல் பார்க்"),
}

# Ten ways to name the place. %s = the place. Index-aligned English / Tamil.
DEST = [
    ("%s, please.", "%s போகணும்."),
    ("Will you go to %s?", "%s போவீங்களா?"),
    ("Can you take me to %s?", "%s வரைக்கும் வருவீங்களா?"),
    ("I need to get to %s. Coming?", "%s பக்கம் போகணும், வரீங்களா?"),
    ("%s. Shall we go?", "அண்ணா, %s போகலாமா?"),
    ("%s, quickly please. I'm in a hurry.", "%s போகணும் அண்ணா, அவசரம்."),
    ("All the way to %s, can you?", "%s வரைக்கும் போகணும்."),
    ("%s? Come, let's go.", "%s, போலாமா?"),
    ("Can you drop me at %s?", "%s வரைக்கும் விடுறீங்களா?"),
    ("Straight to %s, please.", "நேரா %s போங்க."),
]
# The same ten for a short trip to a nearby street (its road name stays on the card only).
NEAR = [
    ("Just nearby, two streets away.", "பக்கத்துலதான், ரெண்டு தெரு தள்ளி."),
    ("It's close by. Will you come?", "இங்க பக்கத்துலதான், வருவீங்களா?"),
    ("Not far. Shall we go?", "கொஞ்ச தூரம்தான், போலாமா?"),
    ("Just the next street.", "அடுத்த தெருதான் அண்ணா."),
    ("I need the road next to this one.", "பக்கத்து ரோடு போகணும்."),
    ("It's close, we'll be there quickly.", "கிட்டதான், சீக்கிரம் போயிடலாம்."),
    ("Only a little way from here.", "இங்கிருந்து கொஞ்ச தூரம்தான்."),
    ("A house nearby. Can you drop me?", "பக்கத்துல ஒரு வீடு, விடுறீங்களா?"),
    ("I'll show you the way. Go.", "நான் வழி சொல்றேன், போங்க."),
    ("It's not far. Come.", "ரொம்ப தூரம் இல்ல, வாங்க."),
]

# Rider lines: category -> (acting tag, ten (English, Tamil) lines).
RIDER = {
    "call": ("shouting", [
        ("Auto, please!", "ஆட்டோ!"),  # "Auto!" alone came out silent in the girl's voice
        ("Auto! Auto!", "ஆட்டோ! ஆட்டோ!"),
        ("Hey, auto!", "அண்ணா, ஆட்டோ!"),
        ("Auto, stop please!", "ஆட்டோ, கொஞ்சம் நில்லுங்க!"),
        ("Boss, are you free?", "அண்ணா, ஃப்ரீயா?"),
        ("Auto, free?", "ஆட்டோ, வருமா?"),
        ("Over here! Auto!", "இங்க! ஆட்டோ!"),
        ("This side, this side!", "அண்ணா, இந்தப் பக்கம்!"),
        ("Auto, will you come?", "ஆட்டோ, வருவீங்களா?"),
        ("Hello, auto!", "ஹலோ, ஆட்டோ!"),
    ]),
    # The rider's opening price; the amount is on the card, never spoken.
    "open": ("conversational", [
        ("This is all I can pay.", "இவ்வளவுதான் தர முடியும்."),
        ("Will you come for this much?", "இதுக்கு வருவீங்களா?"),
        ("I always pay this much.", "எப்பவும் இவ்வளவுதான் குடுப்பேன்."),
        ("This is the fair price.", "நியாயமா இதுதான் வரும்."),
        ("I don't have more than this.", "இதுக்கு மேல கையில இல்ல."),
        ("This is enough, right?", "இவ்வளவு போதும் தானே?"),
        ("Don't ask too much. This is it.", "ரொம்ப கேக்காதீங்க, இதுதான்."),
        ("Shall we go at this rate?", "இந்த ரேட்டுக்கு போலாமா?"),
        ("I pay this every day.", "டெய்லி இவ்வளவுதான் குடுக்கறேன்."),
        ("I'll give you this much, okay?", "இவ்வளவு தரேன், சரியா?"),
    ]),
    "counter": ("firm", [
        ("No no, that's too much.", "இல்ல இல்ல, ரொம்ப அதிகம்."),
        ("Bring it down a little.", "கொஞ்சம் குறைங்க அண்ணா."),
        ("I can't pay that much.", "அவ்வளவு எல்லாம் முடியாது."),
        ("Meet me in the middle.", "நடுவுல வாங்க, இவ்வளவு தரேன்."),
        ("That much? Make it a bit less.", "அய்யோ, அவ்வளவா? கொஞ்சம் கம்மி பண்ணுங்க."),
        ("Okay, I'll add a little.", "சரி, கொஞ்சம் ஏத்தித் தரேன்."),
        ("The app is cheaper than that, you know.", "ஆப்ல இதைவிட கம்மி தெரியுமா?"),
        ("Just agree to this much.", "இவ்வளவுக்கு ஓகே பண்ணுங்க."),
        ("It's not that far. Bring it down.", "ரொம்ப தூரம் இல்லையே, குறைங்க."),
        ("Be reasonable, please.", "கொஞ்சம் பாத்துக் குடுங்க அண்ணா."),
    ]),
    "angry": ("angry", [
        ("Are you joking? Last offer!", "விளையாடுறீங்களா? இதுதான் கடைசி!"),
        ("What is this, daylight robbery?", "என்ன இது, பகல் கொள்ளையா?"),
        ("Asking that much? Is that fair?", "அவ்வளவு கேக்கறீங்களே, நியாயமா?"),
        ("Not one paisa more!", "இதுக்கு மேல ஒரு பைசா கூட இல்ல!"),
        ("This is my last price, or I'm going.", "இதுதான் கடைசி ரேட், இல்லனா போறேன்."),
        ("Why so much? This is it.", "ஏன் இவ்வளவு கேக்கறீங்க? இதுதான்."),
        ("Too much, way too much!", "அய்யோ, ரொம்ப ஓவர்!"),
        ("Don't try to cheat me!", "சும்மா ஏமாத்தாதீங்க!"),
        ("Take it, or I'll find another auto.", "வேணும்னா இது, இல்லனா வேற ஆட்டோ."),
        ("Final answer, this much only!", "கடைசியா சொல்றேன், இவ்வளவுதான்!"),
    ]),
    "deal": ("happy", [
        ("Okay, let's go.", "சரி, போலாம்."),
        ("Fine, fine, let's go.", "ஓகே, ஓகே, வாங்க போலாம்."),
        ("Okay, I'm getting in.", "சரி அண்ணா, ஏறிக்கறேன்."),
        ("Alright, go quickly.", "சரி, சீக்கிரம் போங்க."),
        ("Deal. Let's move.", "டீல், கிளம்புங்க."),
        ("Okay, never mind, fine.", "சரி சரி, பரவாயில்ல."),
        ("Hmm, okay, let's go.", "ம்ம், சரி போலாம்."),
        ("Good, start the auto.", "நல்லது, வண்டிய எடுங்க."),
        ("Okay, drive safely.", "சரி, பத்திரமா போங்க."),
        ("Okay, I'm in. Go.", "ஓகே, ஏறிட்டேன், போங்க."),
    ]),
    "walk": ("frustrated", [
        ("Forget it, I'll find another auto.", "வேண்டாம், வேற ஆட்டோ பாக்கறேன்."),
        ("Leave it, I'll take the bus.", "விடுங்க, பஸ்லயே போயிடறேன்."),
        ("Not for that price. Go.", "இவ்வளவுக்கு முடியாது, போங்க."),
        ("Okay, leave it.", "சரி, விடுங்க."),
        ("I'll book on the app.", "ஆப்ல புக் பண்ணிக்கறேன்."),
        ("This won't work.", "இது சரிப்பட்டு வராது."),
        ("Someone else will come.", "வேற யாராவது வருவாங்க."),
        ("I'll just walk.", "நடந்தே போயிடறேன்."),
        ("No use talking to you.", "உங்ககிட்ட பேசி பிரயோஜனம் இல்ல."),
        ("You go. I'll wait for another.", "போங்க, நான் வேற ஆட்டோக்கு காத்திருக்கேன்."),
    ]),
    "happy": ("happy", [
        ("Nice driving, thank you!", "நல்லா ஓட்டினீங்க, நன்றி!"),
        ("Right on time, thanks.", "சரியான நேரத்துக்கு வந்துட்டோம், தேங்க்ஸ்."),
        ("That was very comfortable.", "ரொம்ப சௌகரியமா இருந்தது."),
        ("Thank you, see you again.", "நன்றி அண்ணா, மறுபடியும் பாக்கலாம்."),
        ("Super, we got here fast!", "சூப்பர், சீக்கிரம் வந்துட்டோம்!"),
        ("You got me here safely, thanks.", "பத்திரமா கொண்டு வந்தீங்க, நன்றி."),
        ("Good ride, thank you so much.", "நல்ல சவாரி, ரொம்ப நன்றி."),
        ("Next time I'll call you again.", "அடுத்த தடவையும் உங்களையே கூப்பிடறேன்."),
        ("Wonderful, no tension at all.", "அருமை, டென்ஷனே இல்ல."),
        ("Thanks, take care.", "தேங்க்ஸ் அண்ணா, நல்லா இருங்க."),
    ]),
    "upset": ("scared", [
        ("Drive slowly, I was scared!", "மெதுவா ஓட்டுங்க, பயமா இருந்தது!"),
        ("We're very late.", "ரொம்ப லேட் ஆயிடுச்சு."),
        ("You hit every pothole!", "என்ன இது, எல்லா பள்ளத்துலயும் விட்டீங்க!"),
        ("Why brake like that?", "இப்படி பிரேக் போட்டா எப்படி?"),
        ("I won't take your auto again.", "இனிமே உங்க ஆட்டோல வரமாட்டேன்."),
        ("My back hurts. Drive carefully.", "முதுகு வலிக்குது, கொஞ்சம் பாத்து ஓட்டுங்க."),
        ("Why did it take so long?", "இவ்வளவு நேரமா ஆகும்?"),
        ("All my things fell over!", "என் பொருள் எல்லாம் விழுந்துடுச்சு!"),
        ("Here's the money, but I'm not happy.", "பணம் தரேன், ஆனா திருப்தி இல்ல."),
        ("Ayyo, I almost died!", "அய்யோ, உயிர் போயிடுச்சு!"),
    ]),
}

# The hero's side of the bargain (his locked voice). meter / more / high follow the ask button.
DRIVER = {
    "meter": [
        ("Just pay the meter, that's enough.", "மீட்டர் படி குடுங்க, போதும்."),
        ("Meter rate only.", "மீட்டர் ரேட் போதும்."),
        ("Fair and square, by the meter.", "நியாயமா, மீட்டர் படிதான்."),
        ("Come on, the meter fare, that's all.", "மீட்டருக்கு வாங்க, அவ்வளவுதான்."),
        ("Give me the meter money.", "மீட்டர் காசு குடுங்க."),
        ("I'm only asking the government rate.", "அரசு ரேட் தான் கேக்கறேன்."),
        ("Meter charge, nothing more.", "மீட்டர் சார்ஜ், அதுக்கு மேல வேணாம்."),
        ("Let's go by the meter.", "மீட்டர் படியே போலாம்."),
        ("Right price, it's the meter.", "சரியான ரேட், மீட்டர் தான்."),
        ("Check the meter and pay that.", "மீட்டர் பாத்துக்கோங்க, அதே குடுங்க."),
    ],
    "more": [
        ("Add a little more.", "கொஞ்சம் சேர்த்துக் குடுங்க."),
        ("Gas prices went up, a bit more.", "கேஸ் விலை ஏறிடுச்சு, கொஞ்சம் கூட."),
        ("Heavy traffic, add a little.", "டிராஃபிக் ஜாஸ்தி, கொஞ்சம் கூட போடுங்க."),
        ("Put a little extra.", "கொஞ்சம் மேல போடுங்க."),
        ("I'll come back empty, give a bit more.", "திரும்ப காலியா வரணும், கொஞ்சம் கூட குடுங்க."),
        ("That little? Raise it a bit.", "அவ்வளவு கம்மியா? கொஞ்சம் ஏத்துங்க."),
        ("Fairly, it comes to a bit more.", "நியாயமா கொஞ்சம் கூட வரும்."),
        ("Driving in this heat, add a little.", "வெயில்ல ஓட்டணும், கொஞ்சம் சேருங்க."),
        ("Just a little more, that's all.", "இன்னும் கொஞ்சம், அவ்வளவுதான்."),
        ("A bit more and we leave right now.", "கொஞ்சம் கூட குடுத்தா உடனே கிளம்பலாம்."),
    ],
    "high": [
        ("At this hour, the rate is higher.", "இந்த நேரத்துக்கு ரேட் ஜாஸ்தி."),
        ("That's far, it'll cost a lot.", "அவ்வளவு தூரம், நிறைய ஆகும்."),
        ("In this traffic, you have to pay this.", "இந்த டிராஃபிக்ல இவ்வளவு குடுக்கணும்."),
        ("Nobody goes that side. Pay more.", "அந்த பக்கம் யாரும் போக மாட்டாங்க, கூட குடுங்க."),
        ("I have to go round the one-way. It costs more.", "ஒன் வே சுத்தணும், ஜாஸ்தி ஆகும்."),
        ("I won't get a ride back from there.", "திரும்பி வர சவாரி கிடைக்காது."),
        ("Pay what I ask and I'll come.", "கேட்டது குடுத்தா வரேன்."),
        ("This is my rate. Come if you want.", "இதுதான் என் ரேட், வேணும்னா வாங்க."),
        ("That little won't cover it.", "அவ்வளவு கம்மிக்கு கட்டுப்படியாகாது."),
        ("Pay a good rate and I'll drop you nicely.", "நல்ல ரேட் குடுங்க, நல்லா கொண்டு போய் விடறேன்."),
    ],
    "accept": [
        ("Okay, get in.", "சரி, ஏறுங்க."),
        ("Fine, come, let's go.", "சரி, வாங்க போலாம்."),
        ("Okay, sit down.", "ஓகே, உக்காருங்க."),
        ("Alright, alright, get in.", "சரி சரி, ஏறுங்க."),
        ("No problem, let's go.", "பரவாயில்ல, போலாம்."),
        ("Okay, mind your step.", "சரி, பாத்து ஏறுங்க."),
        ("Okay, let's leave.", "ஓகே, கிளம்பலாம்."),
        ("Okay, just for you.", "சரி, உங்களுக்காக."),
        ("Fine, let's go.", "சரி, போயிடலாம்."),
        ("Get in, we'll be there quickly.", "ஏறுங்க, சீக்கிரம் போயிடலாம்."),
    ],
    "letgo": [
        ("No, I'm not going that side.", "இல்ல, அந்த பக்கம் வரல."),
        ("No, leave it.", "வேண்டாம், விடுங்க."),
        ("That price doesn't work for me.", "அவ்வளவுக்கு கட்டுப்படியாகாது."),
        ("Find another auto.", "வேற ஆட்டோ பாருங்க."),
        ("No, I can't come.", "இல்லங்க, வண்டி வராது."),
        ("I'm not going that way now.", "இப்போ அந்த பக்கம் போகல."),
        ("Sorry, can't do it.", "சாரி, முடியாது."),
        ("No, I'm done for now.", "இல்ல, டைம் ஆச்சு."),
        ("Take the next auto.", "அடுத்த ஆட்டோல போங்க."),
        ("No thanks, I'm off.", "வேணாம், நான் கிளம்பறேன்."),
    ],
}


def tamil_for(voice: str, ta: str) -> str:
    """The elder rider calls the (younger) driver தம்பி, not அண்ணா."""
    return ta.replace("அண்ணா", "தம்பி") if voice == "elder" else ta


def dest_templates(voice: str, place_index: int) -> list[int]:
    """Which of the 10 destination templates this voice speaks for this place (same in the game)."""
    g = VOICES.index(voice)
    return [(g * 3 + j + place_index) % 10 for j in range(DEST_PER_VOICE)]


def place_ids() -> list[str]:
    return list(PLACES) + ["near"]


def rows() -> list[tuple[str, str, str]]:
    out = []
    for pid, (en, ta) in PLACES.items():
        out.append((f"SAV_PLACE_{pid.upper()}", en, ta))
    for i, (en, ta) in enumerate(DEST, 1):
        out.append((f"SAV_DEST_{i:02d}", en, ta))
    for i, (en, ta) in enumerate(NEAR, 1):
        out.append((f"SAV_NEAR_{i:02d}", en, ta))
    for cat, (_tag, lines) in RIDER.items():
        for i, (en, ta) in enumerate(lines, 1):
            out.append((f"SAV_{cat.upper()}_{i:02d}", en, ta))
    for cat, lines in DRIVER.items():
        for i, (en, ta) in enumerate(lines, 1):
            out.append((f"SAV_DRV_{cat.upper()}_{i:02d}", en, ta))
    return out


def script() -> str:
    head = """# Savari (street rides): Voice Script

Generated by `tools/voice/savari_lines.py` — edit the lines there, not here. Voices:
`assets/audio/voice/sav/<id>_<ta|en>.ogg`. Rider voices follow the character at the kerb (man,
woman, elder, college girl); the elder says தம்பி where others say அண்ணா. Each destination is
voiced with 4 of its 10 phrasings per rider voice, rotating so all 10 are heard.

## Cast
- Rider Man: Chennai man, 25-40, casual. Rider Woman: Chennai woman, 30-50, brisk.
- Rider Elder: man in his 60s, slow and slightly hoarse. Rider Girl: college girl, about 20, quick.
- Driver (hero): the locked hero voice, same as every quest.
"""
    out = [head]
    out.append("\n## Rider lines\n")
    for voice in VOICES:
        out.append(f"\n### {SPEAKER[voice]}\n")
        for cat, (tag, lines) in RIDER.items():
            for i, (en, ta) in enumerate(lines, 1):
                out.append(f"- sav_{cat}_{i:02d}_{voice} {SPEAKER[voice]}: [{tag}] {tamil_for(voice, ta)} / [{tag}] {en}")
        for pi, pid in enumerate(place_ids()):
            for t in dest_templates(voice, pi):
                if pid == "near":
                    en, ta = NEAR[t]
                else:
                    en, ta = DEST[t][0] % PLACES[pid][0], DEST[t][1] % PLACES[pid][1]
                    en = en[0].upper() + en[1:]
                out.append(f"- sav_dest_{pid}_{t + 1:02d}_{voice} {SPEAKER[voice]}: [conversational] "
                           f"{tamil_for(voice, ta)} / [conversational] {en}")
    out.append("\n## Driver (hero) bargaining\n")
    for cat, lines in DRIVER.items():
        for i, (en, ta) in enumerate(lines, 1):
            out.append(f"- sav_drv_{cat}_{i:02d} Driver: [conversational] {ta} / [conversational] {en}")
    return "\n".join(out) + "\n"


def write_csv() -> None:
    text = CSV.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    kept = [ln for ln in lines if not ln.startswith("SAV_")]
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    for key, en, ta in rows():
        w.writerow([key, en, ta])
    if kept and not kept[-1].endswith("\n"):
        kept[-1] += "\n"
    CSV.write_text("".join(kept) + buf.getvalue(), encoding="utf-8")


def main() -> int:
    write_csv()
    SCRIPT.write_text(script(), encoding="utf-8")
    n = sum(1 for ln in script().splitlines() if ln.startswith("- sav_"))
    print(f"{len(rows())} strings, {n} voiced lines ({n * 2} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
