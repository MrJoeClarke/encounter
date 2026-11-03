//
//  TownMaker+Buildings.swift
//  encounter
//

import Foundation

extension SettlementGenerator.TownMaker {
    /// A spot on a street where a building could stand facing it.
    struct Frontage {
        /// A point on the street.
        var point: V
        /// The way the street runs there, and the way to the building from it.
        var along: V
        var inward: V
        var ward: Int
        var isMain: Bool
    }

    private enum VenueKind {
        case inn, merchant

        /// Metres along the street, and back from it.
        var size: (width: Double, depth: Double) { self == .inn ? (16, 12) : (11, 9) }
    }

    /// How many inns and how many merchants a settlement of a size has.
    static func venueCounts(for size: SettlementOptions.Size) -> (inns: Int, merchants: Int) {
        switch size {
        case .hamlet: (1, 1)
        case .village: (2, 4)
        case .town: (4, 10)
        case .city: (8, 22)
        }
    }

    /// Every spot along a street, in a ward that is not the square or a castle's, that something could face.
    private func frontages() -> [Frontage] {
        var sites: [Frontage] = []
        var length = 0.0
        let eligible = wards.indices.filter { !wards[$0].isSquare && !wards[$0].isBank && wards[$0].landmark != .castle }
        func streetEdge(_ index: Int, _ i: Int) -> Edge? {
            let ids = wards[index].vertexIDs
            guard ids.count == wards[index].polygon.count else { return nil }
            guard let e = edgeIndex[edgeKey(ids[i], ids[(i + 1) % ids.count])], !edges[e].isBoundary, !edges[e].isRiver else { return nil }
            return edges[e]
        }
        for index in eligible {
            let polygon = wards[index].polygon
            for i in polygon.indices where streetEdge(index, i) != nil { length += polygon[i].distance(to: polygon[(i + 1) % polygon.count]) }
        }
        // Over a very big area the spots are farther apart, so there are never tens of thousands.
        let step = max(14.0, length / 3_000)
        for index in eligible {
            let polygon = wards[index].polygon
            let anticlockwise = Plane.signedArea(polygon) > 0
            for i in polygon.indices {
                guard let edge = streetEdge(index, i) else { continue }
                let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                let span = a.distance(to: b)
                guard span >= 14 else { continue }
                let along = (b - a).unit
                let left = along.perpendicular
                let inward = anticlockwise ? left : left * -1
                var d = 8.0
                while d <= span - 8 {
                    sites.append(Frontage(point: a + along * d, along: along, inward: inward, ward: index, isMain: edge.rank == .major))
                    d += step
                }
            }
        }
        return sites
    }

