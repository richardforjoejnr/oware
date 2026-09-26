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
| Adinkra embossed faintly near the score areas | Tried, then removed the same evening under the restraint direction: the Heritage board is plain hardwood. Symbols stay on Undo (Sankofa) and Hint (Nyansapo) only |
| Kente border stripe | Kente edge bands and title rules on Home only; no frame on the Heritage board (the carved bands remain for the Ebony / Cape Coast / Kente looks) |
| Palette #4A2C2A / #5A3E36 / bone / #C49627 / #708238 | Added to `Theme` as `bark`, `barkLight`, `bone`, `brass`, `olive` |
| Communal, uncluttered | Pass & Play keeps one board; HUD never covers hollows |
| Capture: lift and drop into the bowl, seeds flip once, no glow | `BoardScene.animate` `.capture`: dark ring on the house (no gold fill), lift → flight → set down → one flip |
| Kente/flag colours only to mark whose turn | `GameView.kenteMark`: red·gold·green dots beside the active player's name |
| Scoreboard numerals large; retro font optional | Store counts drawn at `cell × 0.5` in the bowls; a pixel/rounded face for numerals is open, not adopted |
| Wooden percussion, optional acoustic music | Synthesised tick/pick-up/capture today; real samples and an off-by-default kalimba loop are Milestone 5 backlog |

## Asset pack (owner, 2026-09-26 evening) — `art/pack-2026-09-26/`

| File | Used as |
|---|---|
| `ghana_hardwood_texture.png` 2048² | `wood` (seam-free 1024² from the upper plank, +12 % brightness) and `ground` (same wood at 42 % brightness, desaturated) |
| `oware_pit.png` 1536² alpha | superseded the same evening (read as a bowl standing on the board) |
| `oware_score_trough.png` 1536² alpha | superseded the same evening by the board-sheet trough |
| `home_woodworker.png` 1440×2560 | `heroHome` — kept for the heritage screen; Home no longer has a hero image (dark wood, title, Continue, 2×2 grid) |
| `oware_board_master_reference.png` | reference only (it shows eight houses); the board is built from parts |
| `journey_ghana_map.png` | `splashMap`: the carved map (cropped to drop the generated caption blocks) is the **splash screen**; the small generated labels on the map remain and are worth regenerating text-free |
| `oware_seed.png` 1024² | superseded by the six stones from the board sheet |
| `sheet_journey_medallions.png` | `Journey/chapter-<id>` for the eight chapters, `chapter-locked`, `chapter-done`, `star-gold`, `star-empty`, `chapter-link` — shown in `JourneyView` |
| `sheet_wood_icons.png` | `Icons/wood-*` (back, play, plus, map, book, people, knot, gear, sound, mute, more, info, lock, unlock, star, home, close, restart, trophy, five round buttons) — the Home menu glyphs |
| `sheet_wood_panels.png` | reference only for now (carved pills would put wooden chrome back around everything) |
| `sheet_board_pits_seeds.png` | **the source for the board**: `pit` (top-down hollow), `trough` (3.09:1, bowl = 84 % of width), `seed1…8` (six grey-green stones, two rotated). Gold-ring and glow states unused. The plain horizontal board is the model for landscape |
