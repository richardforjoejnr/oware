# Lelu Ludo — Ludo as it is played in Ghana

Second app in the monorepo (see the [root README](../../README.md)). Bundle id `com.richardforjoe.leluludo`.

- Plan, rules, stages and test pyramid: **[docs/GAME_PLAN.md](docs/GAME_PLAN.md)**
- Art brief for the assets: **[docs/ART_DIRECTION.md](docs/ART_DIRECTION.md)**
- Where things stand: **[docs/STATUS.md](docs/STATUS.md)**
- Rules engine: [`../../packages/LudoEngine`](../../packages/LudoEngine) (`swift test` there, or `make engine-test` at the root)

```bash
make open APP=lelu-ludo
make test APP=lelu-ludo
```
