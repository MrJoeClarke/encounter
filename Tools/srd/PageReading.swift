// Reads the text of an SRD PDF page in reading order. Shared by the converter and the verifier.
//
// The PDF doesn't store a page's text in the order it's read: it has two columns, with tables and captions across
// both, and the lines of a column can come out of order. So each line is put back in place from where it sits.

import Foundation
import PDFKit

func headingLevel(size: Double) -> Int? {
    switch size {
    case 25.9...26: return 1
    case 17.9...18.1: return 2
    case 13.9...14: return 3
    case 11.9...12.1: return 4
    default: return nil
    }
}

func isSize(_ size: Double, _ target: Double) -> Bool { abs(size - target) < 0.05 }

enum LineKind { case heading(Int), body, table, caption, ignored }

struct Line {
    var kind: LineKind
    var text: String
    var minX: Double
    var maxX: Double
    var y: Double
}

/// How to read the lines of one edition's PDF: what each font means, and whether the page's numbers can be dropped.
struct PageProfile {
    var classify: (NSAttributedString) -> LineKind
    var dropsNumberOnlyTableLines: Bool
    /// Whether the lines are already in reading order, as they are in the 5.2.1 PDF, rather than needing to be put back.
    var readsInStreamOrder = false
}

func fontDetails(_ value: Any?) -> (name: String, size: Double) {
    let object = value as AnyObject
    return (object.value(forKey: "fontName") as? String ?? "", object.value(forKey: "pointSize") as? Double ?? 0)
}

/// The first font in a line that carries meaning decides what the line is. The apostrophe and the bullet are
/// set in fonts of their own, so those are skipped.
func classifyByFirstFont(_ text: NSAttributedString, using decide: (String, Double) -> LineKind?) -> LineKind {
    var found: LineKind?
    text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, _, stop in
        let (name, size) = fontDetails(value)
        if let kind = decide(name, size) {
            found = kind
            stop.pointee = true
        }
    }
    return found ?? .body
}

/// SRD 5.1: headings in GillSans by size, text in Helvetica, tables in small Helvetica.
let srd51Profile = PageProfile(classify: { text in
    classifyByFirstFont(text) { name, size in
        if name.hasPrefix("GillSans") {
            // A heading in the small size is a sidebar's, unless it's just a page number.
            let isNumber = text.string.trimmingCharacters(in: .whitespacesAndNewlines).allSatisfy(\.isNumber)
            return headingLevel(size: size).map { .heading($0) } ?? (isSize(size, 10.8) && !isNumber ? .heading(5) : .ignored)
        } else if name.hasPrefix("Helvetica") {
            if isSize(size, 10.8) { return .ignored }   // running footer
            if isSize(size, 8.88) { return .table }
            if isSize(size, 12.0) { return .caption }
            return .body
        }
        return nil
    }
}, dropsNumberOnlyTableLines: true)

/// SRD 5.2.1: headings in GillSans SemiBold by size, text in Helvetica, tables in small GillSans.
let srd52Profile = PageProfile(classify: { text in
    classifyByFirstFont(text) { name, size in
        if name == "GillSans-SemiBold" {
            if isSize(size, 11.0) { return .ignored }   // page number
            if isSize(size, 10.5) { return .caption }
            if isSize(size, 9.25) { return .table }
            if isSize(size, 10.0) { return .body }      // a species' creature type, size and speed
            return headingLevel(size: size).map { .heading($0) } ?? .body
        } else if name.hasPrefix("GillSans") {
            if isSize(size, 11.0) { return .ignored }   // running footer
            if isSize(size, 9.0) { return .ignored }    // the text of a sidebar, set in a grey box
            return size < 9.9 ? .table : .body
        } else if name.hasPrefix("Helvetica") {
            if isSize(size, 11.0) { return .heading(5) }   // a sidebar's title
            return .body
        }
        return nil
    }
}, dropsNumberOnlyTableLines: false, readsInStreamOrder: true)

/// Drops the lines nobody reads and puts the rest in order from the top of a column to the bottom.
func sortedDown(_ lines: [Line]) -> [Line] {
    // Lines on the same baseline, such as a bullet and its text, go left to right.
    lines.sorted { first, second in
        abs(first.y - second.y) < 1 ? first.minX < second.minX : first.y > second.y
    }
}

/// The lines of a page in reading order. The pages have two columns, with tables and their captions across both.
/// The PDF doesn't store the text in that order, so it's put back using where each line sits on the page.
func readingOrder(of page: PDFPage, profile: PageProfile) -> [Line] {
    let box = page.bounds(for: .cropBox)
    guard let selection = page.selection(for: box) else { return [] }
    var lines: [Line] = []
    for part in selection.selectionsByLine() {
        guard let attributed = part.attributedString, let string = part.string,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        let bounds = part.bounds(for: page)
        lines.append(Line(kind: profile.classify(attributed), text: string.trimmingCharacters(in: .newlines),
                          minX: bounds.minX, maxX: bounds.maxX, y: bounds.maxY))
    }
    lines.removeAll { if case .ignored = $0.kind { return true } else { return false } }
    if profile.readsInStreamOrder { return lines }

    let middle = box.midX
    // The numbers of a class table (spell slots and the like) are set apart from the feature names, and end up away
    // from the rest of the row. They aren't needed, so lines holding nothing else are dropped.
    func isOnlyNumbers(_ line: Line) -> Bool {
        guard case .table = line.kind else { return false }
        let hasOrdinal = line.text.range(of: "\\b\\d+(st|nd|rd|th)\\b", options: .regularExpression) != nil
        return !hasOrdinal && line.text.filter(\.isLetter).allSatisfy { "dft".contains($0) }
    }
    if profile.dropsNumberOnlyTableLines { lines.removeAll(where: isOnlyNumbers) }

    let spanning = lines.filter { $0.minX < middle - 10 && $0.maxX > middle + 40 }.sorted { $0.y > $1.y }
    let spanningIDs = Set(spanning.map { "\($0.y)/\($0.minX)" })
    let others = lines.filter { !spanningIDs.contains("\($0.y)/\($0.minX)") }

    var ordered: [Line] = []
    for band in 0...spanning.count {
        let top = band == 0 ? Double.infinity : spanning[band - 1].y
        let bottom = band == spanning.count ? -Double.infinity : spanning[band].y
        let inBand = others.filter { $0.y < top && $0.y >= bottom }
        ordered += sortedDown(inBand.filter { $0.minX < middle - 10 })
        ordered += sortedDown(inBand.filter { $0.minX >= middle - 10 })
        if band < spanning.count { ordered.append(spanning[band]) }
    }
    return ordered
}



// MARK: Text helpers shared by the converters

/// Collapses the odd spacing in the PDF text, and turns the special hyphens the SRD 5.1 uses for real hyphens into "-".
func cleanLine(_ raw: String) -> String {
    var line = raw
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: "-?\u{00AD}?[\u{2010}\u{2011}]+", with: "-", options: .regularExpression)
        .replacingOccurrences(of: "\u{00AD}", with: "")
        .replacingOccurrences(of: "Dexterit y", with: "Dexterity")   // a gap in the PDF's own text
    line = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return line.trimmingCharacters(in: .whitespaces)
}

func slug(_ name: String) -> String {
    name.lowercased()
        .replacingOccurrences(of: "[’']", with: "", options: .regularExpression)
        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

func jsonString(_ value: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes]),
          let text = String(data: data, encoding: .utf8) else { return "\"\"" }
    return String(text.dropFirst().dropLast())
}
