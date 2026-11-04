//
//  TownMaker+Landmarks.swift
//  encounter
//

import Foundation

extension SettlementGenerator.TownMaker {
    /// About how much ground a landmark covers, in square metres. A castle takes its whole ward.
    private static func area(of landmark: Landmark) -> Double {
        switch landmark {
        case .cathedral: 3_500
        case .castle: .infinity
        case .university: 5_000
        case .library: 1_800
        case .guildhall: 1_600
        case .arena: 5_500
        case .infirmary: 1_800
        case .wizardsTower: 150
        case .prison: 1_400
        }
    }

    /// The part of a ward's ground, about `area` square metres, that backs on its longest side, so a landmark faces a street
    /// and not the middle of the block. All of it, if it isn't much bigger than that.
    static func faceTheStreet(_ ground: [V], area wanted: Double) -> [V] {
        let whole = Plane.area(ground)
        guard whole > wanted * 1.15 else { return ground }
        let polygon = Plane.anticlockwise(ground)
        var longest = 0.0
        var start = polygon[0], end = polygon[1]
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            if a.distance(to: b) > longest { longest = a.distance(to: b); start = a; end = b }
        }
        let along = (end - start).unit
        let inward = along.perpendicular
        // Deep enough to be a solid block, not a strip along the street: a bit wider than it is deep.
        let depth = (wanted / 1.4).squareRoot()
        var kept = Plane.clip(polygon, through: start + inward * depth, normal: inward * -1)
        guard kept.count >= 3 else { return ground }
        if Plane.area(kept) > wanted * 1.1 {
            let middle = Plane.centroid(kept)
            let half = wanted / depth / 2
            let trimmed = Plane.clip(Plane.clip(kept, through: middle - along * half, normal: along), through: middle + along * half, normal: along * -1)
            if trimmed.count >= 3 { kept = trimmed }
        }
        return kept
    }

    /// Puts each landmark the creator asked for in the ward that suits it best, and says what ground it takes so no
    /// houses are built there. A ward holds one landmark.
    mutating func placeLandmarks() -> (features: [GeneratedFeature], reserved: [[V]]) {
        var features: [GeneratedFeature] = []
        var reserved: [[V]] = []
        var free = Set(wards.indices.filter { !wards[$0].isSquare && !wards[$0].isBank })
        guard let plaza = wards.first(where: \.isSquare) else { return (features, reserved) }
        let plazaVertices = Set(plaza.vertexIDs)
        let boundaryVertices = Set(edges.filter(\.isBoundary).flatMap { [$0.a, $0.b] })
        let largest = wards.map { Plane.area($0.polygon) }.max() ?? 1

        func t(_ i: Int) -> Double { min(wards[i].site.distance(to: square) / radius, 1.2) }
        func gate(_ i: Int) -> Double { min((gatePoints.map { wards[i].site.distance(to: $0) }.min() ?? radius) / radius, 1.2) }
        func touchesSquare(_ i: Int) -> Bool { wards[i].vertexIDs.contains { plazaVertices.contains($0) } }
        func touchesEdge(_ i: Int) -> Bool { wards[i].vertexIDs.contains { boundaryVertices.contains($0) } }
        func size(_ i: Int) -> Double { Plane.area(wards[i].polygon) / largest }
        func score(_ landmark: Landmark, _ i: Int) -> Double {
            let quarter = wards[i].quarter
            // Every landmark but the tower wants a big ward, since it is a big building.
            let room = landmark == .wizardsTower ? 0 : -0.6 * size(i)
            return room + base(landmark, i, quarter)
        }
        func base(_ landmark: Landmark, _ i: Int, _ quarter: Quarter?) -> Double {
            switch landmark {
            case .cathedral: return (touchesSquare(i) ? 0 : 1 + t(i)) - (quarter == .temple ? 0.3 : 0)
            case .castle: return (touchesEdge(i) ? 0 : 0.25) - 0.3 * t(i) - 1.5 * size(i)
            case .university: return (quarter == .scholars ? -1 : abs(t(i) - 0.5)) + (quarter == .slum ? 1 : 0)
            case .library: return t(i) - ([.scholars, .wealthy, .temple].contains(quarter) ? 0.5 : 0)
            case .guildhall: return t(i) + (t(i) > 0.6 ? 0.5 : 0) - ([.merchant, .craft].contains(quarter) ? 0.4 : 0)
            case .arena: return -t(i) - 0.3 * size(i) + (quarter == .slum ? 0.3 : 0)
            case .infirmary: return abs(t(i) - 0.4) - (quarter == .temple ? 0.4 : 0)
            case .wizardsTower: return -t(i)
            case .prison: return gate(i) - (quarter == .military ? 0.4 : 0)
            }
        }

        var seen = Set<Landmark>()
        for landmark in options.landmarks where seen.insert(landmark).inserted {
            guard let index = free.sorted(by: { (score(landmark, $0), $0) < (score(landmark, $1), $1) }).first else { break }
            free.remove(index)
            wards[index].landmark = landmark
            let ward = wards[index]
            // The ground inside the streets round the ward.
            // (Cutting in along every edge takes too much off a ward with a curved side, so then it is shrunk evenly instead.)
            var ground = Plane.inset(ward.polygon, by: 5)
            if Plane.area(ground) < Plane.area(ward.polygon) * 0.6 {
                let middle = Plane.centroid(ward.polygon)
                ground = ward.polygon.map { middle + ($0 - middle) * 0.9 }
            }
            guard ground.count >= 3 else { continue }
            let footprint: [V]
            switch landmark {
            case .castle:
                footprint = ground
                reserved.append(ward.polygon)
            case .wizardsTower:
                // Standing on a street side of the ground, not in the middle of it.
                let polygon = Plane.anticlockwise(ground)
                let edge = polygon.indices.max { polygon[$0].distance(to: polygon[($0 + 1) % polygon.count]) < polygon[$1].distance(to: polygon[($1 + 1) % polygon.count]) } ?? 0
                let a = polygon[edge], b = polygon[(edge + 1) % polygon.count]
                let along = (b - a).unit
                let centre = (a + b) * 0.5 + along.perpendicular * 8
                footprint = SettlementGenerator.rectangle(centre: centre, direction: along, width: 11, depth: 11)
                reserved.append(SettlementGenerator.rectangle(centre: centre, direction: along, width: 30, depth: 30))
            default:
                footprint = Self.faceTheStreet(ground, area: Self.area(of: landmark))
                reserved.append(ward.polygon)
            }
            features.append(GeneratedFeature(
                name: names.landmark(landmark, using: &random), placeType: "Landmark", summary: landmark.summary, shape: .polygon(footprint.map(\.grid)),
                kind: landmark.rawValue
            ))
        }
        return (features, reserved)
    }
}
