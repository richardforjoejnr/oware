# Lelu Ludo — cultural sources

As for Lelu Oware: every Ghanaian word or symbol the app uses is listed here with where it came
from, and stays marked **to confirm** until a native speaker has checked it and there are two
sources.

## Phrases on the game-over card and the home cheer (`Outcome` in LudoSession.swift)

| Phrase | Meaning | Where it shows | Source | Status |
|---|---|---|---|---|
| **Wadi nkunim!** | Twi, "you have won" (contracted from *wo adi nkunim*; the same form also reads "she/he has won") | Win card, green ribbon | The owner (2026-10-10), correcting "M'adi nkonim" ("I've won") to the second person, as the game speaks to the player | To confirm: spelling (*nkunim* / *nkonim*) with a native speaker; second written source |
| **Wa ri, wa ri!** | "You've lost, you've lost!": teasing from the winner | Lose card, red ribbon | Reported from a Ghana Black Stars Ludo match (Yen.com.gh), via the owner's research; chosen by the owner (2026-10-10) | To confirm: a second source and a native speaker (meaning and spelling) |
| **Eiii! Chale!** | An excited cheer; *chale* is Ghanaian Pidgin/English for "friend, mate" | Bubble over your token when it reaches home | Everyday Ghanaian English; the owner (2026-10-10) | To confirm: second written source |

The words are set by the app, not painted into the art (art/make_celebration.py), so a correction is
a one-line change to `Outcome.winPhrase`, `losePhrase` or `homePhrase`.
