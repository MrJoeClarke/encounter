//
//  WorldGenerator.swift
//  encounter
//

import Foundation

/// How the land lies in the world.
nonisolated enum WorldShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case continent, coast, island

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continent: String(localized: "Continent")
        case .coast: String(localized: "Coast")
        case .island: String(localized: "Island")
        }
    }

    var summary: String {
        switch self {
        case .continent: String(localized: "A large land with sea round its edges.")
        case .coast: String(localized: "Land stretching off the edge of the map, with sea along one side.")
        case .island: String(localized: "One island in the sea.")
        }
    }

    /// How much of the map is land.
    var landShare: Double {
        switch self {
        case .continent: 0.62
        case .coast: 0.6
        case .island: 0.3
        }
    }
}

/// How much of something there is.
nonisolated enum WorldAmount: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, few, some, many

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: String(localized: "None")
        case .few: String(localized: "A Little")
        case .some: String(localized: "Some")
        case .many: String(localized: "A Lot")
        }
    }

    /// The share of the land that is mountains.
    var mountainShare: Double {
        switch self {
        case .none: 0
        case .few: 0.04
        case .some: 0.09
        case .many: 0.16
        }
    }

    /// The share of the land that is forest.
    var forestShare: Double {
        switch self {
        case .none: 0
        case .few: 0.08
        case .some: 0.18
        case .many: 0.3
        }
    }
}

/// A place the user has asked for in the world.
nonisolated struct WorldLocation: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case city, town, village

        var id: String { rawValue }

        var title: String {
            switch self {
            case .city: String(localized: "City")
            case .town: String(localized: "Town")
            case .village: String(localized: "Village")
            }
        }
    }

    var id = UUID()
    var name = ""
    var kind = Kind.town
    /// The capital of a realm. Only a city can be.
    var isCapital = false
    /// Where it is, as a share of the width from the west and from the south. Nil lets the generator choose.
    var east: Double?
    var north: Double?
}

/// What to generate for a world: how big, what shape, how many realms and how thickly settled, and the seed. The same options
/// (and the same places already on the map) always give the same world.
nonisolated struct WorldOptions: Codable, Equatable, Sendable {
    /// Metres across and up.
    var width = 600_000.0
    var shape = WorldShape.continent
    var seed: UInt64 = 1
    /// The number of realms, each with a capital city.
    var realms = 3
    /// About how far apart, in metres, places of a kind are from others of the same kind.
    var citySpacing = 170_000.0
    var townSpacing = 80_000.0
    var villageSpacing = 50_000.0
    var mountains = WorldAmount.some
    var forests = WorldAmount.some
    var rivers = 4
    var locations: [WorldLocation] = []
    /// Whether the settlements already on the world map are kept and built around.
    var includeExisting = true

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fresh = WorldOptions()
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? fresh.width
        shape = try container.decodeIfPresent(WorldShape.self, forKey: .shape) ?? fresh.shape
        seed = try container.decodeIfPresent(UInt64.self, forKey: .seed) ?? fresh.seed
        realms = try container.decodeIfPresent(Int.self, forKey: .realms) ?? fresh.realms
        citySpacing = try container.decodeIfPresent(Double.self, forKey: .citySpacing) ?? fresh.citySpacing
        townSpacing = try container.decodeIfPresent(Double.self, forKey: .townSpacing) ?? fresh.townSpacing
        villageSpacing = try container.decodeIfPresent(Double.self, forKey: .villageSpacing) ?? fresh.villageSpacing
        mountains = try container.decodeIfPresent(WorldAmount.self, forKey: .mountains) ?? fresh.mountains
        forests = try container.decodeIfPresent(WorldAmount.self, forKey: .forests) ?? fresh.forests
        rivers = try container.decodeIfPresent(Int.self, forKey: .rivers) ?? fresh.rivers
        locations = try container.decodeIfPresent([WorldLocation].self, forKey: .locations) ?? []
        includeExisting = try container.decodeIfPresent(Bool.self, forKey: .includeExisting) ?? true
    }
}

/// A settlement that is already there, which the generator builds around, or one the user asked for at a spot.
nonisolated struct FixedSettlement: Equatable, Sendable {
    var name: String
    var kind: WorldLocation.Kind
    /// In metres from the south-west corner of the map.
    var position: GridPoint
    var isCapital = false
    /// Whether it is made as a new place. A place already on the map is not.
    var emit = false
}

/// What a world generator made.
nonisolated struct GeneratedWorld: Equatable, Sendable {
    var options: WorldOptions
    var extent: Double
    var features: [GeneratedFeature]

    func features(of placeType: String) -> [GeneratedFeature] { features.filter { $0.placeType == placeType } }
}

nonisolated enum WorldGenerator {
    /// The world, made from the options and the settlements already on the map.
    static func generate(_ options: WorldOptions, fixed: [FixedSettlement] = []) -> GeneratedWorld {
        var maker = WorldMaker(options: options, fixed: fixed)
        return maker.make()
    }

    /// The same, worked out away from the main actor, and nil if the work was cancelled.
    static func generateInBackground(_ options: WorldOptions, fixed: [FixedSettlement] = []) async -> GeneratedWorld? {
        let work = Task.detached(priority: .userInitiated) { generate(options, fixed: fixed) }
        return await withTaskCancellationHandler {
            let result = await work.value
            return Task.isCancelled ? nil : result
        } onCancel: {
            work.cancel()
        }
    }
}
