import SwiftUI
import SwiftData

struct BudgetsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PayTransaction.date, order: .reverse) private var transactions: [PayTransaction]
    @Query(sort: \PayBudget.monthStart, order: .reverse) private var budgets: [PayBudget]
    @State private var showAdd = false

    private func spent(for category: PayCategory) -> Double {
        transactions.filter { $0.category == category && $0.kind == .expense && Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }.map(\.amount).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if budgets.isEmpty {
                        Text("No budgets yet. Add one per category — PAYFLOW tracks real spending against it automatically, no manual entry needed.")
                            .font(.subheadline).foregroundStyle(PayTheme.textSecondary).payCard()
                    }
                    ForEach(budgets) { b in
                        let s = spent(for: b.category)
                        let pct = b.monthlyLimit > 0 ? min(s / b.monthlyLimit, 1) : 0
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: b.category.systemImage).foregroundStyle(PayTheme.emerald)
                                Text(b.category.displayName).bold().foregroundStyle(PayTheme.textPrimary)
                                Spacer()
                                Text("\(s.asCurrency()) / \(b.monthlyLimit.asCurrency())").font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                            }
                            ProgressView(value: pct)
                                .tint(pct >= 1 ? PayTheme.danger : pct >= 0.8 ? PayTheme.warning : PayTheme.emerald)
                            HStack {
                                Text(pct >= 1 ? "Over budget" : "\(Int(pct * 100))% used · \((b.monthlyLimit - s).asCurrency()) left")
                                    .font(.caption).foregroundStyle(pct >= 1 ? PayTheme.danger : PayTheme.textSecondary)
                                Spacer()
                                Button(role: .destructive) { context.delete(b); try? context.save() } label: {
                                    Label("Delete", systemImage: "trash").font(.caption)
                                }
                            }
                        }
                        .payCard()
                    }
                    Button { showAdd = true } label: {
                        Label("Add budget", systemImage: "plus").frame(maxWidth: .infinity).padding()
                            .background(PayTheme.emerald).foregroundStyle(.black).font(.headline)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding()
            }
            .navigationTitle("Budgets")
            .payNavBar()
            .sheet(isPresented: $showAdd) { AddBudgetView() }
        }
    }
}

struct AddBudgetView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var category: PayCategory = .groceries
    @State private var limitText = ""
    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $category) {
                    ForEach(PayCategory.allCases.filter { !$0.isIncome && $0 != .transfer && $0 != .uncategorized }) { c in Text(c.displayName).tag(c) }
                }
                TextField("Monthly limit (USD)", text: $limitText).keyboardType(.decimalPad)
                Text("Applies to \(Date().monthYearLabel). Spending is measured from imported transactions.")
                    .font(.caption).foregroundStyle(PayTheme.textSecondary)
            }
            .navigationTitle("New budget")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let limit = Double(limitText), limit > 0 else { return }
                        context.insert(PayBudget(category: category, monthlyLimit: limit, monthStart: Date().startOfMonth()))
                        try? context.save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: { dismiss() }) }
            }
        }
    }
}
