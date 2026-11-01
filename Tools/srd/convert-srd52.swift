// Converts the species and classes of the official SRD 5.2.1 PDF into a content pack.
//
// Usage (from the repository root):
//   sh Tools/srd/convert.sh 52 /path/to/SRD_CC_v5.2.1.pdf encounter/encounter/Content/srd52.json
//
// The PDF isn't part of the repository. Download it from
//   https://media.dndbeyond.com/compendium-images/srd/5.2/SRD_CC_v5.2.1.pdf
//
// Text is copied from the PDF as it is. The only changes are layout ones: lines are joined, words split across
// lines are rejoined, and soft hyphens are removed. The 5.2.1 document is laid out more plainly than the 5.1 one:
// each class feature has a heading such as "Level 3: Primal Knowledge", so levels come straight from the PDF, and the
// first line of a paragraph is indented, which is how paragraphs are told apart.
//
// The tool prints a report of what it found, with anything it isn't sure about listed at the end, for a person to
// check against the PDF. Run Tools/srd/verify.sh afterwards to confirm every passage appears in the PDF.

import Foundation
import PDFKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("Usage: convert-srd52 <srd.pdf> <pack.json>")
    exit(2)
}
guard let document = PDFDocument(url: URL(fileURLWithPath: arguments[1])) else {
    print("Could not read the PDF at \(arguments[1])")
    exit(2)
}

let classNames = ["Barbarian", "Bard", "Cleric", "Druid", "Fighter", "Monk", "Paladin", "Ranger", "Rogue", "Sorcerer", "Warlock", "Wizard"]
var report: [String] = []
var review: [String] = []
var hyphenJoins: [String] = []
var mergedHeadings: [String] = []
var omittedSidebars: [String] = []

// MARK: Reading the PDF

/// The lines from the start of the Classes chapter to the end of the species descriptions, with a heading split
/// over two lines (such as "Barbarian Subclass:" and "Path of the Berserker") made one.
var lines: [Line] = []
var started = false
pages: for index in 0..<document.pageCount {
    guard let page = document.page(at: index) else { continue }
    for line in readingOrder(of: page, profile: srd52Profile) {
        if case .heading(1) = line.kind {
            if line.text == "Classes" { started = true }
            if started && line.text == "Equipment" { break pages }
        }
        guard started else { continue }
        // A subclass heading can wrap over several lines: "Sorcerer Subclass:", "Draconic", "Sorcery".
        if case .heading(let level) = line.kind, let last = lines.last, case .heading(level) = last.kind,
           last.text.hasSuffix(":") || last.text.contains("Subclass: ") {
            lines[lines.count - 1].text += " " + line.text
            mergedHeadings.append(lines[lines.count - 1].text)
        } else {
            lines.append(line)
        }
    }
}

// MARK: Building text

/// Fragments before a hyphen that make real compound words, so the hyphen stays when a line ends there.
let keptHyphenPrefixes: Set<String> = ["non", "self", "two", "one", "three", "four", "half", "well", "multi"]

/// Adds a line to text that wraps. A hyphen at the end of a line either splits a word or is part of one, such as
/// "15-foot", so it's dropped only when the word before it isn't one that keeps its hyphen.
func appendWrapped(_ current: inout String, _ text: String) {
    guard current.hasSuffix("-"), let first = text.first, first.isLowercase else {
        current += current.isEmpty ? text : " " + text
        return
    }
    let before = current.dropLast()
    let fragment = String(before.split(separator: " ").last ?? "").lowercased()
    let afterDigit = before.last?.isNumber ?? false
    if afterDigit || keptHyphenPrefixes.contains(fragment) {
        current += text
    } else {
        current.removeLast()
        current += text
        hyphenJoins.append(fragment + "|" + String(text.prefix { $0.isLetter }))
    }
}

/// Pieces of a section's text, in order: paragraphs, and tables with their captions.
struct Piece {
    var text: String
    var isTable = false
    var caption: String?
}

/// Joins lines into paragraphs. The first line of a paragraph is indented, and a bullet is a line of its own that
/// comes before its text.
final class TextBuilder {
    var pieces: [Piece] = []
    private var current = ""
    private var awaitingBulletText = false
    private var bulletTextX: Double?
    private var tableRows: [String] = []
    private var tableCaption: String?

    /// Fragments before a hyphen that make real compound words, so the hyphen stays when a line ends there.
    private static let keptPrefixes: Set<String> = ["non", "self", "two", "one", "three", "four", "half", "well", "multi"]

    func flush() {
        if !current.isEmpty { pieces.append(Piece(text: current)) }
        current = ""
        flushTable()
    }

    private func flushTable() {
        guard !tableRows.isEmpty || tableCaption != nil else { return }
        pieces.append(Piece(text: tableRows.joined(separator: "\n"), isTable: true, caption: tableCaption))
        tableRows = []
        tableCaption = nil
    }

    func addHeading(_ text: String) {
        flush()
        pieces.append(Piece(text: text))
    }

    func addCaption(_ text: String) {
        flush()
        tableCaption = text
    }

    func addTableLine(_ text: String) {
        if !current.isEmpty { pieces.append(Piece(text: current)); current = "" }
        tableRows.append(cleanLine(text))
    }

