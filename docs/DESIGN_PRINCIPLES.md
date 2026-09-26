# Design principles for every app in this repo

Distilled from the owner's brief (2026-09-26) and what has worked in Lelu Oware. Indie feel,
authentically Ghanaian, native iOS. Shared code for this will live in `packages/AkanKit`.

## Feel
- **The object is the screen.** The board, page or instrument fills the display; controls float
  over its edges as small glass chips. Nothing competes with the play area.
- **Quiet, warm, real.** Dark wood browns, bone-white text, one gold accent, one muted green. A
  faint vignette and aged sheen on textures; no gaudy filters, no particle showers.
- **Every tap answers at once.** Lift, carry, drop: motion tells the truth about the model. Haptics
  and sound are tied to physical events (a seed landing), never to UI chrome.
- **No gimmicks, no dark patterns.** No timers, streaks, pop-ups or paywalls. A tip jar at most.
- **Communal.** Oware is played with people around the board; layouts stay centred and uncluttered
  so a phone can be passed across a table.

## Ghanaian material
- **Wood first.** West African hardwoods (mahogany, obeche, osese): pronounced grain, hand-tool
  marks, bevelled pit edges, carved trays. Textures at 1024² or better, tiled invisibly.
- **Adinkra as language, not wallpaper.** Symbols carry meaning; each use is logged in the app's
  `CULTURE_SOURCES.md` with two sources. Sankofa = undo/history, Nyansapo = wisdom/hints,
  Adinkrahene = leadership/rank, Dwennimmen = strength with humility. **Gye Nyame is reserved for
  the heritage screen**, never decoration.
- **Kente as accent.** A narrow stripe or rule in two or three colours; never a full-screen pattern.
- **Seeds and objects from life.** Nickernuts, cowries, brass weights, calabashes — from reference
  photographs, not imagination.
- **Language.** Akan greetings and thanks where natural (Akwaaba, Medaase, Ayekoo), always with
  the English beside them the first time.

## Game pieces (from the owner's second note)
- **Pits**: twelve carved hollows with bevelled rims and a soft shadow inside; **troughs**: two
  half-round carved bowls at the ends in the same style, big numerals for captured seeds.
- **Seeds**: small, reflective, dark polished beads or nuts (nickernuts today; onyx-like stones
  are an acceptable alternative look).
- **Capture**: lift, fly, drop into the bowl, one flip as the seed settles. No glows, no neon.
- **Turn**: a tiny Kente mark (red · gold · green) beside the player to move; the only HUD colour.
- **Sound**: wooden percussion for moves (synthesised today, real samples later); optional soft
  acoustic music (kalimba, guitar) that defaults off.
- **Type**: light text on dark wood, big enough to read at a glance. A retro pixel or rounded
  sans is an option for the *scoreboard numerals only*; a carved display face for the title.

## Palette (tokens in `Theme`)
| Token | Hex | Use |
|---|---|---|
| `bark` | #4A2C2A | deep wood brown, panels |
| `barkLight` | #5A3E36 | raised wood, cards |
| `bone` | #EDE3D2 | primary text on wood |
| `brass` | #C49627 | the one accent: actions, current turn |
| `olive` | #708238 | secondary accent: success, growth |
| Kente red / green / gold | existing | stripes and rules only |

## Type
- Titles in the system serif (New York): warm and legible.
- Controls and body in the system sans (SF) via Dynamic Type; never below 13 pt.
- Bone on dark wood, contrast ≥ 4.5:1. No thin weights on textures.

## Native
- SwiftUI + SpriteKit/Rive for motion; system button styles (Liquid Glass on iOS 26, bordered
  before); 44 pt targets; Reduce Motion honoured; VoiceOver labels on every element.
- No web-style cards or full-width coloured pills.
