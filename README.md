# PAYFLOW — Native iOS App

Private, local-first personal finance for iPhone. Single user, no account, no ads, no tracking.

**iPhone only · Swift · SwiftUI · SwiftData · Swift Charts · Apple Keychain · Face ID**

> **Testing status — read first.** This project was built and statically validated on a Linux machine that has no Xcode, no Swift toolchain and no iOS Simulator, so it has **not** yet been run on an iPhone Simulator or a real iPhone. Every Swift file was checked for balanced syntax, duplicate types, valid `project.pbxproj` references, valid plists and valid asset catalogs (see "What was verified" below), but the first real build on a Mac is still the test that matters. Do not treat any feature as proven until you have run the checklist in "First-run test checklist". No feature in this README is claimed as tested on-device.

## What it does

| Screen | What works in v1.0 |
|---|---|
| **Home / Overview** | Total balance (light glossy hero card), this-month income vs spending, **swipeable cards carousel** (swipe left/right between your cards — dark-navy card visuals, last 4 digits, this month's spend per card), 6-month spending chart (Swift Charts), cashflow forecast (3-month average, projected month-end, safe-to-spend/day, runway), recent transactions, subscriptions preview |
| **Transactions** | Search, category filter chips, tap for detail, delete, source + sync status on every row, fingerprint shown in detail |
| **Analytics** | Month stepper, income / expenses / net, spending-by-category donut + breakdown, daily spending bars, monthly report view |
| **Budgets** | Per-category monthly budgets, progress vs real imported spending, over-budget warning |
| **Subscriptions** | Recurring detection from real history (3+ charges, regular weekly/monthly/yearly interval), confirm-to-track, monthly/yearly totals, cancel |
| **AI Assistant** | Local-first insights + Q&A computed on-device from your actual records (spending, income, subscriptions, budgets, forecast). External AI is **off** by default and needs explicit consent in Settings |
| **Integrations** | Statement import (CSV / XLSX / PDF), bank connections recorded honestly as **Not connected** until you complete your bank's official authorisation, **Automation** (Apple Pay / card-app notifications — see below), **Cards & accounts carousel** (same swipeable cards as Home) |
| **Settings** | Face ID toggle, optional private iCloud backup, currency, external-AI consent, demo data load/delete, delete-all, Automation switches |

## Design — Black & Silver (muted) theme + swipeable cards (20 Nov 2026)

User's direction after grey-navy: black silver, but not too bright ("hitam silver tapi jgn terlalu terang", 20 Nov 2026). Black base with DIM silver — no bright white, no bright silver: header `#0A0A0A`, body `#141414`, cards `#1E1E1E`, accent dim silver `#9CA3AF`, text off-white `#E8E8E8`, secondary dim silver `#8A8F98`. Income is off-white and expenses are dim silver, both with +/− signs. The app forces the dark scheme (`preferredColorScheme(.dark)` in `PayflowApp.swift`) and applies the near-black header via `payNavBar()`. The physical card visual is black with a muted silver chip.

Cards are swipeable: `CardsCarouselView` in `Views/Components/SharedComponents.swift` is a paging `TabView` — swipe left / right to move between cards, with dots and a `1 / 3` counter. It appears on Home (under the balance) and at the top of Integrations ("Cards & accounts"). Each card shows the institution, `•••• •••• •••• 4321` (last 4 digits only — PAYFLOW never stores a full number), and this month's spend on that card from real transactions. With demo data loaded, the carousel shows the reference's three demo cards (BCA •••• 4321, Mandiri •••• 7788, Jago •••• 9911, balance 0 so the demo total is unchanged).

## Automation — pay with a card, PAYFLOW notifies you

This is the feature the user asked for on 20 Nov 2026: *when the card is used, PAYFLOW automatically logs it and notifies me* — for Apple Pay cards and crypto cards (KAST, Bybit, …) added to Wallet.

**Honest limit first:** iOS does not let one app silently read another app's notifications, SMS, or Apple Pay history. PAYFLOW does not do that. The only route is one **you** set up yourself in Shortcuts, once. PAYFLOW only receives a payment you explicitly route to it.

**How it works (code: `Services/AutomationService.swift`, `Services/NotificationService.swift`, `Views/AutomationView.swift`, URL scheme `payflow://` in `Info.plist`):**

1. **In PAYFLOW:** Integrations → **Set up automation** (or Settings → Automation). Turn on **Receive automations** and **Notify me for each payment**, tap **Allow notifications**.
2. **Apple Pay — tap to pay (iOS 17+):** Shortcuts → Automation → + → Wallet → Transaction → select your card(s) → **Run Immediately** → Add Action **Open URLs** → paste `payflow://log-payment?amount=[Amount]&currency=IDR&merchant=[Merchant]&card=[Card]&source=applepay`, replacing the brackets with the Shortcut's Transaction variables. First tap: iPhone asks to open PAYFLOW — tap **Always Allow**. Catches tap-to-pay only, not online shopping or physical swipes.
3. **Card-app notification (iOS 27+):** Shortcuts → Automation → + → App Notification → choose your card app (KAST, Bybit, …) → **Run Immediately** → Add Action **Open URLs** → paste `payflow://log-payment?text=[Notification Text]&source=notification`. Needs iOS 27 + Apple Intelligence on, and the card app's payment notifications on with previews shown. PAYFLOW parses amount / merchant / card from that text on-device; if no amount can be found it **rejects** the payment instead of guessing.
4. **What PAYFLOW does on receipt:** parses `payflow://log-payment?...` in `PayflowApp.onOpenURL`, categorises with the same engine as imports, **dedups** (exact fingerprint + fuzzy ±3-day — a payment is never logged twice), creates one account per card label (e.g. `KAST •••• 1234`), and fires a **local** notification: e.g. `KAST •••• 1234 — Rp 45.000 · Starbucks · Dining · Rp 155.000 left in Dining this month` (budget line only when a budget exists for that category). If the app was locked when the payment arrived, it is queued and processed after Face ID unlock — never inserted while locked.
5. **Test without a real card:** Automation screen → **Simulate an Apple Pay payment** inserts one labelled simulated payment (Starbucks, Rp 45.000, KAST •••• 1234) through the same code path. Run it twice: the second run must report **duplicate**, proving dedup works.

**What it cannot do:** read a card's history by itself, catch a payment when the automation is off or was never set up, or log a payment whose notification text contains no amount. A crypto card that is not in Apple Pay and whose app sends no payment notification cannot trigger this — CSV import remains the fallback for those. Bybit also offers a read-only API key for card history (polling, minutes of delay, not instant) — not built in; the Shortcuts route above is the instant one.

## Automation (the primary workflow is import, not manual entry)

- **Ingestion:** CSV, XLSX and PDF statement imports via the system file picker (`Transactions → Import` or `Home → Import statement`). A sample file is included: `Payflow/Resources/SampleStatements/sample-statement.csv`.
- **Categorisation:** keyword rules + merchant normalisation (`AMZN MKTP US*…` → Amazon). Correct a category once in a transaction's detail view and PAYFLOW saves a `MerchantRule` — future imports from that merchant use it automatically.
- **Duplicate detection:** exact fingerprint (date + amount + normalised merchant + account) plus a fuzzy check (same amount + merchant within ±3 days). Duplicates are counted and skipped, never imported twice.
- **Recurring detection:** see Subscriptions above. Nothing is created as a subscription until you tap **Track**.
- **Forecasting:** last-3-months average income/expenses; labelled low-confidence with fewer than 10 transactions.
- **Reports:** monthly report (income, expenses, net, by-category, top merchants) with CSV and PDF export (share sheet).

## Privacy — the hard rules, enforced in code

- **Local-first.** SwiftData on-device. iCloud is **off** by default; enabling it in Settings uses only your private CloudKit database (see below).
- **Never fake live bank connectivity.** A bank shows **Not connected** until you complete that bank's own official OAuth / Open Banking authorisation. There is no simulated balance, no demo bank presented as real.
- **Never scrape banking websites. Never ask for a banking password, PIN or OTP.** There is nowhere in the app to enter one, and no code path that logs in to a bank for you.
- **No SMS / inbox access.** Email ingestion means: save a statement attachment from Mail/Gmail to Files, then import it. PAYFLOW does not read your inbox or SMS. **Automation is the one exception, and it is user-routed, not app-read:** PAYFLOW only receives a payment when your own Shortcuts automation sends it via `payflow://log-payment?...`. It never reads other apps, notifications or SMS by itself, and a `payflow://` link does nothing while Automation is off.
- **Secrets in Keychain only.** Bank API tokens and any external-AI key live in Apple Keychain (`KeychainService`), never in SwiftData, UserDefaults, logs or files.
- **External AI needs consent.** Off by default. Turning it on shows a confirmation alert and the exact aggregate summary that would be sent (totals only — no raw descriptions, merchant history or account numbers). Local AI never sends anything.
- **Face ID.** The app locks on launch and when backgrounded (`LocalAuthentication`). No PAYFLOW password exists; device passcode is the only fallback, handled by the system.

## Requirements

- Mac with **Xcode 16+** (Swift 5, iOS 17 SDK)
- **iOS 17.0+** on the iPhone / Simulator (iPhone only — `TARGETED_DEVICE_FAMILY = 1`)
- Apple ID signed in to Xcode (free personal team works for running on your own iPhone; a paid Developer Program account is only needed for App Store / TestFlight distribution)
- No third-party dependencies, no CocoaPods, no SPM packages — the project builds offline

## Build & install

### 1. Open the project
```bash
unzip PAYFLOW.zip
cd PAYFLOW
open PAYFLOW.xcodeproj
```
Or double-click `PAYFLOW.xcodeproj` in Finder.

### 2. Signing (first time only)
1. In Xcode, select the **Payflow** target → **Signing & Capabilities**.
2. Tick **Automatically manage signing**.
3. Choose your Team (your Apple ID). If Xcode warns about the bundle ID, change `com.payflow.app` to something unique, e.g. `com.yourname.payflow` — keep it consistent everywhere.
4. The entitlements file references a placeholder iCloud container (`iCloud.com.payflow.app`). **Leave iCloud off in the app and this does nothing.** Only if you want the optional iCloud backup: add the **iCloud → CloudKit** capability, replace the container ID with your own, and change `cloudKitDatabase: .none` to `.private` in `Payflow/PayflowApp.swift` (see "Optional iCloud backup" below).

### 3. Run on Simulator (fastest first test)
1. Choose a simulator, e.g. **iPhone 16 Pro, iOS 18**, in the run destination menu.
2. Press **⌘R** (Product → Run).
3. Note: Simulator has **no Face ID enrolment by default** — use **Features → Face ID → Enrolled**, then **Matching Face** when prompted, or temporarily turn off "Require Face ID" in Settings inside the app. On a real iPhone, Face ID works as enrolled on the device.

### 4. Run on a real iPhone
1. Connect the iPhone by USB (or Wi-Fi after first pairing).
2. Select your iPhone as the run destination, press **⌘R**.
3. First launch on the device: **Settings → General → VPN & Device Management → [your Apple ID] → Trust** (free personal team only; paid team usually skips this).
4. Grant Face ID when prompted — the usage string is in `Payflow/Info.plist` (`NSFaceIDUsageDescription`).

## First-run test checklist (do this before trusting any number)

1. **Launch** — onboarding appears once, then the lock screen. Unlock with Face ID / passcode.
2. **Demo data (optional)** — Settings → **Load demo data**. Home, Analytics and AI should populate immediately. Every demo row is labelled **Demo Data**. The cards carousel should show 3 demo cards (BCA •••• 4321, Mandiri •••• 7788, Jago •••• 9911) — swipe left / right between them. Delete it in Settings → **Delete demo data** before importing real statements.
3. **Import the sample statement** — Home → **Import statement** → choose `Payflow/Resources/SampleStatements/sample-statement.csv` (copy it to the Mac first, or AirDrop it to the phone and pick it from Files). Expect: **11 rows parsed, 11 imported, 0 duplicates**. Re-import the same file: expect **0 imported, 11 duplicates skipped**.
4. **Categorisation learning** — open a transaction, change its category, Save. Import a new statement containing the same merchant: it should arrive with your corrected category.
5. **Subscriptions** — with demo data loaded, Subscriptions should offer Netflix / Spotify as detected candidates (monthly, 3 occurrences). Tap **Track** on one and confirm the monthly total updates.
6. **Budgets** — Budgets → **Add budget** (e.g. Groceries $400). Progress should reflect real imported spending for the current month.
7. **Reports** — Analytics → pick a month → **Monthly report** → **Export CSV** and **Export PDF**; both should open the share sheet.
8. **AI** — Assistant → ask *"How much did I spend this month?"* and *"What are my subscriptions?"*. Answers must cite your imported numbers. With External AI off (default), the privacy badge must say **Local AI**.
9. **Locking** — background the app and reopen it: it must ask for Face ID again.
10. **Automation** — Integrations → Set up automation → turn on **Receive automations** → **Simulate an Apple Pay payment**. Expect: a Starbucks Rp 45.000 transaction appears in Transactions with source **Apple Pay Automation**, account `KAST •••• 1234`, and a local notification. Tap Simulate again: expect **duplicate — correctly skipped**. Then **Send a test notification** and check the banner appears. Only after this works, set up the real Shortcuts automation above and tap to pay with a real card in Apple Pay.
11. **Real statement** — download a real CSV from your bank and import it. If headers differ, the importer looks for Date / Description / Amount (or Debit + Credit columns) and reports unrecognised rows instead of silently dropping them.

## Optional iCloud backup

Off by default. To enable:
1. Xcode → target → **Signing & Capabilities** → add **iCloud**, tick **CloudKit**, add your container (e.g. `iCloud.com.yourname.payflow`).
2. Update the same container ID in `Payflow/Payflow.entitlements`.
3. In `Payflow/PayflowApp.swift`, change `cloudKitDatabase: .none` to `cloudKitDatabase: .private`.
4. In the app, Settings → turn on **Private iCloud backup**. It applies on next launch. Your data syncs only through your private CloudKit database; there is no PAYFLOW server.

## Known limitations (v1.0, honest)

- **XLSX:** the first sheet only, header row required. Decompression uses `libcompression` (zlib); if a workbook uses an unsupported compression, the importer fails with a clear message and suggests CSV. CSV export from your bank is the most reliable format for every bank.
- **PDF:** text-based statements only. Scanned/image-only PDFs contain no extractable text and cannot be parsed — use CSV in that case. PDF layouts vary by bank; lines that don't match `date … description … amount` are skipped and counted in the result message.
- **Bank API — all Indonesian banks:** Integrations lists 24 Indonesian banks (BCA, Mandiri, BRI, BNI, CIMB Niaga, Permata, Danamon, BTN, BSI, Muamalat, BCA Syariah, Jago, Jenius, SeaBank, Neo, Allo, Blu, OCBC, Maybank, Panin, Mega, KB Bank, Sinarmas, MAS) with a real Connect flow per bank — Brick / Brankas aggregator, or direct BI-SNAP bank API. What is **not** included, and cannot be faked: the aggregator/bank credentials themselves. Indonesia's SNAP standardises the API shape, but access is granted under a cooperation agreement with each bank, so a personal app connects via an aggregator account (Brick covers the 7 largest banks, >90% of accounts) or a per-bank developer registration (e.g. BRIAPI at [developers.bri.co.id](https://developers.bri.co.id)). In the app: Integrations → tap Connect on a bank → pick Brick / Brankas / Direct → paste the API key (Keychain only) → the bank/aggregator's own authorisation page opens in `ASWebAuthenticationSession` → only a token callback marks it Connected. Without a key / without completing that authorisation, the bank stays **Not connected**. File import is the working ingestion path until you add a key. Brick docs: [docs.onebrick.io](https://docs.onebrick.io).
- **Forecast:** a 3-month average, not a prediction market — with sparse history it says so.
- **Automation:** Apple Pay Wallet trigger catches tap-to-pay only; online / swipe payments need the iOS 27 notification trigger, or CSV import. Notification-text parsing is best-effort and rejects a payment when no amount can be found. A payment arriving while the app is locked is queued until Face ID unlock — it is not inserted while locked.
- **App icon:** `Assets.xcassets/AppIcon.appiconset` ships with the required slots but no artwork yet. Add a 1024×1024 icon in Xcode (AppIcon) before any TestFlight/App Store submission.
- **No macOS / iPad / Android / web version.** iPhone only, by design.

## Project structure

```
PAYFLOW.xcodeproj/            Xcode project (iOS 17, iPhone only, no dependencies)
Payflow/
  PayflowApp.swift            @main, SwiftData ModelContainer (local-first)
  Info.plist                  Face ID usage string, orientations
  Payflow.entitlements        Data protection; placeholder iCloud container
  Models/AppModels.swift      SwiftData: PayTransaction, PayAccount, PayBudget,
                              PaySubscription, MerchantRule, BankConnection
  Services/
    CategorizationEngine.swift  Merchant normalisation, keyword rules, duplicates
    ImportService.swift         CSV / XLSX (ZIP+XML) / PDF (PDFKit) import + apply
    AutomationService.swift     Receives Shortcuts automations (payflow://log-payment),
                                dedup + categorise + per-card accounts + pending queue
    NotificationService.swift   Local notifications for received payments + test
    RecurringDetector.swift     Recurring detection + ForecastEngine
    AIAssistantService.swift    Local insights + Q&A, external-AI payload preview
    ReportService.swift         Monthly/yearly reports, CSV + PDF export
    KeychainService.swift       SecItem wrapper (tokens only, never passwords)
    BiometricAuthService.swift  Face ID / passcode gate (LocalAuthentication)
    SampleData.swift            Clearly-labelled demo data (deletable)
  Views/
    Theme.swift                 Charcoal + muted emerald design system
    ContentView.swift           Lock screen, onboarding, 8-tab navigation
    HomeView.swift              Balance, forecast, 6-month chart, recent
    TransactionsView.swift      List, search, filters, detail, import sheet
    AnalyticsView.swift         Charts + monthly report + export
    BudgetsView.swift           Budgets vs real spending
    SubscriptionsView.swift     Detected + active subscriptions
    AIAssistantView.swift       Local AI chat + insights
    IntegrationsView.swift      Honest bank / email / file integrations + Automation entry
    SettingsView.swift          Face ID, iCloud, external AI, data controls, Automation switches
    AutomationView.swift        Automation setup: switches, Shortcuts steps, copy URL, test simulation, received log
    Components/SharedComponents.swift
  Resources/
    Assets.xcassets/            AccentColor (muted emerald), AppIcon slots
    SampleStatements/sample-statement.csv
```

## What was verified (and what was not)

Verified on Linux (no Xcode available here):
- 25 Swift files, all braces/parens balanced, no duplicate type names
- `project.pbxproj` references every Swift file; every referenced file exists
- `Info.plist` and `Payflow.entitlements` parse as valid plists; asset catalog JSON is valid
- No code path requests a banking password, PIN, OTP, SMS access or website scraping (the only matches are "never do this" statements)

**Not verified:** compiling in Xcode, running on Simulator, running on a real iPhone, Face ID on-device, iCloud sync, XLSX decompression against every bank's workbook, PDF parsing against every bank's layout. Run the checklist above and treat anything that fails there as a bug to fix before relying on the app.

## Privacy summary

Your transactions stay on your iPhone unless you (a) turn on private iCloud backup, or (b) explicitly consent to external AI in Settings. PAYFLOW has no server, no account, and no analytics.
