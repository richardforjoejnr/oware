# Lelu Oware: action list to TestFlight and the App Store

Your to-do list, in order. Tick items as you go. Details for services are in [SERVICES.md](SERVICES.md);
signing and CI are in [../../../docs/PIPELINE.md](../../../docs/PIPELINE.md); store text is in
[APP_STORE.md](APP_STORE.md). Written 27 September 2026.

## Stage 0: this week, before the paid membership

Nothing here needs the US$99 Apple Developer Program.

- [ ] **Merge the open PRs in order:** #23, then #24, then #25. After each: `git checkout main && git pull && make project`.
- [ ] **Play it with family on your own iPhones** (see "Testing with family before you pay" below).
- [ ] **Write down what testers find.** A simple note per device: what they tapped, what felt wrong.
- [ ] **Support email:** choose the address and put it in `docs/lelu-oware/privacy.md` and `support.md`.
- [ ] **Cultural review:** read Heritage, the Journey names and the Twi wording in the app.
- [ ] **"Lelu":** confirm what the name means, for the store description.
- [ ] **Accounts that are free:** create the Kit (newsletter) and TelemetryDeck (analytics) accounts
      now; see SERVICES.md sections 4 and 6. Paste the Kit form values into `newsletter.md`.

### Testing with family before you pay

You can put the app on a few iPhones straight from Xcode with a free Apple ID. The limits:
apps stop opening after **7 days** (plug in and run again to renew), only **a few devices**
(Apple allows about three on a free account), and each phone must be **plugged into your Mac**
the first time. TestFlight needs the paid membership.

1. In Xcode ▸ Settings ▸ Accounts, sign in with your Apple ID. It appears as a "Personal Team".
2. In Terminal, in the repo: `make family APP=lelu-oware`. This opens a copy of the project
   without Game Center (free accounts cannot sign it) and with a separate bundle id
   (`com.richardforjoe.oware.family`) so the real one stays free for your paid account.
3. In Xcode select the **Oware** target ▸ Signing & Capabilities ▸ Team: your Personal Team.
4. Plug in the family iPhone, unlock it and tap **Trust**. Choose it as the run destination and
   press Run (▶).
5. On the iPhone, first time only:
   - Settings ▸ Privacy & Security ▸ **Developer Mode** ▸ on, then restart.
   - Settings ▸ General ▸ **VPN & Device Management** ▸ your Apple ID ▸ **Trust**.
6. Tips use Xcode's local test store, so nobody is charged. Leaderboards will not appear in this
   build; that is expected.
7. When done, run `make project` to go back to the normal project.

## Stage 1: the day you join the Apple Developer Program

- [ ] **Enrol** at https://developer.apple.com/programs/enroll/ (US$99 a year). As an **individual**
      your own name shows as the seller. As an **organisation** you need a D-U-N-S number. Approval
      usually takes a day or two.
- [ ] **Fix the Xcode account and team:** sign in to Xcode with the Apple ID that holds the
      membership, and note the 10-character **Team ID** (developer.apple.com/account). Then
      `export DEVELOPMENT_TEAM=<Team ID>` in `~/.zshrc`.
- [ ] **Small Business Program** (free, separate sign-up, 15% instead of 30%):
      https://developer.apple.com/app-store/small-business-program/
- [ ] **Agreements, tax and banking:** App Store Connect ▸ Business. Accept the **Paid Apps
      Agreement** and add bank and tax details. Tips are in-app purchases, so this is needed even
      though the app is free.
- [ ] **Register the App ID** `com.richardforjoe.oware` (Certificates, IDs & Profiles ▸ Identifiers)
      with **Game Center** and **In-App Purchase** switched on.
- [ ] **Create the app record** in App Store Connect ▸ Apps ▸ "+": iOS, name **Lelu Oware**,
      English (UK), bundle id `com.richardforjoe.oware`, SKU `oware-ios`.

## Stage 2: set up the app in App Store Connect

- [ ] **Game Center:** enable it and create the 3 leaderboards and 6 achievements (SERVICES.md section 3).
- [ ] **Tips:** three consumable in-app purchases, exactly as in APP_STORE.md. Add the review note.
- [ ] **App Privacy label:** as in SERVICES.md section 5. Privacy policy URL:
      https://richardforjoejnr.github.io/oware/lelu-oware/privacy
- [x] **TelemetryDeck App ID** into `project.yml` (done 27 Sep 2026). Use the analytics answers
      for the privacy label below.
- [ ] **Age rating** questionnaire (expect 4+). Category **Games ▸ Board**.

## Stage 3: TestFlight (share with family and friends)

- [ ] **Upload a build:** `make archive APP=lelu-oware` in the repo (a fresh build number every
      time), then in the Organizer that opens: **Distribute App ▸ App Store Connect ▸ Upload**.
      The build appears in App Store Connect ▸ TestFlight after 5–15 minutes. The app version is
      1.0, matching App Store Connect; see PIPELINE.md "Versions and build numbers".
- [ ] **Test it yourself first:** TestFlight ▸ Internal Testing ▸ add yourself. Install the
      **TestFlight** app on your iPhone and open the invite.
- [ ] **Invite family and friends:** TestFlight ▸ External Testing ▸ new group ("Family") ▸ add
      the build ▸ add testers by email, or turn on a **public link** and send that.
      - The first external build goes through **Beta App Review** (usually about a day). Later
        builds are often approved faster.
      - Testers need an iPhone or iPad on iOS 17 or later, and the free TestFlight app.
      - Tips in TestFlight are free test purchases; nobody is charged.
      - Each build lasts **90 days**. Upload a new one before then.
      - Testers send feedback and screenshots from the TestFlight app; read it under TestFlight ▸ Feedback.
- [ ] **Optional, automatic builds:** follow PIPELINE.md to add **all** the CI secrets first, and
      only then set `SIGNING_READY=true`. Every merge to `main` then uploads a TestFlight build.
      With the flag on and no secrets, the TestFlight workflow fails on every merge.

## Stage 4: App Store submission

- [ ] **Screenshots:** 6.9" iPhone (1320 × 2868) and 13" iPad (2064 × 2752); shot list in APP_STORE.md.
- [ ] **Text:** name, subtitle, description, keywords, support URL, copyright; from APP_STORE.md.
- [ ] **Price:** Free. **Availability:** all countries (the game is for anyone who likes Oware).
- [ ] **Review notes:** no login; tips unlock nothing; works offline.
- [ ] **Attach the build and the three tips** to the version, then **Submit for Review**
      (typically 1–2 days).
- [ ] **Release:** choose manual release or phased release (7 days), so you control launch day.

## Stage 5: after launch

- [ ] Weekly: App Store Connect analytics (downloads, sources), TelemetryDeck (what people play),
      crashes (Xcode ▸ Organizer), and ratings and reviews.
- [ ] Reply to reviews; send the first newsletter when there is news.
- [ ] After 4–8 weeks, review the numbers against the research note's signals before deciding
      on online play.
