import Foundation

/// PAYFLOW AI assistant — local-first.
/// By default every answer is computed on-device from the user's own
/// SwiftData records. NOTHING is sent to any external AI service unless
/// the user explicitly turns on "External AI" in Settings, sees exactly
/// what will be sent, and confirms. The external path stores its API key
/// in the Keychain and sends only an anonymised aggregate summary — never
/// raw descriptions, account numbers or full merchant history — and only
/// after that consent is recorded.
struct AIAssistantService {

    struct Insight: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        let tone: Tone
        enum Tone { case good, warning, neutral }
    }

    /// Proactive insights, computed locally from real transactions.
    static func insights(transactions: [PayTransaction], subscriptions: [PaySubscription]) -> [Insight] {
        var out: [Insight] = []
        let cal = Calendar.current
        let now = Date()
        let thisMonth = transactions.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
        let spent = thisMonth.filter { $0.kind == .expense }.map(\.amount).reduce(0, +)
        let earned = thisMonth.filter { $0.kind == .income }.map(\.amount).reduce(0, +)
        out.append(Insight(title: "This month so far",
                           body: "Spent \(spent.asCurrency()) · earned \(earned.asCurrency()) · net \((earned - spent).asCurrency()).",
                           tone: earned >= spent ? .good : .warning))
        // Top category this month.
        let byCat = Dictionary(grouping: thisMonth.filter { $0.kind == .expense }, by: \.category)
            .mapValues { $0.map(\.amount).reduce(0, +) }.sorted { $0.value > $1.value }
        if let top = byCat.first {
            out.append(Insight(title: "Biggest category: \(top.key.displayName)",
                               body: "\(top.value.asCurrency()) this month — \(Int(top.value / max(spent, 1) * 100))% of spending.",
                               tone: .neutral))
        }
        // Subscriptions total.
        let active = subscriptions.filter(\.isActive)
        let monthlySubs = active.map(\.monthlyCost).reduce(0, +)
        if !active.isEmpty {
            out.append(Insight(title: "\(active.count) active subscriptions",
                               body: "About \(monthlySubs.asCurrency()) / month. Review them on the Subscriptions tab — cancelling one unused service is the fastest saving.",
                               tone: .neutral))
        }
        // Uncategorised.
        let uncat = transactions.filter { $0.category == .uncategorized }.count
        if uncat > 0 {
            out.append(Insight(title: "\(uncat) transactions need a category",
                               body: "Correct one and PAYFLOW learns it — future imports from that merchant will be categorised automatically.",
                               tone: .warning))
        }
        // Largest single expense this month.
        if let biggest = thisMonth.filter({ $0.kind == .expense }).max(by: { $0.amount < $1.amount }) {
            out.append(Insight(title: "Largest expense: \(biggest.merchant)",
                               body: "\(biggest.amount.asCurrency()) on \(biggest.date.shortDateLabel).",
                               tone: .neutral))
        }
        return out
    }

    /// Local Q&A: keyword-based answers computed from real records.
    /// Returns nil when the question needs data the app does not have.
    static func answerLocally(_ question: String, transactions: [PayTransaction],
                              subscriptions: [PaySubscription], budgets: [PayBudget]) -> String? {
        let q = question.lowercased()
        let cal = Calendar.current
        let now = Date()
        func monthTotal(_ kind: TransactionKind, monthOffset: Int = 0) -> Double {
            guard let m = cal.date(byAdding: .month, value: monthOffset, to: now) else { return 0 }
            return transactions.filter { $0.kind == kind && cal.isDate($0.date, equalTo: m, toGranularity: .month) }.map(\.amount).reduce(0, +)
        }
        if q.contains("how much did i spend") || q.contains("spending this month") || q.contains("spent this month") {
            let spent = monthTotal(.expense)
            let top = Dictionary(grouping: transactions.filter { $0.kind == .expense && cal.isDate($0.date, equalTo: now, toGranularity: .month) }, by: \.category)
                .mapValues { $0.map(\.amount).reduce(0, +) }.max(by: { $0.value < $1.value })
            return "You spent \(spent.asCurrency()) this month." + (top.map { " Your biggest category is \($0.key.displayName) at \($0.value.asCurrency())." } ?? "")
        }
        if q.contains("income") || q.contains("earn") {
            return "Income this month: \(monthTotal(.income).asCurrency()). Last month: \(monthTotal(.income, monthOffset: -1).asCurrency())."
        }
        if q.contains("subscription") {
            let active = subscriptions.filter(\.isActive)
            let total = active.map(\.monthlyCost).reduce(0, +)
            let list = active.map { "\($0.merchant) (\($0.amount.asCurrency())/\($0.interval))" }.joined(separator: ", ")
            return active.isEmpty ? "No active subscriptions are tracked yet. Import transactions and PAYFLOW will detect recurring charges." : "You have \(active.count) active subscriptions costing about \(total.asCurrency()) / month: \(list)."
        }
        if q.contains("budget") {
            if budgets.isEmpty { return "No budgets set yet. Add one on the Budgets tab and I can track it against real spending." }
            let lines = budgets.map { b in
                let spent = transactions.filter { $0.category == b.category && $0.kind == .expense && cal.isDate($0.date, equalTo: now, toGranularity: .month) }.map(\.amount).reduce(0, +)
                return "\(b.category.displayName): \(spent.asCurrency()) of \(b.monthlyLimit.asCurrency())"
            }
            return lines.joined(separator: "\n")
        }
        if q.contains("save") || q.contains("saving") || q.contains("cut") {
            let subs = subscriptions.filter(\.isActive).sorted { $0.monthlyCost > $1.monthlyCost }
            if let biggest = subs.first {
                return "Your largest subscription is \(biggest.merchant) at \(biggest.amount.asCurrency()) / \(biggest.interval). Cancelling it would save about \(biggest.monthlyCost.asCurrency()) / month. I can also show your top spending categories on the Analytics tab."
            }
            return "Import a month of statements first and I can point to the specific categories and subscriptions where savings are realistic."
        }
        if q.contains("forecast") || q.contains("end of month") || q.contains("project") {
            let f = ForecastEngine.forecast(transactions: transactions, currentBalance: 0)
            return "Based on the last 3 months: expected income \(f.expectedIncome.asCurrency()), expected expenses \(f.expectedExpenses.asCurrency()). \(f.trendNote)"
        }
        return nil
    }

    /// What WOULD be sent to an external AI, if the user consents.
    /// Shown verbatim in Settings before consent — no hidden fields.
    static func externalPayloadPreview(transactions: [PayTransaction]) -> String {
        let total = transactions.count
        let spent = transactions.filter { $0.kind == .expense }.map(\.amount).reduce(0, +)
        let earned = transactions.filter { $0.kind == .income }.map(\.amount).reduce(0, +)
        return """
        Aggregated summary only (no raw descriptions, no account numbers):
        - Transactions in scope: \(total)
        - Total income: \(earned.asCurrency())
        - Total spending: \(spent.asCurrency())
        - Spending by category (totals only, no merchant names)
        """
    }
}
