import Foundation
import SwiftData
import AuthenticationServices
import UIKit

// MARK: - Indonesian banks — how connection actually works
//
// Indonesia has NO single free public login that connects every bank.
// Bank Indonesia's SNAP (2021) standardises the API shape, but access
// itself is granted under a cooperation agreement between the app
// provider and each bank. For a personal app there are two real routes:
//
//  1. Aggregator (recommended): Brick or Brankas. You integrate once,
//     the aggregator maintains the bank connections. Brick covers
//     Indonesia's 7 largest banks (>90% of accounts); Brankas covers
//     BCA, Mandiri, BNI and BRI, among others. You need a (free sandbox)
//     account + API key from the aggregator — stored in the Keychain.
//  2. Direct bank API (BI-SNAP): register as a developer at each bank
//     (e.g. BRIAPI at developers.bri.co.id), sign a cooperation
//     agreement, get client credentials. Slower, per-bank, but no
//     middleman.
//
// PAYFLOW implements both routes honestly: a bank becomes "Connected"
// ONLY after the official authorisation callback returns a token.
// Until then it stays "Not connected" — never simulated.
// Docs: Brick — https://docs.onebrick.io
//        BRIAPI — https://developers.bri.co.id

enum BankCategory: String, CaseIterable {
    case big = "Big banks", digital = "Digital banks", syariah = "Syariah", other = "Other banks"
}

struct IndonesianBank: Identifiable, Hashable {
    let id: String          // BI bank code, e.g. "014"
    let name: String        // e.g. "Bank Central Asia"
    let shortName: String   // e.g. "BCA"
    let brickShortCode: String?
    let category: BankCategory
    let directAPINote: String

    static let all: [IndonesianBank] = [
        .init(id: "014", name: "Bank Central Asia", shortName: "BCA", brickShortCode: "BCA", category: .big, directAPINote: "BCA API — developer registration required"),
        .init(id: "008", name: "Bank Mandiri", shortName: "Mandiri", brickShortCode: "MANDIRI", category: .big, directAPINote: "Mandiri API — developer registration required"),
        .init(id: "002", name: "Bank Rakyat Indonesia", shortName: "BRI", brickShortCode: "BRI", category: .big, directAPINote: "BRIAPI — developers.bri.co.id"),
        .init(id: "009", name: "Bank Negara Indonesia", shortName: "BNI", brickShortCode: "BNI", category: .big, directAPINote: "BNI API — developer registration required"),
        .init(id: "022", name: "Bank CIMB Niaga", shortName: "CIMB Niaga", brickShortCode: "CIMB_NIAGA", category: .big, directAPINote: "CIMB API — developer registration required"),
        .init(id: "013", name: "Bank Permata", shortName: "Permata", brickShortCode: "PERMATA", category: .big, directAPINote: "Permata API — developer registration required"),
        .init(id: "011", name: "Bank Danamon", shortName: "Danamon", brickShortCode: "DANAMON", category: .big, directAPINote: "Danamon API — developer registration required"),
        .init(id: "200", name: "Bank Tabungan Negara", shortName: "BTN", brickShortCode: "BTN", category: .big, directAPINote: "BTN API — developer registration required"),
        .init(id: "451", name: "Bank Syariah Indonesia", shortName: "BSI", brickShortCode: "BSI", category: .syariah, directAPINote: "BSI API — developer registration required"),
        .init(id: "147", name: "Bank Muamalat", shortName: "Muamalat", brickShortCode: "MUAMALAT", category: .syariah, directAPINote: "Muamalat API — developer registration required"),
        .init(id: "422", name: "BCA Syariah", shortName: "BCA Syariah", brickShortCode: "BCA_SYR", category: .syariah, directAPINote: "BCA Syariah API — developer registration required"),
        .init(id: "542", name: "Bank Jago", shortName: "Jago", brickShortCode: "JAGO", category: .digital, directAPINote: "Jago API — developer registration required"),
        .init(id: "213", name: "Bank BTPN / Jenius", shortName: "Jenius", brickShortCode: "BTPN", category: .digital, directAPINote: "Jenius API — developer registration required"),
        .init(id: "535", name: "SeaBank", shortName: "SeaBank", brickShortCode: "SEABANK", category: .digital, directAPINote: "SeaBank API — developer registration required"),
        .init(id: "490", name: "Bank Neo Commerce", shortName: "Neo", brickShortCode: "BNC", category: .digital, directAPINote: "Neo API — developer registration required"),
        .init(id: "531", name: "Allo Bank", shortName: "Allo", brickShortCode: "ALLO", category: .digital, directAPINote: "Allo API — developer registration required"),
        .init(id: "501", name: "BCA Digital / Blu", shortName: "Blu", brickShortCode: "BCA_DIGITAL", category: .digital, directAPINote: "Blu API — developer registration required"),
        .init(id: "028", name: "Bank OCBC NISP", shortName: "OCBC", brickShortCode: "OCBC", category: .other, directAPINote: "OCBC API — developer registration required"),
        .init(id: "016", name: "Bank Maybank Indonesia", shortName: "Maybank", brickShortCode: "MAYBANK", category: .other, directAPINote: "Maybank API — developer registration required"),
        .init(id: "019", name: "Bank Panin", shortName: "Panin", brickShortCode: "PANIN", category: .other, directAPINote: "Panin API — developer registration required"),
        .init(id: "167", name: "Bank Mega", shortName: "Mega", brickShortCode: "MEGA", category: .other, directAPINote: "Mega API — developer registration required"),
        .init(id: "441", name: "Bank Bukopin / KB Bank", shortName: "KB Bank", brickShortCode: "BUKOPIN", category: .other, directAPINote: "KB Bank API — developer registration required"),
        .init(id: "153", name: "Bank Sinarmas", shortName: "Sinarmas", brickShortCode: "SINARMAS", category: .other, directAPINote: "Sinarmas API — developer registration required"),
        .init(id: "548", name: "Bank Multi Arta Sentosa", shortName: "MAS", brickShortCode: "MAS", category: .other, directAPINote: "MAS API — developer registration required"),
    ]
}

