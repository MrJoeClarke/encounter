//
//  WorldGenerator.swift
//  encounter
//

import Foundation

/// How the land lies in the world.
nonisolated enum WorldShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case continent, coast, peninsula, archipelago, inland

    var id: String { rawValue }

    /// Worlds saved with the shape Island, which this replaced (it came out much like a continent), open as a continent.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WorldShape(rawValue: raw) ?? .continent
    }

    var title: String {
        switch self {
        case .continent: String(localized: "Continent")
        case .coast: String(localized: "Coast")
        case .peninsula: String(localized: "Peninsula")
        case .archipelago: String(localized: "Archipelago")
        case .inland: String(localized: "Inland")
        }
    }

    var summary: String {
        switch self {
        case .continent: String(localized: "A large land with sea round its edges.")
        case .coast: String(localized: "Land stretching off the edge of the map, with sea along one side.")
        case .peninsula: String(localized: "A big land joined to the edge of the map by a neck, with sea on three sides.")
        case .archipelago: String(localized: "Islands in the sea, from one for each realm to many small ones.")
        case .inland: String(localized: "Land all over the map, with no sea.")
        }
    }

    /// How much of the map is land.
    var landShare: Double {
        switch self {
        case .continent: 0.36
        case .coast: 0.6
        case .peninsula: 0.33
        case .archipelago: 0.16
        case .inland: 1
        }
    }
}

/// How much the coast bays and juts: smooth is gentle curves, rugged is deep bays, headlands and long capes.
nonisolated enum WorldCoastline: String, Codable, CaseIterable, Identifiable, Sendable {
    case smooth, natural, rugged

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smooth: String(localized: "Smooth")
        case .natural: String(localized: "Natural")
        case .rugged: String(localized: "Rugged")
        }
    }

    /// How far, in the units the land is worked out in, the sea is let cut into the land and the land reach out, at the scale of bays
    /// and headlands.
    var bays: Double {
        switch self {
        case .smooth: 0.1
        case .natural: 0.42
        case .rugged: 0.9
        }
    }

    /// How far long arms of land reach out as capes and peninsulas.
    var capes: Double {
        switch self {
        case .smooth: 0
        case .natural: 0.25
        case .rugged: 0.6
        }
    }

    /// How rough the coast is at the finest scale.
    var detail: Double {
        switch self {
        case .smooth: 0
        case .natural: 0.07
        case .rugged: 0.2
        }
    }
}

/// How many islands there are. For an archipelago this is how many make it up.
nonisolated enum WorldIslands: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, few, many

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: String(localized: "None")
        case .few: String(localized: "Few")
        case .many: String(localized: "Many")
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
    /// Metres across and up. The defaults are round numbers of miles, which is how a world's distances are shown.
    var width = 643_737.6  // 400 miles, the unit worlds are shown in
    var shape = WorldShape.continent
    /// How many islands there are: for an archipelago, one for each realm (few) or many small ones.
    var islands = WorldIslands.few
    /// How much the coast bays and juts.
    var coastline = WorldCoastline.natural
    var seed: UInt64 = 1
    /// The number of realms, each with a capital city.
    var realms = 3
    /// About how far apart, in metres, places of a kind are from others of the same kind.
    var citySpacing = 160_934.4  // 100 miles
    var townSpacing = 80_467.2  // 50 miles
    var villageSpacing = 48_280.3  // 30 miles
    var mountains = WorldAmount.some
    var forests = WorldAmount.some
    var rivers = 4
    var locations: [WorldLocation] = []
    /// Whether the settlements already on the world map are kept and built around.
    var includeExisting = true
    /// The id of the `RootLanguage` the names are made in.
    var namingStyle = RootLanguages.englishID
    /// The languages of each realm, by realm number, with their weights. A realm with none uses `namingStyle`.
    var realmLanguages: [[LanguageWeight]] = []
    /// What each realm is like, in the user's words, by realm number. Used to suggest its languages.
    var realmDescriptions: [String] = []

    init() {}

    /// The languages the names of a realm (and of the settlements in it) are made in.
    func languages(forRealm realm: Int) -> [LanguageWeight] {
        if realm >= 0, realm < realmLanguages.count, !realmLanguages[realm].isEmpty { return realmLanguages[realm] }
        return [LanguageWeight(id: namingStyle, weight: 50)]
    }

    func description(forRealm realm: Int) -> String { realm >= 0 && realm < realmDescriptions.count ? realmDescriptions[realm] : "" }

    mutating func setDescription(_ text: String, forRealm realm: Int) {
        guard realm >= 0 else { return }
        while realmDescriptions.count <= realm { realmDescriptions.append("") }
        realmDescriptions[realm] = text
    }

    /// Sets the languages of a realm outright.
    mutating func setLanguages(_ mix: [LanguageWeight], forRealm realm: Int) {
        guard realm >= 0, !mix.isEmpty else { return }
        storeLanguages(mix, forRealm: realm)
    }

    /// Turns one language on or off for a realm. The last one on can't be turned off.
    mutating func setLanguage(_ id: String, on: Bool, forRealm realm: Int) {
        guard realm >= 0 else { return }
        var mix = languages(forRealm: realm)
        mix.set(id, on: on)
        storeLanguages(mix, forRealm: realm)
    }

    mutating func setWeight(_ weight: Int, of id: String, forRealm realm: Int) {
        var mix = languages(forRealm: realm)
        mix.setWeight(weight, of: id)
        storeLanguages(mix, forRealm: realm)
    }

    private mutating func storeLanguages(_ mix: [LanguageWeight], forRealm realm: Int) {
        while realmLanguages.count <= realm { realmLanguages.append([]) }
        realmLanguages[realm] = mix
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fresh = WorldOptions()
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? fresh.width
        shape = try container.decodeIfPresent(WorldShape.self, forKey: .shape) ?? fresh.shape
        islands = try container.decodeIfPresent(WorldIslands.self, forKey: .islands) ?? fresh.islands
        coastline = try container.decodeIfPresent(WorldCoastline.self, forKey: .coastline) ?? fresh.coastline
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
        namingStyle = try container.decodeIfPresent(String.self, forKey: .namingStyle) ?? RootLanguages.englishID
        realmLanguages = try container.decodeIfPresent([[LanguageWeight]].self, forKey: .realmLanguages) ?? []
        realmDescriptions = try container.decodeIfPresent([String].self, forKey: .realmDescriptions) ?? []
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
