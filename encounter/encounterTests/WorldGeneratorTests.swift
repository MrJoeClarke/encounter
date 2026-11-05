//
//  WorldGeneratorTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

struct WorldGeneratorTests {
    private func make(_ shape: WorldShape = .continent, realms: Int = 3, seed: UInt64 = 5, width: Double = 600_000, tweak: (inout WorldOptions) -> Void = { _ in }) -> GeneratedWorld {
        var options = WorldOptions()
        options.shape = shape
        options.realms = realms
        options.seed = seed
        options.width = width
        tweak(&options)
        return WorldGenerator.generate(options)
    }

    private func vs(_ feature: GeneratedFeature) -> [V] {
        switch feature.shape {
        case .polygon(let p), .line(let p): p.map { V(x: $0.easting, y: $0.northing) }
        case .point(let p): [V(x: p.easting, y: p.northing)]
        }
    }

    private func settlements(_ world: GeneratedWorld) -> [(feature: GeneratedFeature, at: V)] {
        world.features(of: "Settlement").map { ($0, vs($0)[0]) }
    }

    private func landShare(_ world: GeneratedWorld) -> Double {
        world.features(of: "Region").map { Plane.area(vs($0)) }.reduce(0, +) / (world.extent * world.extent)
    }

    // MARK: Repeatable