    func addBody(_ line: Line) {
        flushTableIfNeeded()
        let text = cleanLine(line.text)
        if text.isEmpty { return }
        if text == "•" {
            if !current.isEmpty { pieces.append(Piece(text: current)) }
            current = "• "
            awaitingBulletText = true
            return
        }
        if awaitingBulletText {
            current += text
            bulletTextX = line.minX
            awaitingBulletText = false
            return
        }
        let base = line.minX < 297 ? 63.0 : 313.5
        if let x = bulletTextX {
            if abs(line.minX - x) < 3 {
                join(text)
                return
            }
            bulletTextX = nil
            if line.minX < x - 3 {
                flush()
                current = text
                return
            }
        }
        // The first line of a paragraph is indented. In a list the opposite happens (the first line is flush left
        // and the rest are indented), so an indented line only starts a paragraph if the line before ended a sentence.
        let previousEndedSentence = current.last.map { ".!?:”\")".contains($0) } ?? true
        if current.isEmpty || (line.minX > base + 4 && previousEndedSentence) {
            if !current.isEmpty { pieces.append(Piece(text: current)) }
            current = text
        } else {
            join(text)
        }
    }

    private func flushTableIfNeeded() {
        if !tableRows.isEmpty || tableCaption != nil { flushTable() }
    }

    private func join(_ text: String) {
        appendWrapped(&current, text)
    }

    var text: String {
        flush()
        return pieces.map(pieceText).joined(separator: "\n\n")
    }
}

