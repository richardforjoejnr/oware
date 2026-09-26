# Design brief — Lelu Oware (owner's notes, 2026-09-26) and how they are applied

The owner supplied a brief on Ghanaian woodcraft, Oware mechanics and mobile UI. The repo-wide
distillation is `../../docs/DESIGN_PRINCIPLES.md`. This file maps the brief to the app.

| Brief | Status in the app |
|---|---|
| Two rows of six pits, 48 seeds, counter-clockwise sowing, Abapa captures of 2–3, 25 to win, grand slam forfeited | Engine defaults (`RuleSet`: `winningSeeds` 25, `grandSlam: .forfeitCapture`); variants in Settings |
| Wooden board filling the screen, carved pits and end trays | `BoardLayout` fills the area; `pit`/`pitHewn` hollows; stores are carved troughs |
| Hardwood textures with grain; polish sheen; aged feel | `wood` (amber Ahwiaa), `woodHewn` (village); key light + vignette in `BoardTexture` |
| Nickernut / dark bead seeds | `seed1…8` grey-green nickernuts, difference-matted from photos |
| Small wood-themed controls; top bar for menus | Floating glass chips over the board's ends (Home, opponent, Hint, Undo / You, turn) |
| Legible contrasting type | New York serif titles, SF controls, bone/ivory on wood |
| Seeds hop pit to pit; minimal effects | Hand-carried sowing with per-seed drop, tick and haptic; no path highlight except long-press preview |
| Adinkra embossed faintly near the score areas | Faint carved Adinkrahene and Nyansapo flank each store (`BoardScene.buildCarvings`) — **Gye Nyame deliberately not used** (heritage screen only, see `CULTURE_SOURCES.md`) |
| Kente border stripe | Kente edge bands on Home; carved Adinkra band frames the Heritage board; Kente rules under the title |
| Palette #4A2C2A / #5A3E36 / bone / #C49627 / #708238 | Added to `Theme` as `bark`, `barkLight`, `bone`, `brass`, `olive` |
| Communal, uncluttered | Pass & Play keeps one board; HUD never covers hollows |
| Capture: lift and drop into the bowl, seeds flip once, no glow | `BoardScene.animate` `.capture`: dark ring on the house (no gold fill), lift → flight → set down → one flip |
| Kente/flag colours only to mark whose turn | `GameView.kenteMark`: red·gold·green dots beside the active player's name |
| Scoreboard numerals large; retro font optional | Store counts drawn at `cell × 0.5` in the bowls; a pixel/rounded face for numerals is open, not adopted |
| Wooden percussion, optional acoustic music | Synthesised tick/pick-up/capture today; real samples and an off-by-default kalimba loop are Milestone 5 backlog |
