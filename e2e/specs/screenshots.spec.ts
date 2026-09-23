import { byId, tapHouse, waitForTurn } from "../helpers/board";
import fs from "node:fs";
import path from "node:path";

/**
 * Opt-in: `OWARE_SCREENSHOTS=1 npm test` saves screenshots to e2e/screenshots/ for design review.
 * Skipped in normal runs and CI.
 */
const enabled = process.env.OWARE_SCREENSHOTS === "1";
const dir = path.resolve(__dirname, "../screenshots");

(enabled ? describe : describe.skip)("Screenshots", () => {
  before(() => fs.mkdirSync(dir, { recursive: true }));

  it("captures home, a mid-game board, and a long-press preview", async () => {
    await byId("home-title").waitForDisplayed();
    await browser.saveScreenshot(path.join(dir, "home.png"));

    await byId("btn-pass-play").click();
    await byId("house-A1").waitForDisplayed();
    await tapHouse("A3");
    await waitForTurn("B to move");
    await tapHouse("B2");
    await waitForTurn("A to move");
    await tapHouse("A6");
    await waitForTurn("B to move");
    await browser.saveScreenshot(path.join(dir, "board.png"));
  });
});
