//
//  NameTerms.swift
//  encounter
//

import Foundation

/// The plain words of a name, which are the user's language and not a root language's: Street, Road, Gate, Bakery, Chapel, River,
/// Kingdom, and the joining words (of, the, 's). They are English in the code, written as localised strings so that translating the
/// app translates them, and each pattern is one string with its place for the proper name in it, so a translation can put the words
/// in its own order ("Chapel of \(name)" can become "\(name)-Kapelle").
nonisolated enum NameTerms {
    /// The kinds of street, each a way to make a street name from a proper name. Which one a street gets is drawn at random.
    static var streetKinds: [(String) -> String] {
        [
            { String(localized: "\($0) Street") }, { String(localized: "\($0) Lane") }, { String(localized: "\($0) Row") },
            { String(localized: "\($0) Way") }, { String(localized: "\($0) Walk") }, { String(localized: "\($0) Road") },
            { String(localized: "\($0) Close") },
        ]
    }

    /// The kinds of trade: the shop's name from its owner's, and what it is, for the place's summary.
    static var trades: [(name: (String) -> String, summary: String)] {
        [
            ({ String(localized: "\($0)’s Bakery") }, String(localized: "A bakery")),
            ({ String(localized: "\($0)’s Tannery") }, String(localized: "A tannery")),
            ({ String(localized: "\($0)’s Chandlery") }, String(localized: "A chandler’s shop")),
            ({ String(localized: "\($0)’s Weavers") }, String(localized: "A weaver’s workshop")),
            ({ String(localized: "\($0)’s Cooperage") }, String(localized: "A cooperage")),
            ({ String(localized: "\($0)’s Apothecary") }, String(localized: "An apothecary")),
            ({ String(localized: "\($0)’s Grocer") }, String(localized: "A grocer’s")),
            ({ String(localized: "\($0)’s Fletchery") }, String(localized: "A fletcher’s shop")),
            ({ String(localized: "\($0)’s Masonry") }, String(localized: "A mason’s yard")),
            ({ String(localized: "\($0)’s Cobblers") }, String(localized: "A cobbler’s shop")),
        ]
    }

    /// The titles of a realm: "Kingdom of Carrow".
    static var realmTitles: [(String) -> String] {
        [
            { String(localized: "Kingdom of \($0)") }, { String(localized: "Realm of \($0)") }, { String(localized: "Duchy of \($0)") },
            { String(localized: "Principality of \($0)") }, { String(localized: "Dominion of \($0)") },
        ]
    }

    static func quarter(_ name: String) -> String { String(localized: "\(name) Quarter") }
    static func forge(_ owner: String) -> String { String(localized: "\(owner)’s Forge") }
    static func chapel(_ virtue: String) -> String { String(localized: "Chapel of \(virtue)") }
    static func river(_ name: String) -> String { String(localized: "River \(name)") }
    /// The name of a river without the plain word, such as "Hale" from "River Hale".
    static func bareRiverName(_ title: String) -> String {
        let prefix = river("")
        return title.hasPrefix(prefix) ? String(title.dropFirst(prefix.count)) : title
    }
    static func quay(_ river: String) -> String { String(localized: "\(river) Quay") }
    static func embankment(_ river: String) -> String { String(localized: "\(river) Embankment") }
    static func lake(_ name: String) -> String { String(localized: "Lake \(name)") }
    static func manor(_ owner: String) -> String { String(localized: "\(owner) Manor") }
    static func inn(_ name: String) -> String { String(localized: "The \(name)") }
    static func forest(_ name: String) -> String { String(localized: "The \(name) Forest") }
    static func mountains(_ name: String) -> String { String(localized: "The \(name) Mountains") }
    static func sea(_ name: String) -> String { String(localized: "The \(name) Sea") }

    /// A landmark's name from the owner, adjective and virtue drawn for it (it uses the ones it needs).
    static func landmark(_ kind: Landmark, owner: String, adjective: String, virtue: String) -> String {
        switch kind {
        case .cathedral: String(localized: "Cathedral of \(virtue)")
        case .castle: String(localized: "\(owner) Keep")
        case .university: String(localized: "University of \(owner)")
        case .library: String(localized: "The Great Library")
        case .guildhall: String(localized: "The \(adjective) Guildhall")
        case .arena: String(localized: "The \(adjective) Arena")
        case .infirmary: String(localized: "Infirmary of \(virtue)")
        case .wizardsTower: String(localized: "\(owner)’s Spire")
        case .prison: String(localized: "The \(adjective) Gaol")
        }
    }

    /// The gate itself, the road that leaves it, and the road out of a gate whose name is part of the road's: "North Gate", "North
    /// Road" and "North Gate Road". In the last, Gate is the proper name's word for a gate, from the root language.
    static func gate(_ direction: String) -> String { String(localized: "\(direction) Gate") }
    static func road(_ name: String) -> String { String(localized: "\(name) Road") }
    static func old(_ name: String) -> String { String(localized: "Old \(name)") }
    /// A name with the way it lies from somewhere in front: "North Newwick".
    static func directed(_ way: String, _ name: String) -> String { way.isEmpty ? name : String(localized: "\(way) \(name)") }

    static var marketSquare: String { String(localized: "Market Square") }
    static var marketSquareInScene: String { String(localized: "The Market Square") }
}
