import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var auth: BiometricAuthService
    @Query(sort: \PayTransaction.date, order: .reverse) private var transactions: [PayTransaction]
    @AppStorage("payflow.requireBiometrics") private var requireBiometrics = true
    @AppStorage("payflow.icloudEnabled") private var iCloudEnabled = false
    @AppStorage("payflow.externalAIEnabled") private var externalAIEnabled = false
    @AppStorage("payflow.currency") private var currency = "IDR"
    @AppStorage("payflow.automationEnabled") private var automationEnabled = false
    @AppStorage("payflow.automationNotifications") private var automationNotifications = true
    @State private var showAutomation = false
    @State private var showExternalConsent = false
    @State private var showDeleteConfirm = false
    @State private var demoLoaded = false
    @State private var message: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Privacy & security") {
                    Toggle("Require Face ID / passcode on launch", isOn: $requireBiometrics)
                    HStack {
                        Text("Biometrics available")
                        Spacer()
                        Text(auth.biometryAvailable() ? auth.biometryType : "Not available on this device")
                            .foregroundStyle(PayTheme.textSecondary)
                    }
                    Toggle("Private iCloud backup (optional)", isOn: $iCloudEnabled)
                    Text("Off by default. When on, SwiftData syncs through your private CloudKit database only. Turning it on applies on next launch — see README for the entitlements step.")
                        .font(.caption).foregroundStyle(PayTheme.textSecondary)
                    Text("Banking passwords, PINs and OTPs are never stored — by design, there is nowhere in PAYFLOW to enter one.")
                        .font(.caption).foregroundStyle(PayTheme.textSecondary)
                }

                Section("Automation — card payments") {
                    Toggle("Receive automations", isOn: $automationEnabled)
                    Toggle("Notify me for each payment", isOn: $automationNotifications)
                    Button("Set up Apple Pay / card notifications") { showAutomation = true }
                    Text("When on, PAYFLOW accepts payments your own Shortcuts automation routes to it (Apple Pay tap, or a card-app payment notification) and notifies you. It never reads other apps, SMS or notifications by itself.")
                        .font(.caption).foregroundStyle(PayTheme.textSecondary)
                }

                Section("AI assistant") {
                    Toggle("External AI", isOn: $externalAIEnabled)
                        .onChange(of: externalAIEnabled) { _, on in
                            if on { showExternalConsent = true }
                        }
                    Text("Off by default. Local AI answers from your transactions on-device. External AI is only used after you confirm here, and only ever receives the aggregate summary shown below — never raw descriptions or account numbers.")
                        .font(.caption).foregroundStyle(PayTheme.textSecondary)
                    Text(AIAssistantService.externalPayloadPreview(transactions: transactions))
                        .font(.caption).foregroundStyle(PayTheme.textSecondary)
                }

                Section("Data") {
                    Picker("Currency", selection: $currency) {
                        Text("USD").tag("USD"); Text("EUR").tag("EUR"); Text("GBP").tag("GBP"); Text("IDR").tag("IDR"); Text("SGD").tag("SGD")
                    }
                    Button(demoLoaded ? "Demo data loaded" : "Load demo data") {
                        SampleData.loadDemo(context: context)
                        demoLoaded = true
                        message = "Demo data loaded — every row is labelled Demo and can be deleted below."
                    }
                    .disabled(demoLoaded)
                    Button("Delete demo data", role: .destructive) {
                        SampleData.clearDemo(context: context, transactions: transactions)
                        demoLoaded = false
                        message = "Demo data deleted."
                    }
                    Button("Delete ALL transactions", role: .destructive) { showDeleteConfirm = true }
                    if let m = message { Text(m).font(.caption).foregroundStyle(PayTheme.emerald) }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Storage", value: "SwiftData, on-device")
                    LabeledContent("Transactions", value: "\(transactions.count)")
                    Text("PAYFLOW 1.0 — iPhone only, single user, local-first. No account, no ads, no tracking.")
                        .font(.caption).foregroundStyle(PayTheme.textSecondary)
                }
            }
            .navigationTitle("Settings")
            .payNavBar()
            .scrollContentBackground(.hidden)
            .background(PayTheme.background)
            .sheet(isPresented: $showAutomation) { AutomationView() }
            .alert("External AI — please confirm", isPresented: $showExternalConsent) {
                Button("I understand — turn on") { externalAIEnabled = true }
                Button("Keep it off", role: .cancel) { externalAIEnabled = false }
            } message: {
                Text("External AI will receive only the aggregate summary shown above. No raw transaction descriptions, merchant history or account numbers are sent. You can turn this off at any time. Continue?")
            }
            .alert("Delete all transactions?", isPresented: $showDeleteConfirm) {
                Button("Delete everything", role: .destructive) {
                    for tx in transactions { context.delete(tx) }
                    try? context.save()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes every transaction on this device. This cannot be undone.")
            }
        }
    }
}
