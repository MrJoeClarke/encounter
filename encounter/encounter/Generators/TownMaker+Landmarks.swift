//
//  TownMaker+Landmarks.swift
//  encounter
//

import Foundation

extension SettlementGenerator.TownMaker {
    /// About how much ground a landmark covers, in square metres. A castle takes its whole ward.
    private static func area(of landmark: Landmark) -> Double {
        switch landmark {
        case .cathedral: 1_600
        case .castle: .infinity
        case .university: 2_200
        case .library: 900
        case .guildhall: 800
        case .arena: 2_600
        case .infirmary: 800
        case .wizardsTower: 120
        case .prison: 600
        }
    }

    /// Puts each landmark the creator asked for in the ward that suits it best, and says what ground it takes so no
    /// houses are built there. A ward holds one landmark.
    mutating func placeLandmarks() -> (features: [GeneratedFeature], reserved: [[V]]) {
        var features: [GeneratedFeature] = []
        var reserved: [[V]] = []
        var free = Set(wards.indices.filter { !wards[$0].isSquare })
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
            switch landmark {
            case .cathedral: return (touchesSquare(i) ? 0 : 1 + t(i)) - (quarter == .temple ? 0.3 : 0)
            case .castle: return (touchesEdge(i) ? 0 : 1) - 0.3 * t(i) - 0.5 * size(i)
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
            let ground = Plane.inset(ward.polygon, by: 5)
            guard ground.count >= 3 else { continue }
            let footprint: [V]
            switch landmark {
            case .castle:
                footprint = ground
                reserved.append(ward.polygon)
            case .wizardsTower:
                footprint = SettlementGenerator.rectangle(centre: Plane.centroid(ground), direction: V(x: 1, y: 0), width: 11, depth: 11)
                reserved.append(SettlementGenerator.rectangle(centre: Plane.centroid(ground), direction: V(x: 1, y: 0), width: 30, depth: 30))
            default:
                let wanted = min(Self.area(of: landmark), Plane.area(ground) * 0.75)
                let middle = Plane.centroid(ground)
                let scale = min(1, (wanted / max(Plane.area(ground), 1)).squareRoot())
                footprint = ground.map { middle + ($0 - middle) * scale }
                reserved.append(footprint.map { middle + ($0 - middle) * 1.25 })
            }
            features.append(GeneratedFeature(
                name: names.landmark(landmark, using: &random), placeType: "Landmark", summary: landmark.summary, shape: .polygon(footprint.map(\.grid))
            ))
        }
        return (features, reserved)
    }
}