func pieceText(_ piece: Piece) -> String {
    guard piece.isTable else { return piece.text }
    return [piece.caption, piece.text.isEmpty ? nil : piece.text].compactMap { $0 }.joined(separator: "\n\n")
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

// MARK: Species

/// A paragraph that starts a trait: "Darkvision. You have...". Returns the name and the rest.
func traitStart(in text: String) -> (name: String, rest: String)? {
    guard let match = text.range(of: "^[A-Z][A-Za-z’'-]*( (of|the|and|in|to|a|[A-Z][A-Za-z’'-]*))*\\. ", options: .regularExpression) else { return nil }
    let name = String(text[match]).trimmingCharacters(in: .whitespaces)
    return (String(name.dropLast()), String(text[match.upperBound...]))
}

func firstMatch(_ pattern: String, in text: String) -> String? {
    text.range(of: pattern, options: .regularExpression).map { String(text[$0]) }
}

struct SpeciesDraft {
    var name: String
    var facts: [String] = []
    let builder = TextBuilder()
}

func finish(_ draft: SpeciesDraft) {
    draft.builder.flush()
    var summary = ""
    var traits: [Feature] = []
    for piece in draft.builder.pieces {
        if piece.isTable {
            traits.append(Feature(name: piece.caption ?? "Table", level: nil, text: piece.text))
        } else if let start = traitStart(in: piece.text) {
            traits.append(Feature(name: start.name, level: nil, text: start.rest))
        } else if traits.isEmpty {
            summary += (summary.isEmpty ? "" : "\n\n") + piece.text
        } else if traits[traits.count - 1].name.isEmpty == false, !(piece.text.hasPrefix("•") && false) {
            // A further paragraph or a bullet belongs to the trait before it.
            traits[traits.count - 1].text += "\n\n" + piece.text
        }
    }
    var attributes: [(String, String)] = []
    for fact in draft.facts {
        if fact.hasPrefix("Size:") {
            let size = fact.dropFirst("Size:".count).trimmingCharacters(in: .whitespaces)
            if let first = firstMatch("^[A-Z][a-z]+", in: size) { attributes.append(("core.raceSize", first)) }
            if size.contains(" or ") { review.append("\(draft.name): size is “\(size)”, only the first is kept as the Size field") }
        } else if fact.hasPrefix("Speed:"), let speed = firstMatch("\\d+ feet", in: fact) {
            attributes.append(("dnd5e.speed", speed))
        }
    }
    if let darkvision = traits.first(where: { $0.name == "Darkvision" }), let range = firstMatch("\\d+ feet", in: darkvision.text) {
        attributes.append(("dnd5e.darkvision", range))
    }
    entries.append(PackEntry(key: "srd52.race.\(slug(draft.name))", kind: "race", name: draft.name, parent: nil, summary: summary,
                             attributes: attributes, features: traits))
    report.append("Species \(draft.name) (\(attributes.map { $0.1 }.joined(separator: ", "))): " + traits.map(\.name).joined(separator: ", "))
    if summary.isEmpty { review.append("\(draft.name) has no introduction") }
}

// MARK: Classes

/// The labelled rows of a class's "Core Traits" table. Labels are at the left of the table and values to their right.
func coreTraits(from tableLines: [Line]) -> [String: String] {
    guard let labelX = tableLines.map(\.minX).min() else { return [:] }
    let labels = ["Primary Ability", "Hit Point Die", "Saving Throw", "Skill Proficiencies", "Weapon Proficiencies",
                  "Armor Training", "Tool Proficiencies", "Starting Equipment", "Proficiencies"]
    var found: [(label: String, y: Double, inline: String)] = []
    var values: [Line] = []
    for line in tableLines {
        let text = cleanLine(line.text)
        if line.minX < labelX + 5 {
            // Longest label first, so "Saving Throw" isn't taken for part of something else.
            if let label = labels.first(where: { text.hasPrefix($0) }) {
                found.append((label, line.y, String(text.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)))
            }
        } else if line.minX > labelX + 50 {
            values.append(line)
        }
    }
    var result: [String: String] = [:]
    for (label, _, inline) in found where !inline.isEmpty { result[label] = inline }
    // A value belongs to the lowest label that is still above it.
    for value in values {
        let owner = found.filter { $0.y >= value.y - 2 }.min { $0.y < $1.y }
        guard let owner else { continue }
        let text = cleanLine(value.text)
        let existing = result[owner.label]
        if let existing, existing.hasSuffix("-"), let first = text.first, first.isLowercase {
            result[owner.label] = String(existing.dropLast()) + text
            hyphenJoins.append(String(text.prefix(20)))
        } else {
            result[owner.label] = (existing.map { $0 + " " } ?? "") + text
        }
    }
    return result
}

struct ClassDraft {
    var name: String
    var core: [Line] = []
    var progression: [Line] = []
    var summary = TextBuilder()
    var features: [(name: String, level: Int, builder: TextBuilder)] = []
    var subclass: SubclassDraft?
}

struct SubclassDraft {
    var name: String
    var summary = TextBuilder()
    var features: [(name: String, level: Int, builder: TextBuilder)] = []
}

var currentClass: ClassDraft?

func levelHeading(_ text: String) -> (level: Int, name: String)? {
    guard let match = text.range(of: "^Level (\\d{1,2}): ", options: .regularExpression),
          let level = Int(text[match].filter(\.isNumber)) else { return nil }
    return (level, String(text[match.upperBound...]))
}

func finish(_ draft: ClassDraft) {
    let key = "srd52.class.\(slug(draft.name))"
    let traits = coreTraits(from: draft.core)
    var attributes: [(String, String)] = []
    let mapping: [(String, String)] = [("Primary Ability", "dnd5e.primaryAbility"), ("Saving Throw", "dnd5e.savingThrows"),
                                       ("Skill Proficiencies", "dnd5e.skillChoices"), ("Weapon Proficiencies", "dnd5e.weaponProficiencies"),
                                       ("Armor Training", "dnd5e.armorProficiencies"), ("Tool Proficiencies", "dnd5e.toolProficiencies"),
                                       ("Starting Equipment", "dnd5e.startingEquipment")]
    if let die = traits["Hit Point Die"], let size = firstMatch("(?<=D)\\d+", in: die) { attributes.append(("dnd5e.hitDie", "d" + size)) }
    else { review.append("\(draft.name): no hit point die found") }
    for (label, attribute) in mapping {
        if let value = traits[label] { attributes.append((attribute, value)) }
        else if label != "Tool Proficiencies" { review.append("\(draft.name): no \(label.lowercased()) found") }
    }

    // The features table lists what's gained at each level, to check the headings against.
    var rows: [Int: String] = [:]
    var rowLevel: Int?
    for line in draft.progression {
        let text = cleanLine(line.text)
        if line.minX < 120, let match = text.range(of: "^(\\d{1,2}) \\+\\d+(?!\\d)", options: .regularExpression) {
            let level = Int(text[match].split(separator: " ")[0]) ?? 0
            let words = text[match.upperBound...].split(separator: " ").filter { !$0.contains { $0.isNumber } }
            rows[level] = words.joined(separator: " ")
            rowLevel = level
        } else if let level = rowLevel, line.minX >= 110 {
            let words = text.split(separator: " ").filter { !$0.contains { $0.isNumber } }
            rows[level, default: ""] += " " + words.joined(separator: " ")
        }
    }
    if ProcessInfo.processInfo.environment["DEBUG_ROWS"] != nil { print("--- \(draft.name)"); for level in rows.keys.sorted() { print(level, rows[level] ?? "") }; print(draft.progression.map { "\($0.minX): \($0.text)" }.joined(separator: "\n")) }
    let features = draft.features.map { Feature(name: $0.name, level: $0.level, text: $0.builder.text) }
    for feature in features {
        guard let level = feature.level, let row = rows[level] else { continue }
        if !row.contains(feature.name) { review.append("\(draft.name) / \(feature.name): level \(level) in its heading, but the table row for that level doesn't list it") }
    }
    if rows.count != 20 { review.append("\(draft.name): found \(rows.count) rows in the features table, expected 20") }

    attributes += classTableAttributes(for: draft.name, edition: 52, review: &review)
    entries.append(PackEntry(key: key, kind: "class", name: draft.name, parent: nil, summary: draft.summary.text,
                             attributes: attributes, features: features))
    report.append("Class \(draft.name) (\(attributes.count) attributes): " + features.map { "\($0.name) \($0.level ?? 0)" }.joined(separator: ", "))

    if let subclass = draft.subclass {
        let subFeatures = subclass.features.map { Feature(name: $0.name, level: $0.level, text: $0.builder.text) }
        entries.append(PackEntry(key: "srd52.subclass.\(slug(subclass.name))", kind: "subclass", name: subclass.name, parent: key,
                                 summary: subclass.summary.text, attributes: [], features: subFeatures))
        report.append("  Subclass \(subclass.name): " + subFeatures.map { "\($0.name) \($0.level ?? 0)" }.joined(separator: ", "))
    } else {
        review.append("\(draft.name): no subclass found")
    }
}

// MARK: Backgrounds and feats

struct BackgroundDraft {
    var name: String
    var facts: [(label: String, text: String)] = []
}

let backgroundLabels: [(label: String, attribute: String)] = [
    ("Ability Scores", "dnd5e.backgroundAbilityScores"), ("Feat", "dnd5e.backgroundFeat"),
    ("Skill Proficiencies", "dnd5e.backgroundSkills"), ("Tool Proficiency", "dnd5e.backgroundTools"),
    ("Equipment", "dnd5e.backgroundEquipment"),
]

func finish(_ draft: BackgroundDraft) {
    var attributes: [(String, String)] = []
    for fact in draft.facts {
        if let match = backgroundLabels.first(where: { $0.label == fact.label }) { attributes.append((match.attribute, fact.text)) }
    }
    for expected in backgroundLabels where !draft.facts.contains(where: { $0.label == expected.label }) {
        review.append("\(draft.name): no “\(expected.label)” line")
    }
    entries.append(PackEntry(key: "srd52.background.\(slug(draft.name))", kind: "background", name: draft.name, parent: nil,
                             summary: "", attributes: attributes, features: []))
    report.append("Background \(draft.name): " + attributes.map { "\($0.0.replacingOccurrences(of: "dnd5e.background", with: "")) = \($0.1)" }.joined(separator: "; "))
}

struct FeatDraft {
    var name: String
    var category = ""
    let builder = TextBuilder()
}

func finish(_ draft: FeatDraft) {
    draft.builder.flush()
    var summary = ""
    var benefits: [Feature] = []
    for piece in draft.builder.pieces {
        if piece.isTable {
            benefits.append(Feature(name: piece.caption ?? "Table", level: nil, text: piece.text))
        } else if let start = traitStart(in: piece.text) {
            benefits.append(Feature(name: start.name, level: nil, text: start.rest))
        } else if benefits.isEmpty {
            summary += (summary.isEmpty ? "" : "\n\n") + piece.text
        } else {
            benefits[benefits.count - 1].text += "\n\n" + piece.text
        }
    }
    var attributes: [(String, String)] = []
    if let open = draft.category.firstIndex(of: "(") {
        attributes.append(("dnd5e.featCategory", draft.category[..<open].trimmingCharacters(in: .whitespaces)))
        let inside = draft.category[draft.category.index(after: open)...].trimmingCharacters(in: CharacterSet(charactersIn: ") "))
        attributes.append(("dnd5e.featPrerequisite", inside.replacingOccurrences(of: "Prerequisite: ", with: "")))
    } else if !draft.category.isEmpty {
        attributes.append(("dnd5e.featCategory", draft.category))
    } else {
        review.append("\(draft.name): no category line")
    }
    entries.append(PackEntry(key: "srd52.feat.\(slug(draft.name))", kind: "feat", name: draft.name, parent: nil,
                             summary: summary, attributes: attributes, features: benefits))
    report.append("Feat \(draft.name) [\(draft.category)]: " + benefits.map(\.name).joined(separator: ", "))
}

// MARK: Walking the lines

enum Mode { case skipping, classCore, classFeatures, subclass, speciesIntro, species, backgroundsIntro, backgrounds, feats }
var mode = Mode.skipping
var inSpeciesChapter = false
var species: SpeciesDraft?
var background: BackgroundDraft?
var feat: FeatDraft?
var inFeatsChapter = false
var unrecognised: [String] = []

/// The text builder that body lines currently go to, if any.
var featureBuilder: TextBuilder?
var awaitingCaptionOf: String?   // the caption of the table whose lines are coming
var inSpeciesFacts = false
var skippingBullets = false
var skippedBulletX: Double?
var coreOpen = false             // inside a class's "Core Traits" table, whose lines can be interrupted by other text

for line in lines {
    if case .body = line.kind {} else if case .heading(4) = line.kind {} else { skippingBullets = false }
    switch line.kind {
    case .heading(1):
        if let draft = currentClass { finish(draft); currentClass = nil }
        if let draft = species { finish(draft); species = nil }
        if let draft = background { finish(draft); background = nil }
        if let draft = feat { finish(draft); feat = nil }
        mode = .skipping
        featureBuilder = nil
        inSpeciesChapter = line.text == "Character Origins"
        inFeatsChapter = line.text == "Feats"
    case .heading(2):
        if classNames.contains(line.text) {
            if let draft = currentClass { finish(draft) }
            currentClass = ClassDraft(name: line.text)
            coreOpen = false
            mode = .classCore
            featureBuilder = nil
        } else if inSpeciesChapter {
            if let draft = species { finish(draft); species = nil }
            if let draft = background { finish(draft); background = nil }
            mode = line.text == "Character Backgrounds" ? .backgroundsIntro : .skipping
            featureBuilder = nil
        } else if inFeatsChapter {
            // "Feat Descriptions", which holds all the feats.
        } else {
            unrecognised.append("H2 \(line.text)")
        }
    case .heading(3):
        if currentClass != nil {
            if line.text.hasSuffix(" Class Features") {
                // The last lines of the "Core Traits" table can still follow this heading in the PDF's order.
                mode = .classFeatures
                featureBuilder = currentClass?.summary
            } else if let range = line.text.range(of: " Subclass: ") {
                let name = String(line.text[range.upperBound...])
                currentClass?.subclass = SubclassDraft(name: name)
                mode = .subclass
                featureBuilder = currentClass?.subclass?.summary
            } else if line.text.hasPrefix("Becoming a ") {
                // Its text is left out below. In the PDF's order the heading can come after the class's features have begun.
            } else {
                unrecognised.append("H3 \(line.text)")
                mode = .skipping
                featureBuilder = nil
            }
        } else if inSpeciesChapter {
            if let draft = species { finish(draft); species = nil }
            if let draft = background { finish(draft); background = nil }
            switch line.text {
            case "Species Descriptions": mode = .speciesIntro
            case "Background Descriptions": mode = .backgrounds
            default: mode = .skipping
            }
            featureBuilder = nil
        } else if inFeatsChapter {
            // A category of feat: its name is "Origin Feats", and each feat below says which it is.
            if let draft = feat { finish(draft); feat = nil }
            mode = line.text == "Parts of a Feat" ? .skipping : .feats
            featureBuilder = nil
        }
    case .heading(4):
        if currentClass != nil, ["As a Level 1 Character", "As a Multiclass Character"].contains(line.text) {
            // These explain how to take the class at level 1 or as a second class. They're left out, and in the PDF's
            // order they can land in the middle of another section, so the text around them is left as it was.
            skippingBullets = true
            skippedBulletX = nil
        } else if currentClass != nil, mode != .species, mode != .speciesIntro {
            if let (level, name) = levelHeading(line.text) {
                coreOpen = false
                // Features follow the subclass heading once there is one, and the class's own before it.
                let builder = TextBuilder()
                if currentClass?.subclass == nil { currentClass?.features.append((name, level, builder)) }
                else { currentClass?.subclass?.features.append((name, level, builder)) }
                featureBuilder = builder
            } else if featureBuilder != nil && mode != .skipping {
                // A heading inside a feature stays in its text.
                featureBuilder?.addHeading(line.text)
                unrecognised.append("H4 inside a feature: \(line.text)")
            } else {
                unrecognised.append("H4 skipped: \(line.text)")
            }
        } else if mode == .backgrounds {
            if let draft = background { finish(draft) }
            background = BackgroundDraft(name: line.text)
        } else if mode == .feats {
            if let draft = feat { finish(draft) }
            feat = FeatDraft(name: line.text)
            featureBuilder = feat?.builder
        } else if mode == .speciesIntro || mode == .species {
            if let draft = species { finish(draft) }
            species = SpeciesDraft(name: line.text)
            inSpeciesFacts = false
            featureBuilder = species?.builder
            mode = .species
        }
    case .heading(5):
        omittedSidebars.append(cleanLine(line.text))
    case .heading:
        break
    case .caption:
        let text = cleanLine(line.text)
        if let draft = currentClass, mode == .classCore, text == "Core \(draft.name) Traits" {
            coreOpen = true
        } else if let draft = currentClass, text == "\(draft.name) Features" {
            coreOpen = false
            awaitingCaptionOf = "progression"
        } else {
            awaitingCaptionOf = nil
            featureBuilder?.addCaption(text)
        }
    case .table:
        let text = cleanLine(line.text)
        if currentClass != nil, awaitingCaptionOf == "progression" || text.range(of: "^\\d{1,2} \\+\\d+(?!\\d)", options: .regularExpression) != nil, line.minX < 120 {
            currentClass?.progression.append(line)
        } else if coreOpen {
            currentClass?.core.append(line)
        } else if awaitingCaptionOf == "progression", line.minX < 330 {
            currentClass?.progression.append(line)   // a feature list that wrapped onto a second line
        } else if awaitingCaptionOf == "progression" {
            break   // the numbers at the right of a features table row
        } else {
            featureBuilder?.addTableLine(line.text)
        }
    case .body:
        awaitingCaptionOf = nil
        let text = cleanLine(line.text)
        if skippingBullets {
            if text == "•" {
                skippedBulletX = -1
                continue
            }
            if skippedBulletX == -1 {   // the first line of a bullet's text
                skippedBulletX = line.minX
                continue
            }
            if let x = skippedBulletX, abs(line.minX - x) < 3 { continue }   // still in the bullet's column
            skippingBullets = false
        }
        if mode == .backgrounds, background != nil {
            // Each fact is a line starting with its label, which can wrap onto the next lines.
            if let label = backgroundLabels.map(\.label).first(where: { text.hasPrefix($0 + ": ") }) {
                background?.facts.append((label, String(text.dropFirst(label.count + 2))))
            } else if let last = background?.facts.indices.last {
                appendWrapped(&background!.facts[last].text, text)
            }
            continue
        }
        if mode == .feats, let current = feat, current.category.isEmpty, current.builder.pieces.isEmpty,
           text.range(of: "^(Origin|General|Fighting Style|Epic Boon) Feat", options: .regularExpression) != nil {
            feat?.category = text
            continue
        }
        // A category line with a prerequisite can wrap onto the next line, until its bracket closes.
        if mode == .feats, let current = feat, current.category.contains("("), !current.category.contains(")") {
            appendWrapped(&feat!.category, text)
            continue
        }
        if mode == .species, text.hasPrefix("Creature Type:") {
            inSpeciesFacts = true
        }
        if mode == .species, inSpeciesFacts {
            // The species' creature type, size and speed, which can wrap, run up to the line that introduces its traits.
            if text.hasPrefix("As a ") || text.hasPrefix("As an ") {
                inSpeciesFacts = false
                featureBuilder?.addBody(line)
            } else if ["Creature Type:", "Size:", "Speed:"].contains(where: { text.hasPrefix($0) }) || species?.facts.isEmpty == true {
                species?.facts.append(text)
            } else if let last = species?.facts.indices.last {
                species?.facts[last] += " " + text
            }
        } else {
            featureBuilder?.addBody(line)
        }
    case .ignored:
        break
    }
}
if let draft = currentClass { finish(draft) }
if let draft = species { finish(draft) }
if let draft = background { finish(draft) }
if let draft = feat { finish(draft) }

// MARK: Skills

let skillAbilities = ["Strength", "Dexterity", "Constitution", "Intelligence", "Wisdom", "Charisma"]
let skillNames = ["Acrobatics", "Animal Handling", "Arcana", "Athletics", "Deception", "History", "Insight", "Intimidation", "Investigation",
                  "Medicine", "Nature", "Perception", "Performance", "Persuasion", "Religion", "Sleight of Hand", "Stealth", "Survival"]

/// The Skills table in "Playing the Game": each skill, its ability and an example of its use. Each row is read
/// from the cells that sit on one line of the page.
func readSkills() {
    var rows: [(y: Double, cells: [Line])] = []
    for index in 0..<document.pageCount {
        guard let page = document.page(at: index), page.string?.contains("Skill Ability Example Uses") == true else { continue }
        for line in readingOrder(of: page, profile: srd52Profile) {
            guard case .table = line.kind else { continue }
            if let at = rows.firstIndex(where: { abs($0.y - line.y) < 2 }) {
                rows[at].cells.append(line)
            } else {
                rows.append((line.y, [line]))
            }
        }
        break
    }
    var found: [PackEntry] = []
    for row in rows {
        let text = cleanLine(row.cells.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " "))
        guard let name = skillNames.first(where: { text.hasPrefix($0 + " ") }) else { continue }
        let rest = String(text.dropFirst(name.count + 1))
        guard let ability = skillAbilities.first(where: { rest.hasPrefix($0 + " ") }) else {
            review.append("Skill \(name): no ability found in “\(text)”")
            continue
        }
        found.append(PackEntry(key: "srd52.skill.\(slug(name))", kind: "skill", name: name, parent: nil,
                               summary: String(rest.dropFirst(ability.count + 1)), attributes: [("dnd5e.ability", ability)], features: []))
    }
    entries += found.sorted { $0.name < $1.name }
    report.append("Skills (\(found.count)): " + found.map { "\($0.name) (\($0.attributes.first?.1 ?? "?"))" }.joined(separator: ", "))
    if found.count != 18 { review.append("Found \(found.count) skills, expected 18") }
}

