// Checks that the text in a content pack appears word for word in the official SRD PDF it was taken from.
//
// Usage (from the repository root):
//   sh Tools/srd/verify.sh encounter/encounter/Content/srd51.json /path/to/SRD_CC_v5.1.pdf
//
// For every entry it checks the summary and each trait or feature's text. Both sides are normalised first, so
// differences in line breaks, runs of spaces, soft hyphens and words split across lines don't count. Anything
// else that differs is reported, and the tool exits with a failure. The PDFs aren't part of the repository.
// Download them from:
//   SRD 5.1:   https://media.wizards.com/2023/downloads/dnd/SRD_CC_v5.1.pdf
//   SRD 5.2.1: https://media.dndbeyond.com/compendium-images/srd/5.2/SRD_CC_v5.2.1.pdf

import Foundation
import PDFKit

struct Pack: Decodable {
    var id: String
    var attribution: String
    var entries: [Entry]
}

struct Entry: Decodable {
    var key: String
    var kind: String
    var name: String
    var summary: String?
    var attributes: [String: Attribute]?
    var entries: [Feature]?
}

/// An attribute value, of which only text is checked.
struct Attribute: Decodable {
    var text: String?
    init(from decoder: any Decoder) throws {
        text = try? decoder.singleValueContainer().decode(String.self)
    }
}

struct Feature: Decodable {
    var name: String
    var text: String
}

/// Reduces text to a form where layout differences disappear.
func normalise(_ text: String, joiningSplitWords: Bool) -> String {
    var result = text
        .replacingOccurrences(of: "Dexterit y", with: "Dexterity")   // a gap in the PDF's own text
        .replacingOccurrences(of: "SplASh", with: "Splash")
        .replacingOccurrences(of: "\u{00AD}", with: "")    // soft hyphens
        .replacingOccurrences(of: "\u{2010}", with: "-")   // hyphen
        .replacingOccurrences(of: "\u{2011}", with: "-")   // non-breaking hyphen
        .replacingOccurrences(of: "\u{00A0}", with: " ")
    if joiningSplitWords {
        // "sav-" at the end of a line, "ing" at the start of the next, is one word.
        result = result.replacingOccurrences(of: "-[ \\t]*\\n[ \\t]*(?=[a-z])", with: "", options: .regularExpression)
        // A web address broken after a slash, such as ".../by/4.0/" then "legalcode", is one address.
        result = result.replacingOccurrences(of: "(?<=/)[ \\t]*\\n[ \\t]*(?=[a-z])", with: "", options: .regularExpression)
    }
    result = result
        .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    // A hyphen at the end of a line can be one that's part of the word, such as "15-foot", which can't be told from
    // one that splits a word, so hyphens are left out of the comparison on both sides.
    result = result.replacingOccurrences(of: "-", with: "")
    return result.trimmingCharacters(in: .whitespaces)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("Usage: verify-pack <pack.json> <srd.pdf>")
    exit(2)
}
guard let packData = FileManager.default.contents(atPath: arguments[1]),
      let pack = try? JSONDecoder().decode(Pack.self, from: packData)
else {
    print("Could not read the pack at \(arguments[1])")
    exit(2)
}
guard let document = PDFDocument(url: URL(fileURLWithPath: arguments[2])) else {
    print("Could not read the PDF at \(arguments[2])")
    exit(2)
}

// Read in reading order, as the converter does, since the PDF's own order of the text isn't the order it's read in.
var pdfText = ""
for index in 0..<document.pageCount {
    guard let page = document.page(at: index) else { continue }
    pdfText += readingOrder(of: page, profile: pack.id == "srd52" ? srd52Profile : srd51Profile).map(\.text).joined(separator: "\n") + "\n"
}
let source = normalise(pdfText, joiningSplitWords: true)

var checked = 0
var failures: [String] = []

/// Notes about passages that matched with gaps, for a person to look at.
var notes: [String] = []

/// A passage is found if it appears in the PDF's text in order. The PDF can put other things in the middle of a
/// passage, such as a table or a sidebar between two pages, so it may be found in several runs with gaps between.
/// Each run must be at least four words long, and what the gaps skip over is reported.
func check(_ text: String, describing label: String) {
    checked += 1
    let wanted = normalise(text, joiningSplitWords: false)
    if source.contains(wanted) { return }

    let words = wanted.split(separator: " ").map(String.init)
    var index = 0
    var position = source.startIndex
    var skipped: [String] = []
    let maxGap = 6000
    while index < words.count {
        // The longest run of the next words that appears soon after the last one.
        var low = 0, high = words.count - index
        let searchEnd = index == 0 ? source.endIndex : source.index(position, offsetBy: min(maxGap, source.distance(from: position, to: source.endIndex)))
        while low < high {
            let middle = (low + high + 1) / 2
            let run = words[index..<(index + middle)].joined(separator: " ")
            if source.range(of: run, range: position..<searchEnd) != nil { low = middle } else { high = middle - 1 }
        }
        let remaining = words.count - index
        guard low >= min(4, remaining) else {
            let matched = words[..<index].suffix(6).joined(separator: " ")
            let differs = words[index...].prefix(8).joined(separator: " ")
            failures.append("\(label): matches the PDF up to “…\(matched)”, then the pack has “\(differs)…”")
            return
        }
        let run = words[index..<(index + low)].joined(separator: " ")
        let found = source.range(of: run, range: position..<searchEnd)!
        if found.lowerBound > position, index > 0 {
            skipped.append(String(source[position..<found.lowerBound]).prefix(70) + "…")
        }
        position = found.upperBound
        index += low
    }
    notes.append("\(label): found with \(skipped.count) gap(s): " + skipped.map { "“\($0)”" }.joined(separator: ", "))
}

/// Attributes that are made from several parts of the text rather than copied, such as a feat's category without its prerequisite.
func isWorkedOut(_ name: String) -> Bool {
    ["dnd5e.featCategory", "dnd5e.featPrerequisite", "dnd5e.spellClasses", "dnd5e.spellSchool"].contains(name)
}

check(pack.attribution, describing: "attribution")
for entry in pack.entries {
    if let summary = entry.summary, !summary.isEmpty {
        check(summary, describing: "\(entry.key) summary")
    }
    for feature in entry.entries ?? [] {
        check(feature.text, describing: "\(entry.key) / \(feature.name)")
    }
    // The values of the kinds that are copied whole, such as a background's proficiencies, are the PDF's own words.
    // A race's or class's are worked out from the text, such as a hit die, so aren't checked.
    if !["race", "class", "subclass"].contains(entry.kind) {
        for (name, attribute) in (entry.attributes ?? [:]).sorted(by: { $0.key < $1.key }) {
            if let text = attribute.text, !text.isEmpty, !isWorkedOut(name) { check(text, describing: "\(entry.key) / \(name)") }
        }
    }
}

print("\(pack.id): checked \(checked) passages against \(arguments[2])")
if !notes.isEmpty {
    print("\(notes.count) passage(s) are in the PDF with other text in the middle. Check that what was skipped isn't part of them:")
    for note in notes { print("  - \(note)") }
}
if failures.isEmpty {
    print("All passages appear word for word in the PDF.")
} else {
    print("\(failures.count) passage(s) NOT found in the PDF:")
    for failure in failures { print("  - \(failure)") }
    exit(1)
}