enum ConnectProvider: String, CaseIterable, Identifiable {
    case brick = "Brick — aggregator (recommended)"
    case brankas = "Brankas — aggregator"
    case direct = "Direct bank API (BI-SNAP)"
    var id: String { rawValue }

    /// Keychain key for this provider's API key / client secret.
    var keychainKey: String {
        switch self {
        case .brick: return "brick_api_key"
        case .brankas: return "brankas_api_key"
        case .direct: return "direct_bank_client_secret"
        }
    }
    /// Where to get the credential. Only URLs verified in research are
    /// hard-coded; the rest point at the provider's own dashboard.
    var signupHint: String {
        switch self {
        case .brick: return "Get a key at onebrick.io (free sandbox) → Dashboard → API keys. Docs: docs.onebrick.io"
        case .brankas: return "Get a key at brankas.com → Dashboard → API keys."
        case .direct: return "Register at the bank's developer portal (e.g. BRI: developers.bri.co.id) and sign its cooperation agreement first."
        }
    }
}

enum BankConnectError: Error, LocalizedError {
    case missingAPIKey(ConnectProvider)
    case userCancelled
    case noTokenInCallback
    case authFailed(String)
    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let p): return "No API key saved for \(p.rawValue). Add it first — it is stored in the Keychain, never in the app's database."
        case .userCancelled: return "Authorisation was cancelled. The bank stays Not connected."
        case .noTokenInCallback: return "The bank/aggregator did not return a token. The bank stays Not connected."
        case .authFailed(let s): return "Authorisation failed: \(s)"
        }
    }
}

// MARK: - Connect service

