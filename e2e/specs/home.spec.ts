import { expect } from "@wdio/globals";
import { byId } from "../helpers/board";

describe("Home screen", () => {
  it("shows the title and both ways to play", async () => {
    await expect(byId("home-title")).toBeDisplayed();
    await expect(byId("btn-play-ai")).toBeDisplayed();
    await expect(byId("btn-pass-play")).toBeDisplayed();
  });
});
