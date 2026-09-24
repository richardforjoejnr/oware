# Art direction — the board, the seeds, the wood

Goal: the board in Lelu Oware should look like something a carver in Ahwiaa would sell you, lit the
way Playdead lights a scene (GAME_PLAN §3.2b). This document records what real Ghanaian boards look
like, where that comes from, and how the generated assets are used.

## 1. What Ghanaian carvers actually make

**Where.** Ahwiaa, a town of ~5,000 about 14 km north of Kumasi on the Mampong road, is the Asante
wood-carving centre; Aburi (Eastern Region) is the other well-known craft village. Ahwiaa carvers
list the *oware board* among their traditional products alongside stools, akuaba dolls, masks,
combs, linguist staffs and walking sticks (Adu-Agyem, Sabutey & Mensah 2013, plate 27).

**Wood.** Osese (*Holarrhena floribunda*, a pale, even-grained softwood), Sese/Tweneboa
(*Cordia millenii*, the "drum tree"), Gyenegyene and Nyamedua. Boards sold today are usually osese.

**Tools and process.** Adze (*soso*) for blocking; knives (*sekenmoa*) for paring; flat, V and U
gouges (*bomye*) for the hollows and relief; spokeshave for smoothing curves; hand drill.
Sequence: blocking → designing (no drawing on the wood; the form is cut directly) → detailing →
finishing: smoothing with a knife (*fefa*), sanding, then **dye** and **wax polish**. Materials on
the bench: wood dye, potash, a **shea butter and soot mix**, wax polish, lacquer, sandpaper.

**How a board looks.**
- One block of wood; two rows of six *scooped* hollows plus a larger oval store at each end.
- Hollows are often raised as bulbous, scalloped lobes rather than holes in a flat slab
  (the plate-27 board looks like twelve joined bowls on a stool-like base with a carrying loop).
- Many boards are **hinged to fold** lengthwise and latch, with the 48 seeds stored inside; when
  closed the outside is carved with an **Adinkra symbol, an elephant, or a village scene**.
- Finish: "stained inside and outside with **redwood and black dye**" — a deep red-brown with
  black pushed into the grain and recesses, then waxed to a satin (not gloss) sheen.
- Wear: rims of hollows and the carrying handle polish lighter with use; recesses stay dark.

**Seeds.** *Oware aba*: grey nickernuts (*Caesalpinia / Guilandina bonduc*), about 2 cm, hard,
smooth, glossy, pale grey to grey-green with faint darker mottling and a small dark hilum.
Sellers describe them as "grey/green tear seeds". They darken and polish with handling.
Alternatives seen in Ghana: cowries, palm kernels, pebbles.

## 2. How that becomes the game's look

| Element | Treatment |
|---|---|
| Board slab | Osese, redwood + black dye, wax satin. Slight scallop to the silhouette around each hollow. Rounded, not machine-square. |
| Hollows | Deep scooped bowls with a soft inner shadow, a lighter worn rim, faint gouge marks at the bottom. |
| Stores | Oval, same treatment, slightly deeper. |
| Rim | Shallow relief band of Adinkra symbols with black in the recesses (Sankofa, Gye Nyame only in Heritage, Dwennimmen, Nyansapo, Adinkrahene). |
| Seeds | Nickernuts: grey-green, glossy, each one a different sprite, tiny hilum. Never uniform beads. |
| Light | One warm key light, upper-left; long soft shadows; dark surround; dust in the air. |
| Colour discipline | Kente gold/red/green appear only as accents (capture flash, store rim, selection). |

## 3. Generated assets (Canva, 2026-09-23)

| File | Source prompt (abridged) | Use |
|---|---|---|
| `wood-osese.png` (1264²) | seamless carved osese texture, redwood/black dye, adze marks | Board slab fill (tiled) |
| `pit.png` (1264²) | single scooped hollow in dark stained osese | House + store bowls (masked, scaled) |
| `seeds.png` (1264², alpha) | eight grey nickernuts, background removed | Seed sprite sheet (8 variants) |
| `adinkra-rim.png` (1776×896) | relief-carved Adinkra strip | Board rim band |
| `hero-board.png` (1776×896) | full traditional board, reference | Home/Heritage hero and art reference |
| `AppIcon.png` (1024²) | one carved hollow with three nickernuts, warm key light | App icon (Canva media `MAHWDmM5VRg`) |

### 3b. Second pass (Canva, 2026-09-24) — "authentic and realistic" look

Text-to-image only (plus Canva background removal on our own output). Originals in `art/canva-exports/`.

