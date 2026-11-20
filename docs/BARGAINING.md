# Bargaining

## How a bargain works

1. The rider opens with an offer and hides the most they will pay. The meter fare is on the card.
2. The driver accepts, asks the meter or a bit more, asks high, or lets the ride go.
3. An ask within the top price closes the deal. Otherwise the rider counters and loses patience.
4. A greedy ask (22 % or more past the top price) costs double. At zero patience the rider walks.

Clues on the card tell the driver which way the top price leans:

| Pays more | Pays less |
|---|---|
| Looks in a hurry, heavy bags, raining, late night, new to the city, with family | Checking a cab app, counting change, bus stop close by |

Rush hour, a good star rating and auto decoration raise the top price. Recent greed lowers it, because word spreads at the stand. The meter is always within the top price, so an honest ask never fails.

**Stakes:** a walkout costs the fare and some respect, and an insult costs more. Fair deals in a row pay ₹5 per deal at the drop, up to ₹25. A rider charged over 125 % of the meter tips half.

## What riders and the driver say (Nov 20)

Every moment has ten lines in English and Tamil, spoken aloud (`SavariVoice`, lines in
`tools/voice/savari_lines.py`, voices in `assets/audio/voice/sav/`):

| Moment | Who | Example (EN / TA) |
|---|---|---|
| The auto comes within 38 m | rider shouts, line shows over their head | "Auto! Auto!" / "ஆட்டோ! ஆட்டோ!" |
| The card opens | rider names the place, then makes an offer | "T. Nagar, please. This is all I can pay." / "டி. நகர் போகணும். இவ்வளவுதான் தர முடியும்." |
| Ask the meter / a bit more / high | the driver says it, then the rider counters (or angrily, after a greedy ask) | "Meter rate only." → "Bring it down a little." |
| Accept | driver, then rider | "Okay, get in." → "Okay, let's go." |
| Let it go, a timeout or a walk-out | rider (after the driver, when he refused) | "Leave it, I'll take the bus." |
| The drop | rider, happy or upset | "Right on time, thanks." / "You hit every pothole!" |

Riders speak in one of four voices by the character at the kerb: man, woman, elder (he calls the
driver தம்பி, not அண்ணா) and college girl. A place is named in 4 of its 10 phrasings per voice,
rotating so all 10 are heard; a nearby street gets "Just the next street." style lines. The
round's 9-second clock starts after the rider has finished speaking. The driver's lines are the
hero's locked voice.

## Where the ideas come from

* **Offers, counters, and patience that greedy offers burn fast:** [Kingdom Come: Deliverance 2](https://www.videogamer.com/guides/kingdom-come-deliverance-2-haggle-how-to).
* **Hidden limits and real stakes, not visible percentages:** [The Angry GM](https://theangrygm.com/haggling-and-shopping/).
* **Customer budgets and a reward for a run of good deals:** the idea commonly credited to Recettear. This is from general knowledge, because the page checked did not load.

## Meter rates

The game uses [Tamil Nadu's fares from 29 October 2026](https://www.deccanchronicle.com/amp/southern-states/tamil-nadu/auto-fares-fixed-at-rs-50-minimum-rs-25-for-each-additional-km-1999848): ₹50 for 1.8 km, ₹25/km after, and 1.5× from 10 PM to 5 AM. Waiting charge is not modelled.

Everything earned or bought from the driver's pocket was scaled by about 1.4 to match: autos, upgrades, horns, paint, repairs, towing, quest rewards, goal bonuses and tips. Fuel prices and traffic fines stay as they were, because the fare order did not change them.