@MainActor
final class BankConnectService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var connectingBank: IndonesianBank?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? UIWindow()
    }

    /// Start the official authorisation for one bank.
    /// - Returns: the stored BankConnection, status "connected" ONLY on a
    ///   real token callback. Throws otherwise; status stays notConnected.
    func connect(bank: IndonesianBank, provider: ConnectProvider, context: ModelContext) async throws -> BankConnection {
        guard let apiKey = KeychainService.read(provider.keychainKey), !apiKey.isEmpty else {
            throw BankConnectError.missingAPIKey(provider)
        }
        connectingBank = bank
        defer { connectingBank = nil }

        // Hosted authorisation page of the chosen provider.
        // VERIFY against the provider docs for your account before first
        // use — providers change hosted-auth URLs, and a wrong URL fails
        // closed (stays Not connected) rather than faking a connection.
        let base: String
        switch provider {
        case .brick: base = "https://api.onebrick.io/v1/auth"
        case .brankas: base = "https://api.brankas.com/v1/auth"
        case .direct: base = "https://api.\(bank.shortName.lowercased().replacingOccurrences(of: " ", with: "" )).co.id/oauth"
        }
        var comps = URLComponents(string: base)
        comps?.queryItems = [
            URLQueryItem(name: "bank", value: bank.brickShortCode ?? bank.shortName),
            URLQueryItem(name: "client_id", value: apiKey),
            URLQueryItem(name: "redirect_uri", value: "payflow://bank-callback"),
            URLQueryItem(name: "scope", value: "read:balance read:transactions"),
        ]
        guard let authURL = comps?.url else { throw BankConnectError.authFailed("Invalid authorisation URL") }

        let callbackURL = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "payflow") { url, error in
                if let error { cont.resume(throwing: error); return }
                guard let url else { cont.resume(throwing: BankConnectError.userCancelled); return }
                cont.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true // no cookies kept
            session.start()
        }
        // A token must come back in the callback — code or public_token.
        let query = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let token = query.first(where: { $0.name == "public_token" || $0.name == "code" })?.value, !token.isEmpty else {
            throw BankConnectError.noTokenInCallback
        }
        // Token goes to the Keychain only — never SwiftData, never a log.
        _ = KeychainService.save(token, for: "bank_token_\(bank.id)_\(bank.shortName)")
        let existing = (try? context.fetch(FetchDescriptor<BankConnection>())) ?? []
        if let conn = existing.first(where: { $0.institutionName == bank.name }) {
            conn.status = "connected"; conn.lastSyncAt = Date(); conn.connectionType = provider.rawValue
            try? context.save()
            return conn
        }
        let conn = BankConnection(institutionName: bank.name, connectionType: provider.rawValue, status: "connected")
        conn.lastSyncAt = Date()
        context.insert(conn)
        try? context.save()
        return conn
    }

    func disconnect(bankName: String, context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<BankConnection>())) ?? []
        for c in all where c.institutionName == bankName {
            c.status = "revoked"; c.lastSyncAt = nil
        }
        try? context.save()
    }

    // MARK: - Sync via aggregator (read-only)

    /// Fetch transactions for a connected bank through the aggregator.
    /// Endpoints below are the aggregator's documented shape — verify
    /// them against your Brick/Brankas dashboard before first sync.
    /// Any failure throws; nothing is marked synced on failure.
    func sync(bank: IndonesianBank, provider: ConnectProvider, context: ModelContext,
              existing: [PayTransaction], learned: [MerchantRule]) async throws -> (inserted: Int, duplicates: Int) {
        guard let token = KeychainService.read("bank_token_\(bank.id)_\(bank.shortName)"),
              let apiKey = KeychainService.read(provider.keychainKey) else {
            throw BankConnectError.missingAPIKey(provider)
        }
        let base = provider == .brick ? "https://api.onebrick.io/v1" : "https://api.brankas.com/v1"
        guard let url = URL(string: "\(base)/transactions?bank=\(bank.brickShortCode ?? bank.shortName)") else {
            throw BankConnectError.authFailed("Invalid sync URL")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw BankConnectError.authFailed("Aggregator returned \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        struct AggTx: Decodable { let date: String; let description: String; let amount: Double }
        let decoded = try JSONDecoder().decode([AggTx].self, from: data)
        var rows: [RawTransaction] = []
        for d in decoded {
            guard let date = ImportService.parseDate(d.date) else { continue }
            rows.append(RawTransaction(date: date, merchant: CategorizationEngine.normalizeMerchant(d.description),
                                       rawDescription: d.description, amount: abs(d.amount),
                                       kind: d.amount < 0 ? .expense : .income))
        }
        let applied = ImportService.applyImport(ImportResult(rows: rows, errors: []), source: .bankAPI,
                                                accountName: bank.shortName, context: context,
                                                existing: existing, learned: learned)
        return (applied.inserted, applied.duplicates)
    }
}
