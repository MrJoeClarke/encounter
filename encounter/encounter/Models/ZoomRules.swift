//
//  ZoomRules.swift
//  encounter
//

import Foundation

/// What shows on a map at each zoom, by kind of thing, so a far view has the realms and the cities and a near one the streets and
/// the buildings. Zoom is how much of the map is in view, as a share of its width: 1 is all of it. A rule gives the most of the map
/// that may be in view for the thing to show, so a smaller number needs a closer look. A style holds its own rules.
nonisolated struct ZoomRules: Equatable, Sendable {
    /// For each kind of pin, as `PlacePinKind.rawValue`.
    var pins: [String: Double]
    /// For the name under each kind of pin.
    var pinNames: [String: Double]
    /// For the names on areas and lines, by place type.
    var names: [String: Double]

    /// What a thing that has no rule does: always shows.
    static let always = 1.0

    /// A settlement or scene map shows a town or less, so its whole width counts for this much of a world's.
    static let townScale = 0.25

    func pin(_ kind: PlacePinKind) -> Double { pins[kind.rawValue] ?? Self.always }
    func pinName(_ kind: PlacePinKind) -> Double { pinNames[kind.rawValue] ?? Self.always }
    func name(ofType type: String) -> Double { names[type] ?? Self.always }

    /// How much of a world's width is in view, given how much of this map's width is, so that one set of rules serves a map of the
    /// world and a map of a town.
    static func view(share: Double, on kind: MapKind) -> Double { kind == .world ? share : share * townScale }

    static let standard = ZoomRules(
        pins: [
            "capital": 1, "city": 1, "town": 0.7, "village": 0.4,
            "cathedral": 0.5, "castle": 0.5, "university": 0.5, "library": 0.5, "guildhall": 0.5, "arena": 0.5,
            "infirmary": 0.5, "wizardsTower": 0.5, "prison": 0.5, "landmark": 0.5, "place": 0.5,
        ],
        pinNames: [
            "capital": 1, "city": 1, "town": 0.5, "village": 0.25,
            "cathedral": 0.35, "castle": 0.35, "university": 0.35, "library": 0.35, "guildhall": 0.35, "arena": 0.35,
            "infirmary": 0.35, "wizardsTower": 0.35, "prison": 0.35, "landmark": 0.35, "place": 0.35,
        ],
        names: [
            "Region": 1, "Water": 1, "Lake": 0.5, "Mountains": 0.6, "Forest": 0.6, "Wilderness": 0.6,
            "District": 0.3, "River": 0.5, "Road": 0.35, "Street": 0.15, "Wall": 0.1,
            "Garden": 0.1, "Square": 0.1, "Building": 0.05,
        ]
    )
}
