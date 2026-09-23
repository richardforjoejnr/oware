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

    await byId("btn-home").click();
    await byId("btn-puzzles").waitForDisplayed();
    await byId("btn-puzzles").click();
    await byId("puzzles-title").waitForDisplayed();
    await browser.saveScreenshot(path.join(dir, "puzzles.png"));
    await byId("btn-daily").click();
    await byId("puzzle-goal").waitForDisplayed();
    await browser.saveScreenshot(path.join(dir, "puzzle.png"));

    await byId("btn-home").click();
    await byId("btn-learn").waitForDisplayed();
    await byId("btn-learn").click();
    await byId("btn-next-step").waitForDisplayed();
    await byId("btn-next-step").click();
    await tapHouse("A3");
    await byId("tutorial-after").waitForDisplayed();
    await browser.saveScreenshot(path.join(dir, "tutorial.png"));

    await byId("btn-home").click();
    await byId("btn-heritage").waitForDisplayed();
    await byId("btn-heritage").click();
    await byId("rules-title").waitForDisplayed();
    await browser.saveScreenshot(path.join(dir, "rules.png"));
    await byId("tab-heritage").click();
    await byId("heritage-title").waitForDisplayed();
    await browser.saveScreenshot(path.join(dir, "heritage.png"));

    await byId("btn-back").click();
    await byId("btn-journey").waitForDisplayed();
    await byId("btn-journey").click();
    await byId("journey-title").waitForDisplayed();
    await browser.saveScreenshot(path.join(dir, "journey.png"));
  });
});
