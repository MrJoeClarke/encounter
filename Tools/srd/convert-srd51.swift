// Converts the races and classes of the official SRD 5.1 PDF into a content pack.
//
// Usage (from the repository root):
//   sh Tools/srd/convert.sh 51 /path/to/SRD_CC_v5.1.pdf encounter/encounter/Content/srd51.json
//
// The PDF isn't part of the repository. Download it from
//   https://media.wizards.com/2023/downloads/dnd/SRD_CC_v5.1.pdf
//
// Text is copied from the PDF as it is. The only changes are layout ones: lines are joined, words split across
// lines are rejoined, and soft hyphens are removed. Headings are found by their font (the SRD uses GillSans
// for headings and its size gives the level), so this relies on the layout of that document.
//
// The tool prints a report of what it found, with anything it isn't sure about listed at the end, for a person to
// check against the PDF. Run Tools/srd/verify.sh afterwards to confirm every passage appears in the PDF.

import Foundation
import PDFKit

// MARK: Reading the PDF

enum Block {
    /// level 1 is a chapter title, 2 a section, 3 a feature, 4 a sub-feature
    case heading(level: Int, text: String)
    case body([String])
    /// A table caption, or the rows of a table.
    case caption([String])
    case table([String])
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("Usage: convert-srd51 <srd.pdf> <pack.json>")
    exit(2)
}
guard let document = PDFDocument(url: URL(fileURLWithPath: arguments[1])) else {
    print("Could not read the PDF at \(arguments[1])")
    exit(2)
}

var blocks: [Block] = []
var pendingKind: LineKind?
var pending: [String] = []

func sameKind(_ a: LineKind?, _ b: LineKind) -> Bool {
    switch (a, b) {
    case (.body?, .body), (.table?, .table), (.caption?, .caption): return true
    default: return false
    }
}

func flushPending() {
    defer { pending = []; pendingKind = nil }
    guard let kind = pendingKind, !pending.isEmpty else { return }
    switch kind {
    case .body: blocks.append(.body(pending))
    case .table: blocks.append(.table(pending))
    case .caption: blocks.append(.caption(pending))
    default: break
    }
}

/// Sidebars, such as a paladin's "Breaking Your Oath", aren't part of any feature and are left out.
var omittedSidebars: [String] = []
var inSidebar = false

for pageIndex in 2..<document.pageCount {
    guard let page = document.page(at: pageIndex) else { continue }
    for line in readingOrder(of: page, profile: srd51Profile) {
        if case .heading(5) = line.kind {
            flushPending()
            inSidebar = true
            omittedSidebars.append(line.text.trimmingCharacters(in: .whitespaces))
        } else if inSidebar, case .table = line.kind {
            continue
        } else if case .heading(let level) = line.kind {
            inSidebar = false
            flushPending()
            blocks.append(.heading(level: level, text: line.text.trimmingCharacters(in: .whitespaces)))
        } else {
            inSidebar = false
            if !sameKind(pendingKind, line.kind) { flushPending() }
            pendingKind = line.kind
            pending.append(line.text)
        }
    }
    flushPending()
}

// MARK: Cleaning text

var hyphenJoins: [String] = []

/// Joins the lines of a block into paragraphs. A line that ends in a hyphen the SRD added to wrap a word is joined
/// to the next without the hyphen, and one that ends in a real hyphen keeps it. A new paragraph starts at a bullet,
/// or after a short line that ends a sentence.
func paragraphs(from rawLines: [String], lineWidth: Int) -> [String] {
    var result: [String] = []
    var current = ""
    var previous = ""
    var previousWrapped = false
    var previousRealHyphen = false
    for raw in rawLines {
        let trimmedRaw = raw.trimmingCharacters(in: .whitespaces)
        let line = cleanLine(raw)
        if line.isEmpty { continue }
        // Compared by scalar, since Swift joins a run of hyphens and format characters into a single character.
        let lastScalar = trimmedRaw.unicodeScalars.last?.value
        let realHyphen = lastScalar == 0x2010 || lastScalar == 0x2011
        let wrapped = lastScalar == 0x2D || lastScalar == 0xAD
        if current.isEmpty {
            current = line
        } else {
            let startsBullet = line.hasPrefix("•")
            let endedSentence = previous.last.map { ".!?:”\")".contains($0) } ?? false
            let wasShort = previous.count < lineWidth * 3 / 4
            if startsBullet || (endedSentence && wasShort && !previousWrapped && !previousRealHyphen) {
                result.append(current)
                current = line
            } else if previousWrapped {
                if current.hasSuffix("-") { current.removeLast() }
                current += line
                hyphenJoins.append(String(current.suffix(24)))
            } else if previousRealHyphen {
                current += line
            } else {
                current += " " + line
            }
        }
        previous = line
        previousWrapped = wrapped
        previousRealHyphen = realHyphen
    }
    if !current.isEmpty { result.append(current) }
    return result
}

// MARK: Measuring the page

let bodyLineLengths = blocks.compactMap { block -> [Int]? in
    if case .body(let lines) = block { return lines.map { cleanLine($0).count } }
    return nil
}.flatMap { $0 }.sorted()
let lineWidth = bodyLineLengths.isEmpty ? 60 : bodyLineLengths[bodyLineLengths.count * 95 / 100]

// MARK: Sections

struct Section {
    var heading: String
    var level: Int
    var blocks: [Block] = []

    var bodyParagraphs: [String] {
        var all: [String] = []
        for block in blocks {
            switch block {
            case .body(let lines): all += paragraphs(from: lines, lineWidth: lineWidth)
            case .caption(let lines): all += lines.map(cleanLine)
            case .table(let lines): all += lines.map(cleanLine)
            case .heading: break
            }
        }
        return all
    }
}

/// Splits blocks into sections starting at every heading of one of the given levels.
func split(_ blocks: [Block], atLevels levels: Set<Int>) -> (preamble: [Block], sections: [Section]) {
    var preamble: [Block] = []
    var sections: [Section] = []
    for block in blocks {
        if case .heading(let level, let text) = block, levels.contains(level) {
            sections.append(Section(heading: text, level: level))
        } else if sections.isEmpty {
            preamble.append(block)
        } else {
            sections[sections.count - 1].blocks.append(block)
        }
    }
    return (preamble, sections)
}

// MARK: Output model

struct Feature {
    var name: String
    var level: Int?
    var text: String
}

