import { execSync } from "node:child_process";
import path from "node:path";

// Path to the simulator build produced by `make e2e-build` (or the CI job).
const APP_PATH =
  process.env.OWARE_APP_PATH ??
  path.resolve(__dirname, "../build/Build/Products/Debug-iphonesimulator/Oware.app");

// Reuse the same simulator-picking logic as the Makefile / CI.
const DEVICE_NAME =
  process.env.OWARE_SIM_NAME ??
  execSync(path.resolve(__dirname, "../../../scripts/pick-simulator.sh")).toString().trim();

// Resolve the simulator UDID (booted one preferred). Passing `appium:udid` makes the
// XCUITest driver attach to exactly this simulator and skip its own
// `xcrun --sdk iphonesimulator --show-sdk-version` probe, which has a hard-coded 15 s
// timeout and is memoised on failure, so a cold xcrun cache on a busy CI runner makes
// every session attempt in that Appium process fail.
function resolveSimulatorUdid(name: string): string | undefined {
  if (process.env.OWARE_SIM_UDID) return process.env.OWARE_SIM_UDID;
  try {
    const json = JSON.parse(
      execSync("xcrun simctl list devices available -j", { stdio: ["ignore", "pipe", "ignore"] }).toString(),
    ) as { devices: Record<string, { name: string; udid: string; state: string; isAvailable: boolean }[]> };
    const matches = Object.entries(json.devices)
      .filter(([runtime]) => runtime.includes("iOS"))
      .flatMap(([, devs]) => devs)
      .filter((d) => d.name === name && d.isAvailable);
    return (matches.find((d) => d.state === "Booted") ?? matches[0])?.udid;
  } catch {
    return undefined;
  }
}
const DEVICE_UDID = resolveSimulatorUdid(DEVICE_NAME);

export const config: WebdriverIO.Config = {
  runner: "local",
  specs: ["./specs/**/*.spec.ts"],
  maxInstances: 1,
  logLevel: "info",
  waitforTimeout: 10_000,
  // Session creation includes building WebDriverAgent with xcodebuild, which can take
  // several minutes on hosted CI runners.
  connectionRetryTimeout: 600_000,
  connectionRetryCount: 1,
  // A spec file that fails is run once more on a fresh session. Tests are independent of each other,
  // so this only absorbs CI hiccups (a simulator or WebDriverAgent that starts too slowly); a real
  // failure fails both times.
  specFileRetries: 1,
  framework: "mocha",
  mochaOpts: { timeout: 120_000 },
  // spec for the log; JUnit XML next to this file (e2e/junit-<cid>.xml, gitignored), which CI uploads
  // and scripts/build-reports.py turns into the Pages test report.
  reporters: [
    "spec",
    ["junit", { outputDir: __dirname, outputFileFormat: (o: { cid: string }) => `junit-${o.cid}.xml` }],
  ],
  services: [["appium", { args: { relaxedSecurity: true } }]],
  capabilities: [
    {
      platformName: "iOS",
      "appium:automationName": "XCUITest",
      "appium:deviceName": DEVICE_NAME,
      ...(DEVICE_UDID ? { "appium:udid": DEVICE_UDID } : {}),
      "appium:app": APP_PATH,
      "appium:newCommandTimeout": 240,
      "appium:wdaLaunchTimeout": 240_000,
      "appium:wdaConnectionTimeout": 240_000,
      // The simulator is booted before the suite, but Appium checks again and gives up after 2 min
      // by default, which a busy hosted runner can exceed.
      "appium:simulatorStartupTimeout": 300_000,
      "appium:showXcodeLog": Boolean(process.env.CI),
      "appium:autoAcceptAlerts": true,
      "appium:noReset": false,
      "appium:processArguments": { args: ["--reset-state", "--fast-animations", "--rules=abapa"] },
    },
  ],
};
