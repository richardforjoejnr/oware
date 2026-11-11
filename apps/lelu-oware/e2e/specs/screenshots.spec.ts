import { byId, openMore, tapBelow, tapHouse, waitForTurn } from "../helpers/board";
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

    await openMore();
    await tapBelow("btn-pass-play");
    await byId("house-A1").waitForDisplayed();
    await tapHouse("A3");
    await waitForTurn("B to move");
    await tapHouse("B2");
    await waitForTurn("A to move");
    await tapHouse("A6");
    await waitForTurn("B to move");
    await browser.saveScreenshot(path.join(dir, "board.png"));

    await tapBelow("btn-home");
    await openMore(); // with a game to continue, Riddles is under More
    await tapBelow("btn-puzzles");
    await byId("puzzles-title").waitForDisplayed();
    await browser.saveScreenshot(path.join(dir, "puzzles.png"));
    await tapBelow("btn-daily");
    await byId("puzzle-goal").waitForDisplayed();
    await browser.saveScreenshot(path.join(dir, "puzzle.png"));

    await tapBelow("btn-home");
    await byId("btn-learn").waitForDisplayed();
    await tapBelow("btn-learn");
    await byId("btn-next-step").waitForDisplayed();
    await tapBelow("btn-next-step");
    await tapHouse("A3");
    await byId("tutorial-after").waitForDisplayed();
    await browser.saveScreenshot(path.join(dir, "tutorial.png"));

    await tapBelow("btn-home");
    await openMore();
    await tapBelow("btn-heritage");
    await byId("rules-title").waitForDisplayed();
    await browser.saveScreenshot(path.join(dir, "rules.png"));
    await tapBelow("tab-heritage");
    await byId("heritage-title").waitForDisplayed();
    await browser.saveScreenshot(path.join(dir, "heritage.png"));

    await tapBelow("btn-back");
    await byId("btn-journey").waitForDisplayed();
    await tapBelow("btn-journey");
    await byId("journey-title").waitForDisplayed();
    await browser.saveScreenshot(path.join(dir, "journey.png"));

    await tapBelow("btn-back");
    await openMore();
    await browser.saveScreenshot(path.join(dir, "more.png"));
  });
});
