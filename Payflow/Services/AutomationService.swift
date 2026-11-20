import Foundation
import SwiftData

// MARK: - Automation receiving (Apple Pay + card-app notifications)
//
// What this is — and what it is NOT.
//
// The user asked: "when the card is used, PAYFLOW notifies me automatically."
// On iOS there is no API for one app to silently read another app's
// notifications, SMS, or Apple Pay history. PAYFLOW does NOT do that.
//
// The only honest route is one the user sets up themselves, in Shortcuts:
//   1. Apple Pay (Wallet) trigger — iOS 17+: Shortcuts fires when the user
//      taps to pay with Apple Pay, and passes amount + merchant + card to
//      PAYFLOW through the payflow:// URL below.
//   2. Notification trigger — iOS 27+: Shortcuts fires when the card app
//      (KAST, Bybit, …) posts a payment notification, and passes that
//      notification's text to PAYFLOW the same way.
//
// In both cases the data arrives because the USER routed it, on their own
// iPhone, in an automation they created. No bank password, PIN, OTP,
// SMS access, or background reading of other apps is involved. If the
// automation is off, nothing arrives. If the user never sets it up,
// PAYFLOW behaves exactly as before (CSV / XLSX / PDF import).
//
// URL contract (Shortcuts "Open URLs" action):
//   payflow://log-payment?amount=45000&currency=IDR&merchant=Starbucks
//       &card=KAST%20%E2%80%A2%E2%80%A2%E2%80%A2%E2%80%A2%201234
//       &source=applepay&date=2026-11-20T00:30:00Z
//   payflow://log-payment?text=<URL-encoded notification text>&source=notification
//
//   amount    required, positive number (use amount=-x or kind=income for income)
//   merchant  required for the amount form; optional for the text form
//   currency  optional, default IDR, 3-letter code
//   card      optional, e.g. "KAST •••• 1234" — shown as the account name
//   source    applepay (default) | notification
//   date      optional ISO-8601, default now
//   kind      expense (default) | income

struct AutomationPayment {
    let amount: Double
    let merchant: String
    let rawDescription: String
    let currencyCode: String
    let cardLabel: String
    let date: Date
    let kind: TransactionKind
    let source: TransactionSource
}

enum AutomationOutcome: Equatable {
    case inserted
    case duplicate
    case rejected(String)

    static func == (lhs: AutomationOutcome, rhs: AutomationOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.inserted, .inserted), (.duplicate, .duplicate): return true
        case (.rejected(let a), .rejected(let b)): return a == b
        default: return false
        }
    }
}

struct AutomationResult {
    let outcome: AutomationOutcome
    let transaction: PayTransaction?
    /// Text for the local notification, e.g.
    /// "KAST •••• 1234 — Starbucks Rp 45.000 · Dining · Rp 155.000 left in Dining"
    let notificationTitle: String
    let notificationBody: String
}

enum AutomationService {

    static let scheme = "payflow"
    static let pendingURLKey = "payflow.automation.pendingURL"
    static let lastReceivedKey = "payflow.automation.lastReceived"

    // ---------- URL parsing ----------