    /// The inns and the merchants, if they are wanted. The generator makes no other buildings: the people running the
    /// game place the rest. Each faces a street. Inns go by the square and the gates, where travellers come, and then
    /// spread out; merchants gather by the square and in the merchant and craft quarters, and spread out from there.
    mutating func makeVenues(
        streets: [SettlementGenerator.TownMaker.Street], districts: [Int: String], reserved: [[V]]
    ) -> [GeneratedFeature] {
        guard options.inns || options.merchants else { return [] }
        let wanted = Self.venueCounts(for: size)
        let sites = frontages()
        guard !sites.isEmpty else { return [] }
        // The ground a building can stand on: back from every street round the ward.
        var ground: [Int: [V]] = [:]
        for index in Set(sites.map(\.ward)).sorted() { ground[index] = Plane.inset(wards[index].polygon, by: 2.5) }

        var footprints: [[V]] = []
        var taken = Set<Int>()
        var placed: [V] = []

        /// The building's outline at a spot, or nil if it doesn't fit there.
        func footprint(at site: Frontage, _ kind: VenueKind) -> [V]? {
            let size = kind.size
            let middle = site.point + site.inward * (4 + size.depth / 2)
            let corners = SettlementGenerator.rectangle(centre: middle, direction: site.along, width: size.width, depth: size.depth)
            guard let inner = ground[site.ward], inner.count >= 3, corners.allSatisfy({ Plane.contains(inner, $0) }) else { return nil }
            guard river.isEmpty || corners.allSatisfy({ SettlementGenerator.distance(from: $0, toPolyline: river) >= 7 }) else { return nil }
            guard !reserved.contains(where: { Plane.contains($0, middle) }) else { return nil }
            guard !footprints.contains(where: { SettlementGenerator.overlap($0, corners) }) else { return nil }
            return corners
        }
        /// Takes the first of the spots, in the order given, where the building fits and isn't too near one placed.
        func take(_ order: [Int], _ kind: VenueKind, gap: Double) -> (site: Int, outline: [V])? {
            for index in order where !taken.contains(index) {
                guard placed.allSatisfy({ $0.distance(to: sites[index].point) >= gap }), let outline = footprint(at: sites[index], kind) else { continue }
                taken.insert(index)
                placed.append(sites[index].point)
                footprints.append(outline)
                return (index, outline)
            }
            return nil
        }
        func nearest(to point: V, _ kind: VenueKind, gap: Double, where allowed: (Frontage) -> Bool = { _ in true }) -> (site: Int, outline: [V])? {
            take(sites.indices.filter { allowed(sites[$0]) }.sorted { (sites[$0].point.distance(to: point), $0) < (sites[$1].point.distance(to: point), $1) }, kind, gap: gap)
        }
        func spreadOut(_ kind: VenueKind, gap: Double = 20, where allowed: (Frontage) -> Bool) -> (site: Int, outline: [V])? {
            func clearance(_ site: Frontage) -> Double { placed.map { $0.distance(to: site.point) }.min() ?? site.point.distance(to: square) }
            return take(sites.indices.filter { allowed(sites[$0]) }.sorted { (clearance(sites[$0]), -$0) > (clearance(sites[$1]), -$1) }, kind, gap: gap)
        }

        var inns: [(site: Int, outline: [V])] = [], merchants: [(site: Int, outline: [V])] = []
        if options.inns {
            // One by the square, then one by each gate while there are some left, then the rest spread round.
            if let spot = nearest(to: square, .inn, gap: 0) { inns.append(spot) }
            for gate in gatePoints where inns.count < wanted.inns - (wanted.inns > 3 ? 1 : 0) {
                if let spot = nearest(to: gate, .inn, gap: 30) { inns.append(spot) }
            }
            while inns.count < wanted.inns, let spot = spreadOut(.inn, where: { _ in true }) { inns.append(spot) }
        }
        if options.merchants {
            // A third by the square, then the rest spread round, in the quarters that trade where there are any.
            let trading: (Frontage) -> Bool = { [wards] site in wards[site.ward].quarter.map { [.merchant, .craft, .harbour].contains($0) } ?? true }
            while merchants.count < max(1, wanted.merchants / 3), let spot = nearest(to: square, .merchant, gap: 25, where: trading) { merchants.append(spot) }
            while merchants.count < wanted.merchants {
                guard let spot = spreadOut(.merchant, where: trading) ?? spreadOut(.merchant, where: { _ in true }) else { break }
                merchants.append(spot)
            }
        }

        func description(of site: Frontage, _ kind: String) -> String {
            let street = streets.min { SettlementGenerator.distance(from: site.point, toPolyline: $0.points) < SettlementGenerator.distance(from: site.point, toPolyline: $1.points) }?.name ?? String(localized: "the square")
            let district = districts[site.ward].map { String(localized: ", in the \($0)") } ?? ""
            return "\(kind) on \(street)\(district)."
        }
        var features: [GeneratedFeature] = []
        for spot in inns {
            features.append(GeneratedFeature(
                name: names.inn(using: &random), placeType: "Building",
                summary: description(of: sites[spot.site], String(localized: "An inn and tavern")), shape: .polygon(spot.outline.map(\.grid))
            ))
        }
        for spot in merchants {
            let shop = names.shop(using: &random)
            features.append(GeneratedFeature(
                name: shop.name, placeType: "Building", summary: description(of: sites[spot.site], shop.summary), shape: .polygon(spot.outline.map(\.grid))
            ))
        }
        return features
    }
}
