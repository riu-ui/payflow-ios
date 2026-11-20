import Foundation
import SwiftData

// MARK: - Enums

enum TransactionKind: String, Codable, CaseIterable {
    case income, expense
}

enum TransactionSource: String, Codable, CaseIterable {
    case csvImport = "CSV Import"
    case xlsxImport = "XLSX Import"
    case pdfImport = "PDF Import"
    case bankAPI = "Bank API"
    case emailImport = "Email Statement"
    case manual = "Manual"
    case demo = "Demo Data"
    /// Live payment routed in by the user via a Shortcuts automation
    /// (Apple Pay Wallet trigger, or a card-app notification trigger).
    /// PAYFLOW never reads another app by itself — the user explicitly
    /// routes the payment to PAYFLOW with their own automation.
    case applePayAutomation = "Apple Pay Automation"
    case cardNotification = "Card Notification"

    var systemImage: String {
        switch self {
        case .csvImport: "tablecells"
        case .xlsxImport: "tablecells.badge.ellipsis"
        case .pdfImport: "doc.richtext"
        case .bankAPI: "building.columns"
        case .emailImport: "envelope"
        case .manual: "pencil"
        case .demo: "flask"
        case .applePayAutomation: "wallet.pass"
        case .cardNotification: "bell.badge"
        }
    }
}

enum SyncStatus: String, Codable, CaseIterable {
    case imported = "Imported"
    case synced = "Synced"
    case pending = "Pending"
    case duplicateSkipped = "Duplicate — skipped"
    case needsReview = "Needs review"
}

enum PayCategory: String, Codable, CaseIterable, Identifiable {
    case groceries, dining, transport, housing, utilities
    case entertainment, shopping, health, subscriptions
    case salary, otherIncome, transfer, uncategorized

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .groceries: "Groceries"
        case .dining: "Dining"
        case .transport: "Transport"
        case .housing: "Housing"
        case .utilities: "Utilities"
        case .entertainment: "Entertainment"
        case .shopping: "Shopping"
        case .health: "Health"
        case .subscriptions: "Subscriptions"
        case .salary: "Salary"
        case .otherIncome: "Other Income"
        case .transfer: "Transfer"
        case .uncategorized: "Uncategorized"
        }
    }

    var systemImage: String {
        switch self {
        case .groceries: "cart"
        case .dining: "fork.knife"
        case .transport: "car"
        case .housing: "house"
        case .utilities: "bolt"
        case .entertainment: "play.tv"
        case .shopping: "bag"
        case .health: "heart"
        case .subscriptions: "repeat"
        case .salary: "banknote"
        case .otherIncome: "plus.circle"
        case .transfer: "arrow.left.arrow.right"
        case .uncategorized: "questionmark.circle"
        }
    }

    var isIncome: Bool { self == .salary || self == .otherIncome }
}

// MARK: - Transaction

@Model
final class PayTransaction {
    @Attribute(.unique) var id: UUID
    var date: Date
    var merchant: String
    var rawDescription: String
    var amount: Double // always positive magnitude
    var kindRaw: String
    var categoryRaw: String
    var currencyCode: String
    var sourceRaw: String
    var syncStatusRaw: String
    var accountName: String
    var notes: String
    var fingerprint: String
    var isRecurring: Bool
    var createdAt: Date

    init(date: Date, merchant: String, rawDescription: String, amount: Double,
         kind: TransactionKind, category: PayCategory, currencyCode: String = "IDR",
         source: TransactionSource, syncStatus: SyncStatus = .imported,
         accountName: String = "Primary", notes: String = "",
         fingerprint: String, isRecurring: Bool = false) {
        self.id = UUID()
        self.date = date
        self.merchant = merchant
        self.rawDescription = rawDescription
        self.amount = abs(amount)
        self.kindRaw = kind.rawValue
        self.categoryRaw = category.rawValue
        self.currencyCode = currencyCode
        self.sourceRaw = source.rawValue
        self.syncStatusRaw = syncStatus.rawValue
        self.accountName = accountName
        self.notes = notes
        self.fingerprint = fingerprint
        self.isRecurring = isRecurring
        self.createdAt = Date()
    }