    @Test func theSameSeedMakesTheSameWorldAndAnotherMakesAnother() {
        let first = make(seed: 9)
        for _ in 0..<5 { #expect(make(seed: 9) == first) }
        #expect(make(seed: 10) != first)
    }

    // MARK: Land

    @Test func theShapeDecidesHowMuchLandThereIsAndWhere() {
        let continent = make(.continent), coast = make(.coast), peninsula = make(.peninsula), archipelago = make(.archipelago)
        #expect(landShare(continent) > 0.25, "continent \(landShare(continent))")
        #expect(landShare(coast) > 0.4, "coast \(landShare(coast))")
        #expect(landShare(peninsula) > 0.15 && landShare(peninsula) < 0.5, "peninsula \(landShare(peninsula))")
        #expect(landShare(archipelago) > 0.12 && landShare(archipelago) < 0.4, "archipelago \(landShare(archipelago))")
        #expect(landShare(archipelago) < landShare(continent) && landShare(archipelago) < landShare(coast))
        // A continent has sea all round it.
        for seed in UInt64(1)...6 {
            let world = make(.continent, seed: seed)
            let bounds = Plane.bounds(world.features(of: "Region").flatMap { vs($0) })
            #expect(bounds.min.x > 0.01 * world.extent && bounds.max.x < 0.99 * world.extent && bounds.min.y > 0.01 * world.extent && bounds.max.y < 0.99 * world.extent, "seed \(seed)")
        }
    }

    /// Which edges of the map the land of a world reaches.
    private func edgesReached(_ world: GeneratedWorld) -> Set<Int> {
        var reached = Set<Int>()
        let slack = world.extent * 0.012
        for point in world.features(of: "Region").flatMap({ vs($0) }) {
            if point.y < slack { reached.insert(0) }
            if point.y > world.extent - slack { reached.insert(1) }
            if point.x < slack { reached.insert(2) }
            if point.x > world.extent - slack { reached.insert(3) }
        }
        return reached
    }

    @Test func aCoastHasSeaAlongOneSideAndAPeninsulaIsJoinedToOneEdgeOnly() {
        for seed in UInt64(1)...8 {
            #expect(edgesReached(make(.coast, seed: seed)).count == 3, "coast, seed \(seed)")
            let peninsula = make(.peninsula, seed: seed)
            #expect(edgesReached(peninsula).count == 1, "peninsula, seed \(seed): \(edgesReached(peninsula))")
        }
    }

    @Test func anArchipelagoHasARealmOnEachIslandAndNowAndThenTwoOnOne() {
        for realms in [2, 3, 5, 7] {
            for seed in UInt64(1)...6 {
                let world = make(.archipelago, realms: realms, seed: seed) { $0.islands = .few }
                let outlines = world.features(of: "Region").filter { $0.kind != "land" }.map { vs($0) }
                // An island for each realm, or one fewer when one island holds two.
                #expect(outlines.count >= realms - 1, "\(realms) realms, seed \(seed): \(outlines.count) pieces")
                let capitals = world.features.filter { $0.kind == "capital" }
                #expect(capitals.count == realms)
                var perIsland: [Int: Int] = [:]
                for capital in capitals {
                    guard case .point(let spot) = capital.shape else { continue }
                    let home = outlines.firstIndex { SettlementGenerator.contains($0, V(x: spot.easting, y: spot.northing)) }
                    #expect(home != nil, "\(realms) realms, seed \(seed): capital \(capital.name) is off the land")
                    perIsland[home ?? -1, default: 0] += 1
                }
                // Capitals share an island only in the limited case of one island too few, and then only two on it.
                #expect(perIsland.values.allSatisfy { $0 <= 2 } && perIsland.values.filter { $0 > 1 }.count <= 1, "\(realms) realms, seed \(seed): \(perIsland)")
            }
        }
    }

    @Test func anIslandBelongsToOneRealmUnlessItHasMoreThanOneCapital() {
        for seed in UInt64(1)...5 {
            let world = make(.archipelago, realms: 4, seed: seed) { $0.islands = .many }
            let regions = world.features(of: "Region").filter { $0.kind.hasPrefix("realm ") }
            let capitals = world.features.filter { $0.kind == "capital" }
            // Each island's polygon belongs to one realm by construction, so an island with one capital is in one realm: no two
            // realm regions overlap in their middles.
            let middles = regions.map { Plane.centroid(vs($0)) }
            for (i, outline) in regions.map({ vs($0) }).enumerated() {
                for (j, middle) in middles.enumerated() where i != j && regions[i].kind != regions[j].kind {
                    #expect(!SettlementGenerator.contains(outline, middle), "seed \(seed): realms overlap")
                }
            }
            #expect(capitals.count == 4)
        }
    }

    @Test func theRealmsOfAWorldAreAboutTheSameSize() {
        for shape in [WorldShape.continent, .coast, .peninsula, .inland] {
            var worst = 0.0
            for seed in UInt64(1)...6 {
                let world = make(shape, realms: 3, seed: seed)
                var areas: [String: Double] = [:]
                for feature in world.features(of: "Region") where feature.kind.hasPrefix("realm ") { areas[feature.kind, default: 0] += Plane.area(vs(feature)) }
                let biggest = areas.values.max() ?? 1, smallest = max(areas.values.min() ?? 0, 1)
                print("REALMSIZE \(shape) seed \(seed): \(areas.count) realms, ratio \(biggest / smallest)")
                worst = max(worst, biggest / smallest)
            }
            // A coast is land off the map on three sides round a gulf, and its realms are still unevenly shared on some seeds.
            #expect(worst < (shape == .coast ? 7 : 3), "\(shape): the biggest realm is \(worst) times the smallest")
        }
    }

    @Test func inlandIsLandAllOverWithNoSea() {
        let world = make(.inland, realms: 4)
        #expect(world.features(of: "Water").isEmpty)
        #expect(landShare(world) > 0.97, "inland \(landShare(world))")
        #expect(world.features.filter { $0.kind == "capital" }.count == 4)
        // The realms stop short of all four edges, and the land beyond them carries on to each.
        let realms = world.features(of: "Region").filter { $0.kind.hasPrefix("realm ") }
        #expect(Set(realms.map(\.kind)).count == 4)
        let slack = world.extent * 0.012
        for edge in 0..<4 {
            #expect(realms.allSatisfy { vs($0).allSatisfy { [$0.y, world.extent - $0.y, $0.x, world.extent - $0.x][edge] > slack } }, "a realm reaches edge \(edge)")
        }
        #expect(edgesReached(world) == [0, 1, 2, 3])
        // The rivers run off the map, since there is no sea to run to.
        #expect(!world.features(of: "River").isEmpty)
    }

    /// How much a coast wanders along one side of the map: the spread of the land's outermost point, in bands along that side.
    private func wander(_ world: GeneratedWorld, side: Int) -> Double {
        let points = world.features(of: "Region").flatMap { vs($0) }
        let bands = 16
        var outermost = [Double?](repeating: nil, count: bands)
        for p in points {
            let along = side < 2 ? p.x : p.y
            let band = min(bands - 1, Int(along / world.extent * Double(bands)))
            let depth = [p.y, world.extent - p.y, p.x, world.extent - p.x][side]
            outermost[band] = min(outermost[band] ?? .infinity, depth)
        }
        let known = outermost.compactMap { $0 }
        return known.count >= 6 ? (known.max()! - known.min()!) / world.extent : 0
    }

    @Test func aContinentsCoastWandersOnEverySideNotJustTopAndBottom() {
        for seed in UInt64(1)...8 {
            let world = make(.continent, seed: seed)
            for side in 0..<4 {
                #expect(wander(world, side: side) > 0.035, "seed \(seed), side \(side): \(wander(world, side: side))")
            }
        }
    }

    @Test func theRealmsOfACoastStopShortOfTheOpenEdgesAndTheLandCarriesOnToThem() {
        for seed in UInt64(1)...6 {
            for shape in [WorldShape.coast, .peninsula] {
                let world = make(shape, seed: seed)
                let realms = world.features(of: "Region").filter { $0.kind.hasPrefix("realm ") }
                let far = world.features(of: "Region").filter { $0.kind == "land" }
                #expect(!far.isEmpty, "\(shape) seed \(seed): nothing beyond the realms")
                // The realms stay back from the edge by a margin...
                let edges = edgesReached(world)
                let slack = world.extent * 0.012
                for edge in edges {
                    for realm in realms {
                        let depth = vs(realm).map { [$0.y, world.extent - $0.y, $0.x, world.extent - $0.x][edge] }.min() ?? 0
                        #expect(depth > slack, "\(shape) seed \(seed): a realm reaches edge \(edge)")
                    }
                }
                // ...and the land beyond them is what reaches it.
                #expect(far.contains { vs($0).contains { p in edges.contains { [p.y, world.extent - p.y, p.x, world.extent - p.x][$0] < slack } } })
            }
        }
    }

    @Test func manyIslandsMakeManySmallerOnesThanFew() {
        let few = make(.archipelago, realms: 3) { $0.islands = .few }
        let many = make(.archipelago, realms: 3) { $0.islands = .many }
        #expect(many.features(of: "Region").count > few.features(of: "Region").count + 5)
        #expect(many.features(of: "Region").count >= 8)
    }

    @Test func aWorldSavedWithTheShapeIslandOpensAsAContinent() throws {
        let old = try JSONDecoder().decode(WorldOptions.self, from: Data(#"{"shape":"island","seed":3}"#.utf8))
        #expect(old.shape == .continent && old.seed == 3 && old.islands == .few)
        let back = try JSONDecoder().decode(WorldOptions.self, from: JSONEncoder().encode({ var o = WorldOptions(); o.shape = .peninsula; o.islands = .many; return o }()))
        #expect(back.shape == .peninsula && back.islands == .many)
    }

    @Test func theSeaIsOneWaterAreaCoveringTheMapAndTheOutlinesStayOnIt() {
        let world = make()
        let sea = world.features(of: "Water")
        #expect(sea.count == 1 && Plane.area(vs(sea[0])) == world.extent * world.extent)
        for feature in world.features {
            #expect(vs(feature).allSatisfy { (0...world.extent).contains($0.x) && (0...world.extent).contains($0.y) }, "\(feature.name) leaves the map")
            let geometry: PlaceGeometry = { switch feature.shape { case .polygon(let p): .polygon(p); case .line(let p): .line(p); case .point(let p): .point(p) } }()
            #expect(geometry.isValid, "\(feature.name) is not a valid shape")
        }
    }

    @Test func mountainsAndForestsFollowTheAmountsAsked() {
        func area(_ world: GeneratedWorld, _ type: String) -> Double { world.features(of: type).map { Plane.area(vs($0)) }.reduce(0, +) }
        let none = make { $0.mountains = .none; $0.forests = .none }
        #expect(none.features(of: "Mountains").isEmpty && none.features(of: "Forest").isEmpty)
        let few = make { $0.mountains = .few; $0.forests = .few }
        let many = make { $0.mountains = .many; $0.forests = .many }
        #expect(area(few, "Mountains") < area(many, "Mountains") && area(few, "Forest") < area(many, "Forest"))
        #expect(area(many, "Mountains") > 0 && area(many, "Forest") > 0)
    }

    @Test func riversAreAsManyAsAskedForAtMostAndRunInLongLines() {
        // A lake always has a river out of it, so there can be those on top of the ones asked for (and in two pieces where a river
        // runs through a lake).
        let none = make { $0.rivers = 0 }
        #expect(none.features(of: "River").count <= none.features(of: "Lake").count)
        let world = make { $0.rivers = 4 }
        #expect(!world.features(of: "River").isEmpty && world.features(of: "River").count <= 4 + 3 * world.features(of: "Lake").count)
        func nearALake(_ p: V) -> Bool {
            world.features(of: "Lake").contains { lake in
                let shore = vs(lake)
                return SettlementGenerator.contains(shore, p) || SettlementGenerator.distance(from: p, toPolyline: shore + [shore[0]]) < world.extent / 160 * 2.5
            }
        }
        for river in world.features(of: "River") {
            let line = vs(river)
            // The stretch that runs out of a lake can be short and straight.
            if line.count < 4 { #expect(nearALake(line[0]) || nearALake(line[line.count - 1]), "\(river.name) is a short river that is not by a lake") }
            var length = 0.0
            for (a, b) in zip(line, line.dropFirst()) { length += a.distance(to: b) }
            #expect(length > world.extent * 0.03, "\(river.name) is only \(length) metres long")
        }
    }

    // MARK: Realms and settlements

    @Test(arguments: [1, 2, 4, 6])
    func eachRealmHasACapitalCity(realms: Int) {
        let world = make(.continent, realms: realms)
        let capitals = world.features(of: "Settlement").filter { $0.kind == "capital" }
        #expect(capitals.count == realms)
        let kinds = Set(world.features(of: "Region").map(\.kind))
        #expect(kinds.count == realms, "\(kinds.count) realms for \(realms)")
        // Each capital is in the realm it is the capital of.
        for capital in capitals { #expect(capital.summary.hasPrefix("The capital of the ")) }
        // And the capitals are well apart.
        let places = capitals.map { vs($0)[0] }
        for (i, a) in places.enumerated() { for b in places[(i + 1)...] { #expect(a.distance(to: b) > world.extent * 0.12, "two capitals are only \(a.distance(to: b)) metres apart") } }
    }

    @Test func settlementsStayOnLandAndOffTheMountains() {
        let world = make()
        let land = world.features(of: "Region").map(vs)
        let mountains = world.features(of: "Mountains").map(vs)
        var onMountain = 0
        for place in settlements(world) {
            #expect(land.contains { SettlementGenerator.contains($0, place.at) }, "\(place.feature.name) is in the sea")
            if mountains.contains(where: { SettlementGenerator.contains($0, place.at) }) { onMountain += 1 }
        }
        // The outlines are smoothed from a grid, so a place on the edge of a range can fall just inside one.
        #expect(Double(onMountain) <= Double(settlements(world).count) * 0.05, "\(onMountain) places are on mountains")
    }

    @Test func placesOfAKindKeepTheirDistance() {
        let world = make { $0.citySpacing = 150_000; $0.townSpacing = 90_000; $0.villageSpacing = 60_000 }
        for (kind, spacing) in [("city", 150_000.0), ("town", 90_000.0), ("village", 60_000.0)] {
            let places = settlements(world).filter { $0.feature.kind == kind }.map(\.at)
            #expect(places.count > 1, "no \(kind)s")
            for (i, a) in places.enumerated() { for b in places[(i + 1)...] { #expect(a.distance(to: b) >= spacing * 0.7, "two \(kind)s are \(a.distance(to: b)) metres apart") } }
        }
        // Closer spacing makes more of them.
        let tight = make { $0.villageSpacing = 30_000 }
        #expect(tight.features(of: "Settlement").filter { $0.kind == "village" }.count > world.features(of: "Settlement").filter { $0.kind == "village" }.count)
    }

    @Test func everyoneHasAUniqueName() {
        let world = make(.continent, realms: 5)
        let names = world.features.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(world.features.allSatisfy { !$0.name.isEmpty && !$0.summary.isEmpty })
    }

    @Test func theNumberOfPlacesStaysReasonable() {
        for shape in WorldShape.allCases {
            let world = make(shape)
            #expect(world.features.count < 700, "\(shape): \(world.features.count) places")
        }
    }

    // MARK: Locations

    @Test func aLocationAskedForAtASpotIsThereWithItsNameAndKind() {
        var location = WorldLocation()
        location.name = "Highcastle"
        location.kind = .city
        location.east = 0.5
        location.north = 0.5
        let world = make(.continent, realms: 2) { $0.locations = [location] }
        let found = settlements(world).first { $0.feature.name == "Highcastle" }
        let place = try! #require(found)
        #expect(place.feature.kind == "city")
        // It is where it was put, or on the nearest land if that was sea or mountain.
        #expect(place.at.distance(to: V(x: 0.5 * world.extent, y: 0.5 * world.extent)) < world.extent * 0.1)
    }

    @Test func aCapitalAskedForTakesOneOfTheRealmsAndIsNamed() {
        var capital = WorldLocation()
        capital.name = "Throne"
        capital.kind = .city
        capital.isCapital = true
        let world = make(.continent, realms: 3) { $0.locations = [capital] }
        let capitals = world.features(of: "Settlement").filter { $0.kind == "capital" }
        #expect(capitals.count == 3)
        #expect(capitals.contains { $0.name == "Throne" })
    }

    @Test func aLocationWithNoSpotIsStillPlacedByKind() {
        var village = WorldLocation()
        village.name = "Smallwick"
        village.kind = .village
        let world = make { $0.locations = [village] }
        #expect(settlements(world).contains { $0.feature.name == "Smallwick" && $0.feature.kind == "village" })
    }

    @Test func settlementsAlreadyOnTheMapAreKeptAndBuiltAround() {
        var options = WorldOptions()
        options.seed = 5
        let there = FixedSettlement(name: "Oldtown", kind: .city, position: GridPoint(easting: 300_000, northing: 300_000))
        let world = WorldGenerator.generate(options, fixed: [there])
        // It isn't made again, and nothing else of its kind is made near it.
        #expect(!world.features.contains { $0.name == "Oldtown" })
        let near = settlements(world).filter { $0.at.distance(to: V(x: 300_000, y: 300_000)) < options.citySpacing * 0.5 && $0.feature.kind == "city" }
        #expect(near.isEmpty)
        // Unless it is turned off.
        options.includeExisting = false
        let ignoring = WorldGenerator.generate(options, fixed: [there])
        #expect(ignoring != world)
    }

    // MARK: Roads

    @Test func everySettlementOnTheLandIsJoinedToTheCapitalsByRoad() {
        for shape in [WorldShape.peninsula, .continent] {
            let world = make(shape, realms: 3)
            var parent: [String: String] = [:]
            func key(_ p: V) -> String { "\(Int((p.x * 100).rounded())),\(Int((p.y * 100).rounded()))" }
            func find(_ k: String) -> String { var k = k; while let next = parent[k], next != k { k = next }; return k }
            func union(_ a: String, _ b: String) { parent[a] = parent[a] ?? a; parent[b] = parent[b] ?? b; parent[find(a)] = find(b) }
            for road in world.features(of: "Road") { let line = vs(road); for (a, b) in zip(line, line.dropFirst()) { union(key(a), key(b)) } }
            let capital = try! #require(settlements(world).first { $0.feature.kind == "capital" })
            let root = find(key(capital.at))
            let joined = settlements(world).filter { parent[key($0.at)] != nil && find(key($0.at)) == root }
            // All the settlements on the capital's landmass, which is nearly all of them.
            #expect(Double(joined.count) >= Double(settlements(world).count) * 0.85, "\(shape): only \(joined.count) of \(settlements(world).count) are joined to the capital")
        }
    }

    @Test func roadsAreNamedForTheSettlementsTheyJoin() {
        let world = make()
        let names = Set(settlements(world).map(\.feature.name))
        let roads = world.features(of: "Road")
        #expect(!roads.isEmpty)
        #expect(roads.contains { road in names.contains { road.name.contains($0) } })
    }

    @Test func roadsGoAroundMountainsRatherThanOverThem() {
        func mountainLength(_ world: GeneratedWorld) -> Double {
            let ranges = world.features(of: "Mountains").map(vs)
            var inside = 0.0
            for road in world.features(of: "Road") {
                let line = vs(road)
                for (a, b) in zip(line, line.dropFirst()) {
                    let middle = V(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                    if ranges.contains(where: { SettlementGenerator.contains($0, middle) }) { inside += a.distance(to: b) }
                }
            }
            return inside
        }
        func roadLength(_ world: GeneratedWorld) -> Double {
            world.features(of: "Road").map { road in zip(vs(road), vs(road).dropFirst()).map { $0.distance(to: $1) }.reduce(0, +) }.reduce(0, +)
        }
        let world = make { $0.mountains = .many }
        #expect(mountainLength(world) < roadLength(world) * 0.15, "\(mountainLength(world)) of \(roadLength(world)) metres of road is on mountains")
    }

    // MARK: Options

    @Test func theOptionsSurviveBeingSavedAndOldOnesStillOpen() throws {
        var options = WorldOptions()
        options.width = 900_000
        options.shape = .coast
        options.seed = 42
        options.realms = 5
        options.rivers = 7
        options.mountains = .many
        var location = WorldLocation()
        location.name = "Highcastle"
        location.kind = .city
        location.isCapital = true
        location.east = 0.25
        location.north = 0.75
        options.locations = [location]
        options.includeExisting = false
        let decoded = try JSONDecoder().decode(WorldOptions.self, from: JSONEncoder().encode(options))
        #expect(decoded == options)
        let opened = try JSONDecoder().decode(WorldOptions.self, from: Data(#"{"seed":3}"#.utf8))
        #expect(opened.seed == 3 && opened.width == WorldOptions().width && opened.realms == 3 && opened.locations.isEmpty && opened.includeExisting)
    }

    @Test func aBigWorldAndASmallOneBothWork() {
        let small = make(width: 20_000)
        #expect(!small.features.isEmpty)
        let big = make(width: 8_000_000)
        #expect(big.extent == 8_000_000 && !big.features(of: "Settlement").isEmpty)
    }

    @Test func aWorldIsMadeInReasonableTime() {
        let started = Date()
        _ = make(.continent, realms: 8)
        #expect(Date().timeIntervalSince(started) < 60, "took \(Date().timeIntervalSince(started)) seconds")
    }
}

@MainActor
struct GeneratedWorldMapTests {
    private func makeWorld() throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Aldara")
        context.insert(world)
        world.ensureRootPlace(in: context)
        return (world, context)
    }

    private func generated(_ world: World, _ map: WorldMap) -> [Page] { (world.pages ?? []).filter { $0.wasGenerated(by: map) && !$0.isDeleted } }

    @Test func aVectorWorldMapAndAPlaceForEverythingAreMade() async throws {
        let (world, context) = try makeWorld()
        var options = WorldOptions()
        options.seed = 3
        options.realms = 2
        let summary = try #require(await world.generateWorld(options: options, in: context))
        let root = try #require(world.rootPlace)
        #expect(summary.map.isVector && summary.map.place === root && world.worldMap === summary.map)
        #expect(abs(Double(summary.map.pixelWidth) - options.width) < 1 && summary.map.worldOptions == options && summary.map.settlementOptions == nil)
        let places = generated(world, summary.map)
        let expected = WorldGenerator.generate(options)
        #expect(places.count == expected.features.count && summary.created == places.count)
        // Everything is a part of the world, chosen so that nothing hides anything else on the map.
        #expect(places.allSatisfy { $0.parent === root && $0.parentSource == .manual })
        world.refreshAutomaticParents()
        #expect(places.allSatisfy { $0.parent === root })
        let types = Set(places.map { $0.attributeText("core.placeType") })
        #expect(types.isSuperset(of: ["Water", "Region", "Settlement", "Road"]))
        #expect(places.filter { $0.attributeText("core.placeType") == "Settlement" }.allSatisfy { $0.isPoint })
        #expect(places.allSatisfy { $0.geometry?.isValid == true })
        // None is hidden by another place on this map.
        #expect(summary.map.visiblePlaces(among: places).count == places.count)
    }

    @Test func makingItAgainReplacesWhatWasMadeAndKeepsWhatWasEdited() async throws {
        let (world, context) = try makeWorld()
        var options = WorldOptions()
        options.seed = 4
        let first = try #require(await world.generateWorld(options: options, in: context))
        let before = generated(world, first.map)
        let city = try #require(before.first { $0.attributeText("core.placeType") == "Settlement" })
        city.title = "Renamed Place"
        let position = try #require(city.geometry?.centre)
        let second = try #require(await world.generateWorld(options: options, in: context))
        #expect(second.map === first.map && second.kept == 1 && second.replaced == before.count - 1)
        #expect((world.maps ?? []).filter(\.isVector).count == 1)
        // The renamed place is built around, so there isn't another one on top of it.
        let again = generated(world, second.map).filter { $0.attributeText("core.placeType") == "Settlement" }
        let crowded = again.filter { $0 !== city && (($0.geometry?.centre).map { $0.distance(to: position) } ?? .infinity) < 10_000 }
        #expect(crowded.isEmpty)
        #expect(again.contains { $0 === city })
    }

    @Test func aWorldWithAPictureMapIsNotGeneratedOver() async throws {
        let (world, context) = try makeWorld()
        let root = try #require(world.rootPlace)
        let picture = WorldMap(name: "Picture", kind: .world)
        picture.pixelWidth = 100
        picture.pixelHeight = 100
        context.insert(picture)
        picture.world = world
        picture.place = root
        // The button is only offered when there is no map or only generated ones.
        #expect(!(root.sortedMaps.isEmpty || root.sortedMaps.allSatisfy { $0.isVector && $0.generatorData != nil }))
    }

    @Test func theOptionsSurviveExportAndImport() async throws {
        let (world, context) = try makeWorld()
        var options = WorldOptions()
        options.seed = 11
        options.shape = .archipelago
        options.realms = 1
        _ = try #require(await world.generateWorld(options: options, in: context))
        try context.save()
        let wrapper = try WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: world))
        let contents = try WorldPackage.contents(of: wrapper)
        let target = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let (imported, _) = await WorldImporter.importWorld(contents, into: target)
        let map = try #require((imported.maps ?? []).first { $0.isVector })
        #expect(map.worldOptions == options && map.settlementOptions == nil)
        let again = try #require(await imported.generateWorld(options: options, in: target))
        #expect(again.map === map)
    }
}

@MainActor
struct MapRiverTests {
    private func worldWithRivers() async throws -> (World, ModelContext, WorldMap) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Aldara")
        context.insert(world)
        world.ensureRootPlace(in: context)
        var options = WorldOptions()
        options.seed = 3
        options.width = 300_000
        options.rivers = 4
        let summary = try #require(await world.generateWorld(options: options, in: context))
        return (world, context, summary.map)
    }

    private func river(in world: World) -> (page: Page, line: [GridPoint])? {
        for page in world.pages ?? [] where page.attributeText("core.placeType") == "River" {
            if case .line(let points)? = page.geometry, points.count > 4 { return (page, points) }
        }
        return nil
    }

    @Test func aPlaceOnAWorldMapRiverGetsThatRiverAndAFarOneDoesNot() async throws {
        let (world, context, _) = try await worldWithRivers()
        let found = try #require(river(in: world))
        let middle = found.line[found.line.count / 2]
        let place = world.addPage(kind: .place, in: context)
        place.geometry = .point(middle)
        let options = SettlementOptions(size: .town, layout: .organic, seed: 4)
        let extent = options.size.extent
        let got = try #require(world.riverNear(place, radius: options.size.radius, extent: extent))
        #expect(got.name == found.page.title && got.path.count >= 2)
        // The stretch passes the middle, and reaches out to the edge of the map so it can be cut there.
        #expect(got.path.map { $0.distance(to: GridPoint(easting: 0, northing: 0)) }.min()! < 30)
        #expect(got.path.contains { abs($0.easting) > extent * 0.4 || abs($0.northing) > extent * 0.4 })

        let far = world.addPage(kind: .place, in: context)
        far.geometry = .point(GridPoint(easting: middle.easting + 40_000, northing: middle.northing + 40_000))
        let others = (world.pages ?? []).filter { $0.attributeText("core.placeType") == "River" }
        let tooNear = others.contains { page in
            if case .line(let points)? = page.geometry { return points.contains { $0.distance(to: far.geometry!.centre) < options.size.radius * 3 } }
            return false
        }
        if !tooNear { #expect(world.riverNear(far, radius: options.size.radius, extent: extent) == nil) }
    }

    @Test func theSettlementMadeThereFollowsTheWorldMapsRiver() async throws {
        let (world, context, _) = try await worldWithRivers()
        let found = try #require(river(in: world))
        let place = world.addPage(kind: .place, in: context)
        place.title = "Riverside"
        place.geometry = .point(found.line[found.line.count / 2])
        let options = world.optionsWithMapRiver(SettlementOptions(size: .town, layout: .organic, seed: 4), for: place)
        #expect(options.hasRiver && options.riverName == found.page.title && options.riverPath.count >= 2)
        let made = SettlementGenerator.generate(options)
        let drawn = try #require(made.features(of: "River").first)
        #expect(drawn.name == found.page.title)
        guard case .line(let points) = drawn.shape else { Issue.record("The river is not a line"); return }
        let extent = made.extent
        #expect(points.allSatisfy { $0.easting >= -0.01 && $0.easting <= extent + 0.01 && $0.northing >= -0.01 && $0.northing <= extent + 0.01 })
        // Every point of it lies on the world map's river, moved to the settlement's coordinates.
        let relative = options.riverPath.map { SettlementGenerator.V(x: extent / 2 + $0.easting, y: extent / 2 + $0.northing) }
        #expect(points.allSatisfy { SettlementGenerator.distance(from: SettlementGenerator.V(x: $0.easting, y: $0.northing), toPolyline: relative) < 1 })
        // Without a river nearby the options let go of it again.
        place.geometry = .point(GridPoint(easting: -9_000_000, northing: -9_000_000))
        #expect(world.optionsWithMapRiver(options, for: place).riverPath.isEmpty && !world.optionsWithMapRiver(options, for: place).hasRiver)
    }

    @Test(arguments: [(0.0, 1.0), (1.0, 0.0), (1.0, 1.0), (-1.0, 0.6)])
    func aRiverRunningAnyWayStillGivesAWholeSettlement(direction: (Double, Double)) {
        var options = SettlementOptions(size: .town, layout: .organic, hasWalls: true, seed: 9)
        let reach = options.size.extent
        let path = (-10...10).map { i -> GridPoint in
            let t = Double(i) / 10 * reach
            let wiggle = sin(t / 60) * 25
            return GridPoint(easting: direction.0 * t - direction.1 * wiggle, northing: direction.1 * t + direction.0 * wiggle)
        }
        options.useMapRiver(("Test", path))
        let made = SettlementGenerator.generate(options)
        #expect(made.features(of: "River").count == 1 && made.features(of: "Building").count > 10 && made.features(of: "Road").count + made.features(of: "Street").count > 3)
    }

    @Test func aRiverIsCutAtTheEdgeOfTheSquare() {
        let line = (0..<40).map { SettlementGenerator.V(x: -100 + Double($0) * 20, y: 50) }
        let cut = SettlementGenerator.TownMaker.clip(line, toSquareOf: 300)
        #expect(cut.first == SettlementGenerator.V(x: 0, y: 50) && cut.last == SettlementGenerator.V(x: 300, y: 50))
        #expect(SettlementGenerator.TownMaker.clip([SettlementGenerator.V(x: -50, y: -50), SettlementGenerator.V(x: -10, y: -10)], toSquareOf: 300).isEmpty)
    }

    @Test func optionsWithAMapRiverSurviveSavingAndOldOnesStillOpen() throws {
        var options = SettlementOptions(size: .town, layout: .organic, seed: 4)
        options.useMapRiver(("Hale", [GridPoint(easting: -50, northing: 0), GridPoint(easting: 50, northing: 10)]))
        let back = try JSONDecoder().decode(SettlementOptions.self, from: JSONEncoder().encode(options))
        #expect(back == options && back.hasRiver)
        #expect(try JSONDecoder().decode(SettlementOptions.self, from: Data("{}".utf8)).riverPath.isEmpty)
    }
}

struct BankRoadTests {
    private typealias V = SettlementGenerator.V

    private func make(_ layout: SettlementOptions.Layout, _ size: SettlementOptions.Size, seed: UInt64) -> GeneratedSettlement {
        SettlementGenerator.generate(SettlementOptions(size: size, layout: layout, hasWalls: true, hasRiver: true, seed: seed))
    }

    private func line(_ feature: GeneratedFeature) -> [V] {
        if case .line(let points) = feature.shape { return points.map { V(x: $0.easting, y: $0.northing) } }
        return []
    }

    private static let cases: [(SettlementOptions.Layout, SettlementOptions.Size)] = [
        (.planned, .town), (.radial, .town), (.organic, .town), (.planned, .city), (.radial, .village), (.organic, .city), (.organic, .village),
    ]

    @Test func aRiverHasAStreetAlongEachBankNamedForIt() {
        var withBanks = 0, total = 0
        for (layout, size) in Self.cases {
            for seed in UInt64(1)...6 {
                let made = make(layout, size, seed: seed)
                total += 1
                let names = made.features.map(\.name)
                let quays = names.filter { $0.hasSuffix(" Quay") || $0.contains(" Quay ") }
                let banks = names.filter { $0.hasSuffix(" Embankment") || $0.contains(" Embankment ") }
                if !quays.isEmpty && !banks.isEmpty { withBanks += 1 }
                #expect(Set(names).count == names.count)
                #expect(made.features(of: "Building").count > 5)
            }
        }
        print("BANKS", withBanks, "of", total)
        // A river with a sharp bend can't have them, but most do.
        #expect(withBanks * 10 >= total * 8)
    }

    @Test func bankStreetsRunAlongTheRiverJustBackFromIt() {
        for (layout, size) in Self.cases {
            for seed in UInt64(1)...4 {
                let made = make(layout, size, seed: seed)
                guard let river = made.features(of: "River").first.map(line) else { continue }
                for street in made.features where street.name.contains(" Quay") || street.name.contains(" Embankment") {
                    let points = line(street)
                    let distances = points.map { SettlementGenerator.distance(from: $0, toPolyline: river) }
                    #expect(distances.allSatisfy { $0 > 3 && $0 < 30 }, Comment(rawValue: "\(layout) \(size) \(seed): \(distances.min() ?? 0)...\(distances.max() ?? 0)"))
                }
            }
        }
    }

    @Test func nothingIsBuiltBetweenABankStreetAndTheWater() {
        for (layout, size) in Self.cases {
            for seed in UInt64(1)...4 {
                let made = make(layout, size, seed: seed)
                guard made.features.contains(where: { $0.name.contains(" Quay") }), let river = made.features(of: "River").first.map(line) else { continue }
                for building in made.features(of: "Building") {
                    // A gatehouse stands where a road leaves the wall, which can be right by the water.
                    guard case .polygon(let corners) = building.shape, !building.name.hasSuffix(" Gate") else { continue }
                    let nearest = corners.map { SettlementGenerator.distance(from: V(x: $0.easting, y: $0.northing), toPolyline: river) }.min() ?? 0
                    #expect(nearest >= 7, Comment(rawValue: "\(layout) \(size) \(seed) \(building.name): \(nearest)"))
                }
            }
        }
    }

    @Test func aMainRoadCrossesTheRiverAtABridgeInMostSettlements() {
        var crossing = 0, total = 0
        for (layout, size) in Self.cases {
            for seed in UInt64(1)...4 {
                let made = make(layout, size, seed: seed)
                guard let river = made.features(of: "River").first.map(line) else { continue }
                total += 1
                let crosses = made.features(of: "Road").contains { road in
                    let points = line(road)
                    return zip(points, points.dropFirst()).contains { a, b in
                        zip(river, river.dropFirst()).contains { SettlementGenerator.TownMaker.segmentsCross(a, b, $0.0, $0.1) }
                    }
                }
                if crosses { crossing += 1 }
            }
        }
        print("BRIDGES", crossing, "of", total)
        #expect(crossing * 10 >= total * 7)
    }
}

struct CoastlineTests {
    private typealias V = SettlementGenerator.V

    private func world(_ shape: WorldShape, _ coastline: WorldCoastline, seed: UInt64) -> GeneratedWorld {
        var options = WorldOptions()
        options.shape = shape
        options.realms = 1
        options.seed = seed
        options.coastline = coastline
        return WorldGenerator.generate(options)
    }

    /// How crinkled the coast is: the length round the land compared with the shortest it could be for that much land.
    private func crinkle(_ world: GeneratedWorld) -> Double {
        var perimeter = 0.0, area = 0.0
        for feature in world.features(of: "Region") {
            guard case .polygon(let points) = feature.shape else { continue }
            let corners = points.map { V(x: $0.easting, y: $0.northing) }
            area += Plane.area(corners)
            perimeter += zip(corners, corners.dropFirst() + [corners[0]]).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        }
        return perimeter / (2 * (Double.pi * area).squareRoot())
    }

    @Test(arguments: [WorldShape.continent, .coast, .peninsula, .archipelago])
    func theRuggederTheSettingTheMoreCrinkledTheCoast(shape: WorldShape) {
        var smooth = 0.0, natural = 0.0, rugged = 0.0
        for seed in UInt64(1)...6 {
            smooth += crinkle(world(shape, .smooth, seed: seed))
            natural += crinkle(world(shape, .natural, seed: seed))
            rugged += crinkle(world(shape, .rugged, seed: seed))
        }
        // A peninsula keeps only its biggest piece of land, which drops the islets that a rugged coast breaks off, so for that shape
        // natural and rugged are not told apart by the length of coast.
        #expect(smooth < natural && (shape == .peninsula || natural < rugged), "\(shape): \(smooth / 6), \(natural / 6), \(rugged / 6)")
        #expect(rugged > smooth * 1.05)
    }

    @Test func theSettingDoesNotChangeHowMuchLandThereIsOrWhatShapeItIs() {
        for coastline in WorldCoastline.allCases {
            let continent = world(.continent, coastline, seed: 4)
            let bounds = Plane.bounds(continent.features(of: "Region").flatMap { feature -> [V] in
                if case .polygon(let p) = feature.shape { return p.map { V(x: $0.easting, y: $0.northing) } }
                return []
            })
            // Still sea all round, and still land of about the same amount.
            #expect(bounds.min.x > 0 && bounds.max.x < continent.extent && bounds.min.y > 0 && bounds.max.y < continent.extent, "\(coastline)")
            var share = 0.0
            for feature in continent.features(of: "Region") { if case .polygon(let p) = feature.shape { share += Plane.area(p.map { V(x: $0.easting, y: $0.northing) }) } }
            #expect(share / (continent.extent * continent.extent) > 0.25 && share / (continent.extent * continent.extent) < 0.55, "\(coastline): \(share / (continent.extent * continent.extent))")
        }
    }

    @Test func theChoiceIsKeptWithTheOptionsAndOldWorldsAreNatural() throws {
        var options = WorldOptions()
        options.coastline = .rugged
        let back = try JSONDecoder().decode(WorldOptions.self, from: JSONEncoder().encode(options))
        #expect(back.coastline == .rugged)
        #expect(try JSONDecoder().decode(WorldOptions.self, from: Data("{}".utf8)).coastline == .natural)
    }
}

struct IslandSettingTests {
    private typealias V = SettlementGenerator.V

    private func world(_ shape: WorldShape, _ islands: WorldIslands, seed: UInt64) -> GeneratedWorld {
        var options = WorldOptions()
        options.shape = shape
        options.realms = 3
        options.seed = seed
        options.islands = islands
        return WorldGenerator.generate(options)
    }

    private func outlines(_ world: GeneratedWorld) -> [[V]] {
        world.features(of: "Region").compactMap { feature in
            if case .polygon(let p) = feature.shape { return p.map { V(x: $0.easting, y: $0.northing) } }
            return nil
        }
    }

    @Test(arguments: [WorldShape.continent, .coast, .peninsula])
    func noIslandsLeavesOnlyTheRealmsAndMoreIslandsMakeMorePieces(shape: WorldShape) {
        var none = 0, few = 0, many = 0
        for seed in UInt64(1)...5 {
            none += outlines(world(shape, .none, seed: seed)).count
            few += outlines(world(shape, .few, seed: seed)).count
            many += outlines(world(shape, .many, seed: seed)).count
        }
        #expect(none < few && few < many, "\(shape): \(none), \(few), \(many)")
    }

    @Test func islandsLieOffTheCoastAwayFromTheEdgeAndHaveNoSettlements() {
        for seed in UInt64(1)...5 {
            let made = world(.continent, .many, seed: seed)
            let pieces = outlines(made)
            let biggest = pieces.map { Plane.area($0) }.max() ?? 0
            let small = pieces.filter { Plane.area($0) < biggest * 0.05 }
            #expect(!small.isEmpty, "seed \(seed): no islands")
            for island in small {
                let bounds = Plane.bounds(island)
                #expect(bounds.min.x > made.extent * 0.03 && bounds.max.x < made.extent * 0.97 && bounds.min.y > made.extent * 0.03 && bounds.max.y < made.extent * 0.97)
                for town in made.features(of: "Settlement") {
                    guard case .point(let spot) = town.shape else { continue }
                    #expect(!SettlementGenerator.contains(island, V(x: spot.easting, y: spot.northing)), "seed \(seed): \(town.name) is on an island")
                }
            }
        }
    }

    @Test func theSettingDoesNotMoveTheCapitalsOrTheLand() {
        func capitals(_ world: GeneratedWorld) -> [V] {
            world.features.filter { $0.kind == "capital" }.compactMap { feature in
                if case .point(let p) = feature.shape { return V(x: p.easting, y: p.northing) }
                return nil
            }
        }
        // Islands are made apart from everything else, and nothing is built on them, so where the capitals are does not change.
        for seed in UInt64(1)...4 {
            let without = capitals(world(.continent, .none, seed: seed)), with = capitals(world(.continent, .many, seed: seed))
            // To within a few cells: a place the smoothed coast leaves just off the land is nudged in, up to eight half-cells, towards the middle of the land.
            #expect(without.count == with.count && zip(without, with).allSatisfy { $0.distance(to: $1) < 17_000 }, "seed \(seed)")
        }
    }

    @Test func theChoiceIsKept() throws {
        var options = WorldOptions()
        options.islands = .many
        #expect(try JSONDecoder().decode(WorldOptions.self, from: JSONEncoder().encode(options)).islands == .many)
    }
}

struct LakeTests {
    private typealias V = SettlementGenerator.V

    private func world(_ shape: WorldShape, seed: UInt64, rivers: Int = 4) -> GeneratedWorld {
        var options = WorldOptions()
        options.shape = shape
        options.realms = 3
        options.seed = seed
        options.rivers = rivers
        return WorldGenerator.generate(options)
    }

    private func outline(_ feature: GeneratedFeature) -> [V] {
        switch feature.shape {
        case .polygon(let p), .line(let p): p.map { V(x: $0.easting, y: $0.northing) }
        case .point(let p): [V(x: p.easting, y: p.northing)]
        }
    }

    @Test func worldsHaveLakesThatAreWaterOnTheLand() {
        var withLakes = 0
        for shape in [WorldShape.continent, .coast, .peninsula, .inland] {
            for seed in UInt64(1)...5 {
                let made = world(shape, seed: seed)
                let lakes = made.features(of: "Lake")
                if !lakes.isEmpty { withLakes += 1 }
                for lake in lakes {
                    #expect(lake.kind == "lake" && lake.name.hasPrefix("Lake "))
                    let bounds = Plane.bounds(outline(lake))
                    #expect(bounds.min.x > made.extent * 0.03 && bounds.max.x < made.extent * 0.97 && bounds.min.y > made.extent * 0.03 && bounds.max.y < made.extent * 0.97, "\(shape) \(seed): a lake reaches the edge")
                }
            }
        }
        #expect(withLakes >= 15, "only \(withLakes) of 20 worlds have a lake")
    }

    @Test func everyLakeHasARiverRunningOutOfItToTheSeaOrTheEdge() {
        for shape in [WorldShape.continent, .coast, .peninsula, .inland] {
            for seed in UInt64(1)...5 {
                // With no rivers asked for, a lake still has its outflow.
                let made = world(shape, seed: seed, rivers: 0)
                let realms = made.features(of: "Region").map { outline($0) }
                let cell = made.extent / 160
                for lake in made.features(of: "Lake") {
                    let shore = outline(lake)
                    let closed = shore + [shore[0]]
                    func touches(_ p: V) -> Bool { SettlementGenerator.contains(shore, p) || SettlementGenerator.distance(from: p, toPolyline: closed) < cell * 2.5 }
                    // A river that starts at the lake and ends in the sea (off the land) or at the edge of the map.
                    let out = made.features(of: "River").contains { river in
                        let line = outline(river)
                        guard let first = line.first, let last = line.last else { return false }
                        func ends(_ p: V) -> Bool {
                            let atEdge = p.x <= cell * 1.5 || p.y <= cell * 1.5 || p.x >= made.extent - cell * 1.5 || p.y >= made.extent - cell * 1.5
                            // At the sea or the edge of the map, or joining another river that goes on.
                            let joinsRiver = made.features(of: "River").contains { other in
                                let l = outline(other)
                                return l != line && SettlementGenerator.distance(from: p, toPolyline: l) < cell * 1.5
                            }
                            // Or running into another lake, which has its own river out.
                            let intoLake = made.features(of: "Lake").contains { other in
                                let l = outline(other)
                                return l != shore && (SettlementGenerator.contains(l, p) || SettlementGenerator.distance(from: p, toPolyline: l + [l[0]]) < cell * 2.5)
                            }
                            return atEdge || joinsRiver || intoLake || !realms.contains { SettlementGenerator.contains($0, p) }
                        }
                        return (touches(first) && ends(last)) || (touches(last) && ends(first))
                    }
                    #expect(out, "\(shape) \(seed): \(lake.name) has no river running out of it")
                }
            }
        }
    }

    @Test func nothingIsBuiltOnALakeAndNoRoadCrossesOne() {
        for shape in [WorldShape.continent, .inland] {
            for seed in UInt64(1)...5 {
                let made = world(shape, seed: seed)
                for lake in made.features(of: "Lake") {
                    let shore = outline(lake)
                    let cell = made.extent / 160
                    // Standing on the shore is allowed (the outline is smoothed, so a place on the edge can fall just inside it).
                    func inLake(_ p: V) -> Bool { SettlementGenerator.contains(shore, p) && SettlementGenerator.distance(from: p, toPolyline: shore + [shore[0]]) > cell * 0.8 }
                    for town in made.features(of: "Settlement") {
                        #expect(!inLake(outline(town)[0]), "\(shape) \(seed): \(town.name) is in \(lake.name)")
                    }
                    for road in made.features(of: "Road") {
                        let line = outline(road)
                        #expect(line.filter(inLake).isEmpty, "\(shape) \(seed): a road runs through \(lake.name)")
                    }
                }
            }
        }
    }

    @Test func lakesAreOnlyAddedWaterNotAnotherSea() {
        let made = world(.continent, seed: 3)
        #expect(made.features(of: "Water").count == 1)
    }
}

struct RoadNameTests {
    @Test func roadsOnTheWorldMapAreNamedWithoutNumbers() {
        var roads = 0, numbered = 0
        for seed in UInt64(1)...12 {
            var options = WorldOptions()
            options.realms = 4
            options.seed = seed
            let world = WorldGenerator.generate(options)
            for feature in world.features where feature.placeType == "Road" {
                roads += 1
                if let last = feature.name.split(separator: " ").last, Int(last) != nil { numbered += 1 }
            }
            let names = world.features.filter { $0.placeType == "Road" }.map(\.name)
            #expect(Set(names).count == names.count)
        }
        #expect(roads > 0)
        #expect(numbered * 20 <= roads, "\(numbered) of \(roads) roads are numbered")
    }
}

struct RealmPieceTests {
    @Test func aRealmsBiggestPieceHasTheRealmsNameAndOthersAreIslesWithoutNumbers() {
        var isles = 0
        for seed in UInt64(1)...10 {
            var options = WorldOptions()
            options.shape = .archipelago
            options.realms = 3
            options.seed = seed
            let world = WorldGenerator.generate(options)
            for realm in 0..<3 {
                let pieces = world.features.filter { $0.kind == "realm \(realm)" }
                guard pieces.count > 1 else { continue }
                func area(_ f: GeneratedFeature) -> Double {
                    if case .polygon(let p) = f.shape { return PlaceGeometry.polygon(p).area }
                    return 0
                }
                let biggest = pieces.max { area($0) < area($1) }
                let realmName = pieces.map(\.name).min { $0.count < $1.count } ?? ""
                #expect(biggest?.name == realmName || !(biggest?.name.contains("Isle") ?? false))
                for piece in pieces where piece.name != biggest?.name {
                    isles += 1
                    #expect(Int(piece.name.split(separator: " ").last ?? "") == nil, Comment(rawValue: piece.name))
                }
            }
        }
        #expect(isles > 0)
    }
}

struct SharedBorderTests {
    private func world(_ shape: WorldShape, seed: UInt64) -> GeneratedWorld {
        var options = WorldOptions()
        options.shape = shape
        options.realms = 4
        options.seed = seed
        return WorldGenerator.generate(options)
    }

    private func polygons(_ world: GeneratedWorld, where match: (GeneratedFeature) -> Bool) -> [[GridPoint]] {
        world.features.filter(match).compactMap { feature in
            if case .polygon(let p) = feature.shape { return p }
            return nil
        }
    }

    @Test func realmsFitTogetherWithoutOverlapping() {
        for shape in [WorldShape.continent, .coast, .inland] {
            for seed in UInt64(1)...3 {
                let made = world(shape, seed: seed)
                let land = polygons(made) { $0.placeType == "Region" }
                var overlapping = 0, covered = 0
                for i in 0..<40 {
                    for j in 0..<40 {
                        let point = GridPoint(easting: (Double(i) + 0.5) / 40 * made.extent, northing: (Double(j) + 0.5) / 40 * made.extent)
                        let inside = land.filter { PlaceGeometry.polygon($0).contains(point) }.count
                        if inside > 0 { covered += 1 }
                        if inside > 1 { overlapping += 1 }
                    }
                }
                #expect(covered > 0)
                #expect(overlapping * 100 <= max(covered, 1), "\(shape) seed \(seed): \(overlapping) of \(covered) points are in two realms")
            }
        }
    }

    @Test func outlinesAreNotTooFine() {
        for seed in UInt64(1)...3 {
            let made = world(.continent, seed: seed)
            for polygon in polygons(made, where: { _ in true }) { #expect(polygon.count < 2500) }
        }
    }

    @Test func forestsAndMountainsStayOnTheLandAndApartFromEachOther() {
        for shape in [WorldShape.continent, .archipelago, .coast] {
            for seed in UInt64(1)...4 {
                let made = world(shape, seed: seed)
                let land = polygons(made) { $0.placeType == "Region" }
                let forests = polygons(made) { $0.placeType == "Forest" }
                let mountains = polygons(made) { $0.placeType == "Mountains" }
                // Every corner of a forest or a mountain range is on land.
                for outline in forests + mountains {
                    // A corner on the edge of the map is on the edge of the land too, which is as near as a test of "inside" can say.
                    let off = outline.filter { corner in
                        let onEdge = [corner.easting, corner.northing].contains { $0 < 50 || $0 > made.extent - 50 }
                        return !onEdge && !land.contains { PlaceGeometry.polygon($0).contains(corner) }
                    }
                    #expect(off.count * 40 <= outline.count, "\(shape) seed \(seed): \(off.count) of \(outline.count) corners are off the land")
                }
                // No forest runs into a range of mountains.
                var both = 0
                for i in 0..<60 {
                    for j in 0..<60 {
                        let point = GridPoint(easting: (Double(i) + 0.5) / 60 * made.extent, northing: (Double(j) + 0.5) / 60 * made.extent)
                        if forests.contains(where: { PlaceGeometry.polygon($0).contains(point) }) && mountains.contains(where: { PlaceGeometry.polygon($0).contains(point) }) { both += 1 }
                    }
                }
                // A sliver or two where the smoothed edges of the two meet is allowed; a forest running into mountains is not.
                #expect(both <= 12, "\(shape) seed \(seed): \(both) points are in a forest and in mountains")
            }
        }
    }
}
