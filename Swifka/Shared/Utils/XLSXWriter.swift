import Foundation

/// Minimal OOXML SpreadsheetML (.xlsx) writer — no external dependencies.
/// Builds an in-memory ZIP archive of XML parts using pure Swift CRC-32 and ZIP encoding.
nonisolated enum XLSXWriter {
    /// A single worksheet with column headers and string data rows.
    struct Sheet: Sendable {
        let name: String // tab name (sanitized to ≤31 chars, no \ / * ? [ ])
        let headers: [String]
        let rows: [[String]] // each inner array should match headers.count
    }

    /// Build a complete .xlsx file and return it as in-memory `Data`.
    static func build(sheets: [Sheet]) -> Data {
        let sheetNames = deduplicateNames(sheets.map { sanitizeSheetName($0.name) })

        var files: [(path: String, data: Data)] = []
        files.append(("[Content_Types].xml", utf8(contentTypesXML(sheets.count))))
        files.append(("_rels/.rels", utf8(rootRelsXML)))
        files.append(("xl/workbook.xml", utf8(workbookXML(sheetNames))))
        files.append(("xl/_rels/workbook.xml.rels", utf8(workbookRelsXML(sheets.count))))
        files.append(("xl/styles.xml", utf8(stylesXML)))
        for (i, sheet) in sheets.enumerated() {
            files.append(("xl/worksheets/sheet\(i + 1).xml", utf8(worksheetXML(sheet))))
        }
        return MiniZIP.archive(files)
    }

    private static func utf8(_ string: String) -> Data {
        Data(string.utf8)
    }

    // MARK: - XML Parts

    private static func contentTypesXML(_ sheetCount: Int) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        s += "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        s += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        s += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        s += "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        s += "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        for i in 1 ... sheetCount {
            s += "<Override PartName=\"/xl/worksheets/sheet\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        s += "</Types>"
        return s
    }

    private static var rootRelsXML: String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>"
            + "</Relationships>"
    }

    private static func workbookXML(_ sheetNames: [String]) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        s += "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\""
        s += " xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        s += "<sheets>"
        for (i, name) in sheetNames.enumerated() {
            s += "<sheet name=\"\(xmlEscape(name))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
        }
        s += "</sheets></workbook>"
        return s
    }

    private static func workbookRelsXML(_ sheetCount: Int) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        s += "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for i in 1 ... sheetCount {
            s += "<Relationship Id=\"rId\(i)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i).xml\"/>"
        }
        s += "<Relationship Id=\"rIdStyles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        s += "</Relationships>"
        return s
    }

    private static var stylesXML: String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
            + "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
            + "<fonts count=\"2\">"
            + "<font><sz val=\"11\"/><name val=\"Calibri\"/></font>"
            + "<font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font>"
            + "</fonts>"
            + "<fills count=\"2\">"
            + "<fill><patternFill patternType=\"none\"/></fill>"
            + "<fill><patternFill patternType=\"gray125\"/></fill>"
            + "</fills>"
            + "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"
            + "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
            + "<cellXfs count=\"2\">"
            + "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>"
            + "<xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/>"
            + "</cellXfs>"
            + "</styleSheet>"
    }

    private static func worksheetXML(_ sheet: Sheet) -> String {
        let colCount = sheet.headers.count
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        s += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"

        // Column widths — wider for timestamp column
        s += "<cols>"
        for i in 0 ..< colCount {
            let w = i == 0 ? 28 : 18
            s += "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(w)\" customWidth=\"1\"/>"
        }
        s += "</cols>"

        s += "<sheetData>"

        // Header row (bold — style index 1)
        s += "<row r=\"1\">"
        for (col, header) in sheet.headers.enumerated() {
            let ref = "\(columnLetter(col))1"
            s += "<c r=\"\(ref)\" s=\"1\" t=\"inlineStr\"><is><t>\(xmlEscape(header))</t></is></c>"
        }
        s += "</row>"

        // Data rows
        for (rowIdx, row) in sheet.rows.enumerated() {
            let r = rowIdx + 2 // 1-indexed, skip header
            s += "<row r=\"\(r)\">"
            for (col, value) in row.prefix(colCount).enumerated() {
                let ref = "\(columnLetter(col))\(r)"
                if Double(value) != nil {
                    s += "<c r=\"\(ref)\"><v>\(value)</v></c>"
                } else {
                    s += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(xmlEscape(value))</t></is></c>"
                }
            }
            s += "</row>"
        }

        s += "</sheetData></worksheet>"
        return s
    }

    // MARK: - Helpers

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func sanitizeSheetName(_ name: String) -> String {
        var s = name
        // Excel prohibits: \ / * ? [ ] :
        for ch in ["\\", "/", "*", "?", "[", "]", ":"] {
            s = s.replacingOccurrences(of: ch, with: "-")
        }
        // Leading/trailing apostrophes are also prohibited
        while s.hasPrefix("'") {
            s.removeFirst()
        }
        while s.hasSuffix("'") {
            s.removeLast()
        }
        if s.count > 31 { s = String(s.prefix(31)) }
        if s.isEmpty { s = "Sheet" }
        return s
    }

    /// Ensure all sheet names are unique — append " (2)", " (3)" etc. for duplicates.
    private static func deduplicateNames(_ names: [String]) -> [String] {
        var result: [String] = []
        var seen: [String: Int] = [:]
        for name in names {
            let count = (seen[name] ?? 0) + 1
            seen[name] = count
            if count == 1 {
                result.append(name)
            } else {
                result.append(String("\(name) (\(count))".prefix(31)))
            }
        }
        return result
    }

    /// Convert 0-based column index to Excel column letter(s): 0→A, 1→B, …, 25→Z, 26→AA.
    private static func columnLetter(_ col: Int) -> String {
        var s = ""
        var c = col
        repeat {
            s = String(UnicodeScalar(65 + c % 26)!) + s
            c = c / 26 - 1
        } while c >= 0
        return s
    }
}
