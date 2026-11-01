// Reads the numbers in a class's table (spell slots, cantrips, spells known or prepared, and the levels that
// give an Ability Score Improvement) from an SRD PDF, for the converters to add to each class.
//
// The table is read from the text of the whole page rather than line by line, because a row's numbers can be
// separated from its features by line breaks and by the struck-through dashes the SRD 5.1 uses for empty cells.
// Each row begins with its level and proficiency bonus. The numbers it is after are the last of the run of
// numbers (and dashes) that follows the features, counted from the right, because some tables have more columns
// to the left (rages, sorcery points, channel divinity uses) that aren't needed.

import Foundation
import PDFKit

/// The text of every page, with the odd dashes turned into a plain dash token, runs of spaces and tabs made one
/// space, and the line breaks kept.
private let flattenedPages: String = {
    guard let document = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else { return "" }
    var text = ""
    for index in 0..<document.pageCount { text += (document.page(at: index)?.string ?? "") + "\n" }
    for dash in ["\u{0336}", "\u{2014}", "\u{2013}"] { text = text.replacingOccurrences(of: dash, with: " — ") }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map { line in
        line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    return lines.filter { !$0.isEmpty }.joined(separator: "\n")
}()

/// What the columns of a table hold, from the right-hand end.
private enum Column {
    case cantrips, known, prepared, slot(Int), pactSlots, pactLevel, invocations
}

private func columns(of className: String, edition: Int) -> [Column] {
    let nineSlots = (1...9).map { Column.slot($0) }
    let fiveSlots = (1...5).map { Column.slot($0) }
    switch (edition, className) {
    case (51, "Bard"), (51, "Sorcerer"): return [.cantrips, .known] + nineSlots
    case (51, "Cleric"), (51, "Druid"), (51, "Wizard"): return [.cantrips] + nineSlots
    case (51, "Paladin"): return fiveSlots
    case (51, "Ranger"): return [.known] + fiveSlots
    case (51, "Warlock"): return [.cantrips, .known, .pactSlots, .pactLevel, .invocations]
    case (52, "Bard"), (52, "Cleric"), (52, "Druid"), (52, "Sorcerer"), (52, "Wizard"): return [.cantrips, .prepared] + nineSlots
    case (52, "Paladin"), (52, "Ranger"): return [.prepared] + fiveSlots
    case (52, "Warlock"): return [.invocations, .cantrips, .prepared, .pactSlots, .pactLevel]
    default: return []
    }
}

private func isNumberToken(_ token: Substring) -> Bool {
    token == "—" || token.range(of: "^\\d+(st|nd|rd|th)?$", options: .regularExpression) != nil
}

private func number(_ token: Substring) -> Int {
    token == "—" ? 0 : Int(token.prefix { $0.isNumber }) ?? 0
}

/// The runs of at least `count` number tokens in some text, in order. A number straight before a "+2" is a
/// level label, not a cell, and a run of nothing but ordinals ("1st 2nd 3rd") is a column heading.
private func numberRuns(in tokens: [Substring], count: Int, breakingAtLines: Bool) -> [[Int]] {
    var runs: [[Int]] = []
    var current: [Substring] = []
    func finish() {
        let isHeading = current.allSatisfy { $0 != "—" && $0.last?.isLetter == true }
        if current.count >= count, !isHeading { runs.append(current.map(number)) }
        current = []
    }
    for (index, token) in tokens.enumerated() {
        if token == "¶" {
            if breakingAtLines { finish() }
            continue
        }
        let nextIsBonus = index + 1 < tokens.count && tokens[index + 1].range(of: "^\\+\\d", options: .regularExpression) != nil
        if isNumberToken(token), !nextIsBonus { current.append(token) } else { finish() }
    }
    finish()
    return runs
}

/// The attributes to add to a class: the levels that give an Ability Score Improvement, and for a class that
/// casts spells, its table of cantrips, spells and slots by level. Anything that looks wrong is added to `review`.
func classTableAttributes(for className: String, edition: Int, review: inout [String]) -> [(String, String)] {
    let text = flattenedPages
    let ordinal = edition == 51
    // The table starts at its title, which is followed by the column headings.
    let titlePattern = ordinal
        ? "The\\s\(className)\\s(Level|Proficiency)"
        : "(?<!the\\s)\(className)\\sFeatures\\s(Level\\s)?Proficiency"
    guard let title = text.range(of: titlePattern, options: .regularExpression) else {
        review.append("\(className): couldn't find the class table to read its numbers")
        return []
    }

    // Each row begins with its level and proficiency bonus.
    var starts: [(start: String.Index, end: String.Index)] = []
    var position = title.upperBound
    for level in 1...20 {
        let suffix = ordinal ? "(st|nd|rd|th)" : ""
        let pattern = "(?<![\\d+])\(level)\(suffix)\\s\\+\\d"
        guard let match = text.range(of: pattern, options: .regularExpression, range: position..<text.endIndex) else {
            review.append("\(className): the class table has no row for level \(level)")
            return []
        }
        starts.append((match.lowerBound, match.upperBound))
        position = match.upperBound
    }

    let layout = columns(of: className, edition: edition)
    var improvementLevels: [Int] = []
    for (index, row) in starts.enumerated() {
        let isLast = index == starts.count - 1
        let end = isLast ? text.index(row.end, offsetBy: 120, limitedBy: text.endIndex) ?? text.endIndex : starts[index + 1].start
        // Without the numbers, which can fall between the words of a feature's name when a row is broken up.
        let words = text[row.end..<end].split(whereSeparator: { $0 == " " || $0 == "\n" }).prefix(isLast ? 12 : .max)
            .filter { !isNumberToken($0) }.joined(separator: " ")
        if words.contains("Ability Score Improvement") || (!ordinal && words.contains("Epic Boon")) {
            improvementLevels.append(index + 1)
        }
    }

    // The numbers are the cells of each row. Where the page's text puts a row's cells away from its label, they
    // still come in the order of the rows, so the table is read as twenty runs of numbers.
    var rows: [[Int]] = []
    if !layout.isEmpty {
        let end = text.index(starts[19].end, offsetBy: 800, limitedBy: text.endIndex) ?? text.endIndex
        let region = text[title.upperBound..<end].replacingOccurrences(of: "\n", with: " ¶ ")
        var runs = numberRuns(in: region.split(separator: " "), count: layout.count, breakingAtLines: !ordinal)
        guard runs.count >= 20 else {
            review.append("\(className): found \(runs.count) rows of numbers in the class table, expected 20")
            return []
        }
        runs = Array(runs.prefix(20))
        // A page number can follow the last row.
        while let last = runs[19].last, last > 25 { runs[19].removeLast() }
        rows = runs.map { Array($0.suffix(layout.count)) }
        if runs[19].count < layout.count {
            review.append("\(className): the last row of the class table is short")
            return []
        }
    }

    var result: [(String, String)] = [("dnd5e.asiLevels", improvementLevels.map(String.init).joined(separator: ","))]
    guard !layout.isEmpty else { return result }

    func values(_ wanted: (Column) -> Bool) -> [[Int]] {
        rows.map { row in layout.enumerated().filter { wanted($0.element) }.map { row[$0.offset] } }
    }
    func joined(_ pick: (Column) -> Bool) -> String {
        values(pick).map { $0.first.map(String.init) ?? "0" }.joined(separator: ",")
    }
    if layout.contains(where: { if case .cantrips = $0 { true } else { false } }) {
        result.append(("dnd5e.cantripsKnownByLevel", joined { if case .cantrips = $0 { true } else { false } }))
    }
    if layout.contains(where: { if case .known = $0 { true } else { false } }) {
        result.append(("dnd5e.spellsKnownByLevel", joined { if case .known = $0 { true } else { false } }))
    }
    if layout.contains(where: { if case .prepared = $0 { true } else { false } }) {
        result.append(("dnd5e.preparedSpellsByLevel", joined { if case .prepared = $0 { true } else { false } }))
    }
    if layout.contains(where: { if case .invocations = $0 { true } else { false } }) {
        result.append(("dnd5e.invocationsKnownByLevel", joined { if case .invocations = $0 { true } else { false } }))
    }
    if layout.contains(where: { if case .pactSlots = $0 { true } else { false } }) {
        // A warlock's slots are all of one level: how many, and which level.
        let pact = rows.map { row -> String in
            let count = layout.enumerated().first { if case .pactSlots = $0.element { true } else { false } }.map { row[$0.offset] } ?? 0
            let level = layout.enumerated().first { if case .pactLevel = $0.element { true } else { false } }.map { row[$0.offset] } ?? 0
            return "\(count),\(level)"
        }
        result.append(("dnd5e.pactSlotsByLevel", pact.joined(separator: ";")))
    } else {
        let slots = rows.map { row -> String in
            var perLevel = [Int](repeating: 0, count: 9)
            for (offset, column) in layout.enumerated() { if case .slot(let spellLevel) = column { perLevel[spellLevel - 1] = row[offset] } }
            return perLevel.map(String.init).joined(separator: ",")
        }
        result.append(("dnd5e.spellSlotsByLevel", slots.joined(separator: ";")))
    }
    return result
}
