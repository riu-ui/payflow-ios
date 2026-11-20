import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PayTransaction.date, order: .reverse) private var transactions: [PayTransaction]
    @Query private var rules: [MerchantRule]
    @State private var search = ""
    @State private var filter: PayCategory? = nil
    @State private var showImporter = false
    @State private var editingTx: PayTransaction? = nil

    private var filtered: [PayTransaction] {
        transactions.filter { tx in
            (filter == nil || tx.category == filter) &&
            (search.isEmpty || tx.merchant.localizedCaseInsensitiveContains(search) || tx.rawDescription.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(nil, label: "All")
                        ForEach(PayCategory.allCases) { cat in filterChip(cat, label: cat.displayName) }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                List {
                    ForEach(filtered) { tx in
                        TransactionRowView(tx: tx)
                            .listRowBackground(PayTheme.surface)
                            .contentShape(Rectangle())
                            .onTapGesture { editingTx = tx }
                            .swipeActions {
                                Button(role: .destructive) { context.delete(tx); try? context.save() } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $search, prompt: "Search merchant or description")
            }
            .navigationTitle("Transactions")
            .payNavBar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: { Image(systemName: "tray.and.arrow.down") }
                }
            }
            .sheet(isPresented: $showImporter) { ImportSheetView() }
            .sheet(item: $editingTx) { tx in TransactionDetailView(tx: tx) }
        }
    }

    private func filterChip(_ cat: PayCategory?, label: String) -> some View {
        Button(label) {
            withAnimation { filter = cat }
        }
        .font(.caption.bold())
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(filter == cat ? PayTheme.emerald : PayTheme.surface)
        .foregroundStyle(filter == cat ? .black : PayTheme.textSecondary)
        .clipShape(Capsule())
    }
}

struct TransactionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var rules: [MerchantRule]
    let tx: PayTransaction
    @State private var selectedCategory: PayCategory

    init(tx: PayTransaction) {
        self.tx = tx
        _selectedCategory = State(initialValue: tx.category)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    LabeledContent("Merchant", value: tx.merchant)
                    LabeledContent("Description", value: tx.rawDescription)
                    LabeledContent("Date", value: tx.date.shortDateLabel)
                    LabeledContent("Amount", value: (tx.kind == .income ? "+" : "−") + tx.amount.asCurrency(tx.currencyCode))
                    LabeledContent("Account", value: tx.accountName)
                }
                Section("Source & sync") {
                    LabeledContent("Source", value: tx.source.rawValue)
                    LabeledContent("Sync status", value: tx.syncStatus.rawValue)
                    LabeledContent("Fingerprint", value: String(tx.fingerprint.prefix(24)) + "…")
                }
                Section("Category — correcting this teaches PAYFLOW") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(PayCategory.allCases) { c in Text(c.displayName).tag(c) }
                    }
                    .pickerStyle(.navigationLink)
                    Text("Future imports from \(tx.merchant) will use this category automatically.")
                        .font(.caption).foregroundStyle(PayTheme.textSecondary)
                }
            }
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if selectedCategory != tx.category {
                            tx.categoryRaw = selectedCategory.rawValue
                            ImportService.recordCorrection(merchant: tx.merchant, category: selectedCategory, context: context, existingRules: rules)
                        }
                        try? context.save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Close", action: { dismiss() }) }
            }
        }
    }
}

// MARK: - Import sheet (CSV / XLSX / PDF — the primary ingestion path)

struct ImportSheetView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PayTransaction.date, order: .reverse) private var transactions: [PayTransaction]
    @Query private var rules: [MerchantRule]
    @State private var showPicker = false
    @State private var resultMessage: String? = nil
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Import a bank statement")
                    .font(.title2.bold()).foregroundStyle(PayTheme.textPrimary)
                Text("Choose a CSV, XLSX or PDF statement downloaded from your bank. PAYFLOW categorises each row, detects duplicates, and shows the source and sync status of every transaction.")
                    .font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                VStack(alignment: .leading, spacing: 10) {
                    Label("CSV — most reliable, works with almost every bank", systemImage: "tablecells")
                    Label("XLSX — first sheet, header row detected automatically", systemImage: "tablecells.badge.ellipsis")
                    Label("PDF — text-based statements; scanned/image PDFs cannot be read", systemImage: "doc.richtext")
                    Label("Duplicates are skipped, never imported twice", systemImage: "checkmark.shield")
                }
                .font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                if let msg = resultMessage {
                    Text(msg).font(.subheadline).foregroundStyle(PayTheme.emerald).padding().background(PayTheme.emeraldSoft).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Spacer()
                Button {
                    showPicker = true
                } label: {
                    Label(isImporting ? "Importing…" : "Choose statement file", systemImage: "folder")
                        .frame(maxWidth: .infinity).padding()
                        .background(PayTheme.emerald).foregroundStyle(.black).font(.headline)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isImporting)
                Button("Done", action: { dismiss() }).frame(maxWidth: .infinity).foregroundStyle(PayTheme.textSecondary)
            }
            .padding(24)
            .payScreenBackground()
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.commaSeparatedText, .spreadsheet, .pdf], allowsMultipleSelection: false) { result in
                handlePicked(result)
            }
        }
    }

    private func handlePicked(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            resultMessage = "No file selected."; return
        }
        isImporting = true
        Task { @MainActor in
            defer { isImporting = false }
            guard url.startAccessingSecurityScopedResource() else { resultMessage = "Could not access that file."; return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { resultMessage = "Could not read that file."; return }
            let ext = url.pathExtension.lowercased()
            let source: TransactionSource = ext == "xlsx" ? .xlsxImport : ext == "pdf" ? .pdfImport : .csvImport
            let parsed: ImportResult
            do {
                if ext == "xlsx" { parsed = try ImportService.importXLSX(data) }
                else if ext == "pdf" { parsed = ImportService.importPDF(data) }
                else { parsed = ImportService.importCSV(data) }
            } catch {
                resultMessage = "Import failed: \(error.localizedDescription)"; return
            }
            let applied = ImportService.applyImport(parsed, source: source, accountName: "Primary", context: context, existing: transactions, learned: rules)
            var msg = "Imported \(applied.inserted) transactions · \(applied.duplicates) duplicates skipped"
            if applied.needsReview > 0 { msg += " · \(applied.needsReview) need a category review" }
            if !parsed.errors.isEmpty { msg += "\n\(parsed.errors.prefix(3).joined(separator: "\n"))" }
            resultMessage = msg
        }
    }
}
