import SwiftUI

struct TransactionRowView: View {
    let tx: PayTransaction
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(PayTheme.emeraldSoft).frame(width: 44, height: 44)
                Image(systemName: tx.category.systemImage).foregroundStyle(PayTheme.emerald)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(tx.merchant).font(.subheadline.bold()).foregroundStyle(PayTheme.textPrimary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(tx.category.displayName).font(.caption).foregroundStyle(PayTheme.textSecondary)
                    Text("·").foregroundStyle(PayTheme.textMuted)
                    Text(tx.date.shortDateLabel).font(.caption).foregroundStyle(PayTheme.textMuted)
                    if tx.category == .uncategorized {
                        Text("Needs review").font(.caption.bold()).foregroundStyle(PayTheme.warning)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: tx.source.systemImage).font(.caption2)
                    Text(tx.source.rawValue).font(.caption2)
                    Text("· \(tx.syncStatus.rawValue)").font(.caption2)
                }
                .foregroundStyle(PayTheme.textMuted)
            }
            Spacer()
            Text((tx.kind == .income ? "+" : "−") + tx.amount.asCurrency(tx.currencyCode))
                .font(.subheadline.bold())
                .foregroundStyle(tx.kind == .income ? PayTheme.income : PayTheme.textPrimary)
        }
        .padding(.vertical, 4)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption.bold())
            .tracking(1)
            .foregroundStyle(PayTheme.textMuted)
    }
}

struct StatCard: View {
    let label: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(PayTheme.textSecondary)
            Text(value).font(.headline).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .payCard()
    }
}

// MARK: - Swipeable bank / crypto cards (reference image-156.png)
//
// One dark-navy card visual per account, in a horizontal paging carousel:
// swipe left / right to move between cards, dots + "1 / 3" show where you
// are. This is the "Cards & Accounts" screen from the reference, reused
// on Home (your cards under the balance) and in Integrations.
// The card itself is a visual only — it shows the institution, the last
// 4 digits from the account name when present, and this month's spend
// from real transactions. It never shows a full card number (PAYFLOW
// never stores one).

struct BankCardVisual: View {
    let account: PayAccount
    let spentThisMonth: Double

    private var last4: String {
        let digits = account.name.filter(\.isNumber)
        return digits.count >= 4 ? String(digits.suffix(4)) : "••••"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(account.institution.isEmpty ? account.name : account.institution)
                    .font(.headline.bold()).foregroundStyle(PayTheme.cardTextPrimary)
                Spacer()
                Text("VISA").font(.headline.bold().italic()).foregroundStyle(PayTheme.cardTextPrimary)
            }
            // Muted silver chip (not too bright).
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.61, green: 0.64, blue: 0.69))
                .frame(width: 44, height: 32)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.42, green: 0.45, blue: 0.50), lineWidth: 1))
            Text("•••• •••• •••• \(last4)")
                .font(.title3.bold().monospaced()).foregroundStyle(PayTheme.cardTextPrimary)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.type == "card" ? "Card" : account.type.capitalized)
                        .font(.caption).foregroundStyle(PayTheme.cardTextSecondary)
                    Text(account.name).font(.subheadline.bold()).foregroundStyle(PayTheme.cardTextPrimary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Spent this month").font(.caption).foregroundStyle(PayTheme.cardTextSecondary)
                    Text(spentThisMonth.asCurrency(account.currencyCode))
                        .font(.subheadline.bold()).foregroundStyle(PayTheme.cardTextPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .payHeroCard()
    }
}

struct CardsCarouselView: View {
    let accounts: [PayAccount]
    let spentByAccount: [String: Double]
    @State private var selected = 0

    var body: some View {
        VStack(spacing: 8) {
            if accounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No cards yet").font(.headline).foregroundStyle(PayTheme.textPrimary)
                    Text("Connect a bank or add a crypto card in Integrations — it will appear here, and you can swipe between your cards.")
                        .font(.subheadline).foregroundStyle(PayTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .payCard()
            } else {
                TabView(selection: $selected) {
                    ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                        BankCardVisual(account: account, spentThisMonth: spentByAccount[account.name] ?? 0)
                            .tag(index)
                            .padding(.horizontal, 4)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 210)
                HStack {
                    Text("Swipe left / right to change card")
                        .font(.caption).foregroundStyle(PayTheme.textMuted)
                    Spacer()
                    Text("\(min(selected + 1, accounts.count)) / \(accounts.count)")
                        .font(.caption.bold()).foregroundStyle(PayTheme.textSecondary)
                }
                .padding(.horizontal, 4)
            }
        }
    }
}
