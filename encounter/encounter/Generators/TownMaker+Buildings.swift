//
//  TownMaker+Buildings.swift
//  encounter
//

import Foundation

extension SettlementGenerator.TownMaker {
    /// A plot of land that a building can stand on.
    struct Lot {
        var footprint: [V]
        var centre: V
        var ward: Int
    }

    /// Cuts a ward into plots by repeatedly cutting across its longest side, a little off the middle each time, until
    /// the pieces are about the size of a plot.
    mutating func subdivide(_ polygon: [V], lotArea: Double, depth: Int = 0) -> [[V]] {
        let area = Plane.area(polygon)
        guard area > lotArea * 1.7, depth < 9 else { return [polygon] }
        let along = Plane.longestEdgeDirection(polygon)
        let reach = Plane.extent(of: polygon, along: along)
        let at = reach.low + (reach.high - reach.low) * random.value(in: 0.38...0.62)
        let pieces = Plane.split(polygon, through: along * at, direction: along.perpendicular)
        guard Plane.area(pieces.left) > lotArea * 0.3, Plane.area(pieces.right) > lotArea * 0.3 else { return [polygon] }
        return subdivide(pieces.left, lotArea: lotArea, depth: depth + 1) + subdivide(pieces.right, lotArea: lotArea, depth: depth + 1)
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

    /// The inns and the merchants, if they are wanted. The generator makes no other buildings: the people running the
    /// game place the rest. Inns go by the square and the gates, where travellers come, and then spread out; merchants
    /// gather by the square and in the merchant and craft quarters, and spread out from there.
    mutating func makeVenues(
        streets: [SettlementGenerator.TownMaker.Street], districts: [Int: String], reserved: [[V]]
    ) -> [GeneratedFeature] {
        guard options.inns || options.merchants else { return [] }
        let wanted = Self.venueCounts(for: size)

        // Somewhere each could stand: a plot in a ward that is not the square or a castle's. Over a very big area (an
        // outline drawn round a county, say) the plots are bigger, so there are never tens of thousands to go through.
        let builtArea = wards.indices.filter { !wards[$0].isSquare && wards[$0].landmark != .castle }.reduce(0) { $0 + Plane.area(wards[$1].polygon) }
        let lotArea = max(320, builtArea / 2_500)
        var lots: [Lot] = []
        for index in wards.indices where !wards[index].isSquare && wards[index].landmark != .castle {
            let ward = wards[index]
            let distances: [Double] = ward.vertexIDs.indices.map { i in
                let a = ward.vertexIDs[i], b = ward.vertexIDs[(i + 1) % ward.vertexIDs.count]
                guard let edge = edgeIndex[edgeKey(a, b)] else { return 3 }
                return edges[edge].isBoundary || edges[edge].rank == .major ? 4.5 : 3
            }
            let inner = Plane.inset(ward.polygon, distances: distances)
            guard inner.count >= 3 else { continue }
            for plot in subdivide(inner, lotArea: lotArea) {
                var footprint = Plane.inset(plot, by: 1)
                guard footprint.count >= 3, Plane.area(footprint) >= 40 else { continue }
                let middle = Plane.centroid(footprint)
                // A building is never bigger than a large hall, however big the plot is.
                let footprintArea = Plane.area(footprint)
                if footprintArea > 700 {
                    let shrink = (700 / footprintArea).squareRoot()
                    footprint = footprint.map { V(x: middle.x + ($0.x - middle.x) * shrink, y: middle.y + ($0.y - middle.y) * shrink) }
                }
                guard Plane.distanceToEdge(middle, footprint) >= 2.5 else { continue }
                // Not on the river, where only a bridge would be.
                guard river.isEmpty || footprint.allSatisfy({ SettlementGenerator.distance(from: $0, toPolyline: river) >= 7 }) else { continue }
                // Not in the grounds of a landmark.
                guard !reserved.contains(where: { Plane.contains($0, middle) }) else { continue }
                lots.append(Lot(footprint: footprint, centre: middle, ward: index))
            }
        }
        guard !lots.isEmpty else { return [] }

        var taken = Set<Int>()
        var placed: [V] = []
        /// Takes the lot nearest a point that is still free and not within `gap` of one taken.
        func nearest(to point: V, gap: Double, where allowed: (Lot) -> Bool = { _ in true }) -> Int? {
            let choice = lots.indices
                .filter { index in !taken.contains(index) && allowed(lots[index]) && placed.allSatisfy { $0.distance(to: lots[index].centre) >= gap } }
                .min { lots[$0].centre.distance(to: point) < lots[$1].centre.distance(to: point) }
            if let choice { taken.insert(choice); placed.append(lots[choice].centre) }
            return choice
        }
        /// Takes the lot farthest from every one taken so far, so they spread out.
        func spreadOut(where allowed: (Lot) -> Bool) -> Int? {
            func clearance(_ lot: Lot) -> Double { placed.map { $0.distance(to: lot.centre) }.min() ?? lot.centre.distance(to: square) }
            let choice = lots.indices
                .filter { !taken.contains($0) && allowed(lots[$0]) }
                .max { (clearance(lots[$0]), -$0) < (clearance(lots[$1]), -$1) }
            if let choice { taken.insert(choice); placed.append(lots[choice].centre) }
            return choice
        }

        var inns: [Int] = [], merchants: [Int] = []
        if options.inns {
            // One by the square, then one by each gate while there are some left, then the rest spread round.
            if let lot = nearest(to: square, gap: 0) { inns.append(lot) }
            for gate in gatePoints where inns.count < wanted.inns - (wanted.inns > 3 ? 1 : 0) {
                if let lot = nearest(to: gate, gap: 30) { inns.append(lot) }
            }
            while inns.count < wanted.inns, let lot = spreadOut(where: { _ in true }) { inns.append(lot) }
        }
        if options.merchants {
            // A third by the square, then the rest spread round, in the quarters that trade where there are any.
            let trading: (Lot) -> Bool = { [wards] lot in wards[lot.ward].quarter.map { [.merchant, .craft, .harbour].contains($0) } ?? true }
            while merchants.count < max(1, wanted.merchants / 3), let lot = nearest(to: square, gap: 25, where: trading) { merchants.append(lot) }
            while merchants.count < wanted.merchants {
                guard let lot = spreadOut(where: trading) ?? spreadOut(where: { _ in true }) else { break }
                merchants.append(lot)
            }
        }

        var features: [GeneratedFeature] = []
        func description(of lot: Lot, _ kind: String) -> String {
            let street = streets.min { SettlementGenerator.distance(from: lot.centre, toPolyline: $0.points) < SettlementGenerator.distance(from: lot.centre, toPolyline: $1.points) }?.name ?? String(localized: "the square")
            let district = districts[lot.ward].map { String(localized: ", in the \($0)") } ?? ""
            return "\(kind) on \(street)\(district)."
        }
        for index in inns {
            let lot = lots[index]
            features.append(GeneratedFeature(
                name: names.inn(using: &random), placeType: "Building",
                summary: description(of: lot, String(localized: "An inn and tavern")), shape: .polygon(lot.footprint.map(\.grid))
            ))
        }
        for index in merchants {
            let lot = lots[index]
            let shop = names.shop(using: &random)
            features.append(GeneratedFeature(
                name: shop.name, placeType: "Building", summary: description(of: lot, shop.summary), shape: .polygon(lot.footprint.map(\.grid))
            ))
        }
        return features
    }
}