struct PackEntry {
    var key: String
    var kind: String
    var name: String
    var parent: String?
    var summary: String
    var attributes: [(String, String)] = []
    var features: [Feature] = []
}

var entries: [PackEntry] = []
var report: [String] = []
var review: [String] = []

// MARK: Split the document into the races and the classes

/// The one subclass each class has in the SRD. The headings of the class's own features and of its subclass look alike.
let subclassNames: Set<String> = ["Path of the Berserker", "College of Lore", "Life Domain", "Circle of the Land", "Champion", "Way of the Open Hand",
                                  "Oath of Devotion", "Hunter", "Thief", "Draconic Bloodline", "The Fiend", "School of Evocation"]
/// The class feature at which each class chooses its subclass.
let subclassChoosers: Set<String> = ["Primal Path", "Bard College", "Divine Domain", "Druid Circle", "Martial Archetype", "Monastic Tradition",
                                     "Sacred Oath", "Ranger Archetype", "Roguish Archetype", "Sorcerous Origin", "Otherworldly Patron", "Arcane Tradition"]
let classNames = ["Barbarian", "Bard", "Cleric", "Druid", "Fighter", "Monk", "Paladin", "Ranger", "Rogue", "Sorcerer", "Warlock", "Wizard"]
var chapters: [(title: String, blocks: [Block])] = []
for block in blocks {
    if case .heading(1, let text) = block {
        if text == "Races" || classNames.contains(text) {
            chapters.append((text, []))
        } else if !chapters.isEmpty, chapters.last?.title == "Wizard" {
            break   // the next chapter after the last class
        } else if chapters.isEmpty {
            continue
        } else {
            chapters[chapters.count - 1].blocks.append(block)
        }
    } else if !chapters.isEmpty {
        chapters[chapters.count - 1].blocks.append(block)
    }
}

// MARK: Races

/// A line that starts a trait: "Darkvision. Accustomed to...". Returns the name and the rest of the line.
func traitStart(in line: String) -> (name: String, rest: String)? {
    guard let match = line.range(of: "^[A-Z][A-Za-z’'-]*( (of|the|and|in|to|a|[A-Z][A-Za-z’'-]*))*\\. ", options: .regularExpression)
    else { return nil }
    let name = String(line[match]).trimmingCharacters(in: .whitespaces)
    return (String(name.dropLast()), String(line[match.upperBound...]))
}

/// Splits race text into a summary (what comes before the first trait) and the traits. A table becomes a trait of its
/// own, named after its caption.
func parseTraits(blocks: [Block]) -> (summary: String, traits: [Feature]) {
    struct Draft { var name: String; var lines: [String] = []; var isTable = false }
    var summary: [String] = []
    var drafts: [Draft] = []
    var previous = ""
    for block in blocks {
        switch block {
        case .body(let rawLines):
            for raw in rawLines {
                let line = cleanLine(raw)
                if line.isEmpty { continue }
                let afterSentence = previous.isEmpty || ".!?”\")".contains(previous.last ?? " ")
                if afterSentence, !(drafts.last?.isTable ?? false) || previous.isEmpty, let start = traitStart(in: line) {
                    // Keep the line as it is in the PDF, minus the name, so the way it ends is still known.
                    let remainder = raw.range(of: start.name + ".").map { String(raw[$0.upperBound...]) } ?? start.rest
                    drafts.append(Draft(name: start.name, lines: [remainder]))
                } else if drafts.isEmpty {
                    summary.append(raw)
                } else {
                    drafts[drafts.count - 1].lines.append(raw)
                }
                previous = line
            }
        case .caption(let lines):
            var name = lines.map(cleanLine).joined(separator: " ")
            if drafts.contains(where: { $0.name == name }) { name += " (table)" }
            drafts.append(Draft(name: name, isTable: true))
            previous = ""
        case .table(let lines):
            if drafts.last?.isTable ?? false {
                drafts[drafts.count - 1].lines += lines
            }
            previous = ""
        case .heading: break
        }
    }
    // A table named like the trait that explains it, such as "Draconic Ancestry", is told apart.
    for index in drafts.indices.dropLast() where drafts[index].isTable && drafts[index].name == drafts[index + 1].name {
        drafts[index].name += " (table)"
    }
    let summaryText = paragraphs(from: summary, lineWidth: lineWidth).joined(separator: "\n\n")
    let features = drafts.map { draft -> Feature in
        if draft.isTable { return Feature(name: draft.name, level: nil, text: draft.lines.map(cleanLine).joined(separator: "\n")) }
        return Feature(name: draft.name, level: nil, text: paragraphs(from: draft.lines, lineWidth: lineWidth).joined(separator: "\n\n"))
    }
    return (summaryText, features)
}

func derivedRaceAttributes(from traits: [Feature]) -> [(String, String)] {
    var result: [(String, String)] = []
    func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }
    for trait in traits {
        switch trait.name {
        case "Size":
            if let size = firstMatch("(?<=[Yy]our size is )[A-Z][a-z]+", in: trait.text) { result.append(("core.raceSize", size)) }
        case "Speed":
            if let speed = firstMatch("(?<=walking speed is )\\d+ feet", in: trait.text) { result.append(("dnd5e.speed", speed)) }
        case "Darkvision":
            if let range = firstMatch("(?<=within )\\d+ feet", in: trait.text) { result.append(("dnd5e.darkvision", range)) }
        case "Languages":
            if let spoken = firstMatch("(?<=can speak, read, and write ).*?(?=\\.)", in: trait.text) { result.append(("dnd5e.languages", spoken)) }
        default: break
        }
    }
    return result
}

if let races = chapters.first(where: { $0.title == "Races" }) {
    let (_, sections) = split(races.blocks, atLevels: [2])
    for section in sections where section.level == 2 {
        let raceKey = "srd51.race.\(slug(section.heading))"
        // Everything before the first sub-race heading is the race itself.
        let (raceBlocks, subraces) = split(section.blocks, atLevels: [4])
        let raceOnly = raceBlocks.filter { block in
            if case .heading = block { return false }
            return true
        }
        let parsed = parseTraits(blocks: raceOnly)
        entries.append(PackEntry(key: raceKey, kind: "race", name: section.heading, parent: nil, summary: parsed.summary,
                                 attributes: derivedRaceAttributes(from: parsed.traits), features: parsed.traits))
        report.append("Race \(section.heading): \(parsed.traits.map(\.name).joined(separator: ", "))")
        if parsed.summary.isEmpty { review.append("\(section.heading) has no introduction") }

        for subrace in subraces where subrace.level == 4 {
            let parsedSub = parseTraits(blocks: subrace.blocks)
            entries.append(PackEntry(key: "srd51.race.\(slug(subrace.heading))", kind: "race", name: subrace.heading, parent: raceKey,
                                     summary: parsedSub.summary, attributes: derivedRaceAttributes(from: parsedSub.traits), features: parsedSub.traits))
            report.append("  Subrace \(subrace.heading): \(parsedSub.traits.map(\.name).joined(separator: ", "))")
        }
    }
}

