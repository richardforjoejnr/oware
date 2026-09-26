# TypeScript end-to-end tests (Appium + WebdriverIO)

Black-box UI tests written in TypeScript against the iOS Simulator. They sit alongside the
Maestro YAML flows in `../.maestro` (quick smoke checks) and the XCUITest target (developer tests).

```bash
cd e2e
npm install                     # installs Appium 3, the XCUITest driver (from package.json) and WebdriverIO
make -C .. e2e-build            # builds the simulator app into ../build
npm test                        # runs specs/**/*.spec.ts
```

Selectors use accessibility identifiers (`$("~house-A1")`), never text or coordinates.
Set `OWARE_SIM_NAME` (or `OWARE_SIM_UDID`) to target a specific simulator, or `OWARE_APP_PATH` for a different build.
The config resolves the simulator's UDID and passes `appium:udid`, so Appium attaches to the booted
simulator instead of probing Xcode for an SDK version (a 15 s, non-configurable timeout that is flaky on CI).
