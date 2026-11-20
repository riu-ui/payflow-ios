import Foundation

/// Automatic categorisation + merchant detection.
/// Order of precedence (highest first):
///  1. A learned MerchantRule from a user correction (stored in SwiftData)
///  2. Keyword rules below (merchant / description matching)
///  3. .uncategorized — never guessed silently; shown as "Needs review".
struct CategorizationEngine {

    /// Normalise a raw bank description into a clean merchant name.
    /// e.g. "AMZN MKTP US*2K..." -> "Amazon", "SQ *BLUE BOTTLE" -> "Blue Bottle".
    static func normalizeMerchant(_ raw: String) -> String {
        var s = raw.uppercased()
        // Strip common bank-description prefixes / suffixes.
        let stripPrefixes = ["SQ *", "TST*", "AMZN MKTP US*", "PAYPAL *", "DD *", "ACH *"]
        for p in stripPrefixes where s.hasPrefix(p) { s = String(s.dropFirst(p.count)) }
        s = s.replacingOccurrences(of: #"[^A-Z0-9 &']+"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespaces)
        // Collapse trailing location / reference numbers: "WHOLE FOODS 10234" -> "WHOLE FOODS"
        s = s.replacingOccurrences(of: #"\s\d{3,}$"#, with: "", options: .regularExpression)
        let pretty = s.lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return pretty.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : pretty
    }

    static func normalizeKey(_ raw: String) -> String {
        normalizeMerchant(raw).lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Keyword rules. Kept deliberately explicit and auditable — no black box.
    private static let rules: [(keywords: [String], category: PayCategory)] = [
        (["whole foods", "trader joe", "safeway", "kroger", "walmart grocery", "aldi", "grocery", "supermarket", "costco", "target grocery"], .groceries),
        (["starbucks", "blue bottle", "chipotle", "doordash", "ubereats", "uber eats", "restaurant", "cafe", "coffee", "mcdonald", "sweetgreen", "tst*"], .dining),
        (["uber", "lyft", "shell", "chevron", "exxon", "parking", "metro", "transit", "airline", "delta", "united air", "gas station"], .transport),
        (["landlord", "rent", "mortgage", "apartment", "zillow rent"], .housing),
        (["electric", "water bill", "comcast", "xfinity", "verizon", "at&t", "t-mobile", "internet", "utility"], .utilities),
        (["netflix", "spotify", "apple.com/bill", "hulu", "disney+", "youtube premium", "prime video", "cinema", "amc"], .subscriptions),
        (["amc", "steam", "playstation", "xbox", "concert", "ticketmaster", "spotify"], .entertainment),
        (["amazon", "target", "ikea", "apple store", "best buy", "zara", "h&m", "nike"], .shopping),
        (["cvs", "walgreens", "pharmacy", "hospital", "clinic", "dentist", "gym", "fitness"], .health),
        (["payroll", "salary", "employer", "direct dep"], .salary),
        (["interest", "dividend", "refund", "venmo received", "zelle received"], .otherIncome),
        (["venmo", "zelle", "transfer", "wire"], .transfer),
    ]

    /// Categorise using learned rules first, then keywords.
    /// - Parameters:
    ///   - learned: rules loaded from SwiftData (user corrections)
    ///   - kind: income transactions never get an expense category
    static func categorize(merchant: String, rawDescription: String,
                           learned: [MerchantRule], kind: TransactionKind) -> (category: PayCategory, confidence: Double, learnedRuleUsed: Bool) {
        let key = normalizeKey(merchant + " " + rawDescription)
        for rule in learned where key.contains(rule.normalizedMerchant) || rule.normalizedMerchant.contains(key) {
            return (rule.category, 0.98, true)
        }
        let haystack = (merchant + " " + rawDescription).lowercased()
        for rule in rules {
            for kw in rule.keywords where haystack.contains(kw) {
                if kind == .income && !rule.category.isIncome && rule.category != .transfer {
                    continue
                }
                return (rule.category, 0.82, false)
            }
        }
        if kind == .income { return (.otherIncome, 0.55, false) }
        return (.uncategorized, 0.30, false)
    }
}

/// Duplicate detection — fingerprint + fuzzy window.
/// A transaction is a duplicate when its fingerprint matches exactly,
/// OR when amount + normalised merchant match within ±3 days.
struct DuplicateDetector {
    static func fingerprint(date: Date, amount: Double, merchant: String, accountName: String) -> String {
        let day = Calendar.current.startOfDay(for: date)
        let iso = ISO8601DateFormatter().string(from: day)
        let key = "\(iso)|\(String(format: "%.2f", abs(amount)))|\(CategorizationEngine.normalizeKey(merchant))|\(accountName.lowercased())"
        return key // stored verbatim; hashed at the store layer if needed
    }

    static func isFuzzyDuplicate(candidateDate: Date, candidateAmount: Double, candidateMerchant: String,
                                 existing: PayTransaction) -> Bool {
        guard abs(existing.amount - abs(candidateAmount)) < 0.01 else { return false }
        guard CategorizationEngine.normalizeKey(existing.merchant) == CategorizationEngine.normalizeKey(candidateMerchant) else { return false }
        let days = abs(Calendar.current.dateComponents([.day], from: existing.date, to: candidateDate).day ?? 99)
        return days <= 3
    }
}