readSkills()

// MARK: Equipment

/// The weapons and armor tables, and the tools and adventuring gear, from the Equipment chapter.
func readEquipment() {
    var equipmentLines: [Line] = []
    var started = false
    pages: for index in 0..<document.pageCount {
        guard let page = document.page(at: index) else { continue }
        for line in readingOrder(of: page, profile: srd52Profile) {
            if case .heading(1) = line.kind {
                if line.text == "Equipment" { started = true } else if started { break pages }
            }
            if started { equipmentLines.append(line) }
        }
    }

    // Rows of a table are one or more lines on the same baseline, with wrapped text on lines of their own beneath.
    struct Row { var left = ""; var right = ""; var middle: [String] = []; var minX = 0.0; var italic = false }
    var tables: [String: [Row]] = [:]
    var tableName: String?
    var lastY: Double?

    var section = ""
    var subsection = ""
    var itemName: String?
    var itemCost = ""
    var itemFacts: [String] = []
    var itemBuilder = TextBuilder()
    var found: [PackEntry] = []

    func closeItem() {
        guard let name = itemName else { return }
        itemBuilder.flush()
        var attributes: [(String, String)] = [("dnd5e.equipmentCategory", subsection.isEmpty ? section : subsection), ("dnd5e.cost", itemCost)]
        var details: [Feature] = []
        var summaryPieces: [String] = []
        for piece in itemBuilder.pieces where !piece.isTable { summaryPieces.append(piece.text) }
        // A tool's lines: "Ability: Intelligence Weight: 8 lb.", "Utilize: ..." and "Craft: ..."
        var factText = ""
        for fact in itemFacts {
            if fact.hasPrefix("Ability: ") {
                let rest = String(fact.dropFirst("Ability: ".count))
                if let weight = rest.range(of: " Weight: ") {
                    attributes.append(("dnd5e.toolAbility", String(rest[..<weight.lowerBound])))
                    attributes.append(("dnd5e.weight", String(rest[weight.upperBound...])))
                } else { attributes.append(("dnd5e.toolAbility", rest)) }
            } else if fact.hasPrefix("Utilize: ") || fact.hasPrefix("Craft: ") || fact.hasPrefix("Variants: ") || fact.hasPrefix("Weight: ") {
                factText = fact
                let label = String(fact.prefix { $0 != ":" })
                details.append(Feature(name: label, level: nil, text: String(fact.dropFirst(label.count + 2))))
            }
        }
        _ = factText
        found.append(PackEntry(key: "srd52.equipment.\(slug(name))", kind: "equipment", name: name, parent: nil,
                               summary: summaryPieces.joined(separator: "\n\n"), attributes: attributes, features: details))
        itemName = nil
        itemFacts = []
        itemBuilder = TextBuilder()
    }

    for line in equipmentLines {
        let text = cleanLine(line.text)
        switch line.kind {
        case .heading(2):
            closeItem(); section = text; subsection = ""; tableName = nil
        case .heading(3):
            closeItem(); subsection = text; tableName = nil
        case .heading(4):
            // An item's heading carries its cost: "Alchemist’s Supplies (50 GP)".
            closeItem()
            guard ["Artisan’s Tools", "Other Tools", "Adventuring Gear"].contains(subsection.isEmpty ? section : subsection) || section == "Adventuring Gear" else { continue }
            if section == "Adventuring Gear" || section == "Tools", let open = text.range(of: " (", options: .backwards), text.hasSuffix(")") {
                itemName = String(text[..<open.lowerBound])
                itemCost = String(text[open.upperBound...].dropLast())
            }
        case .caption:
            closeItem()
            tableName = ["Weapons", "Armor"].contains(text) ? text : nil
            if let tableName { tables[tableName] = [] }
            lastY = nil
        case .table where tableName != nil:
            guard let name = tableName else { break }
            var rows = tables[name] ?? []
            let italic = false
            if let y = lastY, abs(y - line.y) < 2, !rows.isEmpty {
                // The other part of the row above: its right-hand cells.
                if line.minX >= 420 { rows[rows.count - 1].right = text } else { rows[rows.count - 1].left += " " + text }
            } else if line.minX > 100 {
                // A wrapped cell, which belongs between the two parts of the row above.
                if !rows.isEmpty { rows[rows.count - 1].middle.append(text) }
            } else if text.hasPrefix("Name ") || text.hasPrefix("Armor Armor Class") {
                lastY = nil
                tables[name] = rows
                continue
            } else {
                rows.append(Row(left: text, minX: line.minX, italic: italic))
            }
            lastY = line.y
            tables[name] = rows
        case .body:
            if itemName != nil {
                if ["Ability: ", "Utilize: ", "Craft: ", "Variants: ", "Weight: "].contains(where: { text.hasPrefix($0) }) {
                    itemFacts.append(text)
                } else if let last = itemFacts.indices.last, line.minX > 70, itemBuilder.pieces.isEmpty, !itemFacts.isEmpty, line.minX < 330 || line.minX > 330 {
                    appendWrapped(&itemFacts[last], text)
                } else {
                    itemBuilder.addBody(line)
                }
            }
        case .table:
            // A wrapped line of a tool's facts is set in the table's small type.
            if itemName != nil, let last = itemFacts.indices.last { appendWrapped(&itemFacts[last], text) }
        default:
            break
        }
    }
    closeItem()

    // Weapons: "Name Damage Properties Mastery Weight Cost"
    let weaponRow = try! NSRegularExpression(pattern: "^(.+?) (\\d+(?:d\\d+)?) (Bludgeoning|Piercing|Slashing) (.+) (Cleave|Graze|Nick|Push|Sap|Slow|Topple|Vex) (\\d+(?:/\\d+)? lb\\.|—) ([\\d,]+ (?:GP|SP|CP))$")
    let armorRow = try! NSRegularExpression(pattern: "^(.+?) (\\+?\\d+(?: \\+ Dex modifier(?: \\(max 2\\))?)?)(?: ?—| (Str \\d+)) (Disadvantage|—) (\\d+ lb\\.) ([\\d,]+ (?:GP|SP|CP))$")
    func groups(_ expression: NSRegularExpression, in text: String) -> [String]? {
        guard let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            match.range(at: index).location == NSNotFound ? "" : (text as NSString).substring(with: match.range(at: index))
        }
    }

    var category = ""
    for row in tables["Weapons"] ?? [] {
        let full = ([row.left] + row.middle + [row.right]).filter { !$0.isEmpty }.joined(separator: " ")
        if row.minX < 58 { category = full; continue }
        guard let g = groups(weaponRow, in: full) else { review.append("Weapon row not understood: \(full)"); continue }
        found.append(PackEntry(key: "srd52.equipment.\(slug(g[0]))", kind: "equipment", name: g[0], parent: nil, summary: "",
            attributes: [("dnd5e.equipmentCategory", category), ("dnd5e.damage", "\(g[1]) \(g[2])"), ("dnd5e.weaponProperties", g[3]),
                         ("dnd5e.weaponMastery", g[4])] + (g[5] == "—" ? [] : [("dnd5e.weight", g[5])]) + [("dnd5e.cost", g[6])], features: []))
    }
    category = ""
    for row in tables["Armor"] ?? [] {
        let full = ([row.left] + row.middle + [row.right]).filter { !$0.isEmpty }.joined(separator: " ")
        if row.minX < 70 {
            category = full.range(of: " (").map { String(full[..<$0.lowerBound]) } ?? full
            continue
        }
        guard let g = groups(armorRow, in: full) else { review.append("Armor row not understood: \(full)"); continue }
        found.append(PackEntry(key: "srd52.equipment.\(slug(g[0]))", kind: "equipment", name: g[0], parent: nil, summary: "",
            attributes: [("dnd5e.equipmentCategory", category), ("dnd5e.armorFormula", g[1])] + (g[2].isEmpty ? [] : [("dnd5e.strengthRequirement", g[2])])
                + (g[3] == "—" ? [] : [("dnd5e.stealth", g[3])]) + [("dnd5e.weight", g[4]), ("dnd5e.cost", g[5])], features: []))
    }

    var seen = Set<String>()
    for var entry in found {
        if !seen.insert(entry.key).inserted { review.append("Equipment “\(entry.name)” appears twice; the second was left out"); continue }
        entry.attributes.sort { $0.0 < $1.0 }
        entries.append(entry)
    }
    let byCategory = Dictionary(grouping: found) { $0.attributes.first { $0.0 == "dnd5e.equipmentCategory" }?.1 ?? "?" }
    report.append("Equipment (\(found.count)): " + byCategory.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.count)" }.joined(separator: ", "))
}