// MARK: Classes

/// The level a feature says it's gained at, such as "At 3rd level" or "At 3rd, 5th, 7th, and 9th level".
/// Only the opening sentences are read; later ones talk about the feature improving.
func firstLevelMentioned(in fullText: String, sentences: Int = 1) -> Int? {
    let opening = fullText.components(separatedBy: ". ").prefix(sentences)
    for sentence in opening where sentence.contains("level") {
        if let range = sentence.range(of: "\\b(\\d{1,2})(st|nd|rd|th)\\b", options: .regularExpression) {
            return Int(sentence[range].prefix { $0.isNumber })
        }
    }
    return nil
}

/// Reads the class table into the features listed at each level.
func progression(from lines: [String]) -> [Int: String] {
    let joined = lines.map(cleanLine).joined(separator: " ").replacingOccurrences(of: "\u{0336}", with: "")
    var rows: [Int: String] = [:]
    // A row starts with its level followed by the proficiency bonus, which the spell slot headings above it lack.
    let pattern = try? NSRegularExpression(pattern: "\\b(20|1[0-9]|[1-9])(st|nd|rd|th)\\s*\\+\\d", options: [])
    let ns = joined as NSString
    let matches = pattern?.matches(in: joined, range: NSRange(location: 0, length: ns.length)) ?? []
    for (index, match) in matches.enumerated() {
        let level = Int(ns.substring(with: match.range(at: 1))) ?? 0
        let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
        let content = ns.substring(with: NSRange(location: match.range.upperBound, length: end - match.range.upperBound))
        // Drop the numbers in the other columns, leaving the feature names.
        let words = content.split(separator: " ").filter { word in
            !word.contains { $0.isNumber } && !["—", "–", "-", "Unlimited", "ft."].contains(String(word))
        }
        if rows[level] == nil { rows[level] = words.joined(separator: " ") }
    }
    return rows
}

func lowestLevel(of name: String, in rows: [Int: String]) -> Int? {
    if let level = lowestLevelExactly(name, in: rows) { return level }
    // The table says "Signature Spell" where the feature is headed "Signature Spells".
    return name.hasSuffix("s") ? lowestLevelExactly(String(name.dropLast()), in: rows) : nil
}

func lowestLevelExactly(_ name: String, in rows: [Int: String]) -> Int? {
    let pattern = "(^|[^A-Za-z])" + NSRegularExpression.escapedPattern(for: name) + "([^A-Za-z]|$)"
    return rows.filter { $0.value.range(of: pattern, options: .regularExpression) != nil }.keys.min()
}

func joinedText(_ section: Section) -> String {
    section.bodyParagraphs.joined(separator: "\n\n")
}

for chapter in chapters where classNames.contains(chapter.title) {
    let className = chapter.title
    let classKey = "srd51.class.\(slug(className))"
    var classAttributes: [(String, String)] = []
    var summary = ""

    // Text before the first feature: the intro, hit points, proficiencies, equipment and the class table.
    var introBlocks: [Block] = []
    for block in chapter.blocks {
        if case .heading(3, _) = block { break }
        introBlocks.append(block)
    }
    let (introPreamble, introSections) = split(introBlocks, atLevels: [4])
    summary = paragraphs(from: introPreamble.flatMap { block -> [String] in
        if case .body(let lines) = block { return lines }
        return []
    }, lineWidth: lineWidth).joined(separator: "\n\n")
    if summary.isEmpty {
        // The sentence under "Class Features".
        summary = introSections.first(where: { $0.heading == "Class Features" }).map { joinedText($0) } ?? ""
    }
    var tableLines: [String] = []
    for block in introBlocks {
        if case .table(let lines) = block { tableLines += lines }
    }
    let rows = progression(from: tableLines)
    if ProcessInfo.processInfo.environment["DEBUG_ROWS"] != nil {
        print("--- \(className) table"); for level in rows.keys.sorted() { print(level, rows[level] ?? "") }
    }
    if rows.count < 18 { review.append("\(className): found \(rows.count) rows in the class table, expected 20") }

    for section in introSections {
        // Only the section's own text: the class table's caption comes straight after "Equipment".
        let text = paragraphs(from: section.blocks.flatMap { block -> [String] in
            if case .body(let lines) = block { return lines }
            return []
        }, lineWidth: lineWidth).joined(separator: " ")
        switch section.heading {
        case "Hit Points":
            if let range = text.range(of: "(?<=Hit Dice: 1)d\\d+", options: .regularExpression) {
                classAttributes.append(("dnd5e.hitDie", String(text[range])))
            } else { review.append("\(className): no hit die found") }
        case "Equipment":
            let bodyLines = section.blocks.flatMap { block -> [String] in
                if case .body(let lines) = block { return lines }
                return []
            }
            classAttributes.append(("dnd5e.startingEquipment", paragraphs(from: bodyLines, lineWidth: lineWidth).joined(separator: "\n")))
        case "Proficiencies":
            let labels = ["Armor", "Weapons", "Tools", "Saving Throws", "Skills"]
            let keys = ["dnd5e.armorProficiencies", "dnd5e.weaponProficiencies", "dnd5e.toolProficiencies", "dnd5e.savingThrows", "dnd5e.skillChoices"]
            for (index, label) in labels.enumerated() {
                let next = index + 1 < labels.count ? "(?=\(labels[index + 1]): )" : "$"
                if let range = text.range(of: "(?<=\(label): ).*?\(next)", options: .regularExpression) {
                    classAttributes.append((keys[index], String(text[range]).trimmingCharacters(in: .whitespaces)))
                } else { review.append("\(className): no \(label.lowercased()) proficiencies found") }
            }
        default: break
        }
    }

    // The class's own features come first. The subclass starts at the first heading that isn't in the class table.
    let groups = blocksGrouped(chapter.blocks)
    let subclassIndex = groups.indices.first { subclassNames.contains(groups[$0].heading) }
    let featureGroups = subclassIndex.map { Array(groups[..<$0]) } ?? groups
    let subclassSection = subclassIndex.map { groups[$0] }

    var features: [Feature] = []
    for section in featureGroups {
        let text = mergedFeatureText(section)
        var level = lowestLevel(of: section.heading, in: rows)
        let mentioned = firstLevelMentioned(in: text, sentences: 2)
        if level == nil {
            level = mentioned ?? 1
            review.append("\(className) / \(section.heading): not found in the class table, took level \(level ?? 1) from its text")
        } else if let mentioned, level != mentioned {
            review.append("\(className) / \(section.heading): table says level \(level ?? 0), text says \(mentioned) (used the table)")
        }
        features.append(Feature(name: section.heading, level: level, text: text))
    }

    entries.append(PackEntry(key: classKey, kind: "class", name: className, parent: nil, summary: summary,
                             attributes: classAttributes, features: features))
    report.append("Class \(className) (\(classAttributes.count) attributes): " + features.map { "\($0.name) \($0.level ?? 0)" }.joined(separator: ", "))

    if let subclass = subclassSection {
        let (subIntro, subFeatures) = split(subclass.blocks, atLevels: [4])
        let introText = paragraphs(from: subIntro.flatMap { block -> [String] in
            if case .body(let lines) = block { return lines }
            return []
        }, lineWidth: lineWidth).joined(separator: "\n\n")
        // Until a feature says otherwise, a subclass feature comes at the level the class chooses its subclass.
        let chooser = features.first { subclassChoosers.contains($0.name) }
        if chooser == nil { review.append("\(className) / \(subclass.heading): no feature chooses a subclass, so features default to level 3") }
        var previousLevel = chooser?.level ?? 3
        var subclassFeatures: [Feature] = []
        // Tables such as a domain's spell list sit before the first feature and are features of their own.
        var tableName = ""
        for block in subIntro {
            if case .caption(let lines) = block { tableName = lines.map(cleanLine).joined(separator: " ") }
            if case .table(let lines) = block {
                subclassFeatures.append(Feature(name: tableName.isEmpty ? "Table" : tableName, level: previousLevel, text: lines.map(cleanLine).joined(separator: "\n")))
                tableName = ""
            }
        }
        for feature in subFeatures {
            let text = mergedFeatureText(feature)
            var level = firstLevelMentioned(in: text, sentences: 2)
            if level == nil {
                level = previousLevel
                review.append("\(className) / \(subclass.heading) / \(feature.heading): no level in its text, used \(previousLevel)")
            }
            previousLevel = level ?? previousLevel
            subclassFeatures.append(Feature(name: feature.heading, level: level, text: text))
        }
        entries.append(PackEntry(key: "srd51.subclass.\(slug(subclass.heading))", kind: "subclass", name: subclass.heading, parent: classKey,
                                 summary: introText, attributes: [], features: subclassFeatures))
        report.append("  Subclass \(subclass.heading): " + subclassFeatures.map { "\($0.name) \($0.level ?? 0)" }.joined(separator: ", "))
    } else {
        review.append("\(className): no subclass found")
    }
}

