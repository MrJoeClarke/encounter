//
//  NamingStyle.swift
//  encounter
//

import Foundation

/// How the names of a place sound: word lists and patterns for streets, quarters, inns, shops, chapels, landmarks, towns and
/// realms. A style is data (see `Content/naming.json`), so more can be added without changing the generators.
nonisolated struct NamingStyle: Codable, Identifiable, Hashable, Sendable {
    struct Trade: Codable, Hashable, Sendable {
        /// What the shop is called, such as "Bakery" or "Panetteria".
        var shop: String
        /// What it is, for the place's summary, such as "A bakery".
        var summary: String
    }

    var id: String
    var title: String
    var summary: String
    /// Words to pick from, by the name a pattern uses them under.
    var lists: [String: [String]]
    /// How a name of each kind is put together, such as "{streetStart} {streetEnd}". A kind with several patterns picks one.
    var patterns: [String: [String]]
    var trades: [Trade]

    /// The kinds of name every style must have a pattern for.
    static let requiredPatterns = [
        "street", "quarter", "inn", "forge", "shop", "chapel", "river", "manor", "settlement", "realm", "forest", "mountains", "sea",
        "marketSquare", "gateRoad", "road", "gate",
    ] + Landmark.allCases.map { "landmark.\($0.rawValue)" }

    /// Names a pattern uses that are filled in from other than a list.
    static let presetNames: Set<String> = ["shop", "surname", "adjective", "virtue"]

    /// What is wrong with the style, in words. Empty if it can be used.
    var problems: [String] {
        var found: [String] = []
        for key in Self.requiredPatterns where (patterns[key] ?? []).isEmpty { found.append("\(id): no pattern for \(key).") }
        if trades.isEmpty { found.append("\(id): no trades.") }
        for (kind, options) in patterns {
            for pattern in options {
                for name in Self.placeholders(in: pattern) {
                    // Landmarks fill surname, adjective and virtue from their own lists; shops fill the trade.
                    let isPreset = kind.hasPrefix("landmark.") ? ["surname", "adjective", "virtue"].contains(name) : (kind == "shop" && name == "shop")
                    if isPreset { continue }
                    if (lists[name] ?? []).isEmpty { found.append("\(id): pattern “\(pattern)” uses “\(name)”, which has no words.") }
                }
            }
        }
        if (lists["compass"] ?? []).count != 8 { found.append("\(id): compass needs eight words, east first and turning anticlockwise.") }
        for key in ["landmarkSurname", "landmarkAdjective", "landmarkVirtue"] where (lists[key] ?? []).isEmpty { found.append("\(id): no words for \(key).") }
        return found
    }

    /// The names between braces in a pattern, in order.
    static func placeholders(in pattern: String) -> [String] {
        var names: [String] = []
        var rest = pattern[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            names.append(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return names
    }
}

/// The styles that ship with the app, read from `Content/naming.json` the first time they are needed.
nonisolated enum NamingStyles {
    private struct File: Decodable {
        var formatVersion: Int
        var styles: [NamingStyle]
    }

    private static let token = BundleToken()
    private final class BundleToken {}

    static let all: [NamingStyle] = {
        guard let url = Bundle(for: BundleToken.self).url(forResource: "naming", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data), file.formatVersion == 1
        else { return [] }
        return file.styles.filter { $0.problems.isEmpty }
    }()

    static let englishID = "english"

    /// A style with nothing in it, used only if the file couldn't be read.
    private static let empty = NamingStyle(id: englishID, title: "English", summary: "", lists: [:], patterns: [:], trades: [])

    /// English, from which a style that lacks something borrows it.
    static let english: NamingStyle = all.first { $0.id == englishID } ?? empty

    /// The style with the id, or English if there isn't one.
    static func style(_ id: String) -> NamingStyle {
        all.first { $0.id == id } ?? english
    }
}
