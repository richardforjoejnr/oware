# Lelu Ludo on Android (plan)

Lelu Ludo goes to Android **after Lelu Oware**. It reuses what Oware's work builds: the Gradle
build, the wood kit, the asset script, CI, signing and the Play account. The shared plan is
[docs/ANDROID.md](../../../docs/ANDROID.md); Oware's notes are
[here](../../lelu-oware/docs/ANDROID.md). This file covers what is different for Ludo. Planned
2026-11-15; nothing is built yet.

## What is different from Oware

| | Oware | Ludo |
|---|---|---|
| Board | SpriteKit sprites, rewritten for a Compose `Canvas` | Already drawn in code (`BoardCanvas`, `BoardLayout`, `Palette`): a near line-for-line port |
| Dice | none | `RollingDie` and the die faces in `art/source`; the roll is the one animation to get right |
| Chance | none | Dice. Test vectors carry the rolls, so both engines replay the same game. |
| Sounds | built in code on iOS | Files already (`Resources/Audio/*.m4a`); `make_audio.py` exports `.ogg` as well |
| Orientation | portrait and landscape | portrait on phones; tablets any way up |
| Players | 2 | 2–4, so pass and play matters more and the colour picker ports too |
| End-to-end tests | Appium and Maestro exist | XCUITest only today; Android starts with Compose UI tests and one Maestro flow |
| Nearby play | built on iOS | not built on iOS yet ([NEARBY_PLAY.md](NEARBY_PLAY.md)); not planned on Android, which waits for online play |

## What ports

| iOS | Android |
|---|---|
| `packages/LudoEngine` (`Board`, `GameState`, `Move`, `RuleSet`, `PlayerColor`) | `android/engines/ludo-engine`, same names, must pass `shared/vectors/ludo` |
| `LudoAI` | Same module; choices compared with a fixed seed |
| `LudoSession`, `Seating`, `Dice`, `GameStore`, `Tutorial` | Kotlin classes with the same names |
| `HomeView`, `GameView`, `ColourPicker`, `Celebration`, `SettingsPanels`, `SplashView` | Compose screens; same layout, Android conventions as in the shared plan §7.4 |
| `LudoTipJar` | Not in the first version |

Vectors for Ludo hold: a position, the roll, the legal moves, and the position after each;
whole games with their rolls; and one file per house rule (forward kick, back kick, home kick,
side kick, walls, safe squares, three sixes), so the seven rule sets the Swift reference test
covers are covered in Kotlin too.

## Design notes

- The board is a square: on a tall phone it sits in the middle with the dice and the player to
  move below it, within thumb reach. Nothing tappable in the gesture area at the bottom.
- Flag colours for the four homes as on iOS; tokens keep the 48 dp target even when the square
  is smaller, by enlarging the touch area, as the 44 pt rule does on iOS.
- Choosing between a forward move and a back kick works as it does on iOS, on the board, not in
  a Material dialog.
- TalkBack reads tokens and the die with the same labels VoiceOver has.

## Order

Step 11 of the shared plan: the same sequence as Oware's steps 1–8 (vectors, engine, computer
player, one-phone play, builds for friends, sound and touch, the lesson), about 10–14 working
days because the scaffolding exists by then.
