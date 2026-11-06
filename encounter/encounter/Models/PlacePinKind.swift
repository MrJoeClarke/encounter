//
//  PlacePinKind.swift
//  encounter
//

import Foundation

/// What a pin on the map stands for, which decides its icon: a capital, a city, a town or a village; a landmark of one kind or
/// another; or some other place. Not every place has a pin: an area (a realm, a quarter, a forest) is drawn as an area and named
/// across it, a line (a river, a road, a street) is named along it, and a building is a plain shape, named only when zoomed close.
enum PlacePinKind: String, Sendable {
    case capital, city, town, village
    case cathedral, castle, university, library, guildhall, arena, infirmary, wizardsTower, prison
    case landmark, place

    /// The kind of pin a place has, or nil if it has none and is drawn as an area, a line or a building.
    static func of(_ page: Page) -> PlacePinKind? {
        let type = page.attributeText("core.placeType")
        let made = page.attributeText("gen.kind")
        switch page.geometry {
        case .line?: return nil
        case .point?, nil: return named(made, type: type)
        case .polygon?, .multiPolygon?:
            // Only a settlement or a landmark that has an outline keeps a pin, in the middle of it.
            return ["Settlement", "Landmark"].contains(type) ? named(made, type: type) : nil
        }
    }

    private static func named(_ made: String, type: String) -> PlacePinKind {
        if let kind = PlacePinKind(rawValue: made) { return kind }
        switch type {
        case "Settlement": return .town
        case "Landmark": return .landmark
        default: return .place
        }
    }

    /// The icon, as the name of an SF Symbol.
    var symbol: String {
        switch self {
        case .capital: "crown.fill"
        case .city: "building.2.fill"
        case .town: "building.fill"
        case .village: "house.fill"
        case .cathedral: "building.columns.fill"
        case .castle: "shield.fill"
        case .university: "graduationcap.fill"
        case .library: "books.vertical.fill"
        case .guildhall: "hammer.fill"
        case .arena: "flag.fill"
        case .infirmary: "cross.case.fill"
        case .wizardsTower: "wand.and.stars"
        case .prison: "lock.fill"
        case .landmark: "star.fill"
        case .place: "mappin"
        }
    }

    /// How big the pin is, in points: bigger places have bigger pins.
    var size: Double {
        switch self {
        case .capital: 30
        case .city: 26
        case .town: 22
        case .village: 18
        case .place: 20
        default: 22
        }
    }

    /// Which pins win a place on the screen when they crowd each other, from 0 to 1000: the bigger the place, the higher.
    var priority: Float {
        switch self {
        case .capital: 900
        case .city: 750
        case .town: 600
        case .castle, .cathedral, .university, .library, .guildhall, .arena, .infirmary, .wizardsTower, .prison, .landmark: 500
        case .village: 400
        case .place: 450
        }
    }
}

/// How a place is named on the map when it has no pin: across an area, or along a line.
enum PlaceLabelKind: Sendable {
    /// Across an area, at its middle.
    case area
    /// Along a line.
    case line

    /// The place types that are named, and how: areas across, lines along. A building is named too, but only when the zoom is close
    /// (see `ZoomRules`). The smaller things in a scene are not named here.
    static func of(type: String) -> PlaceLabelKind? {
        switch type {
        case "Region", "District", "Forest", "Mountains", "Water", "Lake", "Wilderness", "Garden", "Square", "Building": .area
        case "River", "Road", "Street", "Wall": .line
        default: nil
        }
    }

    /// Which names win a place on the screen when they crowd each other, from 0 to 1000: realms and seas over rivers over roads.
    static func priority(type: String) -> Float {
        switch type {
        case "Region": 1000
        case "Water": 990
        case "Lake": 800
        case "Mountains", "Forest", "Wilderness": 700
        case "District": 640
        case "River": 620
        case "Road": 420
        case "Garden", "Square": 330
        case "Building": 200
        case "Street": 300
        case "Wall": 250
        default: 100
        }
    }
}