readEquipment()

// MARK: Spells

/// Every spell in the Spell Descriptions. A spell is recognised by its type line, such as "Level 2 Evocation (Wizard)"
/// or "Evocation Cantrip (Sorcerer, Wizard)", with the spell's name on the line before. The classes are in brackets.
func readSpells() {
    var spellLines: [Line] = []
    var started = false
    pages: for index in 0..<document.pageCount {
        guard let page = document.page(at: index) else { continue }
        for line in readingOrder(of: page, profile: srd52Profile) {
            if case .heading(2) = line.kind, line.text == "Spell Descriptions" { started = true }
            if started, case .heading(1) = line.kind { break pages }
            if started { spellLines.append(line) }
        }
    }

    let leveled = try! NSRegularExpression(pattern: "^Level (\\d) ([A-Z][a-z]+)(?: \\((.*)\\))?$")
    let cantrip = try! NSRegularExpression(pattern: "^([A-Z][a-z]+) Cantrip(?: \\((.*)\\))?$")
    func match(_ expression: NSRegularExpression, _ text: String) -> [String]? {
        guard let m = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : (text as NSString).substring(with: m.range(at: $0)) }
    }
    /// The type line starting at an index, which can wrap onto a second line, and how many lines it takes.
    func typeLine(at index: Int) -> (level: Int, school: String, classes: String, lines: Int)? {
        guard index < spellLines.count, case .body = spellLines[index].kind else { return nil }
        var text = cleanLine(spellLines[index].text)
        var count = 1
        if text.contains("("), !text.contains(")"), index + 1 < spellLines.count {
            text += " " + cleanLine(spellLines[index + 1].text)
            count = 2
        }
        if let g = match(leveled, text) { return (Int(g[0]) ?? 0, g[1], g[2], count) }
        if let g = match(cantrip, text) { return (0, g[0], g[1], count) }
        return nil
    }

    struct Draft {
        var name: String
        var level: Int
        var school: String
        var classes: String
        var facts: [String: String] = [:]
        var lastLabel: String?
        var bodyStarted = false
        let builder = TextBuilder()
    }
    let labels = ["Casting Time:", "Range:", "Components:", "Duration:"]
    let keys = ["dnd5e.castingTime", "dnd5e.spellRange", "dnd5e.components", "dnd5e.duration"]
    var drafts: [Draft] = []
    var draft: Draft?

    var i = 0
    while i < spellLines.count {
        let line = spellLines[i]
        let text = cleanLine(line.text)
        // The line before a type line is a spell's name.
        if let type = typeLine(at: i + 1), line.kind.isTextual {
            if let d = draft { drafts.append(d) }
            draft = Draft(name: text, level: type.level, school: type.school, classes: type.classes)
            i += 1 + type.lines
            continue
        }
        i += 1
        guard let d = draft else { continue }
        // The facts are in bold type, which can be set in one of two weights, so their lines come as body or table
        // lines. The PDF also says "Component:" in places, for "Components:".
        let factText = text.hasPrefix("Component: ") ? "Components: " + text.dropFirst("Component: ".count) : text
        if !d.bodyStarted, line.kind.isTextOrTable, let label = labels.first(where: { factText.hasPrefix($0) }) {
            draft?.facts[label] = String(factText.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
            draft?.lastLabel = label
            continue
        }
        switch line.kind {
        case .body:
            if !d.bodyStarted, let label = d.lastLabel, line.fontName == "GillSans-SemiBold" {
                appendWrapped(&draft!.facts[label]!, text)
            } else {
                draft?.bodyStarted = true
                d.builder.addBody(line)
            }
        case .caption:
            draft?.bodyStarted = true
            d.builder.addCaption(text)
        case .table:
            // A wrapped line of a fact, such as a long list of materials, is in the small type of a table.
            if !d.bodyStarted, let label = d.lastLabel {
                appendWrapped(&draft!.facts[label]!, text)
            } else {
                draft?.bodyStarted = true
                d.builder.addTableLine(line.text)
            }
        default:
            break
        }
    }
    if let d = draft { drafts.append(d) }

    for d in drafts {
        var attributes: [(String, String)] = [("dnd5e.spellLevel", String(d.level)), ("dnd5e.spellSchool", d.school)]
        if !d.classes.isEmpty { attributes.append(("dnd5e.spellClasses", d.classes)) }
        for (label, key) in zip(labels, keys) {
            if let value = d.facts[label] { attributes.append((key, value)) } else { review.append("\(d.name): no \(label)") }
        }
        if (d.facts["Casting Time:"] ?? "").contains("Ritual") { attributes.append(("dnd5e.ritual", "true")) }
        entries.append(PackEntry(key: "srd52.spell.\(slug(d.name))", kind: "spell", name: d.name, parent: nil,
                                 summary: d.builder.text, attributes: attributes, features: []))
    }
    report.append("Spells (\(drafts.count)): \(Dictionary(grouping: drafts, by: \.level).sorted { $0.key < $1.key }.map { "L\($0.key) \($0.value.count)" }.joined(separator: ", "))")
    let withoutClasses = drafts.filter { $0.classes.isEmpty }.map(\.name)
    if !withoutClasses.isEmpty { review.append("Spells with no class in their type line: \(withoutClasses.joined(separator: ", "))") }
}

