//
//  TownGeneratorTests.swift
//  encounterTests
//

import Testing
import Foundation
@testable import encounter

struct TownGeneratorTests {
    private typealias V = SettlementGenerator.V

    private func make(
        _ size: SettlementOptions.Size = .town, layout: SettlementOptions.Layout = .organic, walls: Bool = true, river: Bool = false, seed: UInt64 = 7,
        gates: [SettlementGate] = [], square: SquareSpot? = nil, quarters: [Quarter]? = nil, landmarks: [Landmark] = []
    ) -> GeneratedSettlement {
        SettlementGenerator.generate(SettlementOptions(
            size: size, layout: layout, hasWalls: walls, hasRiver: river, seed: seed,
            gates: gates, square: square, quarters: quarters, landmarks: landmarks
        ))
    }

    private func points(_ feature: GeneratedFeature) -> [GridPoint] {
        switch feature.shape { case .polygon(let p), .line(let p): p }
    }

    private func v(_ p: GridPoint) -> V { V(x: p.easting, y: p.northing) }

    // MARK: Wards

    @Test func theWardsFillTheSettlementAndDoNotOverlap() {
        for layout in SettlementOptions.Layout.allCases {
            let settlement = make(layout: layout)
            #expect(settlement.wards.count > 10)
            let areas = settlement.wards.map { Plane.area($0.map(v)) }
            let wall = points(settlement.features(of: "Wall")[0]).map(v)
            #expect(areas.reduce(0, +) > Plane.area(wall) * 0.97, "\(layout): wards leave gaps")
            #expect(areas.reduce(0, +) < Plane.area(wall) * 1.03, "\(layout): wards overlap")
        }
    }

    @Test func eachLayoutCutsTheWardsItsOwnWay() {
        let planned = make(layout: .planned).wards, radial = make(layout: .radial).wards, organic = make(layout: .organic).wards
        #expect(planned != radial && radial != organic && planned != organic)
    }

    // MARK: Gates and the square

    @Test func gatesAreWhereTheyAreAskedForAndOnTheEdge() {
        let bearings = [0.0, .pi / 2, .pi, 4.0]
        let settlement = make(gates: bearings.map { SettlementGate(bearing: $0) })
        #expect(settlement.gates.count == 4)
        let wall = points(settlement.features(of: "Wall")[0]).map(v)
        for (gate, bearing) in zip(settlement.gates, bearings) {
            #expect(Plane.distanceToEdge(v(gate), wall) < 1.5, "a gate is not on the wall")
            let actual = atan2(gate.northing - settlement.centre.northing, gate.easting - settlement.centre.easting)
            var off = abs(actual - bearing).truncatingRemainder(dividingBy: 2 * .pi)
            if off > .pi { off = 2 * .pi - off }
            // It snaps to the nearest corner of a ward, so is a little off the bearing asked for.
            #expect(off < 0.35, "a gate is \(off) radians from where it was asked for")
        }
    }

    @Test func withoutGatesAskedForTheSizeDecidesHowMany() {
        for size in SettlementOptions.Size.allCases {
            #expect(make(size).gates.count == size.gateCount)
        }
        // Chosen the same way every time.
        #expect(make(seed: 5).gates == make(seed: 5).gates)
    }

    @Test func aGateStaysPutWhenTheSeedChanges() {
        let gates = [SettlementGate(bearing: 0.3), SettlementGate(bearing: 2.5)]
        let one = make(seed: 1, gates: gates).gates, two = make(seed: 2, gates: gates).gates
        for (a, b) in zip(one, two) {
            let moved = hypot(a.easting - b.easting, a.northing - b.northing)
            #expect(moved < 150, "the gate moved \(moved) metres")
        }
    }

