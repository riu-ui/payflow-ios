import Foundation
import SwiftData
import PDFKit
import Compression

// MARK: - Raw parsed row (before categorisation / dedup)

struct RawTransaction {
    let date: Date
    let merchant: String
    let rawDescription: String
    let amount: Double // positive magnitude
    let kind: TransactionKind
}

struct ImportResult {
    let rows: [RawTransaction]
    let errors: [String]
}

// MARK: - Import service: CSV / XLSX / PDF statement imports

enum ImportService {

    // ---------- Shared helpers ----------

    static let dateFormats = ["yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy", "yyyy/MM/dd",
                              "MMM d, yyyy", "d MMM yyyy", "MM-dd-yyyy", "yyyyMMdd"]

    static func parseDate(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in dateFormats {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return d }
        }
        return nil
    }

    static func parseAmount(_ s: String) -> Double? {
        var t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        var negative = false
        if t.hasPrefix("(") && t.hasSuffix(")") { negative = true; t = String(t.dropFirst().dropLast()) }
        if t.hasPrefix("-") { negative = true; t = String(t.dropFirst()) }
        t = t.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let v = Double(t) else { return nil }
        return negative ? -v : v
    }

    // ---------- CSV ----------

    /// Robust CSV: quoted fields, embedded commas/newlines, header detection.
    static func importCSV(_ data: Data) -> ImportResult {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return ImportResult(rows: [], errors: ["Could not read file as text."])
        }
        let records = parseCSVRecords(text)
        guard let header = records.first else { return ImportResult(rows: [], errors: ["Empty file."]) }
        let lower = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func col(_ names: [String]) -> Int? { names.compactMap { lower.firstIndex(of: $0) }.first }
        guard let dateCol = col(["date", "transaction date", "posted date", "trans date"]),
              let descCol = col(["description", "merchant", "payee", "name", "details"]),
              let amountCol = col(["amount", "value", "total"]) ?? col(["debit", "withdrawal"]) else {
            return ImportResult(rows: [], errors: ["Could not find Date / Description / Amount columns. Headers found: \(header.joined(separator: ", "))"])
        }
        let debitCol = col(["debit", "withdrawal", "money out"])
        let creditCol = col(["credit", "deposit", "money in"])
        var rows: [RawTransaction] = []
        var errors: [String] = []
        for (i, rec) in records.dropFirst().enumerated() {
            guard rec.count > max(dateCol, descCol, amountCol) else { continue }
            guard let date = parseDate(rec[dateCol]) else { errors.append("Row \(i + 2): unrecognised date '\(rec[dateCol])'"); continue }
            let desc = rec[descCol].trimmingCharacters(in: .whitespaces)
            guard !desc.isEmpty else { continue }
            var amount: Double?
            var kind: TransactionKind = .expense
            if let d = debitCol, let c = creditCol {
                // Two-column statements: debit = expense, credit = income.
                let dv = parseAmount(rec[d]); let cv = parseAmount(rec[c])
                if let dv, dv != 0 { amount = abs(dv); kind = .expense }
                else if let cv, cv != 0 { amount = abs(cv); kind = .income }
            } else if let v = parseAmount(rec[amountCol]) {
                amount = abs(v); kind = v < 0 ? .expense : .income
            }
            guard let amount else { errors.append("Row \(i + 2): unrecognised amount '\(rec[amountCol])'"); continue }
            rows.append(RawTransaction(date: date, merchant: CategorizationEngine.normalizeMerchant(desc),
                                       rawDescription: desc, amount: amount, kind: kind))
        }
        return ImportResult(rows: rows, errors: errors)
    }

    /// Minimal CSV record parser honouring double-quoted fields.
    static func parseCSVRecords(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var field = "", record: [String] = [], inQuotes = false
        var chars = text.makeIterator()
        while let ch = chars.next() {
            if inQuotes {
                if ch == "\"" { inQuotes = false } else { field.append(ch) }
            } else if ch == "\"" { inQuotes = true }
            else if ch == "," { record.append(field); field = "" }
            else if ch == "\n" || ch == "\r" {
                // Handle \r\n as one break.
                if ch == "\r" { continue }
                record.append(field); field = ""
                if !record.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { records.append(record) }
                record = []
            } else { field.append(ch) }
        }
        if !field.isEmpty || !record.isEmpty { record.append(field); records.append(record) }
        return records
    }

    // ---------- XLSX ----------

    enum XLSXError: Error, LocalizedError {
        case notZip, entryMissing(String), decompressionFailed(String)
        var errorDescription: String? {
            switch self {
            case .notZip: return "Not a valid .xlsx (ZIP) file."
            case .entryMissing(let n): return "Missing entry in workbook: \(n)"
            case .decompressionFailed(let n): return "Could not decompress \(n). Try exporting the statement as CSV instead."
            }
        }
    }

    /// .xlsx is a ZIP of XML parts. Reads sharedStrings + first sheet,
    /// maps header names the same way as CSV, then reuses that logic.
    static func importXLSX(_ data: Data) throws -> ImportResult {
        let zip = try ZipReader(data: data)
        guard let shared = try? zip.read("xl/sharedStrings.xml") else {
            throw XLSXError.entryMissing("xl/sharedStrings.xml")
        }
        let strings = SharedStringsParser.parse(shared)
        guard let sheet = try? zip.read("xl/worksheets/sheet1.xml") else {
            throw XLSXError.entryMissing("xl/worksheets/sheet1.xml")
        }
        let grid = SheetParser.parse(sheet, sharedStrings: strings)
        guard !grid.isEmpty else { return ImportResult(rows: [], errors: ["No rows found in first sheet."]) }
        // Reuse CSV column logic by serialising the grid back through it.
        let csvText = grid.map { row in row.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ",") }.joined(separator: "\n")
        guard let csvData = csvText.data(using: .utf8) else { return ImportResult(rows: [], errors: ["Encoding error."]) }
        return importCSV(csvData)
    }

    // ---------- PDF ----------

    /// PDF statements: extract text with PDFKit, then match lines like
    /// "12/03/2026 WHOLE FOODS MARKET $54.20" or "03 Dec 2026 ... -54.20".
    static func importPDF(_ data: Data) -> ImportResult {
        guard let doc = PDFDocument(data: data) else {
            return ImportResult(rows: [], errors: ["Could not open PDF."])
        }
        var text = ""
        for i in 0..<doc.pageCount { text += (doc.page(at: i)?.string ?? "") + "\n" }
        var rows: [RawTransaction] = []
        var errors: [String] = []
        // Date ... description ... amount (amount at end of line, optional $ / minus / parentheses)
        let pattern = #"(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}-\d{2}-\d{2})\s+(.+?)\s+(\(?\$?-?[\d,]+\.\d{2}\)?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ImportResult(rows: [], errors: ["PDF parser unavailable."])
        }
        for line in text.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            guard let m = regex.firstMatch(in: line, range: range),
                  let dR = Range(m.range(at: 1), in: line),
                  let descR = Range(m.range(at: 2), in: line),
                  let amtR = Range(m.range(at: 3), in: line),
                  let date = parseDate(String(line[dR])),
                  let signed = parseAmount(String(line[amtR])) else { continue }
            let desc = String(line[descR]).trimmingCharacters(in: .whitespaces)
            guard !desc.isEmpty, signed != 0 else { continue }
            rows.append(RawTransaction(date: date, merchant: CategorizationEngine.normalizeMerchant(desc),
                                       rawDescription: desc, amount: abs(signed),
                                       kind: signed < 0 ? .expense : .income))
        }
        if rows.isEmpty { errors.append("No transaction lines recognised. PDF layout varies by bank — CSV export from your bank is the most reliable format.") }
        return ImportResult(rows: rows, errors: errors)
    }

    // ---------- Apply an import to SwiftData (categorise + dedup + learn) ----------

    /// Inserts rows, skipping exact + fuzzy duplicates. Returns counts.
    /// Must be called on the main actor with the view's ModelContext.
    @MainActor
    static func applyImport(_ result: ImportResult, source: TransactionSource,
                            accountName: String, context: ModelContext,
                            existing: [PayTransaction], learned: [MerchantRule]) -> (inserted: Int, duplicates: Int, needsReview: Int) {
        var inserted = 0, duplicates = 0, needsReview = 0
        var seenFingerprints = Set(existing.map(\.fingerprint))
        var working = existing
        for row in result.rows {
            let fp = DuplicateDetector.fingerprint(date: row.date, amount: row.amount, merchant: row.merchant, accountName: accountName)
            if seenFingerprints.contains(fp) { duplicates += 1; continue }
            if working.contains(where: { DuplicateDetector.isFuzzyDuplicate(candidateDate: row.date, candidateAmount: row.amount, candidateMerchant: row.merchant, existing: $0) }) {
                duplicates += 1; continue
            }
            let (cat, confidence, _) = CategorizationEngine.categorize(merchant: row.merchant, rawDescription: row.rawDescription, learned: learned, kind: row.kind)
            if confidence < 0.5 { needsReview += 1 }
            let tx = PayTransaction(date: row.date, merchant: row.merchant, rawDescription: row.rawDescription,
                                    amount: row.amount, kind: row.kind, category: cat,
                                    source: source, syncStatus: source == .bankAPI ? .synced : .imported,
                                    accountName: accountName, fingerprint: fp)
            context.insert(tx)
            seenFingerprints.insert(fp)
            working.append(tx)
            inserted += 1
        }
        try? context.save()
        return (inserted, duplicates, needsReview)
    }

    /// Record a user category correction so future imports learn from it.
    @MainActor
    static func recordCorrection(merchant: String, category: PayCategory, context: ModelContext, existingRules: [MerchantRule]) {
        let key = CategorizationEngine.normalizeKey(merchant)
        if let rule = existingRules.first(where: { $0.normalizedMerchant == key }) {
            rule.categoryRaw = category.rawValue
            rule.correctionCount += 1
            rule.updatedAt = Date()
        } else {
            context.insert(MerchantRule(normalizedMerchant: key, category: category))
        }
        try? context.save()
    }
}

