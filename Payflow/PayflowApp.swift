import SwiftUI
import SwiftData
import UserNotifications

/// Shows automation notifications as a banner even while PAYFLOW is open.
final class PayflowNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PayflowNotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

@main
struct PayflowApp: App {
    @StateObject private var auth = BiometricAuthService()
    @AppStorage("payflow.icloudEnabled") private var iCloudEnabled = false
    @AppStorage("payflow.hasOnboarded") private var hasOnboarded = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([PayTransaction.self, PayAccount.self, PayBudget.self,
                             PaySubscription.self, MerchantRule.self, BankConnection.self])
        // Local-first. iCloud is opt-in only (Settings) and uses the private database.
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false,
                                        cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .modelContainer(sharedModelContainer)
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    auth.lock() // lock when backgrounded
                }
                .onOpenURL { url in
                    // Automation receipt: payflow://log-payment?... — sent by the
                    // user's own Shortcuts automation (see AutomationService).
                    // Ignored unless Automation is turned on in the app.
                    Task { @MainActor in await handleAutomationURL(url) }
                }
                .onChange(of: auth.isUnlocked) { _, unlocked in
                    // A payment that arrived while the app was locked was
                    // queued — process it now that Face ID has unlocked.
                    if unlocked {
                        Task { @MainActor in await processPendingAutomation() }
                    }
                }
                .task {
                    // iCloud toggle is applied on next launch; the container above
                    // is local-only by default. See SettingsView for the opt-in flow.
                    _ = iCloudEnabled
                    UNUserNotificationCenter.current().delegate = PayflowNotificationDelegate.shared
                }
        }
    }

    // MARK: - Automation receiving

    @MainActor
    private func handleAutomationURL(_ url: URL) async {
        guard UserDefaults.standard.bool(forKey: "payflow.automationEnabled") else { return }
        guard let payment = AutomationService.parse(url: url) else { return }
        if !auth.isUnlocked {
            // Never insert while locked — queue it and process after unlock.
            AutomationService.savePending(url: url)
            return
        }
        await processPayment(payment)
    }

    @MainActor
    private func processPendingAutomation() async {
        guard UserDefaults.standard.bool(forKey: "payflow.automationEnabled"),
              let url = AutomationService.loadPendingURL(),
              let payment = AutomationService.parse(url: url) else {
            AutomationService.clearPending()
            return
        }
        AutomationService.clearPending()
        await processPayment(payment)
    }

    @MainActor
    private func processPayment(_ payment: AutomationPayment) async {
        let context = sharedModelContainer.mainContext
        let existing = (try? context.fetch(FetchDescriptor<PayTransaction>())) ?? []
        let learned = (try? context.fetch(FetchDescriptor<MerchantRule>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<PayAccount>())) ?? []
        let budgets = (try? context.fetch(FetchDescriptor<PayBudget>())) ?? []
        let result = AutomationService.receive(payment, context: context, existing: existing,
                                               learned: learned, accounts: accounts, budgets: budgets)
        if result.outcome == .inserted {
            NotificationService.notifyPayment(title: result.notificationTitle, body: result.notificationBody)
        }
    }
}
