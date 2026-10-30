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
    var name: String
    var summary: String?
    var entries: [Feature]?
}

struct Feature: Decodable {
    var name: String
    var text: String
}

/// Reduces text to a form where layout differences disappear.
func normalise(_ text: String, joiningSplitWords: Bool) -> String {
    var result = text
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

var pdfText = ""
for index in 0..<document.pageCount {
    pdfText += (document.page(at: index)?.string ?? "") + "\n"
}
let source = normalise(pdfText, joiningSplitWords: true)

var checked = 0
var failures: [String] = []

func check(_ text: String, describing label: String) {
    checked += 1
    // Paragraph breaks in the pack are blank lines. The PDF has no marker for them, so they are just whitespace.
    if !source.contains(normalise(text, joiningSplitWords: false)) {
        failures.append("\(label): \(text.prefix(80))…")
    }
}

check(pack.attribution, describing: "attribution")
for entry in pack.entries {
    if let summary = entry.summary, !summary.isEmpty {
        check(summary, describing: "\(entry.key) summary")
    }
    for feature in entry.entries ?? [] {
        check(feature.text, describing: "\(entry.key) / \(feature.name)")
    }
}

print("\(pack.id): checked \(checked) passages against \(arguments[2])")
if failures.isEmpty {
    print("All passages appear word for word in the PDF.")
} else {
    print("\(failures.count) passage(s) NOT found in the PDF:")
    for failure in failures { print("  - \(failure)") }
    exit(1)
}