// MARK: - Minimal ZIP reader (for .xlsx)

struct ZipReader {
    let data: Data
    struct Entry { let name: String; let method: UInt16; let compressedSize: Int; let offset: Int }

    init(data: Data) throws {
        guard data.count >= 4, data[0] == 0x50, data[1] == 0x4B else { throw ImportService.XLSXError.notZip }
        self.data = data
    }

    func entries() -> [Entry] {
        // Scan for central-directory signatures 0x02014b50.
        var out: [Entry] = []
        var i = 0
        while i + 46 <= data.count {
            if data[i] == 0x50, data[i+1] == 0x4B, data[i+2] == 0x01, data[i+3] == 0x02 {
                let method = u16(at: i + 10)
                let compSize = Int(u32(at: i + 20))
                let nameLen = Int(u16(at: i + 28))
                let extraLen = Int(u16(at: i + 30))
                let commentLen = Int(u16(at: i + 32))
                let offset = Int(u32(at: i + 42))
                let nameStart = i + 46
                guard nameStart + nameLen <= data.count else { break }
                let name = String(data: data[nameStart..<(nameStart + nameLen)], encoding: .utf8) ?? ""
                out.append(Entry(name: name, method: method, compressedSize: compSize, offset: offset))
                i = nameStart + nameLen + extraLen + commentLen
            } else { i += 1 }
        }
        return out
    }