    var kind: TransactionKind { TransactionKind(rawValue: kindRaw) ?? .expense }
    var category: PayCategory { PayCategory(rawValue: categoryRaw) ?? .uncategorized }
    var source: TransactionSource { TransactionSource(rawValue: sourceRaw) ?? .manual }
    var syncStatus: SyncStatus { SyncStatus(rawValue: syncStatusRaw) ?? .imported }
    var signedAmount: Double { kind == .income ? amount : -amount }
}

// MARK: - Account

@Model
final class PayAccount {
    @Attribute(.unique) var id: UUID
    var name: String
    var institution: String
    var type: String // checking, savings, credit, cash
    var balance: Double
    var currencyCode: String
    var lastSyncAt: Date?
    var isDemo: Bool

    init(name: String, institution: String, type: String = "checking",
         balance: Double = 0, currencyCode: String = "USD", isDemo: Bool = false) {
        self.id = UUID()
        self.name = name
        self.institution = institution
        self.type = type
        self.balance = balance
        self.currencyCode = currencyCode
        self.isDemo = isDemo
    }
}

// MARK: - Budget

@Model
final class PayBudget {
    @Attribute(.unique) var id: UUID
    var categoryRaw: String
    var monthlyLimit: Double
    var monthStart: Date // first day of the month this budget applies to
    var createdAt: Date

    init(category: PayCategory, monthlyLimit: Double, monthStart: Date) {
        self.id = UUID()
        self.categoryRaw = category.rawValue
        self.monthStart = Calendar.current.startOfDay(for: monthStart)
        self.monthlyLimit = monthlyLimit
        self.createdAt = Date()
    }

    var category: PayCategory { PayCategory(rawValue: categoryRaw) ?? .uncategorized }
}

// MARK: - Subscription

@Model
final class PaySubscription {
    @Attribute(.unique) var id: UUID
    var merchant: String
    var amount: Double
    var interval: String // weekly, monthly, yearly
    var nextDate: Date
    var categoryRaw: String
    var isActive: Bool
    var detectedFromTransactionId: UUID?
    var createdAt: Date

    init(merchant: String, amount: Double, interval: String, nextDate: Date,
         category: PayCategory, isActive: Bool = true, detectedFromTransactionId: UUID? = nil) {
        self.id = UUID()
        self.merchant = merchant
        self.amount = amount
        self.interval = interval
        self.nextDate = nextDate
        self.categoryRaw = category.rawValue
        self.isActive = isActive
        self.detectedFromTransactionId = detectedFromTransactionId
        self.createdAt = Date()
    }

    var category: PayCategory { PayCategory(rawValue: categoryRaw) ?? .subscriptions }
    var monthlyCost: Double {
        switch interval {
        case "weekly": return amount * 52 / 12
        case "yearly": return amount / 12
        default: return amount
        }
    }
}

// MARK: - Learned merchant rule (user corrections)

@Model
final class MerchantRule {
    @Attribute(.unique) var normalizedMerchant: String
    var categoryRaw: String
    var correctionCount: Int
    var updatedAt: Date

    init(normalizedMerchant: String, category: PayCategory) {
        self.normalizedMerchant = normalizedMerchant
        self.categoryRaw = category.rawValue
        self.correctionCount = 1
        self.updatedAt = Date()
    }

    var category: PayCategory { PayCategory(rawValue: categoryRaw) ?? .uncategorized }
}

// MARK: - Bank connection (metadata only — never a password, PIN or OTP)

@Model
final class BankConnection {
    @Attribute(.unique) var id: UUID
    var institutionName: String
    var connectionType: String // openBanking, plaid, manualFile
    var status: String // notConnected, connected, error, revoked
    var lastSyncAt: Date?
    var externalAccountLabel: String // e.g. "•••• 4821" — never a full number
    var createdAt: Date

    init(institutionName: String, connectionType: String, status: String = "notConnected",
         externalAccountLabel: String = "") {
        self.id = UUID()
        self.institutionName = institutionName
        self.connectionType = connectionType
        self.status = status
        self.externalAccountLabel = externalAccountLabel
        self.createdAt = Date()
    }
}
