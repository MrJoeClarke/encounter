//
//  SettlementGenerator.swift
//  encounter
//

import Foundation

/// A gate in the settlement's edge, placed by its bearing from the middle (radians anticlockwise from east), so it
/// stays where it is when the seed or the size changes.
nonisolated struct SettlementGate: Codable, Equatable, Hashable, Sendable {
    var bearing: Double
}

/// Where the main square is, as a fraction of the settlement's radius east and north of its middle.
nonisolated struct SquareSpot: Codable, Equatable, Hashable, Sendable {
    var east: Double
    var north: Double
}

/// A kind of quarter the creator can ask for. Each takes a ward of its own, and the buildings in it take their look from it.
nonisolated enum Quarter: String, Codable, CaseIterable, Identifiable, Sendable {
    case wealthy, merchant, craft, slum, temple, military, gardens, harbour, scholars

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wealthy: String(localized: "Wealthy")
        case .merchant: String(localized: "Merchants")
        case .craft: String(localized: "Craftsmen")
        case .slum: String(localized: "Slum")
        case .temple: String(localized: "Temple")
        case .military: String(localized: "Military")
        case .gardens: String(localized: "Gardens")
        case .harbour: String(localized: "Harbour")
        case .scholars: String(localized: "Scholars")
        }
    }

    /// The name given to a district of this kind.
    var districtName: String {
        switch self {
        case .wealthy: String(localized: "Noble Quarter")
        case .merchant: String(localized: "Merchant Quarter")
        case .craft: String(localized: "Craft Quarter")
        case .slum: String(localized: "The Warrens")
        case .temple: String(localized: "Temple Quarter")
        case .military: String(localized: "Garrison Quarter")
        case .gardens: String(localized: "The Gardens")
        case .harbour: String(localized: "Harbour Quarter")
        case .scholars: String(localized: "Scholars’ Quarter")
        }
    }
}

/// A major building the creator can ask for.
nonisolated enum Landmark: String, Codable, CaseIterable, Identifiable, Sendable {
    case cathedral, castle, university, library, guildhall, arena, infirmary, wizardsTower, prison

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cathedral: String(localized: "Cathedral")
        case .castle: String(localized: "Castle")
        case .university: String(localized: "University")
        case .library: String(localized: "Great Library")
        case .guildhall: String(localized: "Guildhall")
        case .arena: String(localized: "Arena")
        case .infirmary: String(localized: "Infirmary")
        case .wizardsTower: String(localized: "Wizard’s Tower")
        case .prison: String(localized: "Prison")
        }
    }

    var summary: String {
        switch self {
        case .cathedral: String(localized: "The great church of the settlement.")
        case .castle: String(localized: "A fortress that holds the settlement.")
        case .university: String(localized: "A university, with its halls and lecture rooms.")
        case .library: String(localized: "A great library.")
        case .guildhall: String(localized: "The hall where the guilds meet.")
        case .arena: String(localized: "An arena for games and contests.")
        case .infirmary: String(localized: "A hospital for the sick and hurt.")
        case .wizardsTower: String(localized: "A tall tower where a wizard works.")
        case .prison: String(localized: "The settlement’s prison.")
        }
    }
}

