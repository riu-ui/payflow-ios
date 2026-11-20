import SwiftUI
import SwiftData
import UIKit

// MARK: - Automation setup screen
//
// This screen is the whole "receive automation" feature from the user's
// side: turn it on, grant notifications, follow the Shortcuts steps once,
// then test it with a simulated payment before any real card is involved.
// Every step is on-device and user-initiated — see AutomationService.swift
// for what PAYFLOW does and does not read.

struct AutomationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PayTransaction.date, order: .reverse) private var transactions: [PayTransaction]
    @Query private var rules: [MerchantRule]
    @Query private var accounts: [PayAccount]
    @Query private var budgets: [PayBudget]
    @AppStorage("payflow.automationEnabled") private var automationEnabled = false
    @AppStorage("payflow.automationNotifications") private var automationNotifications = true
    @State private var message: String? = nil
    @State private var copied = false

    /// Template the Shortcuts "Open URLs" action uses. [Amount] etc. are
    /// placeholders the user replaces with the Shortcut's own variables
    /// (Transaction Amount / Merchant / Card) in the Shortcuts app.
    static let applePayURLTemplate =
        "payflow://log-payment?amount=[Amount]&currency=IDR&merchant=[Merchant]&card=[Card]&source=applepay"
    static let notificationURLTemplate =
        "payflow://log-payment?text=[Notification%20Text]&source=notification"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Automatic notifications")
                        Text("When you pay with a card in Apple Pay, or your card app posts a payment notification, PAYFLOW can log it and notify you — “KAST •••• 1234 — Rp 45.000 · Starbucks”.")
                            .font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                        Text("How it works: you create the automation yourself in Shortcuts (steps below). PAYFLOW never reads other apps, SMS or notifications by itself — it only receives the payment you explicitly route to it. No bank password, PIN or OTP is ever involved.")
                            .font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                    }
                    .payCard()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Switches")
                        Toggle("Receive automations", isOn: $automationEnabled)
                        Toggle("Notify me for each payment", isOn: $automationNotifications)
                        Text("If “Receive automations” is off, a payflow:// link does nothing — the payment is ignored, not stored.")
                            .font(.caption).foregroundStyle(PayTheme.textSecondary)
                        Button("Allow notifications") {
                            Task {
                                let ok = await NotificationService.requestAuthorization()
                                message = ok ? "Notifications allowed." : "Notifications not allowed — turn them on in iPhone Settings → PAYFLOW → Notifications."
                            }
                        }
                        .buttonStyle(.bordered)
                        Button("Send a test notification") {
                            NotificationService.notifyTest()
                            message = "Test notification sent — check your lock screen / banner."
                        }
                        .buttonStyle(.bordered)
                    }
                    .payCard()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "1 · Apple Pay — tap to pay (iOS 17+)")
                        ForEach([
                            "Shortcuts → Automation → + → Wallet → Transaction.",
                            "Select the card(s) you pay with (e.g. your KAST / Bybit card in Wallet). Choose “Run Immediately”, no confirmation.",
                            "Add Action → “Open URLs”, paste the URL below. Replace [Amount], [Merchant] and [Card] with the Shortcut's Transaction variables.",
                            "Done. The first time you tap to pay, iPhone asks to open PAYFLOW — tap “Always Allow”.",
                        ], id: \.self) { line in
                            Label(line, systemImage: "1.circle").font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                        }
                        Text(Self.applePayURLTemplate)
                            .font(.caption.monospaced()).foregroundStyle(PayTheme.textPrimary)
                            .padding(10).background(PayTheme.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: 10))
                        Button(copied ? "Copied" : "Copy Apple Pay URL") {
                            UIPasteboard.general.string = Self.applePayURLTemplate
                            copied = true
                        }
                        .buttonStyle(.borderedProminent).tint(PayTheme.emerald).foregroundStyle(.black)
                        Text("Catches tap-to-pay only. Online shopping and physical-card swipes do not go through the Wallet trigger — use step 2 for those.")
                            .font(.caption).foregroundStyle(PayTheme.textSecondary)
                    }
                    .payCard()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "2 · Card-app notification (iOS 27+)")
                        ForEach([
                            "Shortcuts → Automation → + → App Notification → choose your card app (KAST, Bybit, …). Choose “Run Immediately”.",
                            "Add Action → “Open URLs”, paste the URL below. Replace [Notification Text] with the notification's text variable.",
                            "PAYFLOW reads the amount, merchant and card from that text on-device. If no amount can be found, it rejects the payment instead of guessing — check the automation, don't expect a wrong transaction.",
                        ], id: \.self) { line in
                            Label(line, systemImage: "2.circle").font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                        }
                        Text(Self.notificationURLTemplate)
                            .font(.caption.monospaced()).foregroundStyle(PayTheme.textPrimary)
                            .padding(10).background(PayTheme.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: 10))
                        Button("Copy notification URL") {
                            UIPasteboard.general.string = Self.notificationURLTemplate
                        }
                        .buttonStyle(.bordered)
                        Text("Needs iOS 27 + Apple Intelligence on, and the card app's payment notifications turned on with previews shown.")
                            .font(.caption).foregroundStyle(PayTheme.textSecondary)
                    }
                    .payCard()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Test it — no real card needed")
                        Text("This inserts one clearly-labelled simulated payment (Starbucks, Rp 45.000, KAST •••• 1234) through the same code path a real automation uses — same dedup, same categorisation, same notification. Run it twice: the second run must report “duplicate”, proving a payment is never logged twice.")
                            .font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                        Button("Simulate an Apple Pay payment") {
                            simulate()
                        }
                        .buttonStyle(.borderedProminent).tint(PayTheme.emerald).foregroundStyle(.black)
                        if let m = message {
                            Text(m).font(.subheadline).foregroundStyle(PayTheme.emerald)
                                .padding().background(PayTheme.emeraldSoft).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .payCard()

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Received automations")
                        if AutomationService.lastReceived().isEmpty {
                            Text("Nothing received yet. After a real payment (or the test above), the last 20 arrive here.")
                                .font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                        } else {
                            ForEach(AutomationService.lastReceived(), id: \.self) { line in
                                Text(line).font(.caption.monospaced()).foregroundStyle(PayTheme.textSecondary)
                            }
                        }
                    }
                    .payCard()

                    Button("Done", action: { dismiss() }).frame(maxWidth: .infinity).foregroundStyle(PayTheme.textSecondary)
                }
                .padding()
            }
            .navigationTitle("Automation")
            .payScreenBackground()
        }
    }

    private func simulate() {
        guard automationEnabled else {
            message = "Turn on “Receive automations” first, then tap Simulate again."
            return
        }
        let payment = AutomationPayment(amount: 45_000, merchant: "Starbucks",
                                        rawDescription: "Simulated Apple Pay payment — Starbucks",
                                        currencyCode: "IDR", cardLabel: "KAST •••• 1234",
                                        date: Date(), kind: .expense, source: .applePayAutomation)
        let result = AutomationService.receive(payment, context: context, existing: transactions,
                                               learned: rules, accounts: accounts, budgets: budgets)
        switch result.outcome {
        case .inserted:
            NotificationService.notifyPayment(title: result.notificationTitle, body: result.notificationBody)
            message = "Inserted: \(result.notificationBody) — check Transactions, and the notification on your lock screen."
        case .duplicate:
            message = "Duplicate — correctly skipped. \(result.notificationBody)"
        case .rejected(let reason):
            message = "Rejected: \(reason)"
        }
    }
}
