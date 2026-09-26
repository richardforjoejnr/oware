import { expect } from "@wdio/globals";
import { byId, openMore, seedsIn, tapHouse, waitForTurn } from "../helpers/board";

describe("Pass & Play", () => {
  before(async () => {
    await openMore();
    await byId("btn-pass-play").click();
    await byId("house-A1").waitForDisplayed();
  });

  it("starts with four seeds in every house and A to move", async () => {
    for (const h of ["A1", "A6", "B1", "B6"] as const) {
      expect(await seedsIn(h)).toBe(4);
    }
    await waitForTurn("A to move");
  });

  it("sows A1 counter-clockwise into A2…A5 and passes the turn", async () => {
    await tapHouse("A1");
    await waitForTurn("B to move");
    expect(await seedsIn("A1")).toBe(0);
    expect(await seedsIn("A2")).toBe(5);
    expect(await seedsIn("A5")).toBe(5);
    expect(await seedsIn("A6")).toBe(4);
  });

  it("refuses an empty house with a hint and keeps the turn", async () => {
    await tapHouse("B1");
    await waitForTurn("A to move");
    await tapHouse("A1"); // now empty
    await expect(byId("hint")).toBeDisplayed();
    await waitForTurn("A to move");
  });

  it("undo restores the previous position", async () => {
    await byId("btn-undo").click();
    await waitForTurn("B to move");
    expect(await seedsIn("B1")).toBe(4);
  });
});