/// What to generate: how big, what shape its streets take, whether it has a wall and a river, and the seed. The same
/// options always give the same settlement.
nonisolated struct SettlementOptions: Codable, Equatable, Sendable {
    enum Size: String, Codable, CaseIterable, Identifiable, Sendable {
        case hamlet, village, town, city

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hamlet: String(localized: "Hamlet")
            case .village: String(localized: "Village")
            case .town: String(localized: "Town")
            case .city: String(localized: "City")
            }
        }

        /// The size whose settlement is closest to one of this many metres from the middle to the edge.
        static func nearest(toRadius radius: Double) -> Size {
            allCases.min { abs($0.radius - radius) < abs($1.radius - radius) } ?? .village
        }

        /// Metres across the map, which is square. Room for the settlement and the roads that leave it.
        var extent: Double {
            switch self {
            case .hamlet: 400
            case .village: 700
            case .town: 1_400
            case .city: 2_600
            }
        }

        /// Metres from the middle to the edge, before the edge is made uneven.
        var radius: Double {
            switch self {
            case .hamlet: 60
            case .village: 120
            case .town: 260
            case .city: 480
            }
        }

        /// About how wide a ward is, in metres.
        var wardWidth: Double {
            switch self {
            case .hamlet: 45
            case .village: 60
            case .town: 85
            case .city: 110
            }
        }

        /// How many gates the wall has, when the creator hasn't placed them.
        var gateCount: Int {
            switch self {
            case .hamlet: 2
            case .village: 3
            case .town: 4
            case .city: 5
            }
        }
    }

    enum Layout: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Wards on a grid, turned a little, so the streets cross at right angles.
        case planned
        /// Wards in rings round the square.
        case radial
        /// Wards scattered, small near the square and larger away from it, and evened out.
        case organic

        var id: String { rawValue }

        var title: String {
            switch self {
            case .planned: String(localized: "Planned")
            case .radial: String(localized: "Radial")
            case .organic: String(localized: "Organic")
            }
        }
    }

    var size = Size.village
    var layout = Layout.organic
    var hasWalls = false
    var hasRiver = false
    var seed: UInt64 = 1
    /// Where the gates are. Empty lets the generator choose.
    var gates: [SettlementGate] = []
    /// Where the main square is. Nil puts it near the middle.
    var square: SquareSpot?
    /// The quarters to make. Nil lets the generator choose, by size.
    var quarters: [Quarter]?
    /// The major buildings to put in.
    var landmarks: [Landmark] = []
    /// Whether to put in inns and taverns, and merchants, a number suited to the size, spread round the settlement.
    var inns = true
    var merchants = true

    init(
        size: Size = .village, layout: Layout = .organic, hasWalls: Bool = false, hasRiver: Bool = false, seed: UInt64 = 1,
        gates: [SettlementGate] = [], square: SquareSpot? = nil, quarters: [Quarter]? = nil, landmarks: [Landmark] = [],
        inns: Bool = true, merchants: Bool = true
    ) {
        self.size = size
        self.layout = layout
        self.hasWalls = hasWalls
        self.hasRiver = hasRiver
        self.seed = seed
        self.gates = gates
        self.square = square
        self.quarters = quarters
        self.landmarks = landmarks
        self.inns = inns
        self.merchants = merchants
    }

    // Options saved before the later choices existed still open, with those left to the generator.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decodeIfPresent(Size.self, forKey: .size) ?? .village
        layout = try container.decodeIfPresent(Layout.self, forKey: .layout) ?? .organic
        hasWalls = try container.decodeIfPresent(Bool.self, forKey: .hasWalls) ?? false
        hasRiver = try container.decodeIfPresent(Bool.self, forKey: .hasRiver) ?? false
        seed = try container.decodeIfPresent(UInt64.self, forKey: .seed) ?? 1
        gates = try container.decodeIfPresent([SettlementGate].self, forKey: .gates) ?? []
        square = try container.decodeIfPresent(SquareSpot.self, forKey: .square)
        quarters = try container.decodeIfPresent([Quarter].self, forKey: .quarters)
        landmarks = try container.decodeIfPresent([Landmark].self, forKey: .landmarks) ?? []
        inns = try container.decodeIfPresent(Bool.self, forKey: .inns) ?? true
        merchants = try container.decodeIfPresent(Bool.self, forKey: .merchants) ?? true
    }
}

/// One thing a generator made: an area, a line, or a building. Its shape is in metres from the south-west corner of the
/// map, and it becomes a place when applied.
nonisolated struct GeneratedFeature: Equatable, Sendable {
    enum Shape: Equatable, Sendable {
        case polygon([GridPoint])
        case line([GridPoint])
    }

    var name: String
    /// A place type: District, Building, Landmark, Road, Street, River, Wall.
    var placeType: String
    var summary: String
    var shape: Shape
}

nonisolated struct GeneratedSettlement: Equatable, Sendable {
    var options: SettlementOptions
    /// Metres across and up the map.
    var extent: Double
    /// Districts first, then the wall and river, then streets, then buildings.
    var features: [GeneratedFeature]
    /// The wards the settlement was cut into, which are drawn faintly in the preview and are not places.
    var wards: [[GridPoint]] = []
    /// Where the main square and the gates are, for the preview.
    var square: GridPoint?
    var gates: [GridPoint] = []
    /// The middle of the settlement and its radius in metres, which the gates and square are placed against.
    var centre = GridPoint(easting: 0, northing: 0)
    var radius = 0.0

    func features(of type: String) -> [GeneratedFeature] { features.filter { $0.placeType == type } }
}