// MARK: Helpers used above

/// A section for each level 3 heading, holding everything up to the next one (including smaller headings).
func blocksGrouped(_ blocks: [Block]) -> [Section] {
    var sections: [Section] = []
    for block in blocks {
        if case .heading(3, let text) = block {
            // "Ki" and "Unarmored Movement" can share one run, giving two headings in a row.
            sections.append(Section(heading: text, level: 3))
        } else if !sections.isEmpty {
            sections[sections.count - 1].blocks.append(block)
        }
    }
    return sections
}

/// A feature's text, with any smaller headings inside it kept in place ahead of the text that follows them.
func mergedFeatureText(_ section: Section) -> String {
    var paragraphList: [String] = []
    var pending: [String] = []
    func flush() {
        paragraphList += paragraphs(from: pending, lineWidth: lineWidth)
        pending = []
    }
    for block in section.blocks {
        switch block {
        case .body(let lines): pending += lines
        case .heading(_, let text):
            flush()
            paragraphList.append(text)
        case .caption(let lines):
            flush()
            paragraphList.append(lines.map(cleanLine).joined(separator: " "))
        case .table(let lines):
            flush()
            paragraphList.append(lines.map(cleanLine).joined(separator: "\n"))
        }
    }
    flush()
    return paragraphList.joined(separator: "\n\n")
}

// MARK: Skills

let skillAbilityNames = ["Strength", "Dexterity", "Constitution", "Intelligence", "Wisdom", "Charisma"]

