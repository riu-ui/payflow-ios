import Foundation
import UIKit

/// Monthly / yearly reports from real SwiftData records + CSV/PDF export.
struct ReportService {
    struct MonthlyReport {
        let month: Date
        let income: Double
        let expenses: Double
        let net: Double
        let byCategory: [(PayCategory, Double)]
        let transactionCount: Int
        let topMerchants: [(String, Double)]
    }

    static func monthlyReport(for month: Date, transactions: [PayTransaction]) -> MonthlyReport {
        let cal = Calendar.current
        let list = transactions.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
        let income = list.filter { $0.kind == .income }.map(\.amount).reduce(0, +)
        let expenses = list.filter { $0.kind == .expense }.map(\.amount).reduce(0, +)
        let byCat = Dictionary(grouping: list.filter { $0.kind == .expense }, by: \.category)
            .mapValues { $0.map(\.amount).reduce(0, +) }
            .sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        let top = Dictionary(grouping: list.filter { $0.kind == .expense }, by: \.merchant)
            .mapValues { $0.map(\.amount).reduce(0, +) }
            .sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
        return MonthlyReport(month: month, income: income, expenses: expenses, net: income - expenses,
                             byCategory: byCat, transactionCount: list.count, topMerchants: top)
    }

    static func yearlySummary(year: Int, transactions: [PayTransaction]) -> [MonthlyReport] {
        (1...12).compactMap { m in
            var comps = DateComponents(year: year, month: m, day: 1)
            guard let d = Calendar.current.date(from: comps) else { return nil }
            comps.day = 1
            return monthlyReport(for: d, transactions: transactions)
        }
    }

    static func csv(for transactions: [PayTransaction]) -> String {
        var lines = ["Date,Merchant,Description,Category,Kind,Amount,Currency,Source,Sync Status,Account"]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        for tx in transactions.sorted(by: { $0.date < $1.date }) {
            func esc(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            lines.append([f.string(from: tx.date), esc(tx.merchant), esc(tx.rawDescription),
                          tx.category.displayName, tx.kind.rawValue,
                          String(format: "%.2f", tx.amount), tx.currencyCode,
                          tx.source.rawValue, tx.syncStatus.rawValue, esc(tx.accountName)].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// Simple, printable PDF report rendered on-device with UIGraphicsPDFRenderer.
    static func pdf(for report: MonthlyReport) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 22)]
            let bodyAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13)]
            var y: CGFloat = 48
            func draw(_ s: String, attrs: [NSAttributedString.Key: Any] = bodyAttrs, gap: CGFloat = 22) {
                s.draw(at: CGPoint(x: 48, y: y), withAttributes: attrs); y += gap
            }
            draw("PAYFLOW — \(report.month.monthYearLabel)", attrs: titleAttrs, gap: 34)
            draw("Income: \(report.income.asCurrency())")
            draw("Expenses: \(report.expenses.asCurrency())")
            draw("Net: \(report.net.asCurrency())")
            draw("Transactions: \(report.transactionCount)", gap: 32)
            draw("Spending by category", attrs: [.font: UIFont.boldSystemFont(ofSize: 15)], gap: 26)
            for (cat, amt) in report.byCategory { draw("\(cat.displayName): \(amt.asCurrency())") }
            y += 10
            draw("Top merchants", attrs: [.font: UIFont.boldSystemFont(ofSize: 15)], gap: 26)
            for (m, amt) in report.topMerchants { draw("\(m): \(amt.asCurrency())") }
        }
    }
}