| File | Canva media | Use |
|---|---|---|
| `bowl-hero.png` (1200×1600) | `MAHWH8Kq8TQ` | Home hero: carved osese bowl with three seeds |
| `kente-strip.png` (1776×896) | `MAHWH--ISM0` | `kenteLine` (edge bands on Home) and `kenteBand` |
| `carved-border.png` (1776×896) | `MAHWH5T7BIk` | `rimCarved`: relief band tiled round the board frame |
| `table.png` (900×1600) | `MAHWHzMvp84` | Table surface behind the board |
| `pit2.png` (1264²) | `MAHWH99f9tI` | `pit`: hollow with soft alpha edge, surround colour-matched to the wood |
| `seeds2-black.png` / `seeds2-white.png` | `MAHWH_hePmk` → cut-out `MAHWH-C9Ryo` | `seed1…8`: difference-matted brown and cream seeds |
| `wood2.png` (1264²) | `MAHWHznPiRw` | `wood`: mahogany slab texture, edges cross-faded to tile |

Processing is plain PIL/numpy (crop, resize, alpha mask, difference matting, per-channel gain);
the scripts live in the session transcript, not the repo, and are easy to redo from the originals.

**Licence and rights — what Canva's terms actually say (checked 2026-09-24).**

- *Ownership.* Canva's AI Product Terms: "you own your Output, except for any Output that modifies or
  incorporates Licensed Content", and "You may use your Output for any lawful purpose … at your own
  risk." Our images were pure text-to-image (plus Canva's background-removal tool applied to our own
  output), so no Canva library content is involved and the outputs are ours. The official terms make
  **no distinction between Free and paid plans** for AI output; some third-party blogs claim Free-plan
  outputs are non-commercial, but that is not in Canva's own terms. The Content License Agreement's
  "no trademarks / no on-demand products" list (§9) applies to Canva *library* content, not to AI
  Output you own.
- *Free app, paid app or in-app purchase.* Canva's terms do not care how the app is monetised: "any
  lawful purpose" covers a free download, a one-time purchase, or a paid app. Monetising does raise
  the stakes of any dispute, and standard plans carry **no IP indemnity** (Canva Shield is Enterprise
  only) and an explicit "no warranty" on outputs. Our prompts were generic (wood, seeds, carved
  symbols), which keeps the risk that an output resembles a specific artist's work low.
- *Copyright in the images themselves.* Purely AI-generated images are generally **not copyrightable in
  the US** (Copyright Office, Jan 2025 report: prompting alone is not authorship); the UK's
  computer-generated-works rule (CDPA s.9(3)) is more favourable. Practical meaning: we can use and
  sell with these images, but we may not be able to stop someone else copying *the raw textures*.
  The app as a whole — code, board composition, processing, layout — is human-authored and protected.
- *App icon / trademark.* Using the AI-generated icon as the app icon is fine. If the brand is ever to
  be registered as a trademark, use a human-designed wordmark rather than this image.
- *Obligations we must keep.* Canva prohibits (a) misleading anyone that AI output is human-made and
  (b) removing or altering provenance/C2PA metadata. Our processing re-saves PNGs and therefore does
  not carry the metadata through, so we keep the **original exports untouched in `art/canva-exports/`**
  as the provenance record, this document credits Canva by media ID, and the app's Heritage screen
  states that the board and seed artwork were generated with AI tools and adapted.
- *Apple.* App Review has no rule against AI-generated art; guideline 5.2 only requires that you hold
  the rights, which the AI Product Terms grant. The privacy label is unaffected.
- *Alternative if the owner wants stronger protection:* commission a Ghanaian illustrator or
  photographer for the board and seeds (the composition and pipeline stay the same; only the five
  source images change). This is the only route to images that are themselves copyrightable.

## 4. Sources
- Adu-Agyem, J., Sabutey, G. T. & Mensah, E. (2013). *New trends in the Ahwiaa wood carving industry
  in Ghana.* International Journal of Business and Management Review 1(3), 166–187. (tools, materials,
  finishing, plate 27 oware board)
- Africa Heartwood Project, "Oware (mancala) seed game": osese wood, 12 pits, 2 hinges, "stained
  inside and outside with redwood and black dye", Adinkra/elephant/village carving on the lid,
  48 grey/green seeds. https://africaheartwoodproject.org/product/oware-mancala-seed-game/
- Wikipedia, *Oware* (board forms: pedestal, hinged diptych with stores in the lid; nickernut seeds).
- Wikipedia, *Nickernut* / *Guilandina bonduc*; Mancala World, *Nickernut* ("oware aba").
- Wikipedia, *Ahwiaa*; adanwomase.com "Woodcarving in Ghana" (sese and tweneboa woods).
