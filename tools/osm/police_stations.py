"""Greater Chennai Police law-and-order stations whose areas fall inside the map box.

Codes and names from the Greater Chennai Police station list (Wikipedia "Greater Chennai Police",
Greater Chennai Corporation police-station page): R1 Mambalam, R4 Soundarapandiyanar Angadi (Pondy
Bazaar), E1 Mylapore, E2 Royapettah, E3 Teynampet, E4 Abiramapuram, E5 Foreshore Estate,
D1 Triplicane, D2 Anna Salai, D3 Ice House, D4 Zam Bazaar, D5 Marina, D6 Anna Square,
F3 Nungambakkam, F4 Thousand Lights. Positions are each station's neighbourhood (approximate);
a junction takes the name of the nearest one, so its booth reads like the real one there.
Index order is the sign atlas order (tools/art/make_police_signs.py) - append only.
"""
STATIONS = [
    # code, English area, Tamil area, lat, lon
    ("R-1", "MAMBALAM", "மாம்பலம்", 13.0388, 80.2318),
    ("R-4", "PONDY BAZAAR", "பாண்டி பஜார்", 13.0414, 80.2345),
    ("E-1", "MYLAPORE", "மயிலாப்பூர்", 13.0340, 80.2690),
    ("E-2", "ROYAPETTAH", "ராயப்பேட்டை", 13.0545, 80.2640),
    ("E-3", "TEYNAMPET", "தேனாம்பேட்டை", 13.0440, 80.2500),
    ("E-4", "ABIRAMAPURAM", "அபிராமபுரம்", 13.0310, 80.2560),
    ("E-5", "FORESHORE ESTATE", "ஃபோர்ஷோர் எஸ்டேட்", 13.0292, 80.2785),
    ("D-1", "TRIPLICANE", "திருவல்லிக்கேணி", 13.0600, 80.2760),
    ("D-2", "ANNA SALAI", "அண்ணா சாலை", 13.0640, 80.2630),
    ("D-3", "ICE HOUSE", "ஐஸ் ஹவுஸ்", 13.0530, 80.2790),
    ("D-4", "ZAM BAZAAR", "ஜாம் பஜார்", 13.0560, 80.2735),
    ("D-5", "MARINA", "மெரினா", 13.0440, 80.2810),
    ("D-6", "ANNA SQUARE", "அண்ணா சதுக்கம்", 13.0668, 80.2832),
    ("F-3", "NUNGAMBAKKAM", "நுங்கம்பாக்கம்", 13.0610, 80.2400),
    ("F-4", "THOUSAND LIGHTS", "ஆயிரம் விளக்கு", 13.0590, 80.2530),
]