extension LineKind {
    var isTextOrTable: Bool {
        switch self {
        case .body, .table: true
        default: false
        }
    }

    /// Whether this is a line of words, as opposed to an ignored one.
    var isTextual: Bool {
        switch self {
        case .body, .heading: true
        default: false
        }
    }
}

readSpells()

// MARK: Writing the pack

let attribution = "This work includes material from the System Reference Document 5.2.1 (“SRD 5.2.1”) by Wizards of the Coast LLC, available at https://www.dndbeyond.com/srd. The SRD 5.2.1 is licensed under the Creative Commons Attribution 4.0 International License, available at https://creativecommons.org/licenses/by/4.0/legalcode."

var output = "{\n  \"formatVersion\": 1,\n  \"id\": \"srd52\",\n  \"name\": \"SRD 5.2.1\",\n  \"edition\": \"5.2.1 (2024 rules)\",\n  \"attribution\": \(jsonString(attribution)),\n  \"entries\": [\n"
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

print("Wrote \(entries.count) entries to \(arguments[2])\n")
print(report.joined(separator: "\n"))
print("\nLeft out as sidebars: \(omittedSidebars.joined(separator: "; "))")
print("\nHeadings that were split over two lines: \(mergedHeadings.joined(separator: "; "))")
print("\nHeadings the tool didn't expect (kept in the text or skipped): \(unrecognised.joined(separator: "; "))")
print("\n\(hyphenJoins.count) words were rejoined where a hyphen ended a line (the hyphen was dropped):")
print(hyphenJoins.map { "  " + $0 }.joined(separator: "\n"))
print("\nFor you to check (\(review.count)):")
print(review.map { "  - " + $0 }.joined(separator: "\n"))
