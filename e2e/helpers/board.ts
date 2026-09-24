/**
 * Page-object style helpers. Every interactive element in the app carries an accessibility
 * identifier so tests never depend on visible text or screen coordinates:
 *
 *   Home:  home-title, btn-play-ai (primary), btn-continue, btn-journey, btn-learn, btn-level, level-<name>,
 *          btn-more reveals: btn-pass-play, btn-puzzles, btn-heritage, btn-settings
 *   Game:  board, house-A1 … house-A6, house-B1 … house-B6 (value "N seeds"),
 *          store-A, store-B (value "N seeds"), turn-indicator, btn-undo, btn-home, hint
 *   End:   game-over-title, game-over-score, btn-play-again, btn-home-overlay
 */
export const byId = (id: string) => $(`~${id}`); // "~" = accessibility id selector

export async function textOf(id: string): Promise<string> {
  const el = byId(id);
  await el.waitForDisplayed();
  return el.getText();
}

/** Accessibility value, e.g. "4 seeds" for a house. */
export async function valueOf(id: string): Promise<string> {
  const el = byId(id);
  await el.waitForDisplayed();
  return (await el.getAttribute("value")) ?? "";
}

export async function seedsIn(house: `${"A" | "B"}${1 | 2 | 3 | 4 | 5 | 6}`): Promise<number> {
  const v = await valueOf(`house-${house}`);
  return parseInt(v, 10);
}

export async function tapHouse(house: `${"A" | "B"}${1 | 2 | 3 | 4 | 5 | 6}`) {
  await byId(`house-${house}`).click();
}

export async function waitForTurn(text: string, timeout = 10_000) {
  await browser.waitUntil(async () => (await textOf("turn-indicator")) === text, {
    timeout,
    timeoutMsg: `expected turn indicator "${text}"`,
  });
}

/** Reveal the secondary menu items on the home screen if they are hidden. */
export async function openMore() {
  const settings = byId("btn-settings");
  if (!(await settings.isExisting())) {
    await byId("btn-more").click();
    await settings.waitForDisplayed();
  }
}
