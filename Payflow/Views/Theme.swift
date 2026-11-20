import SwiftUI

// PAYFLOW design system — BLACK & SILVER theme, muted (user 20 Nov 2026,
// "hitam silver tapi jgn terlalu terang"). Black base with DIM silver —
// no bright white, no bright silver: accent #9CA3AF, text off-white
// #E8E8E8. Header #0A0A0A, body #141414, cards #1E1E1E.
// Income is off-white, expenses are dim silver, both with +/− signs.
// The physical card visual is black with a muted silver chip.
// Variable names are kept (emerald = primary accent) so every existing
// view picks up the new look without edits; only the values changed.
// First GitHub Actions build triggered 20 Nov 2026.

enum PayTheme {
    static let background = Color(red: 0.08, green: 0.08, blue: 0.08) // #141414 black body
    static let surface = Color(red: 0.12, green: 0.12, blue: 0.12) // #1E1E1E dark-grey cards
    static let surfaceElevated = Color(red: 0.16, green: 0.16, blue: 0.16) // #2A2A2A
    static let headerDark = Color(red: 0.04, green: 0.04, blue: 0.04) // #0A0A0A near-black header
    static let headerGradient = LinearGradient(
        colors: [Color(red: 0.04, green: 0.04, blue: 0.04), Color(red: 0.08, green: 0.08, blue: 0.08)],
        startPoint: .top, endPoint: .bottom)
    static let border = Color.white.opacity(0.08)
    // Primary accent — DIM silver (muted, not bright).
    static let emerald = Color(red: 0.61, green: 0.64, blue: 0.69) // #9CA3AF
    static let emeraldSoft = Color(red: 0.61, green: 0.64, blue: 0.69).opacity(0.18)
    static let emeraldDeep = Color(red: 0.42, green: 0.45, blue: 0.50) // #6B7280
    static let blueGradient = LinearGradient(
        colors: [Color(red: 0.72, green: 0.74, blue: 0.78), Color(red: 0.61, green: 0.64, blue: 0.69)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Black gradient of the physical card visual.
    static let cardGradient = LinearGradient(
        colors: [Color(red: 0.04, green: 0.04, blue: 0.04), Color(red: 0.12, green: 0.12, blue: 0.12)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Dark-grey gradient of the Total Balance hero card.
    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.08, green: 0.08, blue: 0.08), Color(red: 0.12, green: 0.12, blue: 0.12)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let textPrimary = Color(red: 0.91, green: 0.91, blue: 0.91) // #E8E8E8 off-white, not pure white
    static let textSecondary = Color(red: 0.54, green: 0.56, blue: 0.60) // #8A8F98 dim silver
    static let textMuted = Color(red: 0.36, green: 0.38, blue: 0.41) // #5C6068
    static let danger = Color(red: 0.91, green: 0.91, blue: 0.91) // monochrome: off-white, not red
    static let warning = Color(red: 0.72, green: 0.74, blue: 0.78) // #B8BCC2
    static let income = Color(red: 0.91, green: 0.91, blue: 0.91) // monochrome: off-white + sign
    static let expense = Color(red: 0.54, green: 0.56, blue: 0.60) // #8A8F98 dim silver
    /// Text on the black physical-card visual.
    static let cardTextPrimary = Color(red: 0.91, green: 0.91, blue: 0.91)
    static let cardTextSecondary = Color(red: 0.91, green: 0.91, blue: 0.91).opacity(0.70)

    static let cornerRadius: CGFloat = 20
    static let cardPadding: CGFloat = 16
}

extension View {
    func payCard() -> some View {
        self
            .padding(PayTheme.cardPadding)
            .background(PayTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: PayTheme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PayTheme.cornerRadius, style: .continuous)
                    .stroke(PayTheme.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.40), radius: 14, x: 0, y: 6)
    }

    /// Dark-grey hero card for Total Balance (black-silver, off-white text).
    func payHeroLightCard() -> some View {
        self
            .padding(PayTheme.cardPadding)
            .background(PayTheme.heroGradient)
            .clipShape(RoundedRectangle(cornerRadius: PayTheme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PayTheme.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.40), radius: 16, x: 0, y: 6)
    }

    /// Black physical card visual.
    func payHeroCard() -> some View {
        self
            .padding(PayTheme.cardPadding)
            .background(PayTheme.cardGradient)
            .clipShape(RoundedRectangle(cornerRadius: PayTheme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PayTheme.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.40), radius: 18, x: 0, y: 8)
    }

    func payScreenBackground() -> some View {
        self.background(PayTheme.background.ignoresSafeArea())
    }

    /// Near-black header band for navigation bars (off-white title)
    /// over the black body. Apply inside a NavigationStack.
    func payNavBar() -> some View {
        self
            .toolbarBackground(PayTheme.headerDark, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

extension Double {
    func asCurrency(_ code: String = "IDR") -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.maximumFractionDigits = code == "IDR" ? 0 : 2
        return f.string(from: NSNumber(value: self)) ?? "\(code) \(self)"
    }
}

extension Date {
    var monthYearLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: self)
    }
    var shortDateLabel: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: self)
    }
    func startOfMonth() -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self)) ?? self
    }
}