/// Makes a settlement as vectors, the way a town grows. The area is cut into wards, streets run from the gates to the
/// main square along the edges of the wards, and each ward is cut into plots with a building on each. It is plain
/// geometry with a seeded random source, so it is tested without any map.
nonisolated enum SettlementGenerator {
    /// Makes a settlement. With an `outline` (corners in metres from the map's south-west corner, as drawn for the place
    /// on the map above) the settlement fills it: that is its edge, its size sets how dense it is, and the size in the
    /// options is not used. `extent` is how big the map is, which for an outline comes from `extent(for:outline:)`.
    static func generate(_ options: SettlementOptions, outline: [GridPoint]? = nil, extent: Double? = nil) -> GeneratedSettlement {
        var maker = TownMaker(options: options, outline: usableOutline(outline), extent: extent)
        return maker.make()
    }

    /// Makes a settlement on a background thread, so a city doesn't hold up the screen. Nil if the task is cancelled
    /// before it finishes.
    static func generateInBackground(_ options: SettlementOptions, outline: [GridPoint]? = nil, extent: Double? = nil) async -> GeneratedSettlement? {
        let work = Task.detached(priority: .userInitiated) { generate(options, outline: outline, extent: extent) }
        return await withTaskCancellationHandler {
            let result = await work.value
            return Task.isCancelled ? nil : result
        } onCancel: {
            work.cancel()
        }
    }

    /// An outline that can be built in: at least three corners with an area.
    static func usableOutline(_ outline: [GridPoint]?) -> [GridPoint]? {
        guard let outline, outline.count >= 3, PlaceGeometry.polygon(outline).isValid || PlaceGeometry.polygon(outline).area > 0 else { return nil }
        return outline
    }

    /// How big the map has to be: the size's own, or for an outline, big enough to hold it with room round it.
    static func extent(for options: SettlementOptions, outline: [GridPoint]?) -> Double {
        guard let outline = usableOutline(outline) else { return options.size.extent }
        let shape = PlaceGeometry.polygon(outline)
        let middle = shape.centre
        let farthest = outline.map { $0.distance(to: middle) }.max() ?? 0
        let size = SettlementOptions.Size.nearest(toRadius: (shape.area / .pi).squareRoot())
        return max(size.extent, (farthest * 2.4).rounded(.up))
    }

    // MARK: Plane geometry

    struct V: Equatable {
        var x: Double
        var y: Double

        static func + (a: V, b: V) -> V { V(x: a.x + b.x, y: a.y + b.y) }
        static func - (a: V, b: V) -> V { V(x: a.x - b.x, y: a.y - b.y) }
        static func * (a: V, k: Double) -> V { V(x: a.x * k, y: a.y * k) }
        var length: Double { hypot(x, y) }
        var unit: V { length > 0 ? self * (1 / length) : V(x: 1, y: 0) }
        var perpendicular: V { V(x: -y, y: x) }
        func distance(to other: V) -> Double { (self - other).length }
        var grid: GridPoint { GridPoint(easting: x, northing: y) }
    }

    static func contains(_ polygon: [V], _ point: V) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    static func distance(from p: V, toSegment a: V, _ b: V) -> Double {
        let ab = b - a
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > 0 else { return p.distance(to: a) }
        let t = max(0, min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSquared))
        return p.distance(to: a + ab * t)
    }

    static func distance(from p: V, toPolyline line: [V]) -> Double {
        zip(line, line.dropFirst()).map { distance(from: p, toSegment: $0.0, $0.1) }.min() ?? .infinity
    }

    /// Whether two convex shapes overlap, by looking for a line between them (the separating axis test).
    static func overlap(_ a: [V], _ b: [V]) -> Bool {
        for shape in [a, b] {
            for i in shape.indices {
                let edge = shape[(i + 1) % shape.count] - shape[i]
                let axis = edge.perpendicular.unit
                let projectedA = a.map { $0.x * axis.x + $0.y * axis.y }
                let projectedB = b.map { $0.x * axis.x + $0.y * axis.y }
                if (projectedA.max() ?? 0) < (projectedB.min() ?? 0) || (projectedB.max() ?? 0) < (projectedA.min() ?? 0) { return false }
            }
        }
        return true
    }

    /// A rectangle `width` along `direction` and `depth` across, about `centre`.
    static func rectangle(centre: V, direction: V, width: Double, depth: Double) -> [V] {
        let along = direction.unit * (width / 2), across = direction.unit.perpendicular * (depth / 2)
        return [centre - along - across, centre + along - across, centre + along + across, centre - along + across]
    }

}