    func read(_ name: String) throws -> Data {
        guard let e = entries().first(where: { $0.name == name }) else { throw ImportService.XLSXError.entryMissing(name) }
        // Local header: sig(4) ver(2) flag(2) method(2) time(2) date(2) crc(4) comp(4) uncomp(4) nameLen(2) extraLen(2)
        let base = e.offset
        guard base + 30 <= data.count else { throw ImportService.XLSXError.entryMissing(name) }
        let nameLen = Int(u16(at: base + 26)), extraLen = Int(u16(at: base + 28))
        let start = base + 30 + nameLen + extraLen
        guard start + e.compressedSize <= data.count else { throw ImportService.XLSXError.entryMissing(name) }
        let payload = data[start..<(start + e.compressedSize)]
        if e.method == 0 { return Data(payload) }
        if e.method == 8 {
            guard let out = inflate(Data(payload)) else { throw ImportService.XLSXError.decompressionFailed(name) }
            return out
        }
        throw ImportService.XLSXError.decompressionFailed(name)
    }

    private func u16(at i: Int) -> UInt16 { UInt16(data[i]) | (UInt16(data[i + 1]) << 8) }
    private func u32(at i: Int) -> UInt32 { UInt32(data[i]) | (UInt32(data[i + 1]) << 8) | (UInt32(data[i + 2]) << 16) | (UInt32(data[i + 3]) << 24) }

