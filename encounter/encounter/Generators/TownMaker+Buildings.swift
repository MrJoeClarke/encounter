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
        /// Lower is better: nearer the square, with some chance in it.
        var desirability: Double
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

    /// How big a plot is in a quarter, compared with an ordinary one: the wealthy have room, and the poor are crowded.
    static func lotScale(_ quarter: Quarter?) -> Double {
        switch quarter {
        case .wealthy: 2.0
        case .slum: 0.6
        case .military: 1.6
        case .scholars: 1.3
        case .temple: 1.2
        case .gardens: 1.5
        default: 1
        }
    }

    /// Cuts every ward but the square into plots, picks the best of them, and puts a named building on each. A ward with a
    /// castle in it, and anything inside a landmark's grounds, is left alone.
    mutating func makeBuildings(
        streets: [SettlementGenerator.TownMaker.Street], districts: [Int: String], reserved: [[V]]
    ) -> [GeneratedFeature] {
        let built = wards.indices.filter { !wards[$0].isSquare && wards[$0].landmark != .castle }
        let totalArea = built.reduce(0) { $0 + Plane.area(wards[$1].polygon) }
        let baseLotArea = max(150, min(450, totalArea * 0.7 / Double(max(target, 1))))

        var lots: [Lot] = []
        for index in built {
            let ward = wards[index]
            // Set back from the streets round it: more from a main street or the wall than from a side street.
            let distances: [Double] = ward.vertexIDs.indices.map { i in
                let a = ward.vertexIDs[i], b = ward.vertexIDs[(i + 1) % ward.vertexIDs.count]
                guard let edge = edgeIndex[edgeKey(a, b)] else { return 3 }
                return edges[edge].isBoundary || edges[edge].rank == .major ? 4.5 : 3
            }
            let inner = Plane.inset(ward.polygon, distances: distances)
            guard inner.count >= 3 else { continue }
            for plot in subdivide(inner, lotArea: baseLotArea * Self.lotScale(ward.quarter)) {
                let footprint = Plane.inset(plot, by: 1)
                guard footprint.count >= 3, Plane.area(footprint) >= 28 else { continue }
                let middle = Plane.centroid(footprint)
                // Not a sliver: there has to be room to stand in.
                guard Plane.distanceToEdge(middle, footprint) >= 1.8 else { continue }
                // Not on the river, where only a bridge would be.
                guard river.isEmpty || footprint.allSatisfy({ SettlementGenerator.distance(from: $0, toPolyline: river) >= 7 }) else { continue }
                // Not in the grounds of a landmark.
                guard !reserved.contains(where: { Plane.contains($0, middle) }) else { continue }
                // Gardens are mostly open.
                if ward.quarter == .gardens, !random.chance(0.2) { continue }
                lots.append(Lot(footprint: footprint, centre: middle, desirability: middle.distance(to: square) / radius + random.value(in: -0.2...0.2), ward: index))
            }
        }
        lots.sort { $0.desirability < $1.desirability }
        let chosen = Array(lots.prefix(min(target, 900)))
        return nameBuildings(chosen, streets: streets, districts: districts)
    }

    enum Role { case house, shop, tavern, smithy, chapel, hall, workshop, warehouse, manor, hovel, barracks, scholar }

    /// What a building in a quarter is likely to be, with its odds. `t` is how far it is from the square, 0 to 1.

    static func roleWeights(in quarter: Quarter?, t: Double) -> [(Role, Double)] {
        switch quarter {
        case .wealthy: [(.manor, 0.6), (.house, 0.3), (.shop, 0.1)]
        case .merchant: [(.shop, 0.5), (.warehouse, 0.2), (.house, 0.15), (.tavern, 0.15)]
        case .craft: [(.workshop, 0.5), (.house, 0.3), (.warehouse, 0.15), (.shop, 0.05)]
        case .slum: [(.hovel, 0.8), (.house, 0.15), (.tavern, 0.05)]
        case .temple: [(.house, 0.7), (.chapel, 0.1), (.shop, 0.2)]
        case .military: [(.barracks, 0.5), (.house, 0.2), (.workshop, 0.15), (.warehouse, 0.15)]
        case .gardens: [(.house, 1)]
        case .harbour: [(.warehouse, 0.4), (.tavern, 0.15), (.shop, 0.2), (.house, 0.25)]
        case .scholars: [(.scholar, 0.5), (.house, 0.3), (.shop, 0.1), (.workshop, 0.1)]
        case nil:
            t < 0.4
                ? [(.shop, 0.45), (.house, 0.35), (.tavern, 0.06), (.workshop, 0.12), (.warehouse, 0.02)]
                : [(.house, 0.72), (.shop, 0.1), (.workshop, 0.13), (.tavern, 0.01), (.warehouse, 0.04)]
        }
    }

    /// Gives each building a role by the quarter it is in and how near the square it is, and a name that goes with it.
    mutating func nameBuildings(_ lots: [Lot], streets: [SettlementGenerator.TownMaker.Street], districts: [Int: String]) -> [GeneratedFeature] {
        // Nearest the square first: the special buildings take the best spots.
        let byDistance = lots.indices.sorted { lots[$0].centre.distance(to: square) < lots[$1].centre.distance(to: square) }
        var roles = [Role](repeating: .house, count: lots.count)
        var taken = Set<Int>()
        /// Gives a role to the best-placed lot that qualifies, or if none does, the lot at a rank by distance from the square.
        func assign(_ role: Role, preferring quarter: Quarter? = nil, fallbackRank rank: Int) {
            if let quarter, let index = byDistance.first(where: { !taken.contains($0) && wards[lots[$0].ward].quarter == quarter }) {
                roles[index] = role
                taken.insert(index)
                return
            }
            var rank = rank
            while rank < byDistance.count, taken.contains(byDistance[rank]) { rank += 1 }
            guard rank < byDistance.count else { return }
            roles[byDistance[rank]] = role
            taken.insert(byDistance[rank])
        }
        if size != .hamlet { assign(.hall, fallbackRank: 0) }
        assign(.tavern, fallbackRank: 1)
        assign(.chapel, preferring: .temple, fallbackRank: 3)
        // The smith works with the craftsmen, or out towards the edge.
        assign(.smithy, preferring: .craft, fallbackRank: Int(Double(byDistance.count) * random.value(in: 0.5...0.9)))
        for index in lots.indices where !taken.contains(index) {
            let t = lots[index].centre.distance(to: square) / radius
            roles[index] = random.pick(Self.roleWeights(in: wards[lots[index].ward].quarter, t: t))
        }

        var houseNumbers: [String: Int] = [:]
        var features: [GeneratedFeature] = []
        for index in lots.indices {
            let lot = lots[index]
            // The street it faces is the nearest one.
            let street = streets.min { SettlementGenerator.distance(from: lot.centre, toPolyline: $0.points) < SettlementGenerator.distance(from: lot.centre, toPolyline: $1.points) }?.name ?? String(localized: "the square")
            let district = districts[lot.ward].map { String(localized: ", in the \($0)") } ?? ""
            let name: String, kind: String
            func numbered(_ label: String) -> String {
                houseNumbers[street, default: 0] += 1
                return names.named("\(houseNumbers[street] ?? 1) \(street)")
            }
            switch roles[index] {
            case .house:
                name = numbered(street)
                kind = String(localized: "A house")
            case .hovel:
                name = numbered(street)
                kind = String(localized: "A crowded tenement")
            case .scholar:
                name = numbered(street)
                kind = String(localized: "A scholar’s house")
            case .manor:
                name = names.manor(using: &random)
                kind = String(localized: "A fine house with grounds")
            case .barracks:
                name = names.named(String(localized: "Barracks"))
                kind = String(localized: "Barracks for the garrison")
            case .shop, .workshop:
                let shop = names.shop(using: &random)
                name = shop.name
                kind = shop.summary
            case .tavern:
                name = names.inn(using: &random)
                kind = String(localized: "An inn and tavern")
            case .smithy:
                name = names.forge(using: &random)
                kind = String(localized: "A smithy")
            case .chapel:
                name = names.chapel(using: &random)
                kind = String(localized: "A chapel")
            case .hall:
                name = names.named(size == .village ? String(localized: "Village Hall") : String(localized: "Town Hall"))
                kind = String(localized: "The hall where the settlement is governed")
            case .warehouse:
                name = names.named(String(localized: "Warehouse on \(street)"))
                kind = String(localized: "A warehouse")
            }
            features.append(GeneratedFeature(name: name, placeType: "Building", summary: "\(kind) on \(street)\(district).", shape: .polygon(lot.footprint.map(\.grid))))
        }
        return features
    }
}