/// The 18 skills: which ability each belongs to, from the list in "Using Ability Scores", and the description of
/// each from the ability sections that follow, with its examples.
func readSkills() {
    var firstPage: Int?
    var lastPage: Int?
    for index in 0..<document.pageCount {
        guard let raw = document.page(at: index)?.string else { continue }
        let text = cleanLine(raw)
        if firstPage == nil, text.contains("related to each ability") { firstPage = index }
        if text.contains("(Persuasion)") { lastPage = index }
    }
    guard let firstPage, let lastPage, lastPage >= firstPage else {
        review.append("Couldn't find the skills section")
        return
    }

    var abilityOfSkill: [String: String] = [:]
    var skillOrder: [String] = []
    var ability: String?
    var listDone = false
    var blocksOfLines: [[String]] = []
    var current: [String] = []
    func flush() { if !current.isEmpty { blocksOfLines.append(current); current = [] } }

    for index in firstPage...min(lastPage + 1, document.pageCount - 1) {
        guard let page = document.page(at: index) else { continue }
        for line in readingOrder(of: page, profile: srd51Profile) {
            let text = cleanLine(line.text)
            switch line.kind {
            case .body:
                if index == firstPage, !listDone {
                    if text.hasPrefix("•"), let ability {
                        let name = text.dropFirst().trimmingCharacters(in: .whitespaces)
                        abilityOfSkill[name] = ability
                        skillOrder.append(name)
                        continue
                    }
                    if text.hasPrefix("Sometimes, the GM") { listDone = true }
                }
                current.append(line.text)
            case .heading:
                // In the list of skills, each ability is a heading with its skills beneath it.
                if index == firstPage, !listDone, skillAbilityNames.contains(text) { ability = text }
                flush()
            default:
                flush()
            }
        }
        // A description can carry on to the next page, so the page's end doesn't end the block.
    }
    flush()

    // A skill's description starts with its name, run in at the start of a paragraph or part way through one,
    // and runs to the next skill's, or to the end of the section it's in. Blocks are kept apart by a separator
    // so a description never runs across a heading.
    let separator = "\u{1F}"
    let text = blocksOfLines.map { paragraphs(from: $0, lineWidth: lineWidth).joined(separator: "\n\n") }.joined(separator: separator)
    var starts: [(name: String, start: Range<String.Index>)] = []
    var searchFrom = text.startIndex
    for name in skillOrder {
        let pattern = "(?<=^|[.!?:)\\n\u{1F}] ?)" + NSRegularExpression.escapedPattern(for: name) + "\\. (?=[A-Z])"
        guard let range = text.range(of: pattern, options: .regularExpression, range: searchFrom..<text.endIndex) else { continue }
        starts.append((name, range))
        searchFrom = range.upperBound
    }
    var descriptions: [String: [String]] = [:]
    for (index, item) in starts.enumerated() {
        var end = index + 1 < starts.count ? starts[index + 1].start.lowerBound : text.endIndex
        var body = String(text[item.start.upperBound..<end])
        if let cut = body.firstIndex(of: Character(separator)) { body = String(body[..<cut]) }
        // "Other Strength Checks." and the like begin the next part of the section.
        if let other = body.range(of: "\\s+Other [A-Za-z ]+ Checks\\. ", options: .regularExpression) { body = String(body[..<other.lowerBound]) }
        end = text.endIndex
        // A paragraph never starts in lower case: that's a line wrapped after a short line ending in a bracket.
        body = body.replacingOccurrences(of: "\n\n(?=[a-z])", with: " ", options: .regularExpression)
        descriptions[item.name] = [body.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    for name in skillOrder.sorted() {
        guard let parts = descriptions[name], let ability = abilityOfSkill[name] else {
            review.append("Skill \(name): no description found")
            continue
        }
        entries.append(PackEntry(key: "srd51.skill.\(slug(name))", kind: "skill", name: name, parent: nil,
                                 summary: parts.joined(separator: "\n\n"), attributes: [("dnd5e.ability", ability)], features: []))
    }
    report.append("Skills (\(skillOrder.count)): " + skillOrder.map { "\($0) (\(abilityOfSkill[$0] ?? "?"))" }.joined(separator: ", "))
    if skillOrder.count != 18 { review.append("Found \(skillOrder.count) skills, expected 18") }
}

readSkills()

// MARK: Backgrounds and feats

/// All the lines of the pages from the one with this heading to the heading that ends the section, in reading order.
func lines(from startHeading: (level: Int, text: String), until endHeading: (level: Int, text: String)) -> [Line] {
    var result: [Line] = []
    var started = false
    for index in 0..<document.pageCount {
        guard let page = document.page(at: index) else { continue }
        for line in readingOrder(of: page, profile: srd51Profile) {
            if case .heading(let level) = line.kind {
                if !started, level == startHeading.level, line.text == startHeading.text { started = true }
                else if started, level == endHeading.level, line.text == endHeading.text { return result }
            }
            if started { result.append(line) }
        }
    }
    return result
}

/// The SRD's one background: its proficiencies, languages and equipment, its feature, and its suggested characteristics.
func readBackgrounds() {
    let section = lines(from: (3, "Acolyte"), until: (1, "Equipment"))
    guard !section.isEmpty else { review.append("Couldn't find the Acolyte background"); return }

    let labels = ["Skill Proficiencies", "Tool Proficiencies", "Languages", "Equipment"]
    let attributeKeys = ["Skill Proficiencies": "dnd5e.backgroundSkills", "Tool Proficiencies": "dnd5e.backgroundTools",
                         "Languages": "dnd5e.backgroundLanguages", "Equipment": "dnd5e.backgroundEquipment"]
    var intro: [String] = []
    var facts: [(label: String, lines: [String])] = []
    var features: [Feature] = []
    var current: (name: String, lines: [String])?
    var tableName: String?
    var tables: [(name: String, rows: [String])] = []
    var characteristicsIntro: [String] = []
    var inCharacteristics = false

    func closeFeature() {
        if let current { features.append(Feature(name: current.name, level: nil, text: paragraphs(from: current.lines, lineWidth: lineWidth).joined(separator: "\n\n"))) }
        current = nil
    }

    for line in section.dropFirst() {
        let text = cleanLine(line.text)
        switch line.kind {
        case .heading(4):
            closeFeature()
            tableName = nil
            if text.hasPrefix("Feature: ") {
                current = (String(text.dropFirst("Feature: ".count)), [])
                inCharacteristics = false
            } else if text == "Suggested Characteristics" {
                inCharacteristics = true
            }
        case .table:
            if let range = text.range(of: "^d\\d+ ", options: .regularExpression) {
                tableName = String(text[range.upperBound...])
                tables.append((tableName ?? "", []))
            } else if !tables.isEmpty {
                // A row starts with its number. A line without one carries on the row before it.
                if text.range(of: "^\\d+ ", options: .regularExpression) != nil || tables[tables.count - 1].rows.isEmpty {
                    tables[tables.count - 1].rows.append(text)
                } else {
                    tables[tables.count - 1].rows[tables[tables.count - 1].rows.count - 1] += " " + text
                }
            }
        case .body:
            if inCharacteristics { characteristicsIntro.append(line.text) }
            else if current != nil { current?.lines.append(line.text) }
            else if let label = labels.first(where: { text.hasPrefix($0 + ":") }) {
                facts.append((label, [String(text.dropFirst(label.count + 1)).trimmingCharacters(in: .whitespaces)]))
            } else if !facts.isEmpty {
                facts[facts.count - 1].lines.append(line.text)
            } else {
                intro.append(line.text)
            }
        default:
            break
        }
    }
    closeFeature()

    func joined(_ lines: [String]) -> String {
        var text = ""
        for raw in lines { appendWrapped51(&text, cleanLine(raw)) }
        return text
    }
    var attributes: [(String, String)] = []
    for fact in facts { if let key = attributeKeys[fact.label] { attributes.append((key, joined(fact.lines))) } }
    var details = features
    let suggested = paragraphs(from: characteristicsIntro, lineWidth: lineWidth).joined(separator: "\n\n")
    if !suggested.isEmpty { details.append(Feature(name: "Suggested Characteristics", level: nil, text: suggested)) }
    for table in tables { details.append(Feature(name: table.name, level: nil, text: table.rows.joined(separator: "\n"))) }

    entries.append(PackEntry(key: "srd51.background.acolyte", kind: "background", name: "Acolyte", parent: nil,
                             summary: paragraphs(from: intro, lineWidth: lineWidth).joined(separator: "\n\n"),
                             attributes: attributes, features: details))
    report.append("Background Acolyte: " + attributes.map { "\($0.0.replacingOccurrences(of: "dnd5e.background", with: "")) = \($0.1)" }.joined(separator: "; ")
                  + " | " + details.map(\.name).joined(separator: ", "))
    if tables.count != 4 { review.append("Acolyte: found \(tables.count) suggested characteristics tables, expected 4") }
}

/// The SRD's one feat, Grappler.
func readFeats() {
    let section = lines(from: (3, "Grappler"), until: (1, "Using Ability Scores"))
    // The next chapter's heading is on the following page, so stop at the first heading of its own.
    var body: [String] = []
    for line in section.dropFirst() {
        if case .heading = line.kind { break }   // the next chapter's
        if case .body = line.kind { body.append(line.text) }
    }
    guard let first = body.first else { review.append("Couldn't find the Grappler feat"); return }
    var attributes: [(String, String)] = []
    var rest = body
    let firstText = cleanLine(first)
    if firstText.hasPrefix("Prerequisite:") {
        attributes.append(("dnd5e.featPrerequisite", String(firstText.dropFirst("Prerequisite:".count)).trimmingCharacters(in: .whitespaces)))
        rest.removeFirst()
    }
    entries.append(PackEntry(key: "srd51.feat.grappler", kind: "feat", name: "Grappler", parent: nil,
                             summary: paragraphs(from: rest, lineWidth: lineWidth).joined(separator: "\n\n"),
                             attributes: attributes, features: []))
    report.append("Feat Grappler: " + attributes.map { "\($0.0) = \($0.1)" }.joined())
}

/// Adds a line to text that wraps, rejoining a word split by a hyphen.
func appendWrapped51(_ text: inout String, _ line: String) {
    if text.isEmpty { text = line } else { text += " " + line }
}

readBackgrounds()
readFeats()

// MARK: Equipment

/// Groups of a number and a unit that rows of the equipment tables are made of.
let costPattern = "[\\d,]+ (?:cp|sp|ep|gp|pp)"
let weightPattern = "[\\d½/]+ lb\\."

/// Armor, weapons, adventuring gear and tools, from the tables of the Equipment chapter, and the equipment packs.
func readEquipment() {
    var section = ""
    var started = false
    var category = ""
    var rows: [(entry: PackEntry, kind: String)] = []
    var last: Int?                // the row a wrapped line carries on
    var pendingPacks: [String] = []
    var inPacks = false

    func attributes(_ pairs: [(String, String?)]) -> [(String, String)] { pairs.compactMap { pair in pair.1.map { (pair.0, $0) } } }

    let armorRow = try! NSRegularExpression(pattern: "^(.+?) (\(costPattern)) (\\+?\\d+(?: \\+ Dex modifier(?: \\(max 2\\))?)?) (—|Str \\d+) (—|Disadvantage) (\(weightPattern)|—)$")
    let weaponRow = try! NSRegularExpression(pattern: "^(.+?) (\(costPattern)) (—|\\d+(?:d\\d+)? (?:bludgeoning|piercing|slashing)) (\(weightPattern)|—)(?: (.*))?$")
    let gearRow = try! NSRegularExpression(pattern: "^(.+?) (\(costPattern)) (\(weightPattern)|—)$")

    func groups(_ expression: NSRegularExpression, in text: String) -> [String]? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: range) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            match.range(at: index).location == NSNotFound ? "" : (text as NSString).substring(with: match.range(at: index))
        }
    }

    for index in 0..<document.pageCount {
        guard let page = document.page(at: index) else { continue }
        for line in readingOrder(of: page, profile: srd51Profile) {
            let text = cleanLine(line.text)
            if case .heading(1) = line.kind {
                if text == "Equipment" { started = true } else if started { return finishEquipment(rows.map(\.entry), packs: pendingPacks) }
            }
            guard started else { continue }
            switch line.kind {
            case .heading(2):
                section = text
                category = ""
                inPacks = false
            case .heading(5):
                inPacks = text == "Equipment Packs"
            case .caption:
                inPacks = false   // a table's caption ends the sidebar before it
            case .table where inPacks:
                pendingPacks.append(text)
            case .table:
                guard ["Armor", "Weapons", "Adventuring Gear", "Tools"].contains(section) else { continue }
                // Rows under a heading are indented, in the left or right column.
                let indented = line.minX - (line.minX < 300 ? 57.6 : 328.6) > 5
                if section == "Armor", let g = groups(armorRow, in: text) {
                    let name = g[0]
                    rows.append((PackEntry(key: "srd51.equipment.\(slug(name))", kind: "equipment", name: name.prefix(1).uppercased() + name.dropFirst(), parent: nil, summary: "",
                        attributes: attributes([("dnd5e.equipmentCategory", category.isEmpty ? "Armor" : category), ("dnd5e.cost", g[1]), ("dnd5e.armorFormula", g[2]),
                                                ("dnd5e.strengthRequirement", g[3] == "—" ? nil : g[3]), ("dnd5e.stealth", g[4] == "—" ? nil : g[4]),
                                                ("dnd5e.weight", g[5] == "—" ? nil : g[5])]), features: []), "armor"))
                    last = rows.count - 1
                } else if section == "Weapons", let g = groups(weaponRow, in: text) {
                    let name = g[0]
                    rows.append((PackEntry(key: "srd51.equipment.\(slug(name))", kind: "equipment", name: name, parent: nil, summary: "",
                        attributes: attributes([("dnd5e.equipmentCategory", category), ("dnd5e.cost", g[1]), ("dnd5e.damage", g[2] == "—" ? nil : g[2]),
                                                ("dnd5e.weight", g[3] == "—" ? nil : g[3]), ("dnd5e.weaponProperties", g[4].isEmpty || g[4] == "—" ? nil : g[4])]), features: []), "weapon"))
                    last = rows.count - 1
                } else if section == "Adventuring Gear" || section == "Tools", let g = groups(gearRow, in: text) {
                    var name = g[0]
                    // Items grouped under a heading such as "Arcane focus" have names like "Crystal".
                    if indented, category.lowercased().hasSuffix("focus") || category.lowercased().hasSuffix("symbol") {
                        name = "\(name) (\(category.lowercased()))"
                    }
                    let group = indented && !category.isEmpty ? category : section
                    rows.append((PackEntry(key: "srd51.equipment.\(slug(name))", kind: "equipment", name: name.prefix(1).uppercased() + name.dropFirst(), parent: nil, summary: "",
                        attributes: attributes([("dnd5e.equipmentCategory", group), ("dnd5e.cost", g[1]), ("dnd5e.weight", g[2] == "—" ? nil : g[2])]), features: []), "gear"))
                    last = rows.count - 1
                } else if !indented, text.range(of: "\\d") == nil, !text.hasPrefix("*"), text.count < 40 {
                    // A heading inside the table, such as "Light Armor" or "Simple Melee Weapons".
                    category = text
                    last = nil
                } else if let at = last, rows[at].kind == "weapon" {
                    // The properties of a weapon can wrap onto another line.
                    var current = rows[at].entry.attributes.first { $0.0 == "dnd5e.weaponProperties" }?.1 ?? ""
                    current += (current.isEmpty ? "" : " ") + text
                    rows[at].entry.attributes.removeAll { $0.0 == "dnd5e.weaponProperties" }
                    rows[at].entry.attributes.append(("dnd5e.weaponProperties", current))
                }
            default:
                break
            }
        }
    }
    finishEquipment(rows.map(\.entry), packs: pendingPacks)
}