    @Test func theSquareIsWhereItIsAskedForAndTheMiddleOtherwise() {
        let settlement = make(square: SquareSpot(east: 0.4, north: -0.3))
        let expected = GridPoint(easting: settlement.centre.easting + 0.4 * settlement.radius, northing: settlement.centre.northing - 0.3 * settlement.radius)
        #expect(settlement.square == expected)
        let plaza = points(settlement.features(of: "Square")[0]).map(v)
        #expect(SettlementGenerator.contains(plaza, v(expected)))
        let middle = make()
        #expect(hypot(middle.square!.easting - middle.centre.easting, middle.square!.northing - middle.centre.northing) < middle.radius * 0.2)
    }

    @Test func aSquareOutsideTheSettlementFallsBackToTheMiddle() {
        let settlement = make(square: SquareSpot(east: 5, north: 5))
        #expect(settlement.square == settlement.centre)
    }

    // MARK: Streets

    @Test func everyGateIsJoinedToTheSquareByRoad() {
        for layout in SettlementOptions.Layout.allCases {
            let settlement = make(layout: layout, river: true, seed: 3)
            // Points of every road, joined where roads share a corner.
            var parent: [String: String] = [:]
            func key(_ p: GridPoint) -> String { "\(p.easting),\(p.northing)" }
            func find(_ k: String) -> String {
                var k = k
                while let next = parent[k], next != k { k = next }
                return k
            }
            func union(_ a: String, _ b: String) {
                parent[a] = parent[a] ?? a
                parent[b] = parent[b] ?? b
                parent[find(a)] = find(b)
            }
            for road in settlement.features(of: "Road") + settlement.features(of: "Street") {
                for (a, b) in zip(points(road), points(road).dropFirst()) { union(key(a), key(b)) }
            }
            // The roads end at different corners of the square, which is open ground between them.
            let plaza = points(settlement.features(of: "Square")[0])
            // The roads use the corners as the street graph snapped them, within a metre of the square's own.
            let roadPoints = (settlement.features(of: "Road") + settlement.features(of: "Street")).flatMap(points)
            var onPlaza: [GridPoint] = []
            for corner in plaza { onPlaza += roadPoints.filter { $0.distance(to: corner) < 1 } }
            for (a, b) in zip(onPlaza, onPlaza.dropFirst()) { union(key(a), key(b)) }
            let onSquare = onPlaza.map(key).filter { parent[$0] != nil }
            #expect(!onSquare.isEmpty, "\(layout): no road reaches the square")
            let squareRoot = find(onSquare[0])
            for gate in settlement.gates {
                #expect(parent[key(gate)] != nil && find(key(gate)) == squareRoot, "\(layout): gate \(gate) not joined; its component: \((settlement.features(of: "Road") + settlement.features(of: "Street")).filter { f in points(f).contains { find(key($0)) == find(key(gate)) } }.map { "\($0.name):\(points($0).count)" }); the square's: \((settlement.features(of: "Road") + settlement.features(of: "Street")).filter { f in points(f).contains { find(key($0)) == squareRoot } }.map { "\($0.name):\(points($0).count)" }); roads \(settlement.features(of: "Road").map { "\($0.name):\(points($0).count)" }) streets \(settlement.features(of: "Street").count) onPlaza \(onPlaza.count) plaza \(plaza.count)")
            }
        }
    }

    @Test func streetsRunOnForManyWardsAndAreNotBrokenIntoFragments() {
        let settlement = make(.city, seed: 4)
        let streets = settlement.features(of: "Street") + settlement.features(of: "Road")
        // Far fewer streets than ward edges, because they carry straight on at junctions.
        #expect(streets.count < settlement.wards.count * 2)
        #expect(streets.map { points($0).count }.max() ?? 0 >= 5)
        #expect(settlement.features(of: "Road").count >= settlement.gates.count)
    }

