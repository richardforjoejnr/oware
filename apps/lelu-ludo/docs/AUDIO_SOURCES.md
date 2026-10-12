# Lelu Ludo — where every sound comes from

Every sound and tune in the app is listed here with its source and licence, so the app never ships audio it
has no right to. Keep the receipt or licence for anything bought or commissioned with this file.

## Now: made by the app's own script (owned outright)

`art/make_audio.py` builds every file in `LeluLudo/Resources/Audio/` from arithmetic alone: no samples,
sample libraries or AI tools. Run it from `apps/lelu-ludo` (`python art/make_audio.py`, needs numpy and
scipy, see `art/requirements.txt`); it writes the same files every time.

| File | What it is | Plays |
|---|---|---|
| `sfx-step-1…4` | A wooden pawn set down on wood (four takes, slightly different pitch) | Each square a token walks |
| `sfx-roll-1…3` | A die thrown onto wood: bounces, then a short roll | Each throw |
| `sfx-kick-1…2` | A hard knock, then the pawn clattering away | A kick |
| `sfx-home-1` | Three rising xylophone notes and a bell | A token home |
| `sfx-threeSixes-1` | Two drum hits and a falling pair of notes | Three sixes lose the turn |
| `sfx-win-1` | A run up the scale, a chord, bell and shaker | A person wins |
| `sfx-lose-1` | A gentle fall of four notes | A computer wins against you |
| `music-menu` | Harp-lute pattern with soft xylophone and shaker, 12/8, ~28 s loop | The menu |
| `music-game` | Xylophone over bell, shaker and drum, 12/8, ~29 s loop | During a game (quiet at game over) |

The instruments are imitations made in code, after the gyil (wooden xylophone with gourd
resonators), a double iron bell, a seed shaker, a hand drum and the seperewa (harp-lute). The bell
plays the common West African 12/8 pattern, which belongs to no one. The app makes no cultural claim
about the music (it names no style or people), so nothing here needs the cultural review in
`CULTURE_SOURCES.md`. If a later version names a style, it does.

## Next: replacing the stand-ins

A file with the same name replaces a stand-in with no code change. The sound effects must be mono at
44.1 kHz (`.m4a`), or that sound falls back to the synthesised tone; `MusicTests` checks this.
Add more takes of an effect by numbering on (`sfx-step-5.m4a`).

1. **Foley you record yourself** (owned outright): a real die thrown on a wooden board, pawns
   tapped and knocked over. A phone in a quiet room is enough; trim and level them before use.
2. **Music commissioned from a Ghanaian musician**: a written work-for-hire or full buyout
   agreement covering commercial use in apps, worldwide, for ever. Record the musician's name
   and the agreement's date here, and credit them in the app if they wish.
3. **CC0 libraries** (Kenney.nl, Freesound filtered to CC0, OpenGameArt filtered to CC0). Note
   each file's page URL here. Plain CC-BY is fine with a credit in the app. Never use CC-BY-NC
   (no commercial use) or CC-BY-SA (share-alike).
4. **Avoid** anything sounding like a known song, and AI-generated audio unless its plan's
   licence clearly covers commercial use (the law is unsettled).

| File | Source | Licence / agreement | Date |
|---|---|---|---|
| *(none replaced yet)* | | | |
