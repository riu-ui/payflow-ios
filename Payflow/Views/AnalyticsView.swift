import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PayTransaction.date, order: .reverse) private var transactions: [PayTransaction]
    @State private var monthOffset = 0
    @State private var showReport = false

    private var month: Date {
        Calendar.current.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }
    private var monthTx: [PayTransaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }
    private var byCategory: [(PayCategory, Double)] {
        Dictionary(grouping: monthTx.filter { $0.kind == .expense }, by: \.category)
            .mapValues { $0.map(\.amount).reduce(0, +) }.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
    private var daily: [(Date, Double)] {
        let cal = Calendar.current
        var days: [Date: Double] = [:]
        for tx in monthTx where tx.kind == .expense { days[cal.startOfDay(for: tx.date), default: 0] += tx.amount }
        return days.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
    private var income: Double { monthTx.filter { $0.kind == .income }.map(\.amount).reduce(0, +) }
    private var expenses: Double { monthTx.filter { $0.kind == .expense }.map(\.amount).reduce(0, +) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Month stepper
                    HStack {
                        Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text(month.monthYearLabel).font(.headline).foregroundStyle(PayTheme.textPrimary)
                        Spacer()
                        Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }
                            .disabled(monthOffset >= 0).opacity(monthOffset >= 0 ? 0.3 : 1)
                    }
                    .foregroundStyle(PayTheme.emerald)
                    .padding(.horizontal, 4)

                    HStack(spacing: 12) {
                        StatCard(label: "Income", value: income.asCurrency(), tint: PayTheme.income)
                        StatCard(label: "Expenses", value: expenses.asCurrency(), tint: PayTheme.expense)
                        StatCard(label: "Net", value: (income - expenses).asCurrency(), tint: (income - expenses) >= 0 ? PayTheme.emerald : PayTheme.danger)
                    }

                    if byCategory.isEmpty {
                        Text("No spending in \(month.monthYearLabel) yet. Import a statement to see analytics here.")
                            .font(.subheadline).foregroundStyle(PayTheme.textSecondary).payCard()
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Spending by category")
                            Chart(byCategory, id: \.0) { cat, amt in
                                SectorMark(angle: .value("Amount", amt), innerRadius: .ratio(0.55), angularInset: 2)
                                    .foregroundStyle(by: .value("Category", cat.displayName))
                            }
                            .frame(height: 220)
                            ForEach(byCategory, id: \.0) { cat, amt in
                                HStack {
                                    Image(systemName: cat.systemImage).foregroundStyle(PayTheme.emerald).frame(width: 22)
                                    Text(cat.displayName).foregroundStyle(PayTheme.textPrimary)
                                    Spacer()
                                    Text(amt.asCurrency()).bold().foregroundStyle(PayTheme.textPrimary)
                                    Text(String(format: "%.0f%%", amt / max(expenses, 1) * 100)).font(.caption).foregroundStyle(PayTheme.textSecondary).frame(width: 38, alignment: .trailing)
                                }
                                .font(.subheadline)
                            }
                        }
                        .payCard()

                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Daily spending")
                            Chart(daily, id: \.0) { day, amt in
                                BarMark(x: .value("Day", day, unit: .day), y: .value("Spent", amt))
                                    .foregroundStyle(PayTheme.emerald.gradient)
                            }
                            .frame(height: 140)
                        }
                        .payCard()
                    }

                    Button { showReport = true } label: {
                        Label("Monthly report — \(month.monthYearLabel)", systemImage: "doc.text")
                            .frame(maxWidth: .infinity).padding()
                            .background(PayTheme.surface).foregroundStyle(PayTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding()
            }
            .navigationTitle("Analytics")
            .payNavBar()
            .sheet(isPresented: $showReport) { ReportView(month: month) }
        }
    }
}

struct ReportView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PayTransaction.date, order: .reverse) private var transactions: [PayTransaction]
    let month: Date
    @State private var shareURL: URL? = nil
    @State private var showShare = false

    private var report: ReportService.MonthlyReport { ReportService.monthlyReport(for: month, transactions: transactions) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(month.monthYearLabel).font(.title2.bold()).foregroundStyle(PayTheme.textPrimary)
                    HStack(spacing: 12) {
                        StatCard(label: "Income", value: report.income.asCurrency(), tint: PayTheme.income)
                        StatCard(label: "Expenses", value: report.expenses.asCurrency(), tint: PayTheme.expense)
                    }
                    StatCard(label: "Net", value: report.net.asCurrency(), tint: report.net >= 0 ? PayTheme.emerald : PayTheme.danger)
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "By category · \(report.transactionCount) transactions")
                        ForEach(report.byCategory, id: \.0) { cat, amt in
                            HStack { Text(cat.displayName).foregroundStyle(PayTheme.textPrimary); Spacer(); Text(amt.asCurrency()).bold().foregroundStyle(PayTheme.textPrimary) }.font(.subheadline)
                        }
                    }.payCard()
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Top merchants")
                        ForEach(report.topMerchants, id: \.0) { m, amt in
                            HStack { Text(m).foregroundStyle(PayTheme.textPrimary); Spacer(); Text(amt.asCurrency()).foregroundStyle(PayTheme.textSecondary) }.font(.subheadline)
                        }
                    }.payCard()
                    HStack(spacing: 12) {
                        Button("Export CSV") { exportCSV() }.buttonStyle(.borderedProminent).tint(PayTheme.emerald).foregroundStyle(.black)
                        Button("Export PDF") { exportPDF() }.buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showShare) {
                if let url = shareURL { ShareSheet(url: url) }
            }
        }
    }

    private func exportCSV() {
        let csv = ReportService.csv(for: transactions.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("payflow-\(month.monthYearLabel).csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        shareURL = url; showShare = true
    }
    private func exportPDF() {
        let data = ReportService.pdf(for: report)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("payflow-\(month.monthYearLabel).pdf")
        try? data.write(to: url)
        shareURL = url; showShare = true
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