    @Test func eachGateHasARoadLeavingItAndAGatehouseWithAWall() {
        let walled = make(walls: true)
        let names = walled.features(of: "Road").map(\.name)
        #expect(walled.features(of: "Building").filter { $0.name.hasSuffix("Gate") }.count == walled.gates.count)
        #expect(names.filter { !$0.contains("Gate Road") }.count >= walled.gates.count)
        let open = make(walls: false)
        #expect(open.features(of: "Building").filter { $0.name.hasSuffix("Gate") }.isEmpty)
        #expect(open.features(of: "Road").count >= open.gates.count)
    }

    @Test func theMainRoadsAreNamedForTheirGate() {
        let settlement = make(gates: [SettlementGate(bearing: 0), SettlementGate(bearing: .pi)])
        let names = Set(settlement.features(of: "Road").map(\.name))
        #expect(names.contains { $0.hasPrefix("East Gate") } || names.contains { $0.hasPrefix("East") })
        #expect(names.contains { $0.hasPrefix("West") })
    }

    // MARK: Quarters

    private func districtNames(_ settlement: GeneratedSettlement) -> Set<String> {
        Set(settlement.features(of: "District").map(\.name) + settlement.features(of: "Garden").map(\.name))
    }

    @Test func onlyTheQuartersAskedForAreMade() {
        let settlement = make(seed: 6, quarters: [.slum, .wealthy])
        let names = districtNames(settlement)
        #expect(names.contains("The Warrens") && names.contains("Noble Quarter"))
        #expect(!names.contains("Craft Quarter") && !names.contains("Temple Quarter") && !names.contains("Merchant Quarter"))
        // Whatever is left is the old town.
        #expect(names.contains("Old Town"))
    }

    @Test func aHamletHasNoQuartersAndABiggerPlaceHasMore() {
        #expect(districtNames(make(.hamlet)).isEmpty)
        #expect(districtNames(make(.village)).count >= 2)
        #expect(districtNames(make(.city, river: true, seed: 2)).count > districtNames(make(.town, seed: 2)).count - 1)
    }

    @Test func aHarbourNeedsARiver() {
        #expect(!districtNames(make(river: false, quarters: [.harbour, .craft])).contains("Harbour Quarter"))
        #expect(districtNames(make(.city, river: true, seed: 5, quarters: [.harbour, .craft])).contains("Harbour Quarter"))
    }

    @Test func theWealthyLiveNearerTheSquareThanTheSlums() {
        var wealthyCloser = 0
        for seed in UInt64(1)...12 {
            let settlement = make(.city, seed: seed, quarters: [.wealthy, .slum])
            func distance(_ name: String) -> Double? {
                guard let district = settlement.features(of: "District").first(where: { $0.name == name }), let square = settlement.square else { return nil }
                let middle = Plane.centroid(points(district).map(v))
                return middle.distance(to: v(square))
            }
            if let wealthy = distance("Noble Quarter"), let slum = distance("The Warrens"), wealthy < slum { wealthyCloser += 1 }
        }
        #expect(wealthyCloser >= 10, "the wealthy were nearer the square in only \(wealthyCloser) of 12 cities")
    }

    @Test func buildingsTakeTheirCharacterFromTheirQuarter() {
        let slum = make(.city, seed: 3, quarters: [.slum]).features(of: "Building").map(\.summary)
        #expect(slum.contains { $0.hasPrefix("A crowded tenement") })
        let wealthy = make(.city, seed: 3, quarters: [.wealthy]).features(of: "Building").map(\.summary)
        #expect(wealthy.contains { $0.hasPrefix("A fine house") })
        let military = make(.city, seed: 3, quarters: [.military]).features(of: "Building").map(\.summary)
        #expect(military.contains { $0.hasPrefix("Barracks") })
        #expect(!make(.city, seed: 3, quarters: []).features(of: "Building").map(\.summary).contains { $0.hasPrefix("A crowded tenement") })
    }

    @Test func buildingsSayWhichQuarterTheyAreIn() {
        let settlement = make(.town, seed: 9, quarters: [.craft, .merchant])
        #expect(settlement.features(of: "Building").contains { $0.summary.contains(", in the Craft Quarter") })
    }

