import Foundation
import UserNotifications

// MARK: - Local notifications for automation receipts
//
// PAYFLOW has no server and sends nothing anywhere. These are LOCAL
// notifications, scheduled on the iPhone itself, only when:
//   1. the user turned Automation on (Settings / Integrations), AND
//   2. the user granted notification permission, AND
//   3. a payment actually arrived through their own Shortcuts automation.
// Turning Automation off stops them. Nothing is delivered when the app
// is not running — the notification is the receipt itself.

enum NotificationService {

    /// Ask once, from the Automation screen. Returns false when denied;
    /// the caller shows the Settings hint instead of failing silently.
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Immediate local notification for one received payment.
    static func notifyPayment(title: String, body: String) {
        guard AutomationService.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }

    /// Test notification, so the user can verify the sound / banner
    /// before any real card is involved. Uses clearly-labelled demo text.
    static func notifyTest() {
        let content = UNMutableNotificationContent()
        content.title = "PAYFLOW — test notification"
        content.body = "This is a test. A real payment would read e.g. “KAST •••• 1234 — Rp 45.000 · Starbucks · Dining”."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "payflow.automation.test",
                                            content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }
}
