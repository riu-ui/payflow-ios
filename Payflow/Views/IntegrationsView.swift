import SwiftUI
import SwiftData

/// Integrations — all Indonesian banks, honest by design.
/// Every bank below has a real Connect flow (aggregator or direct
/// BI-SNAP). A bank becomes "Connected" ONLY after the official
/// authorisation callback returns a token. Until then it stays
/// "Not connected" — never simulated. PAYFLOW never asks for a banking
/// password, PIN or OTP, and never scrapes a banking website.
struct IntegrationsView: View {
    @Environment(\.modelContext) private var context
    @Query private var connections: [BankConnection]
    @Query private var accounts: [PayAccount]
    @Query(sort: \PayTransaction.date, order: .reverse) private var transactions: [PayTransaction]
    @Query private var rules: [MerchantRule]
    @StateObject private var connector = BankConnectService()
    @State private var search = ""
    @State private var showImporter = false
    @State private var selectedBank: IndonesianBank? = nil
    @State private var connectMessage: String? = nil
    @State private var showAutomation = false

    private var filteredBanks: [IndonesianBank] {
        IndonesianBank.all.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.shortName.localizedCaseInsensitiveContains(search) }
    }
    private func connection(for bank: IndonesianBank) -> BankConnection? {
        connections.first { $0.institutionName == bank.name }
    }
    private func isConnected(_ bank: IndonesianBank) -> Bool { connection(for: bank)?.status == "connected" }
    private var spentByAccount: [String: Double] {
        var out: [String: Double] = [:]
        for tx in transactions where tx.kind == .expense && Calendar.current.isDate(tx.date, equalTo: Date(), toGranularity: .month) {
            out[tx.accountName, default: 0] += tx.amount
        }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Cards & accounts — swipe to change card")
                        CardsCarouselView(accounts: accounts, spentByAccount: spentByAccount)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Automatic notifications — Apple Pay / crypto cards")
                        Text("Pay with a card in Apple Pay (e.g. KAST, Bybit) and PAYFLOW logs it and notifies you — no import, no typing. Set it up once in Shortcuts; PAYFLOW only receives payments you explicitly route to it.")
                            .font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                        Button { showAutomation = true } label: {
                            Label("Set up automation", systemImage: "bolt.fill")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent).tint(PayTheme.emerald).foregroundStyle(.black)
                    }
                    .payCard()

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Connect a bank — Indonesia")
                        Text("Tap Connect on your bank. You will authorise on the bank / aggregator's own page — PAYFLOW only receives a read-only token, stored in the Keychain. No password, PIN or OTP is ever entered in PAYFLOW.\n\nTwo routes: Brick / Brankas (aggregator — one integration, they maintain the bank links) or Direct bank API (BI-SNAP — register at each bank's developer portal first). File import (CSV / XLSX / PDF) always works without any of this.")
                            .font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                        if let msg = connectMessage {
                            Text(msg).font(.subheadline).foregroundStyle(PayTheme.emerald).padding().background(PayTheme.emeraldSoft).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        HStack {
                            Text("\(connections.filter { $0.status == "connected" }.count) of \(IndonesianBank.all.count) banks connected")
                                .font(.caption.bold()).foregroundStyle(PayTheme.textSecondary)
                            Spacer()
                            Button { showImporter = true } label: { Label("Import statement", systemImage: "tray.and.arrow.down").font(.caption.bold()) }
                        }
                    }
                    .payCard()

                    ForEach(BankCategory.allCases, id: \.self) { cat in
                        let banks = filteredBanks.filter { $0.category == cat }
                        if !banks.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: cat.rawValue)
                                ForEach(banks) { bank in
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10).fill(PayTheme.emeraldSoft).frame(width: 40, height: 40)
                                            Text(String(bank.shortName.prefix(2))).bold().font(.caption).foregroundStyle(PayTheme.emerald)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(bank.name).bold().font(.subheadline).foregroundStyle(PayTheme.textPrimary)
                                            Text(bank.shortName + (isConnected(bank) ? " · last sync \(connection(for: bank)?.lastSyncAt?.shortDateLabel ?? "—")" : " · \(bank.directAPINote)")).font(.caption).foregroundStyle(PayTheme.textSecondary).lineLimit(2)
                                        }
                                        Spacer()
                                        if isConnected(bank) {
                                            Button("Sync") { Task { await sync(bank) } }.buttonStyle(.bordered).font(.caption.bold())
                                            Button("Disconnect", role: .destructive) { connector.disconnect(bankName: bank.name, context: context) }.font(.caption)
                                        } else {
                                            Button("Connect") { selectedBank = bank }
                                                .buttonStyle(.borderedProminent).tint(PayTheme.emerald).foregroundStyle(.black).font(.caption.bold())
                                        }
                                    }
                                    .padding(10).background(PayTheme.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .payCard()
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "What PAYFLOW will never do")
                        ForEach(["Ask for a banking password, PIN or OTP",
                                 "Scrape a banking website",
                                 "Read SMS, inbox or other apps by itself — automation only receives payments you explicitly route to PAYFLOW in Shortcuts",
                                 "Show a bank as 'connected' before you authorise it"], id: \.self) { line in
                            Label(line, systemImage: "xmark.shield").font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                        }
                    }
                    .payCard()
                }
                .padding()
            }
            .navigationTitle("Integrations")
            .payNavBar()
            .searchable(text: $search, prompt: "Search banks — BCA, Jago, BRI…")
            .sheet(isPresented: $showImporter) { ImportSheetView() }
            .sheet(item: $selectedBank) { bank in BankConnectSheet(bank: bank) { msg in connectMessage = msg } }
            .sheet(isPresented: $showAutomation) { AutomationView() }
        }
    }

    private func sync(_ bank: IndonesianBank) async {
        guard let conn = connection(for: bank) else { return }
        let provider: ConnectProvider = conn.connectionType.contains("Brick") ? .brick : conn.connectionType.contains("Brankas") ? .brankas : .direct
        do {
            let r = try await connector.sync(bank: bank, provider: provider, context: context, existing: transactions, learned: rules)
            connectMessage = "\(bank.shortName): synced — \(r.inserted) new, \(r.duplicates) duplicates skipped."
        } catch {
            connectMessage = "\(bank.shortName): sync failed — \(error.localizedDescription)"
        }
    }
}

