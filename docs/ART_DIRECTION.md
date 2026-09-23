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

**Licence note (owner to confirm before submission).** These were generated with Canva's AI image
tool under the owner's Canva account. Canva's terms permit commercial use of generated content;
keep the Canva media IDs (`MAHWDeGSt8I`, `MAHWDWhl30o`, `MAHWDSefze8`, `MAHWDUtKk1A`, `MAHWDTiWR1Y`)
with the assets as provenance, and do not present them as photographs of a specific real board.

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
