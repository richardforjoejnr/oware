# Lelu Ludo: playing online (plan)

Two to four people in different places, one board. Friends join with a 6-letter code or a link.
The whole plan, shared with Lelu Oware, is [ONLINE_PLAY.md](../../../docs/ONLINE_PLAY.md). This
file is what is specific to Ludo. Planned 2026-11-15; nothing is built.

**Ludo comes second.** Online play needs the match format, the seats and the session from steps
1–3 of [NEARBY_PLAY.md](NEARBY_PLAY.md), and none of those is built yet. The relay takes four-seat
rooms from its first version, and its tests run one, so Ludo does not wait on the server.

## What is different from Oware

| | Lelu Oware | Lelu Ludo |
|---|---|---|
| Phones | 2 | 2–4 |
| Dice | None | **The server rolls.** A phone asks; the relay makes roll number *n* once, keeps it and sends it to every phone. `LudoMatch` refuses a list of actions whose *n*th roll is not the server's, or that skips one |
| Computer seats | None | Run on the creator's phone at first; their rolls come from the server too |
| Someone leaves | The other is offered the computer | The computer takes the seat after the waiting time and the game goes on; they can take the seat back |
| The creator leaves | The game ends for both | At first, as nearby: each guest can finish against computers. Fixed when the server referees (shared plan, stage 8) |
| Message size | Under 1 KB | The match grows with every roll and move. Keep it under 32 KB (a test); send only new actions if a long game gets close |
| Cost | About US$0.001 a game | About US$0.01 a game with four phones |

Nearby play keeps the host's phone rolling: friends are in one room and no server is involved.
`LudoMatch` therefore takes "where rolls come from" as a setting: the host's `DiceSource` nearby,
the server's numbered rolls online. A roll is a number in the action list either way.

## Order

1. Nearby steps 1–3: `LudoMatch`, seats, the session (already planned).
2. `feat(lelu-play): dice for Ludo` in the AWS repo: `roll` → `rolled {n, value}`, tested for
   order, repeats and a fair spread.
3. `feat(ludo): play online with friends`: the lobby with a code, four seats and colours, computer
   seats, server rolls checked in `LudoMatch`, hidden behind `online: .off`.
4. Turn it on, with the privacy page, label and review notes.

## Still to decide

- Whether a turn timer is needed when someone puts the phone down without leaving (also open for
  nearby play). Online it matters more: three people wait.
- Whether 3–4 phones online is its own switch (`onlineFourPlayers`), as `nearbyFourPlayers` is.
