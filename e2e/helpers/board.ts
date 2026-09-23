/**
 * Page-object style helpers. Every interactive element in the app carries an
 * accessibility identifier (see docs/GAME_PLAN.md §3.2) so tests never depend on
 * visible text or screen coordinates:
 *
 *   home-title, home-seed-count          (placeholder home screen, Milestone 0)
 *   house-A1 … house-A6, house-B1 … house-B6, store-A, store-B   (Milestone 2)
 */
export const byId = (id: string) => $(`~${id}`); // "~" = accessibility id selector

export async function textOf(id: string): Promise<string> {
  const el = byId(id);
  await el.waitForDisplayed();
  return el.getText();
}

export async function tapHouse(player: "A" | "B", index: 1 | 2 | 3 | 4 | 5 | 6) {
  await byId(`house-${player}${index}`).click();
}
