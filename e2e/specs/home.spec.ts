import { expect } from "@wdio/globals";
import { byId, textOf } from "../helpers/board";

describe("Home screen", () => {
  it("shows the title and the initial 48 seeds", async () => {
    await expect(byId("home-title")).toBeDisplayed();
    expect(await textOf("home-seed-count")).toBe("Seeds on board: 48");
  });
});