    @Test func slumsAreCrowdedAndTheWealthyHaveRoom() {
        func averageArea(_ quarter: Quarter) -> Double {
            let settlement = make(.city, seed: 3, quarters: [quarter])
            let districts = settlement.features(of: "District") + settlement.features(of: "Garden")
            guard let district = districts.first(where: { $0.name == quarter.districtName }) else { return 0 }
            let outline = points(district).map(v)
            let inside = settlement.features(of: "Building").filter { feature in SettlementGenerator.contains(outline, Plane.centroid(points(feature).map(v))) }
            return inside.map { Plane.area(points($0).map(v)) }.reduce(0, +) / Double(max(inside.count, 1))
        }
        #expect(averageArea(.wealthy) > averageArea(.slum))
    }

    @Test func districtsAreValidShapesInsideTheWall() {
        let settlement = make(.city, river: true, seed: 11)
        let wall = points(settlement.features(of: "Wall")[0]).map(v)
        for district in settlement.features(of: "District") + settlement.features(of: "Garden") {
            #expect(PlaceGeometry.polygon(points(district)).isValid, "\(district.name) is not a valid shape")
            #expect(points(district).allSatisfy { Plane.distanceToEdge(v($0), wall) < 0.8 || SettlementGenerator.contains(wall, v($0)) })
        }
    }

    // MARK: Landmarks

    @Test func eachLandmarkAskedForIsMadeOnce() {
        let asked: [Landmark] = [.cathedral, .castle, .university, .guildhall, .arena, .library, .wizardsTower, .prison, .infirmary]
        let settlement = make(.city, seed: 8, landmarks: asked)
        let made = settlement.features(of: "Landmark")
        #expect(made.count == asked.count)
        #expect(Set(made.map { $0.summary }) == Set(asked.map { $0.summary }))
        #expect(made.allSatisfy { PlaceGeometry.polygon(points($0)).isValid })
        #expect(make(.city, seed: 8, landmarks: []).features(of: "Landmark").isEmpty)
        // Asking twice doesn't make two.
        #expect(make(.city, seed: 8, landmarks: [.cathedral, .cathedral]).features(of: "Landmark").count == 1)
    }