/// Adds the rows to the pack, along with the equipment packs.
func finishEquipment(_ rows: [PackEntry], packs: [String]) {
    var seen = Set<String>()
    for row in rows {
        var entry = row
        // A name can appear twice, such as "Club" as a weapon, and an item can fall under two groups.
        if !seen.insert(entry.key).inserted { review.append("Equipment “\(entry.name)” appears twice; the second was left out"); continue }
        entry.attributes.sort { $0.0 < $1.0 }
        entries.append(entry)
    }
    // The packs: "Burglar’s Pack (16 gp). Includes a backpack, ..."
    var text = ""
    for line in packs { appendWrapped51(&text, line) }
    let pattern = try! NSRegularExpression(pattern: "([A-Z][A-Za-z’ ]+ Pack) \\((\(costPattern))\\)\\. ")
    let ns = text as NSString
    let matches = pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
    for (index, match) in matches.enumerated() {
        let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
        let name = ns.substring(with: match.range(at: 1))
        let cost = ns.substring(with: match.range(at: 2))
        let contents = ns.substring(with: NSRange(location: match.range.upperBound, length: end - match.range.upperBound)).trimmingCharacters(in: .whitespaces)
        entries.append(PackEntry(key: "srd51.equipment.\(slug(name))", kind: "equipment", name: name, parent: nil, summary: contents,
                                 attributes: [("dnd5e.cost", cost), ("dnd5e.equipmentCategory", "Equipment Pack")], features: []))
    }
    let byCategory = Dictionary(grouping: entries.filter { $0.kind == "equipment" }) { entry in
        entry.attributes.first { $0.0 == "dnd5e.equipmentCategory" }?.1 ?? "?"
    }
    report.append("Equipment (\(entries.filter { $0.kind == "equipment" }.count)): " + byCategory.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.count)" }.joined(separator: ", "))
    if matches.count != 7 { review.append("Found \(matches.count) equipment packs, expected 7") }
}

