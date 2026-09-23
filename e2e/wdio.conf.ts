import { execSync } from "node:child_process";
import path from "node:path";

// Path to the simulator build produced by `make e2e-build` (or the CI job).
const APP_PATH =
  process.env.OWARE_APP_PATH ??
  path.resolve(__dirname, "../build/Build/Products/Debug-iphonesimulator/Oware.app");

// Reuse the same simulator-picking logic as the Makefile / CI.
const DEVICE_NAME =
  process.env.OWARE_SIM_NAME ??
  execSync(path.resolve(__dirname, "../scripts/pick-simulator.sh")).toString().trim();

export const config: WebdriverIO.Config = {
  runner: "local",
  specs: ["./specs/**/*.spec.ts"],
  maxInstances: 1,
  logLevel: "info",
  waitforTimeout: 10_000,
  connectionRetryTimeout: 120_000,
  framework: "mocha",
  mochaOpts: { timeout: 120_000 },
  reporters: ["spec"],
  services: [["appium", { args: { relaxedSecurity: true } }]],
  capabilities: [
    {
      platformName: "iOS",
      "appium:automationName": "XCUITest",
      "appium:deviceName": DEVICE_NAME,
      "appium:app": APP_PATH,
      "appium:newCommandTimeout": 240,
      "appium:autoAcceptAlerts": true,
      "appium:noReset": false,
    },
  ],
};