    /// Raw DEFLATE via libcompression. XLSX entries are raw deflate streams;
    /// prefixing the zlib header lets COMPRESSION_ZLIB decode them.
    private func inflate(_ input: Data) -> Data? {
        var wrapped = Data([0x78, 0x9C])
        wrapped.append(input)
        let dstSize = 4 * 1024 * 1024
        var dst = Data(count: dstSize)
        let decoded = dst.withUnsafeMutableBytes { dstPtr in
            wrapped.withUnsafeBytes { srcPtr in
                compression_decode_buffer(dstPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), dstSize,
                                          srcPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), wrapped.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard decoded > 0 else { return nil }
        return dst.prefix(decoded)
    }
}

// MARK: - XLSX XML helpers

enum SharedStringsParser {
    static func parse(_ data: Data) -> [String] {
        let delegate = StringsDelegate()
        let p = XMLParser(data: data)
        p.delegate = delegate
        p.parse()
        return delegate.strings
    }
    private final class StringsDelegate: NSObject, XMLParserDelegate {
        var strings: [String] = []
        private var current = "", inT = false, inSI = false
        func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if e == "si" { inSI = true; current = "" }
            if e == "t" { inT = true }
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { if inT { current += s } }
        func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
            if e == "t" { inT = false }
            if e == "si" { inSI = false; strings.append(current) }
        }
    }
}

enum SheetParser {
    static func parse(_ data: Data, sharedStrings: [String]) -> [[String]] {
        let delegate = SheetDelegate(sharedStrings: sharedStrings)
        let p = XMLParser(data: data)
        p.delegate = delegate
        p.parse()
        return delegate.rows
    }
    private final class SheetDelegate: NSObject, XMLParserDelegate {
        let sharedStrings: [String]
        var rows: [[String]] = []
        private var currentRow: [String] = [], currentCell = "", currentType = "", inV = false, inRow = false
        init(sharedStrings: [String]) { self.sharedStrings = sharedStrings }
        func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if e == "row" { inRow = true; currentRow = [] }
            if e == "c" { currentType = attributes["t"] ?? ""; currentCell = "" }
            if e == "v" || e == "is" { inV = true }
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { if inV { currentCell += s } }
        func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
            if e == "v" || e == "is" { inV = false }
            if e == "c" {
                if currentType == "s", let idx = Int(currentCell), idx < sharedStrings.count { currentRow.append(sharedStrings[idx]) }
                else { currentRow.append(currentCell) }
            }
            if e == "row" { inRow = false; rows.append(currentRow) }
        }
    }
}
