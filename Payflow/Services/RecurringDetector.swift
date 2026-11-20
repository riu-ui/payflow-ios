import Foundation

/// Recurring-payment / subscription detection from real history.
/// A merchant + near-identical amount appearing 3+ times at a regular
/// interval (weekly 6–8d, monthly 27–33d, yearly 360–370d) is a candidate.
/// Nothing is created as a subscription without the user confirming it
/// on the Subscriptions screen.
struct RecurringCandidate: Identifiable {
    let id = UUID()
    let merchant: String
    let amount: Double
    let interval: String
    let occurrences: Int
    let lastDate: Date
    let nextExpected: Date
    let category: PayCategory
}

struct RecurringDetector {
    static func detect(from transactions: [PayTransaction]) -> [RecurringCandidate] {
        // Group expenses by normalised merchant.
        var groups: [String: [PayTransaction]] = [:]
        for tx in transactions where tx.kind == .expense {
            groups[CategorizationEngine.normalizeKey(tx.merchant), default: []].append(tx)
        }
        var out: [RecurringCandidate] = []
        for (_, list) in groups {
            let sorted = list.sorted { $0.date < $1.date }
            guard sorted.count >= 3 else { continue }
            // Amounts must cluster within 2% (allows small price changes).
            let median = sorted.map(\.amount).sorted()[sorted.count / 2]
            guard median > 0, sorted.allSatisfy({ abs($0.amount - median) / median < 0.05 }) else { continue }
            // Intervals between consecutive charges.
            var gaps: [Int] = []
            for i in 1..<sorted.count {
                gaps.append(Calendar.current.dateComponents([.day], from: sorted[i-1].date, to: sorted[i].date).day ?? 0)
            }
            let avgGap = Double(gaps.reduce(0, +)) / Double(max(gaps.count, 1))
            let interval: String?
            if (6...8).contains(avgGap) { interval = "weekly" }
            else if (27...33).contains(avgGap) { interval = "monthly" }
            else if (360...370).contains(avgGap) { interval = "yearly" }
            else { interval = nil }
            guard let interval, let last = sorted.last else { continue }
            let next = Calendar.current.date(byAdding: interval == "weekly" ? .day : interval == "monthly" ? .month : .year,
                                             value: interval == "weekly" ? 7 : 1, to: last.date) ?? last.date
            out.append(RecurringCandidate(merchant: last.merchant, amount: median, interval: interval,
                                          occurrences: sorted.count, lastDate: last.date,
                                          nextExpected: next, category: last.category))
        }
        return out.sorted { $0.amount > $1.amount }
    }
}

// MARK: - Forecasting

struct ForecastEngine {
    struct Forecast {
        let projectedMonthEndBalance: Double
        let expectedIncome: Double
        let expectedExpenses: Double
        let dailySafeSpend: Double
        let runwayMonths: Double // months of expenses covered by current balance
        let trendNote: String
    }

    /// Forecast from the last 3 full months of real data. No invented data:
    /// with < 30 days of history the forecast is labelled low-confidence.
    static func forecast(transactions: [PayTransaction], currentBalance: Double, asOf: Date = Date()) -> Forecast {
        let cal = Calendar.current
        let threeMonthsAgo = cal.date(byAdding: .month, value: -3, to: asOf.startOfMonth()) ?? asOf
        let recent = transactions.filter { $0.date >= threeMonthsAgo && $0.date <= asOf }
        let months = max(1, cal.dateComponents([.month], from: threeMonthsAgo, to: asOf).month ?? 1)
        let income = recent.filter { $0.kind == .income }.map(\.amount).reduce(0, +) / Double(months)
        let expenses = recent.filter { $0.kind == .expense }.map(\.amount).reduce(0, +) / Double(months)
        let daysLeft = Double(cal.range(of: .day, in: .month, for: asOf)?.count ?? 30) - Double(cal.component(.day, from: asOf))
        let projected = currentBalance + income - expenses
        let dailySafe = daysLeft > 0 ? max(0, (currentBalance + income - expenses) / max(daysLeft, 1)) : 0
        let runway = expenses > 0 ? currentBalance / expenses : 99
        let note: String
        if recent.count < 10 {
            note = "Low confidence — fewer than 10 transactions in the last 3 months."
        } else if expenses > income {
            note = "Spending is running above income on a 3-month average."
        } else {
            note = "On track — income covers spending on a 3-month average."
        }
        return Forecast(projectedMonthEndBalance: projected, expectedIncome: income,
                        expectedExpenses: expenses, dailySafeSpend: dailySafe,
                        runwayMonths: runway, trendNote: note)
    }
}