readEquipment()

// MARK: Spells

/// Every spell, from the Spell Descriptions, with the classes that have it from the Spell Lists.
func readSpells() {
    var classesOfSpell: [String: [String]] = [:]
    var descriptionLines: [Line] = []
    var section = ""
    var listClass: String?
    var listLevel = 0
    var done = false

    for index in 0..<document.pageCount where !done {
        guard let page = document.page(at: index) else { continue }
        for line in readingOrder(of: page, profile: srd51Profile) {
            let text = cleanLine(line.text)
            if case .heading(let level) = line.kind {
                if level <= 2, !section.isEmpty, section == "Spell Descriptions" { done = true; break }
                if level == 2 { section = text; listClass = nil }
                else if section == "Spell Lists", level == 3, text.hasSuffix(" Spells") { listClass = String(text.dropLast(" Spells".count)) }
                else if section == "Spell Lists", level == 4 {
                    listLevel = text.hasPrefix("Cantrips") ? 0 : Int(text.prefix { $0.isNumber }) ?? 0
                }
            }
            if section == "Spell Lists", let listClass, case .body = line.kind, !text.isEmpty {
                classesOfSpell[text.replacingOccurrences(of: "'", with: "’"), default: []].append(listClass)
            }
            if section == "Spell Descriptions" { descriptionLines.append(line) }
        }
    }
    _ = listLevel

    // The type line: "2nd-level evocation", "Conjuration cantrip", "1st-level divination (ritual)".
    let typeLine = try! NSRegularExpression(pattern: "^(?:(\\d)(?:st|nd|rd|th)-level ([a-z]+)|([A-Z][a-z]+) cantrip)( \\(ritual\\))?$")
    let labels = ["Casting Time:", "Range:", "Components:", "Duration:"]
    let keys = ["dnd5e.castingTime", "dnd5e.spellRange", "dnd5e.components", "dnd5e.duration"]

    struct Draft { var name: String; var level = 0; var school = ""; var ritual = false; var facts: [String: String] = [:]; var lastLabel: String?; var paragraphs: [String] = []; var tableRows: [String] = []; var current = ""; var base = 0.0 }
    var drafts: [Draft] = []
    var draft: Draft?

    func flushParagraph() {
        guard var d = draft else { return }
        if !d.current.isEmpty { d.paragraphs.append(d.current); d.current = "" }
        if !d.tableRows.isEmpty { d.paragraphs.append(d.tableRows.joined(separator: "\n")); d.tableRows = [] }
        draft = d
    }
    func finishDraft() {
        flushParagraph()
        if let d = draft { drafts.append(d) }
        draft = nil
    }

    for line in descriptionLines {
        let text = cleanLine(line.text)
        switch line.kind {
        case .heading(4):
            finishDraft()
            draft = Draft(name: text)
        case .body, .table:
            guard var d = draft else { continue }
            if d.school.isEmpty {
                let range = NSRange(text.startIndex..., in: text)
                if let match = typeLine.firstMatch(in: text, range: range) {
                    func group(_ n: Int) -> String? { match.range(at: n).location == NSNotFound ? nil : (text as NSString).substring(with: match.range(at: n)) }
                    if let level = group(1) { d.level = Int(level) ?? 0; d.school = group(2) ?? "" } else { d.level = 0; d.school = (group(3) ?? "").lowercased() }
                    d.ritual = group(4) != nil
                    draft = d
                } else { review.append("\(d.name): type line not understood: \(text)") }
                continue
            }
            // The SRD has "Component:" once, for "Components:".
            let text = text.hasPrefix("Component: ") ? "Components: " + text.dropFirst("Component: ".count) : text
            if let label = labels.first(where: { text.hasPrefix($0) }) {
                d.facts[label] = String(text.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
                d.lastLabel = label
                draft = d
                continue
            }
            // A fact can wrap onto the next line, such as a long list of components.
            if let label = d.lastLabel, d.paragraphs.isEmpty, d.current.isEmpty, d.tableRows.isEmpty, line.minX - (line.minX < 300 ? 57.6 : 328.6) > 5, case .body = line.kind {
                appendWrapped51(&d.facts[label]!, text)
                draft = d
                continue
            }
            d.lastLabel = nil
            draft = d
            if case .table = line.kind {
                if !d.current.isEmpty { d.paragraphs.append(d.current); draft?.current = ""; draft?.paragraphs = d.paragraphs }
                draft?.tableRows.append(text)
                continue
            }
            flushTableRows(&draft)
            // The first line of a paragraph is indented, and a bullet starts one of its own.
            let indented = line.minX - (line.minX < 300 ? 57.6 : 328.6) > 5
            let previousEndedSentence = draft?.current.last.map { ".!?:”\")".contains($0) } ?? true
            if (draft?.current.isEmpty ?? true) || text.hasPrefix("•") || (indented && previousEndedSentence) {
                if let current = draft?.current, !current.isEmpty { draft?.paragraphs.append(current) }
                draft?.current = text
            } else {
                appendWrapped51(&draft!.current, text)
            }
        default:
            break
        }
    }
    finishDraft()

    func flushTableRows(_ draft: inout Draft?) {
        if let rows = draft?.tableRows, !rows.isEmpty {
            draft?.paragraphs.append(rows.joined(separator: "\n"))
            draft?.tableRows = []
        }
    }

    var unlisted: [String] = []
    for d in drafts {
        var attributes: [(String, String)] = [("dnd5e.spellLevel", String(d.level)), ("dnd5e.spellSchool", d.school.prefix(1).uppercased() + d.school.dropFirst())]
        let classes = classesOfSpell[d.name] ?? []
        if classes.isEmpty { unlisted.append(d.name) } else { attributes.append(("dnd5e.spellClasses", classes.sorted().joined(separator: ", "))) }
        for (label, key) in zip(labels, keys) {
            if let value = d.facts[label] { attributes.append((key, value)) } else { review.append("\(d.name): no \(label)") }
        }
        if d.ritual { attributes.append(("dnd5e.ritual", "true")) }
        entries.append(PackEntry(key: "srd51.spell.\(slug(d.name))", kind: "spell", name: d.name, parent: nil,
                                 summary: d.paragraphs.joined(separator: "\n\n"), attributes: attributes, features: []))
    }
    let names = Set(drafts.map(\.name))
    let missing = classesOfSpell.keys.filter { !names.contains($0) }.sorted()
    report.append("Spells (\(drafts.count)): \(Dictionary(grouping: drafts, by: \.level).sorted { $0.key < $1.key }.map { "L\($0.key) \($0.value.count)" }.joined(separator: ", "))")
    if !unlisted.isEmpty { review.append("Spells on no class list: \(unlisted.joined(separator: ", "))") }
    if !missing.isEmpty { review.append("On a class list but not described: \(missing.joined(separator: ", "))") }
}

readSpells()

// MARK: Writing the pack

let attribution = "This work includes material taken from the System Reference Document 5.1 (“SRD 5.1”) by Wizards of the Coast LLC and available at https://dnd.wizards.com/resources/systems-reference-document. The SRD 5.1 is licensed under the Creative Commons Attribution 4.0 International License available at https://creativecommons.org/licenses/by/4.0/legalcode."

var output = "{\n  \"formatVersion\": 1,\n  \"id\": \"srd51\",\n  \"name\": \"SRD 5.1\",\n  \"edition\": \"5.1 (2014 rules)\",\n  \"attribution\": \(jsonString(attribution)),\n  \"entries\": [\n"
var entryTexts: [String] = []
for entry in entries {
    var lines = ["    {", "      \"key\": \(jsonString(entry.key)),", "      \"kind\": \(jsonString(entry.kind)),", "      \"name\": \(jsonString(entry.name)),"]
    if let parent = entry.parent { lines.append("      \"parent\": \(jsonString(parent)),") }
    if !entry.summary.isEmpty { lines.append("      \"summary\": \(jsonString(entry.summary)),") }
    if !entry.attributes.isEmpty {
        lines.append("      \"attributes\": {")
        lines.append(entry.attributes.map { "        \(jsonString($0.0)): \(jsonValue(key: $0.0, value: $0.1))" }.joined(separator: ",\n"))
        lines.append("      },")
    }
    lines.append("      \"entries\": [")
    lines.append(entry.features.map { feature in
        let level = feature.level.map { ", \"level\": \($0)" } ?? ""
        return "        { \"name\": \(jsonString(feature.name))\(level), \"text\": \(jsonString(feature.text)) }"
    }.joined(separator: ",\n"))
    lines.append("      ]")
    lines.append("    }")
    entryTexts.append(lines.joined(separator: "\n"))
}
output += entryTexts.joined(separator: ",\n") + "\n  ]\n}\n"

do {
    try output.write(toFile: arguments[2], atomically: true, encoding: .utf8)
} catch {
    print("Could not write \(arguments[2]): \(error)")
    exit(2)
}

print("Wrote \(entries.count) entries to \(arguments[2]) (line width \(lineWidth))\n")
print(report.joined(separator: "\n"))
let wraps = hyphenJoins.filter { $0.hasPrefix("wrap: ") }
print("\n\(wraps.count) words were rejoined where a hyphen ended a line:")
print(wraps.map { "  " + $0.dropFirst(6) }.joined(separator: "\n"))
print("\nLeft out as sidebars: \(omittedSidebars.joined(separator: ", "))")
print("\nFor you to check (\(review.count)):")
print(review.map { "  - " + $0 }.joined(separator: "\n"))