    /// Parse a payflow://log-payment URL. Returns nil when the URL is not
    /// ours, or when it carries no usable amount / merchant.
    static func parse(url: URL) -> AutomationPayment? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == "log-payment",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        var dict: [String: String] = [:]
        for item in items where item.value != nil { dict[item.name.lowercased()] = item.value }
        let sourceRaw = (dict["source"] ?? "applepay").lowercased()
        let source: TransactionSource = sourceRaw == "notification" ? .cardNotification : .applePayAutomation
        if let text = dict["text"], !text.isEmpty {
            return parseNotificationText(text, source: source)
        }
        guard let amountRaw = dict["amount"], let amount = Double(amountRaw), amount != 0 else { return nil }
        guard let merchantRaw = dict["merchant"]?.trimmingCharacters(in: .whitespaces), !merchantRaw.isEmpty else { return nil }
        let kind: TransactionKind = (dict["kind"]?.lowercased() == "income") || amount < 0 ? .income : .expense
        let currency = (dict["currency"] ?? "IDR").uppercased()
        let date = parseDate(dict["date"]) ?? Date()
        let card = (dict["card"] ?? "").trimmingCharacters(in: .whitespaces)
        let merchant = CategorizationEngine.normalizeMerchant(merchantRaw)
        return AutomationPayment(amount: abs(amount), merchant: merchant,
                                 rawDescription: merchantRaw,
                                 currencyCode: currency.count == 3 ? currency : "IDR",
                                 cardLabel: card, date: date, kind: kind, source: source)
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let seconds = Double(raw) { return Date(timeIntervalSince1970: seconds) }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: raw) { return d }
        return ImportService.parseDate(raw)
    }

    // ---------- Notification-text parsing (best effort) ----------
    //
    // Examples the Shortcuts Notification trigger hands us:
    //   "Pembayaran Rp45.000 di Starbucks - KAST •••• 1234"
    //   "Purchase of $84.32 at WHOLE FOODS with card ending 4321"
    //   "Transaksi berhasil Rp 1.250.000 di Tokopedia"
    // Amount is required; merchant and card are best-effort. If no amount
    // can be found, the text is rejected (never guessed) and the user is
    // told to check the automation instead of getting a wrong transaction.

    static func parseNotificationText(_ text: String, source: TransactionSource = .cardNotification) -> AutomationPayment? {
        let amountPattern = #"(?:Rp|IDR|\$|USD)?\s*([\d]{1,3}(?:[.,]\d{3})*(?:[.,]\d{2})?|[\d]+(?:[.,]\d{2})?)"#
        guard let regex = try? NSRegularExpression(pattern: amountPattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        var amount: Double?
        var currency = "IDR"
        for m in regex.matches(in: text, range: range) {
            guard let r = Range(m.range(at: 1), in: text) else { continue }
            let raw = String(text[r])
            // Skip a bare 4-digit year / day that is not money: a real
            // amount either has a thousands/decimal separator, or a
            // currency marker (Rp, IDR, $, USD) just before it.
            let prefix = String(text[..<r.lowerBound]).suffix(12).lowercased()
            let hasSeparator = raw.contains(".") || raw.contains(",")
            let hasCurrencyMarker = prefix.contains("rp") || prefix.contains("idr")
                || prefix.contains("$") || prefix.contains("usd")
            guard hasSeparator || hasCurrencyMarker else { continue }
            let lower = text.lowercased()
            if lower.contains("rp") || lower.contains("idr") {
                // Indonesian format: dots are thousands separators.
                let idr = Double(raw.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")) ?? 0
                amount = idr
                currency = "IDR"
            } else {
                amount = Double(raw.replacingOccurrences(of: ",", with: ""))
                currency = lower.contains("$") || lower.contains("usd") ? "USD" : "IDR"
            }
            break
        }
        guard let amount, amount > 0 else { return nil }
        let merchant = extractMerchant(from: text) ?? "Card payment"
        let card = extractCardLabel(from: text)
        return AutomationPayment(amount: amount, merchant: CategorizationEngine.normalizeMerchant(merchant),
                                 rawDescription: text, currencyCode: currency,
                                 cardLabel: card, date: Date(), kind: .expense, source: source)
    }

    private static func extractMerchant(from text: String) -> String? {
        // "at X" / "di X" / "to X" — take words until a dash, comma or "with".
        let patterns = [#"(?i)\bat\s+([^,\-–—]+?)(?:\s+with\s|\s*-\s*$|\s*$)"#,
                        #"(?i)\bdi\s+([^,\-–—]+?)(?:\s*-\s*$|\s*$)"#]
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p, options: []) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let m = regex.firstMatch(in: text, range: range), let r = Range(m.range(at: 1), in: text) {
                let v = String(text[r]).trimmingCharacters(in: .whitespaces)
                if !v.isEmpty && v.count <= 60 { return v }
            }
        }
        return nil
    }

    private static func extractCardLabel(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(?:ending|terakhir|••••)\s*(\d{4})"#, options: []) else { return "" }
        let range = NSRange(text.startIndex..., in: text)
        if let m = regex.firstMatch(in: text, range: range), let r = Range(m.range(at: 1), in: text) {
            return "•••• \(text[r])"
        }
        return ""
    }

    // ---------- Receiving (dedup + categorise + store) ----------

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "payflow.automationEnabled") }
    static var notificationsEnabled: Bool { UserDefaults.standard.bool(forKey: "payflow.automationNotifications") }

    /// Account name for a payment: the card label when given, else the
    /// source's generic name. One account per card label is created on
    /// first sight so each crypto card stays separate in the app.
    static func accountName(for payment: AutomationPayment) -> String {
        payment.cardLabel.isEmpty
            ? (payment.source == .applePayAutomation ? "Apple Pay" : "Card")
            : payment.cardLabel
    }

    @MainActor
    static func receive(_ payment: AutomationPayment, context: ModelContext,
                        existing: [PayTransaction], learned: [MerchantRule],
                        accounts: [PayAccount], budgets: [PayBudget]) -> AutomationResult {
        let accountName = accountName(for: payment)
        let fp = DuplicateDetector.fingerprint(date: payment.date, amount: payment.amount,
                                               merchant: payment.merchant, accountName: accountName)
        if existing.contains(where: { $0.fingerprint == fp }) {
            return AutomationResult(outcome: .duplicate, transaction: nil,
                                    notificationTitle: "Already in PAYFLOW",
                                    notificationBody: "\(payment.merchant) \(payment.amount.asCurrency(payment.currencyCode)) was already recorded — skipped, not imported twice.")
        }
        if existing.contains(where: { DuplicateDetector.isFuzzyDuplicate(candidateDate: payment.date, candidateAmount: payment.amount, candidateMerchant: payment.merchant, existing: $0) }) {
            return AutomationResult(outcome: .duplicate, transaction: nil,
                                    notificationTitle: "Already in PAYFLOW",
                                    notificationBody: "\(payment.merchant) \(payment.amount.asCurrency(payment.currencyCode)) looks like a transaction from the last 3 days — skipped as a duplicate.")
        }
        if accounts.first(where: { $0.name == accountName }) == nil {
            let institution = payment.cardLabel.split(separator: " ").first.map(String.init) ?? accountName
            context.insert(PayAccount(name: accountName, institution: institution,
                                      type: "card", balance: 0, currencyCode: payment.currencyCode))
        }
        let (category, _, _) = CategorizationEngine.categorize(merchant: payment.merchant,
                                                                 rawDescription: payment.rawDescription,
                                                                 learned: learned, kind: payment.kind)
        let tx = PayTransaction(date: payment.date, merchant: payment.merchant,
                                rawDescription: payment.rawDescription, amount: payment.amount,
                                kind: payment.kind, category: category, currencyCode: payment.currencyCode,
                                source: payment.source, syncStatus: .synced,
                                accountName: accountName, fingerprint: fp)
        context.insert(tx)
        try? context.save()
        recordLastReceived(payment: payment, category: category)
        let body = notificationBody(for: payment, category: category,
                                    transactions: existing + [tx], budgets: budgets)
        return AutomationResult(outcome: .inserted, transaction: tx,
                                notificationTitle: "\(accountName) — \(payment.amount.asCurrency(payment.currencyCode))",
                                notificationBody: body)
    }

    private static func notificationBody(for payment: AutomationPayment, category: PayCategory,
                                         transactions: [PayTransaction], budgets: [PayBudget]) -> String {
        var body = "\(payment.merchant) · \(category.displayName)"
        if payment.kind == .expense, let budget = budgets.first(where: { $0.category == category }) {
            let spent = transactions
                .filter { $0.category == category && $0.kind == .expense && Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
                .map(\.amount).reduce(0, +)
            let left = budget.monthlyLimit - spent
            body += left < 0
                ? " · Over budget by \((-left).asCurrency(payment.currencyCode))"
                : " · \(left.asCurrency(payment.currencyCode)) left in \(category.displayName) this month"
        }
        return body
    }

    // ---------- Pending queue (app was locked when the URL arrived) ----------

    static func savePending(url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: pendingURLKey)
    }
    static func loadPendingURL() -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: pendingURLKey) else { return nil }
        return URL(string: raw)
    }
    static func clearPending() { UserDefaults.standard.removeObject(forKey: pendingURLKey) }

    // ---------- Last-received log (shown in AutomationView) ----------

    private static func recordLastReceived(payment: AutomationPayment, category: PayCategory) {
        let line = "\(ISO8601DateFormatter().string(from: payment.date)) | \(payment.source.rawValue) | \(payment.merchant) | \(payment.amount) \(payment.currencyCode) | \(category.displayName) | \(accountName(for: payment))"
        var log = UserDefaults.standard.stringArray(forKey: lastReceivedKey) ?? []
        log.insert(line, at: 0)
        UserDefaults.standard.set(Array(log.prefix(20)), forKey: lastReceivedKey)
    }
    static func lastReceived() -> [String] {
        UserDefaults.standard.stringArray(forKey: lastReceivedKey) ?? []
    }
}
