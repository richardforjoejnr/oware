# TypeScript end-to-end tests (Appium + WebdriverIO)

Black-box UI tests written in TypeScript against the iOS Simulator. They sit alongside the
Maestro YAML flows in `../.maestro` (quick smoke checks) and the XCUITest target (developer tests).

```bash
cd e2e
npm ci                          # installs Appium, the XCUITest driver and WebdriverIO
npm run appium:install-driver   # first time only
make -C .. e2e-build            # builds the simulator app into ../build
npm test                        # runs specs/**/*.spec.ts
```

Selectors use accessibility identifiers (`$("~house-A1")`), never text or coordinates.
Set `OWARE_SIM_NAME` to target a specific simulator, or `OWARE_APP_PATH` for a different build.
