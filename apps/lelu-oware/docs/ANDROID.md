# Lelu Oware on Android (plan)

Lelu Oware is the first of the two apps to go to Android. The plan shared with Lelu Ludo is
[docs/ANDROID.md](../../../docs/ANDROID.md): what is shared, what Android cannot do the same way,
costs and the order of work. This file covers what is specific to Oware. Planned 2026-11-15;
nothing is built yet.

## What ports, part by part

| iOS | Android | Notes |
|---|---|---|
| `packages/OwareEngine` (`GameState`, `RuleSet`, `Move`, `OwareMatch`, `Fingerprint`) | `android/engines/oware-engine`, Kotlin, same names | Must pass `shared/vectors/oware`. The fingerprint is FNV-1a over a fixed text, so it ports exactly. |
| `OwareAI` (`Search`, `Evaluation`, `Difficulty`, `SeededGenerator`) | Same module | SplitMix64 gives the same numbers in Kotlin with `ULong`. Compared at fixed depth, not by time. |
| `puzzles.json`, `puzzles-namnam.json` | The same files, copied by the asset script | Still made by `oware puzzles` on the Swift side: one source. |
| `BoardLayout.swift` | Ported as it is | It is arithmetic on a rectangle. Its tests port with it. |
| `BoardScene.swift` (SpriteKit) | A Compose `Canvas` and one animation clock | The largest piece of new work. Same sprites: wood, trough, pit, seeds 1–8, rims, rings, plaques, Kente line. |
| `GameSession`, `GameStore`, `Journey`, `Tutorial`, `PuzzleLibrary` | Kotlin classes with the same names, tested without a phone | Saves are JSON. The two platforms do not need to read each other's saves. |
| `SoundPlayer.swift` (built in code) | The same sounds as files, `SoundPool` | Four detuned takes of each, as now. |
| `Haptics.swift` | One small class | See the shared plan §7.4. |
| `Analytics.swift`, `PlayerEvents.swift` | Same event names and parameters | So the TelemetryDeck dashboard reads both platforms together. |
| `RiddleReminder.swift` | Notification permission and a scheduled job | Same rule: 9 am, skips a day already done. |
| `GameCenter.swift` | Not ported | Off on iOS too today. |
| `OwareTipJar`, SupportKit | Not in the first version | *Rate Lelu Oware* opens the Play listing. |
| `NearbyLobby`, `RemoteGame`, `NearbyView` | Not ported | Decided 2026-11-15: no nearby play on Android. Playing with a friend comes with online play, which reuses the lobby screens. |

## Identifiers the tests rely on

The Android app uses the identifiers listed at the top of `e2e/helpers/board.ts`, unchanged:
`home-title`, `btn-play-ai`, `btn-continue`, `btn-journey`, `btn-learn`, `btn-more`,
`btn-pass-play`, `btn-puzzles`, `btn-heritage`, `btn-settings`, `board`, `house-A1` … `house-B6`
(value "N seeds"), `store-A`, `store-B`, `turn-indicator`, `btn-undo`, `btn-home`, `hint`,
`game-over-title`, `game-over-score`, `btn-play-again`. Launch options keep the names the Maestro
flows already pass (`fastAnimations`, `rules`), read from intent extras by one `LaunchOptions`
class, as on iOS.

## The board on Android

```
 ┌──────────────────────────────────────────────┐  status bar hidden; wood runs to every edge
 │  opponent strip (~7 %)      North · red      │
 ├──────────────────────────────────────────────┤
 │ ╭───╮  ◯   ◯   ◯   ◯   ◯   ◯   ╭───╮         │
 │ │ N │                          │ S │  board (~78 %), built from parts as on iOS:
 │ ╰───╯  ◯   ◯   ◯   ◯   ◯   ◯   ╰───╯  wood · troughs · twelve pits · seeds
 ├──────────────────────────────────────────────┤
 │  player strip (~7 %)   South · gold   ⟲  ⓘ   │  Sankofa (Undo), Nyansapo (Hint): chips
 └──────────────────────────────────────────────┘  kept above the gesture area
```

- Upright phones keep the side strips and owner rings from #82, so it is clear whose side is
  whose.
- In landscape the troughs sit near the left and right edges, where the back gesture starts. They
  are not tappable. Houses keep at least 24 dp from each edge.
- A press on a house: 2–3 % lift and warmer light. No Material ripple.
- TalkBack reads each house with the same label and value as VoiceOver ("4 seeds").

## Real-phone checklist (before each build for friends)

1. Small phone and large phone: the board fills the screen, nothing under the camera cut-out.
2. Back gesture from every screen does what the plan says; in a game the game is saved.
3. A full game against the computer at the top level: no stalls, the phone does not get hot.
4. Sound at low media volume and at zero; haptics on and off.
5. Largest text size: nothing cut off on Home, Settings and the result card.
6. TalkBack: start a game, play a house, hear the turn change.
7. Rotate during a sow: the move finishes and the board is right.
8. Leave the app mid-game, return an hour later: the game is there.

## Still to decide

In the shared plan §9. For Oware in particular: the title typeface.