// MARK: - Connect sheet: provider + API key (Keychain) + official authorisation

struct BankConnectSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var connector = BankConnectService()
    let bank: IndonesianBank
    var onDone: (String) -> Void
    @State private var provider: ConnectProvider = .brick
    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var errorText: String? = nil

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connect \(bank.name)").font(.title2.bold()).foregroundStyle(PayTheme.textPrimary)
                Text("1. Choose a route below.\n2. Paste its API key — saved in the Keychain only, never in the database.\n3. Tap Connect — your bank / the aggregator's own authorisation page opens. PAYFLOW only receives a read-only token.")
                    .font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                Picker("Route", selection: $provider) {
                    ForEach(ConnectProvider.allCases) { p in Text(p.rawValue).tag(p) }
                }
                .pickerStyle(.segmented)
                Text(provider.signupHint).font(.caption).foregroundStyle(PayTheme.textSecondary)
                SecureField("API key / client ID", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { apiKey = KeychainService.read(provider.keychainKey) ?? "" }
                    .onChange(of: provider) { _, p in apiKey = KeychainService.read(p.keychainKey) ?? "" }
                if let err = errorText { Text(err).font(.subheadline).foregroundStyle(PayTheme.danger) }
                Spacer()
                Button {
                    Task { await doConnect() }
                } label: {
                    Label(isConnecting ? "Waiting for authorisation…" : "Connect \(bank.shortName)", systemImage: "link")
                        .frame(maxWidth: .infinity).padding().background(PayTheme.emerald).foregroundStyle(.black).font(.headline)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isConnecting || apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", action: { dismiss() }).frame(maxWidth: .infinity).foregroundStyle(PayTheme.textSecondary)
            }
            .padding(24)
            .payScreenBackground()
        }
    }

    private func doConnect() async {
        isConnecting = true
        defer { isConnecting = false }
        _ = KeychainService.save(apiKey.trimmingCharacters(in: .whitespaces), for: provider.keychainKey)
        do {
            _ = try await connector.connect(bank: bank, provider: provider, context: context)
            onDone("\(bank.shortName) connected via \(provider.rawValue).")
            dismiss()
        } catch {
            errorText = error.localizedDescription
            onDone("\(bank.shortName): \(error.localizedDescription)")
        }
    }
}
