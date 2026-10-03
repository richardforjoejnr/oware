# Lelu Ludo — art brief

What the app needs from the owner's art (made with ChatGPT), and how to make it so it drops in. The
look follows `../../../docs/DESIGN_PRINCIPLES.md` and the mock-ups of 3 October 2026: a carved
dark-wood tray with brass corners, a cream painted board, flag colours, the black star at the centre.

## Ground rules for every image

- **No text in any image.** Titles, buttons and labels are drawn by the app (AI images garble words).
- **Transparent PNG** for anything that sits on something else (tokens, dice, cup, buttons). Ask for
  "isolated on a transparent background"; if the tool cannot, ask for a plain white *and* a plain
  black background version of the same image (the app can separate them, as was done for Oware).
- **Straight top-down** for the board and anything lying on it; no perspective, no shadows baked in
  (the app adds shadows so they match the light).
- **Square pixels, sizes as listed** (or larger in the same proportions). sRGB.
- Flag colours: red `#CE1126`, gold `#FCD116`, green `#006B3F`, black `#000000` (Ghana's flag), aged
  slightly to sit on wood. Black pieces get a thin brass rim.
- Adinkra only with meaning, and checked (see the game plan's note on the knot symbol).

## Assets

| # | Asset | File name | Size | Notes |
|---|---|---|---|---|
| 1 | **Board surface** | `board.png` | 2048×2048 | Top-down, no frame, no tokens, no dice. A 15×15 grid: yards in the corners (red top left, gold top right, black bottom right, green bottom left), cream track squares, each colour's start square and home lane painted in its colour, the centre a 3×3 square split into four triangles in the four colours with the **black star** on top. Squares exactly 1/15 of the width so the app can place tokens on them. No arrows needed (the app can draw them) |
| 2 | Board frame | `frame.png` | 2400×2400, transparent middle | The carved wooden tray seen from above: dark wood sides, brass corner caps, carved zigzag band. Inner opening exactly fits the board |
| 3 | Tokens | `token-red.png`, `-gold`, `-green`, `-black` | 256×256 each | Turned-wood pawns seen from above at a slight angle (as the token sheet), one per file, centred, transparent. Black with a brass rim |
| 4 | Selected glow | (drawn by the app) | — | No asset needed |
| 5 | Die faces | `die-1.png` … `die-6.png` | 256×256 each | Pale wood, black pips, rounded edges, seen straight on. **6 = the black star** instead of pips (proposal) |
| 6 | Die cup | `cup.png` | 768×1024 | The carved cup with the brass star lid, closed, upright, transparent background |
| 7 | Yard bowls (optional) | `yard-<colour>.png` | 512×512 | If the yards should look like carved hollows rather than painted squares |
| 8 | Home hero | `hero.png` | 1290×2796 (portrait phone) | The tray on a table with Kente cloth and plants (as the mock-ups) but **no title text** and no buttons; the menu sits over the bottom half, so keep the board in the top half |
| 9 | Splash | `splash.png` | 1290×2796 | Same scene, darker and calmer; the app writes "Lelu Ludo" on it |
| 10 | Wood textures | `wood-dark.png`, `wood-light.png` | 1024×1024, tileable | For buttons, panels and the menu |
| 11 | App icon | `AppIcon.png` | 1024×1024, **no transparency** | The black star on the cream centre with a hint of the four colours, or a token and die on wood. Must read at 60 px; no text |

## Prompts that work well (ChatGPT image)

- Board: *"Top-down orthographic view of a Ludo board surface only, 15 by 15 square grid, cream painted
  wood squares, corner yards painted in red (top left), golden yellow (top right), black (bottom
  right) and green (bottom left), home lanes in the same colours, centre square divided into four
  coloured triangles with a large black five-pointed star, slightly aged paint on wood grain, flat
  even lighting, no shadows, no text, no pieces, no dice, no frame."*
- Tokens: *"A single turned wooden Ludo pawn painted [colour], round head and flared base, slightly
  aged paint, seen from slightly above, isolated on a transparent background, no shadow, centred."*
- Die: *"A single wooden die face seen straight on, pale beech wood with rounded edges, [n] black pips
  arranged as on a standard die, isolated on a transparent background, no shadow."* (For 6: "a black
  five-pointed star in place of the pips".)

## Hand-over

Put the files in `apps/lelu-ludo/art/` with the names above (the app's asset catalogue is built from
them in stage 3 and 5). Rough versions are fine to start; the app is laid out from the board's grid,
not from the pictures, so better art can replace placeholders at any time.
