import Foundation
import SwiftData

/// Clearly-labelled DEMO data. Never mixed with real imports: every row
/// has source == .demo and account "Demo". Deletable in one tap in Settings.
/// This exists so the charts, budgets and AI can be previewed before the
/// first real statement import — it is not presented as real money.
enum SampleData {
    @MainActor
    static func loadDemo(context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<PayTransaction>())) == 0 else { return }
        let cal = Calendar.current
        let now = Date()
        func d(_ monthsAgo: Int, _ day: Int) -> Date {
            cal.date(byAdding: .month, value: -monthsAgo, to: now).flatMap {
                cal.date(from: DateComponents(year: cal.component(.year, from: $0), month: cal.component(.month, from: $0), day: day))
            } ?? now
        }
        let rows: [(Date, String, Double, TransactionKind, PayCategory)] = [
            (d(0, 1), "Acme Corp Payroll", 4200, .income, .salary),
            (d(1, 1), "Acme Corp Payroll", 4200, .income, .salary),
            (d(2, 1), "Acme Corp Payroll", 4200, .income, .salary),
            (d(0, 2), "Whole Foods Market", 86.40, .expense, .groceries),
            (d(0, 5), "Trader Joe's", 54.20, .expense, .groceries),
            (d(0, 3), "Blue Bottle Coffee", 6.80, .expense, .dining),
            (d(0, 7), "Chipotle", 14.35, .expense, .dining),
            (d(0, 4), "Netflix", 15.49, .expense, .subscriptions),
            (d(0, 4), "Spotify", 11.99, .expense, .subscriptions),
            (d(0, 6), "Shell", 42.10, .expense, .transport),
            (d(0, 8), "Uber", 18.60, .expense, .transport),
            (d(0, 1), "Landlord — Rent", 1450, .expense, .housing),
            (d(0, 10), "Comcast Internet", 79.99, .expense, .utilities),
            (d(0, 9), "Amazon", 32.99, .expense, .shopping),
            (d(1, 2), "Whole Foods Market", 91.15, .expense, .groceries),
            (d(1, 4), "Netflix", 15.49, .expense, .subscriptions),
            (d(1, 4), "Spotify", 11.99, .expense, .subscriptions),
            (d(1, 1), "Landlord — Rent", 1450, .expense, .housing),
            (d(2, 4), "Netflix", 15.49, .expense, .subscriptions),
            (d(2, 1), "Landlord — Rent", 1450, .expense, .housing),
        ]
        for (date, merchant, amount, kind, cat) in rows {
            let fp = DuplicateDetector.fingerprint(date: date, amount: amount, merchant: merchant, accountName: "Demo")
            context.insert(PayTransaction(date: date, merchant: merchant, rawDescription: merchant,
                                          amount: amount, kind: kind, category: cat,
                                          source: .demo, syncStatus: .imported,
                                          accountName: "Demo", fingerprint: fp))
        }
        context.insert(PayAccount(name: "Demo Checking", institution: "Demo Bank", balance: 5240.18, isDemo: true))
        // Demo cards for the swipeable carousel (like the reference's
        // BCA / Mandiri / Jago cards). Balance 0 so they don't change the
        // demo total — they exist so "swipe left / right" can be tried
        // before any real card is connected. Deleted with demo data.
        context.insert(PayAccount(name: "BCA •••• 4321", institution: "BCA", type: "card", balance: 0, currencyCode: "IDR", isDemo: true))
        context.insert(PayAccount(name: "Mandiri •••• 7788", institution: "Mandiri", type: "card", balance: 0, currencyCode: "IDR", isDemo: true))
        context.insert(PayAccount(name: "Jago •••• 9911", institution: "Jago", type: "card", balance: 0, currencyCode: "IDR", isDemo: true))
        context.insert(PayBudget(category: .groceries, monthlyLimit: 400, monthStart: now.startOfMonth()))
        context.insert(PayBudget(category: .dining, monthlyLimit: 200, monthStart: now.startOfMonth()))
        context.insert(PaySubscription(merchant: "Netflix", amount: 15.49, interval: "monthly", nextDate: cal.date(byAdding: .month, value: 1, to: now) ?? now, category: .subscriptions))
        context.insert(PaySubscription(merchant: "Spotify", amount: 11.99, interval: "monthly", nextDate: cal.date(byAdding: .month, value: 1, to: now) ?? now, category: .subscriptions))
        try? context.save()
    }

    @MainActor
    static func clearDemo(context: ModelContext, transactions: [PayTransaction]) {
        for tx in transactions where tx.source == .demo { context.delete(tx) }
        for a in (try? context.fetch(FetchDescriptor<PayAccount>())) ?? [] where a.isDemo { context.delete(a) }
        try? context.save()
    }
}
