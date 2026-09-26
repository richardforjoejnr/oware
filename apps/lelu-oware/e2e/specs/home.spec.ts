import { expect } from "@wdio/globals";
import { byId, openMore } from "../helpers/board";

describe("Home screen", () => {
  it("shows one primary action and hides the rest behind More", async () => {
    await expect(byId("home-title")).toBeDisplayed();
    await expect(byId("btn-play-ai")).toBeDisplayed();
    await expect(byId("btn-journey")).toBeDisplayed();
    expect(await byId("btn-pass-play").isExisting()).toBe(false);
    await openMore();
    await expect(byId("btn-pass-play")).toBeDisplayed();
    await expect(byId("btn-puzzles")).toBeDisplayed();
  });
});
