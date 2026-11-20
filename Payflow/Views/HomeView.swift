import SwiftUI
import SwiftData
import Charts

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PayTransaction.date, order: .reverse) private var transactions: [PayTransaction]
    @Query private var accounts: [PayAccount]
    @Query private var subscriptions: [PaySubscription]
    @State private var showImporter = false

    private var balance: Double { accounts.map(\.balance).reduce(0, +) }
    private var monthIncome: Double {
        transactions.filter { $0.kind == .income && Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }.map(\.amount).reduce(0, +)
    }
    private var monthSpent: Double {
        transactions.filter { $0.kind == .expense && Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }.map(\.amount).reduce(0, +)
    }
    private var forecast: ForecastEngine.Forecast {
        ForecastEngine.forecast(transactions: transactions, currentBalance: balance)
    }
    private var recent: [PayTransaction] { Array(transactions.prefix(5)) }
    private var spentByAccount: [String: Double] {
        var out: [String: Double] = [:]
        for tx in transactions where tx.kind == .expense && Calendar.current.isDate(tx.date, equalTo: Date(), toGranularity: .month) {
            out[tx.accountName, default: 0] += tx.amount
        }
        return out
    }
    private var monthlySeries: [(String, Double)] {
        let cal = Calendar.current
        return (0..<6).reversed().compactMap { offset in
            guard let m = cal.date(byAdding: .month, value: -offset, to: Date()) else { return nil }
            let spent = transactions.filter { $0.kind == .expense && cal.isDate($0.date, equalTo: m, toGranularity: .month) }.map(\.amount).reduce(0, +)
            let f = DateFormatter(); f.dateFormat = "MMM"
            return (f.string(from: m), spent)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Balance hero — light glossy card, like the reference.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Total balance").font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                        Text(balance.asCurrency()).font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(PayTheme.textPrimary)
                        Text(forecast.trendNote).font(.caption).foregroundStyle(PayTheme.textSecondary)
                        HStack(spacing: 12) {
                            Label("+\(monthIncome.asCurrency()) income", systemImage: "arrow.up.right").font(.caption).foregroundStyle(PayTheme.income)
                            Label("−\(monthSpent.asCurrency()) spent", systemImage: "arrow.down.right").font(.caption).foregroundStyle(PayTheme.expense)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .payHeroLightCard()

                    // Income / Expenses — two white mini-cards, like the reference.
                    HStack(spacing: 12) {
                        StatCard(label: "Income", value: monthIncome.asCurrency(), tint: PayTheme.income)
                        StatCard(label: "Expenses", value: monthSpent.asCurrency(), tint: PayTheme.expense)
                    }

                    // Your cards — swipe left / right between them.
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Your cards")
                        CardsCarouselView(accounts: accounts, spentByAccount: spentByAccount)
                    }

                    // Cashflow forecast
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Cashflow forecast")
                        HStack {
                            StatCard(label: "Projected month-end", value: forecast.projectedMonthEndBalance.asCurrency(), tint: PayTheme.textPrimary)
                            StatCard(label: "Safe to spend / day", value: forecast.dailySafeSpend.asCurrency(), tint: PayTheme.emerald)
                        }
                        Text("Runway: \(forecast.runwayMonths >= 99 ? "—" : String(format: "%.1f months", forecast.runwayMonths)) of expenses covered by your current balance.")
                            .font(.caption).foregroundStyle(PayTheme.textSecondary)
                    }

                    // Spending trend
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Spending — last 6 months")
                        Chart(monthlySeries, id: \.0) { month, spent in
                            BarMark(x: .value("Month", month), y: .value("Spent", spent))
                                .foregroundStyle(PayTheme.emerald.gradient)
                                .cornerRadius(6)
                        }
                        .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel().foregroundStyle(PayTheme.textMuted) } }
                        .chartXAxis { AxisMarks { AxisValueLabel().foregroundStyle(PayTheme.textMuted) } }
                        .frame(height: 160)
                    }
                    .payCard()

                    // Quick actions — import first, manual entry is NOT the primary workflow
                    HStack(spacing: 12) {
                        Button { showImporter = true } label: {
                            Label("Import statement", systemImage: "tray.and.arrow.down.fill")
                        }
                        .buttonStyle(.borderedProminent).tint(PayTheme.emerald).foregroundStyle(.black)
                        NavigationLink(destination: TransactionsView()) {
                            Label("All transactions", systemImage: "list.bullet")
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)

                    // Recent
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            SectionHeader(title: "Recent transactions")
                            Spacer()
                            NavigationLink("See all", destination: TransactionsView()).font(.caption)
                        }
                        if recent.isEmpty {
                            Text("No transactions yet. Import a CSV, XLSX or PDF statement to see your finances here — nothing is entered by hand by default.")
                                .font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                        } else {
                            ForEach(recent) { tx in TransactionRowView(tx: tx) }
                        }
                    }
                    .payCard()

                    // Subscriptions preview
                    let activeSubs = subscriptions.filter(\.isActive)
                    if !activeSubs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Subscriptions — \(activeSubs.map(\.monthlyCost).reduce(0, +).asCurrency()) / month")
                            ForEach(activeSubs.prefix(3)) { s in
                                HStack {
                                    Text(s.merchant).foregroundStyle(PayTheme.textPrimary)
                                    Spacer()
                                    Text("\(s.amount.asCurrency()) / \(s.interval)").foregroundStyle(PayTheme.textSecondary)
                                }.font(.subheadline)
                            }
                        }
                        .payCard()
                    }
                }
                .padding()
            }
            .navigationTitle("PAYFLOW")
            .payNavBar()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showImporter = true } label: { Image(systemName: "plus.circle.fill").foregroundStyle(PayTheme.emerald) } } }
            .sheet(isPresented: $showImporter) { ImportSheetView() }
        }
    }
}
