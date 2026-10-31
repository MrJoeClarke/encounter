//
//  LibraryPack.swift
//  encounter
//

import Foundation

/// Which edition of the content library a world uses.
enum LibraryEdition: String, CaseIterable, Identifiable, Codable {
    /// The System Reference Document 5.1 (the 2014 rules).
    case srd51
    /// The System Reference Document 5.2.1 (the 2024 rules).
    case srd52

    var id: String { rawValue }

    /// New D&D worlds start on the current rules.
    static let `default` = LibraryEdition.srd52

    var title: LocalizedStringResource {
        switch self {
        case .srd51: "5.1 (2014 rules)"
        case .srd52: "5.2.1 (2024 rules)"
        }
    }

    /// The name of the bundled pack file, without its extension.
    var resourceName: String { rawValue }

    /// The edition a library entry key belongs to. Keys start with the pack they come from, such as "srd51.race.elf".
    init?(key: String) {
        guard let edition = Self.allCases.first(where: { key.hasPrefix($0.rawValue + ".") }) else { return nil }
        self = edition
    }

    /// What this edition calls the people you play: races in 5.1, species in 5.2.1.
    var raceTermPlural: LocalizedStringResource {
        switch self {
        case .srd51: "Races"
        case .srd52: "Species"
        }
    }

    var raceTermSingular: LocalizedStringResource {
        switch self {
        case .srd51: "Race"
        case .srd52: "Species"
        }
    }
}

/// The kinds of entry a content pack holds.
nonisolated enum LibraryKind: String, Codable, Sendable, CaseIterable {
    case race
    case `class`
    case subclass
    case skill
    case background
    case feat
    case equipment
    case spell

    /// The kind of page a custom version becomes. Subclasses don't have a page kind of their own: they're
    /// copied as part of their class. Skills are fixed rules data, with no custom version. Equipment becomes an
    /// item. Spells gain theirs as their content arrives.
    var pageKind: PageKind? {
        switch self {
        case .race: .race
        case .class: .characterClass
        case .background: .background
        case .feat: .feat
        case .equipment: .item
        case .subclass, .skill, .spell: nil
        }
    }

    /// The list a subrace or subclass appears in.
    var listKind: LibraryKind {
        self == .subclass ? .class : self
    }

    /// The kinds that have a list of their own in the Library, in the order they're shown.
    static let listKinds: [LibraryKind] = [.race, .class, .background, .feat, .skill, .equipment, .spell]

    var systemImage: String {
        switch self {
        case .race: "pawprint"
        case .class, .subclass: "shield.lefthalf.filled"
        case .skill: "star.circle"
        case .background: "book.closed"
        case .feat: "medal"
        case .equipment: "backpack"
        case .spell: "wand.and.stars"
        }
    }

    /// The heading of this kind's list. Races are species in 5.2.1.
    func listTitle(in edition: LibraryEdition) -> LocalizedStringResource {
        switch self {
        case .race: edition.raceTermPlural
        case .class, .subclass: "Classes"
        case .skill: "Skills"
        case .background: "Backgrounds"
        case .feat: "Feats"
        case .equipment: "Equipment"
        case .spell: "Spells"
        }
    }
}

/// One race, species, class or subclass in a content pack. Read-only: a pack is part of the app.
nonisolated struct LibraryEntry: Decodable, Identifiable, Hashable, Sendable {
    /// Permanent. Worlds refer to library entries by this key, so it is never reused or renamed.
    var key: String
    var kind: LibraryKind
    var name: String
    /// The key of the race or class this belongs to, for subraces and subclasses.
    var parent: String?
    var summary: String
    /// Same keys as page attributes, so a custom version is a plain copy.
    var attributes: [String: AttributeValue]
    /// Traits (races) or features (classes), in order.
    var entries: [EntryValue]

    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, kind, name, parent, summary, attributes, entries
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        kind = try container.decode(LibraryKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        parent = try container.decodeIfPresent(String.self, forKey: .parent)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        attributes = (try container.decodeIfPresent([String: PackAttributeValue].self, forKey: .attributes) ?? [:])
            .mapValues(\.value)
        entries = try container.decodeIfPresent([EntryValue].self, forKey: .entries) ?? []
    }

    init(
        key: String,
        kind: LibraryKind,
        name: String,
        parent: String? = nil,
        summary: String = "",
        attributes: [String: AttributeValue] = [:],
        entries: [EntryValue] = []
    ) {
        self.key = key
        self.kind = kind
        self.name = name
        self.parent = parent
        self.summary = summary
        self.attributes = attributes
        self.entries = entries
    }
}

/// A plain JSON value in a pack's `attributes`: a string, number, boolean or list of strings.
private nonisolated struct PackAttributeValue: Decodable {
    let value: AttributeValue

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            value = .number(number)
        } else if let text = try? container.decode(String.self) {
            value = .text(text)
        } else if let list = try? container.decode([String].self) {
            value = .list(list)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported attribute value")
        }
    }
}

/// A bundled content pack: the entries for one edition, with the attribution its licence requires.
nonisolated struct LibraryPack: Decodable, Sendable {
    /// The highest `formatVersion` this app can read.
    static let supportedFormatVersion = 1

    var formatVersion: Int
    var id: String
    var name: String
    var edition: String
    /// The statement the licence requires wherever the content is shown.
    var attribution: String
    var entries: [LibraryEntry]

    private enum CodingKeys: String, CodingKey {
        case formatVersion, id, name, edition, attribution, entries
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        edition = try container.decode(String.self, forKey: .edition)
        attribution = try container.decode(String.self, forKey: .attribution)
        // An entry of a kind this app doesn't know is skipped, so a newer pack still loads.
        entries = try container.decode([FailableEntry].self, forKey: .entries).compactMap(\.entry)
    }

    init(formatVersion: Int = LibraryPack.supportedFormatVersion, id: String, name: String, edition: String, attribution: String, entries: [LibraryEntry]) {
        self.formatVersion = formatVersion
        self.id = id
        self.name = name
        self.edition = edition
        self.attribution = attribution
        self.entries = entries
    }

    /// Decodes an entry, or nil if it can't be read.
    private struct FailableEntry: Decodable {
        let entry: LibraryEntry?

        init(from decoder: any Decoder) throws {
            entry = try? LibraryEntry(from: decoder)
        }
    }
}
