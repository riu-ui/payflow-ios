import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PayTransaction.date, order: .reverse) private var transactions: [PayTransaction]
    @Query(sort: \PaySubscription.nextDate) private var subscriptions: [PaySubscription]
    @State private var showAdd = false

    private var candidates: [RecurringCandidate] {
        let detected = RecurringDetector.detect(from: transactions)
        let known = Set(subscriptions.map { CategorizationEngine.normalizeKey($0.merchant) })
        return detected.filter { !known.contains(CategorizationEngine.normalizeKey($0.merchant)) }
    }
    private var active: [PaySubscription] { subscriptions.filter(\.isActive) }
    private var monthlyTotal: Double { active.map(\.monthlyCost).reduce(0, +) }
    private var yearlyTotal: Double { monthlyTotal * 12 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recurring spending").font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                        Text(monthlyTotal.asCurrency()).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(PayTheme.textPrimary)
                        Text("per month · \(yearlyTotal.asCurrency()) per year across \(active.count) active subscriptions")
                            .font(.caption).foregroundStyle(PayTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).payCard()

                    if !candidates.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Detected — confirm to track")
                            Text("Found in your real transaction history. Nothing is added until you confirm it.")
                                .font(.caption).foregroundStyle(PayTheme.textSecondary)
                            ForEach(candidates) { c in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.merchant).bold().foregroundStyle(PayTheme.textPrimary)
                                        Text("\(c.occurrences) charges · every \(c.interval) · next \(c.nextExpected.shortDateLabel)")
                                            .font(.caption).foregroundStyle(PayTheme.textSecondary)
                                    }
                                    Spacer()
                                    Text(c.amount.asCurrency()).foregroundStyle(PayTheme.textPrimary)
                                    Button("Track") {
                                        context.insert(PaySubscription(merchant: c.merchant, amount: c.amount, interval: c.interval, nextDate: c.nextExpected, category: c.category))
                                        try? context.save()
                                    }
                                    .buttonStyle(.borderedProminent).tint(PayTheme.emerald).foregroundStyle(.black).font(.caption.bold())
                                }
                            }
                        }
                        .payCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Active subscriptions")
                        if active.isEmpty {
                            Text("None tracked yet. Import statements and PAYFLOW will detect recurring charges, or add one manually below.")
                                .font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                        }
                        ForEach(active) { s in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.merchant).bold().foregroundStyle(PayTheme.textPrimary)
                                    Text("Next: \(s.nextDate.shortDateLabel) · \(s.category.displayName)").font(.caption).foregroundStyle(PayTheme.textSecondary)
                                }
                                Spacer()
                                Text("\(s.amount.asCurrency()) / \(s.interval)").foregroundStyle(PayTheme.textPrimary)
                                Button { s.isActive = false; try? context.save() } label: { Text("Cancel").font(.caption.bold()).foregroundStyle(PayTheme.danger) }
                            }
                        }
                    }
                    .payCard()

                    Button { showAdd = true } label: {
                        Label("Add subscription", systemImage: "plus").frame(maxWidth: .infinity).padding()
                            .background(PayTheme.emerald).foregroundStyle(.black).font(.headline)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding()
            }
            .navigationTitle("Subscriptions")
            .payNavBar()
            .sheet(isPresented: $showAdd) { AddSubscriptionView() }
        }
    }
}

struct AddSubscriptionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var merchant = ""
    @State private var amountText = ""
    @State private var interval = "monthly"
    @State private var nextDate = Date()
    var body: some View {
        NavigationStack {
            Form {
                TextField("Merchant (e.g. Netflix)", text: $merchant)
                TextField("Amount", text: $amountText).keyboardType(.decimalPad)
                Picker("Interval", selection: $interval) {
                    Text("Weekly").tag("weekly"); Text("Monthly").tag("monthly"); Text("Yearly").tag("yearly")
                }
                DatePicker("Next charge", selection: $nextDate, displayedComponents: .date)
            }
            .navigationTitle("New subscription")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amt = Double(amountText), amt > 0, !merchant.isEmpty else { return }
                        context.insert(PaySubscription(merchant: merchant, amount: amt, interval: interval, nextDate: nextDate, category: .subscriptions))
                        try? context.save(); dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: { dismiss() }) }
            }
        }
    }
}