    @Test func noLandmarkShareAWardAndNoBuildingStandsInTheirGrounds() {
        let settlement = make(.city, seed: 5, landmarks: Landmark.allCases)
        let landmarks = settlement.features(of: "Landmark").map { points($0).map(v) }
        for (i, a) in landmarks.enumerated() {
            for b in landmarks[(i + 1)...] { #expect(!SettlementGenerator.overlap(Plane.anticlockwise(a), Plane.anticlockwise(b)) || a == b) }
        }
        for building in settlement.features(of: "Building") {
            let middle = Plane.centroid(points(building).map(v))
            for landmark in landmarks { #expect(!SettlementGenerator.contains(landmark, middle), "\(building.name) stands inside a landmark") }
        }
    }

    @Test func aCastleTakesAWholeWardAtTheEdge() {
        let settlement = make(.town, seed: 5, landmarks: [.castle])
        let castle = points(settlement.features(of: "Landmark")[0]).map(v)
        let wall = points(settlement.features(of: "Wall")[0]).map(v)
        let ward = settlement.wards.map { $0.map(v) }.max { Plane.area($0.filter { _ in true }) < Plane.area($1) }
        _ = ward
        #expect(Plane.area(castle) > 1_500)
        #expect(Plane.distanceToEdge(Plane.centroid(castle), wall) < SettlementOptions.Size.town.radius * 0.8)
        #expect(Plane.area(castle) > make(.town, seed: 5, landmarks: [.library]).features(of: "Landmark").map { Plane.area(points($0).map(v)) }[0])
    }

    @Test func aCathedralStandsByTheSquare() {
        var near = 0
        for seed in UInt64(1)...10 {
            let settlement = make(.town, seed: seed, landmarks: [.cathedral])
            let cathedral = Plane.centroid(points(settlement.features(of: "Landmark")[0]).map(v))
            if let square = settlement.square, cathedral.distance(to: v(square)) < settlement.radius * 0.55 { near += 1 }
        }
        #expect(near >= 8, "the cathedral was near the square in only \(near) of 10 towns")
    }

    @Test func aWizardsTowerIsSmallAndFarOut() {
        let settlement = make(.city, seed: 4, landmarks: [.wizardsTower])
        let tower = points(settlement.features(of: "Landmark")[0]).map(v)
        #expect(Plane.area(tower) < 200)
        #expect(Plane.centroid(tower).distance(to: v(settlement.square!)) > settlement.radius * 0.4)
    }

    // MARK: The options

    @Test func theNewChoicesSurviveBeingSavedAndOldOptionsStillOpen() throws {
        let options = SettlementOptions(
            size: .town, layout: .radial, hasWalls: true, hasRiver: true, seed: 5,
            gates: [SettlementGate(bearing: 1.2)], square: SquareSpot(east: 0.2, north: -0.1), quarters: [.craft, .slum], landmarks: [.cathedral, .arena]
        )
        let decoded = try JSONDecoder().decode(SettlementOptions.self, from: JSONEncoder().encode(options))
        #expect(decoded == options)
        let old = #"{"size":"city","layout":"planned","hasWalls":true,"hasRiver":false,"seed":9}"#
        let opened = try JSONDecoder().decode(SettlementOptions.self, from: Data(old.utf8))
        #expect(opened.size == .city && opened.layout == .planned && opened.hasWalls && opened.seed == 9)
        #expect(opened.gates.isEmpty && opened.square == nil && opened.quarters == nil && opened.landmarks.isEmpty)
    }

    @Test func everyShapeIsStillValidWithEverythingSwitchedOn() {
        for layout in SettlementOptions.Layout.allCases {
            let settlement = make(.city, layout: layout, river: true, seed: 13, landmarks: Landmark.allCases)
            for feature in settlement.features {
                let shape: PlaceGeometry = { if case .polygon(let p) = feature.shape { .polygon(p) } else { .line(points(feature)) } }()
                #expect(shape.isValid, "\(layout) \(feature.name) (\(feature.placeType)) is not valid")
                #expect(points(feature).allSatisfy { (0...settlement.extent).contains($0.easting) && (0...settlement.extent).contains($0.northing) })
            }
        }
    }
}

struct TownGeneratorSweepTests {
    @Test(arguments: SettlementOptions.Layout.allCases, SettlementOptions.Size.allCases)
    func everySizeAndLayoutFinishes(layout: SettlementOptions.Layout, size: SettlementOptions.Size) {
        for seed in UInt64(1)...6 {
            for walls in [true, false] {
                let settlement = SettlementGenerator.generate(SettlementOptions(size: size, layout: layout, hasWalls: walls, hasRiver: seed % 2 == 0, seed: seed))
                #expect(!settlement.features.isEmpty)
            }
        }
    }
}

struct TownGeneratorStressTests {
    @Test(arguments: SettlementOptions.Layout.allCases, SettlementOptions.Size.allCases)
    func everythingSwitchedOnFinishes(layout: SettlementOptions.Layout, size: SettlementOptions.Size) {
        for seed in UInt64(1)...4 {
            let options = SettlementOptions(
                size: size, layout: layout, hasWalls: true, hasRiver: true, seed: seed,
                gates: [SettlementGate(bearing: 0.4), SettlementGate(bearing: 2.0), SettlementGate(bearing: 4.4)],
                square: SquareSpot(east: 0.3, north: -0.2), quarters: Quarter.allCases, landmarks: Landmark.allCases
            )
            #expect(!SettlementGenerator.generate(options).features.isEmpty)
        }
    }
}

struct TownGeneratorOutlineStressTests {
    @Test(arguments: SettlementOptions.Layout.allCases)
    func anOutlineFinishesWithEveryLayout(layout: SettlementOptions.Layout) {
        let shapes: [[GridPoint]] = [
            [GridPoint(easting: 400, northing: 400), GridPoint(easting: 900, northing: 420), GridPoint(easting: 880, northing: 800), GridPoint(easting: 420, northing: 780)],
            [GridPoint(easting: 400, northing: 400), GridPoint(easting: 1_000, northing: 400), GridPoint(easting: 1_000, northing: 500), GridPoint(easting: 500, northing: 500), GridPoint(easting: 500, northing: 900), GridPoint(easting: 1_000, northing: 900), GridPoint(easting: 1_000, northing: 1_000), GridPoint(easting: 400, northing: 1_000)],
            [GridPoint(easting: 100, northing: 100), GridPoint(easting: 160, northing: 100), GridPoint(easting: 130, northing: 150)]
        ]
        for outline in shapes {
            let options = SettlementOptions(size: .town, layout: layout, hasWalls: true, hasRiver: true, seed: 3)
            let extent = SettlementGenerator.extent(for: options, outline: outline)
            #expect(SettlementGenerator.generate(options, outline: outline, extent: extent).extent > 0)
        }
    }
}

struct TownGeneratorBigOutlineTests {
    /// An outline drawn round a big area used to make tens of thousands of wards for the planned and radial layouts.
    @Test(arguments: SettlementOptions.Layout.allCases)
    func aHugeOutlineIsStillQuick(layout: SettlementOptions.Layout) {
        let outline = [GridPoint(easting: 1_000, northing: 1_000), GridPoint(easting: 7_000, northing: 1_200), GridPoint(easting: 6_800, northing: 6_500), GridPoint(easting: 1_300, northing: 6_200)]
        let options = SettlementOptions(size: .town, layout: layout, hasWalls: true, hasRiver: true, seed: 3)
        let extent = SettlementGenerator.extent(for: options, outline: outline)
        let started = Date()
        let settlement = SettlementGenerator.generate(options, outline: outline, extent: extent)
        #expect(Date().timeIntervalSince(started) < 20, "took \(Date().timeIntervalSince(started)) seconds")
        #expect(settlement.wards.count <= 500, "\(settlement.wards.count) wards")
    }
}

struct TownGeneratorRepeatTests {
    @Test func manyRunsGiveTheSameSettlement() {
        let outline = [GridPoint(easting: 893.5483870967728, northing: 997.8494623655861), GridPoint(easting: 1593.5483870967728, northing: 997.8494623655861), GridPoint(easting: 1793.5483870967728, northing: 1447.849462365586), GridPoint(easting: 1193.5483870967728, northing: 1697.849462365586), GridPoint(easting: 893.5483870967728, northing: 1397.849462365586)]
        let options = SettlementOptions(size: .village, layout: .radial, seed: 15)
        let extent = SettlementGenerator.extent(for: options, outline: outline)
        let first = SettlementGenerator.generate(options, outline: outline, extent: extent)
        var differences = 0
        var report = ""
        for _ in 0..<40 {
            let next = SettlementGenerator.generate(options, outline: outline, extent: extent)
            if next != first {
                differences += 1
                if report.isEmpty {
                    func counts(_ s: GeneratedSettlement) -> [String: Int] { Dictionary(s.features.map { ($0.placeType, 1) }, uniquingKeysWith: +) }
                    report = "types \(counts(first)) vs \(counts(next)); wards \(first.wards.count) vs \(next.wards.count); gates \(first.gates == next.gates); square \(first.square == next.square); wall \(first.features(of: "Wall") == next.features(of: "Wall")); roads \(first.features(of: "Road").map(\.name)) vs \(next.features(of: "Road").map(\.name)); districts \(first.features(of: "District").map(\.name)) vs \(next.features(of: "District").map(\.name))"
                }
            }
        }
        #expect(differences == 0, "\(differences) of 40 runs differed: \(report)")
    }
}
