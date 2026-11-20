import SwiftUI
import SwiftData

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let isLocal: Bool // false only if an external AI answered (requires consent)
}

struct AIAssistantView: View {
    @Query(sort: \PayTransaction.date, order: .reverse) private var transactions: [PayTransaction]
    @Query private var subscriptions: [PaySubscription]
    @Query private var budgets: [PayBudget]
    @AppStorage("payflow.externalAIEnabled") private var externalAIEnabled = false
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var showConsentInfo = false

    private var insights: [AIAssistantService.Insight] {
        AIAssistantService.insights(transactions: transactions, subscriptions: subscriptions)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Privacy badge — always visible
                        HStack(spacing: 8) {
                            Image(systemName: externalAIEnabled ? "exclamationmark.triangle" : "lock.shield")
                                .foregroundStyle(externalAIEnabled ? PayTheme.warning : PayTheme.emerald)
                            Text(externalAIEnabled
                                 ? "External AI is ON — answers may leave this device. Turn it off in Settings."
                                 : "Local AI — answers are computed on this iPhone from your transactions. Nothing is sent anywhere.")
                                .font(.caption).foregroundStyle(PayTheme.textSecondary)
                        }
                        .payCard()

                        if messages.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Insights from your records")
                                ForEach(insights) { ins in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(ins.title).bold().foregroundStyle(PayTheme.textPrimary)
                                        Text(ins.body).font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(ins.tone == .warning ? PayTheme.warning.opacity(0.12) : PayTheme.emeraldSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .payCard()
                            Text("Try asking:").font(.caption.bold()).foregroundStyle(PayTheme.textMuted)
                            ForEach(["How much did I spend this month?", "What are my subscriptions?", "How are my budgets doing?", "Where can I save money?"], id: \.self) { q in
                                Button(q) { send(q) }
                                    .font(.subheadline).foregroundStyle(PayTheme.emerald)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12).background(PayTheme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        } else {
                            ForEach(messages) { m in
                                HStack {
                                    if m.isUser { Spacer() }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(m.text).font(.subheadline).foregroundStyle(m.isUser ? .black : PayTheme.textPrimary)
                                        if !m.isUser {
                                            Text(m.isLocal ? "Answered locally on-device" : "Answered by external AI (consented)")
                                                .font(.caption2).foregroundStyle(PayTheme.textMuted)
                                        }
                                    }
                                    .padding(12)
                                    .background(m.isUser ? PayTheme.emerald : PayTheme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    if !m.isUser { Spacer() }
                                }
                            }
                        }
                    }
                    .padding()
                }
                HStack(spacing: 10) {
                    TextField("Ask about your money…", text: $input, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(PayTheme.emerald) }
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("AI Assistant")
            .payNavBar()
        }
    }

    private func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        messages.append(ChatMessage(text: q, isUser: true, isLocal: true))
        input = ""
        if let answer = AIAssistantService.answerLocally(q, transactions: transactions, subscriptions: subscriptions, budgets: budgets) {
            messages.append(ChatMessage(text: answer, isUser: false, isLocal: true))
        } else if externalAIEnabled {
            // External path is intentionally gated: without a configured,
            // consented provider this never silently sends data.
            messages.append(ChatMessage(text: "External AI is enabled, but no external provider is configured yet. Add an API key in Settings → External AI (stored in Keychain), and I will send only the aggregate summary shown there — never raw descriptions.", isUser: false, isLocal: false))
        } else {
            messages.append(ChatMessage(text: "I can answer that from your records once there is relevant data — try importing a statement first, or ask about spending, income, subscriptions, budgets or your forecast. External AI is off; turn it on in Settings only if you want answers beyond your local records.", isUser: false, isLocal: true))
        }
    }
}
