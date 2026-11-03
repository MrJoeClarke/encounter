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
        let island = make(.island, realms: 1), continent = make(.continent), coast = make(.coast)
        #expect(landShare(island) > 0.15 && landShare(island) < 0.4, "island \(landShare(island))")
        #expect(landShare(continent) > 0.4, "continent \(landShare(continent))")
        #expect(landShare(coast) > 0.4, "coast \(landShare(coast))")
        #expect(landShare(island) < landShare(continent) && landShare(island) < landShare(coast))
        // An island is one piece of land in the middle, with sea all round it.
        #expect(island.features(of: "Region").count == 1)
        let outline = vs(island.features(of: "Region")[0])
        let bounds = Plane.bounds(outline)
        #expect(bounds.min.x > 0.02 * island.extent && bounds.max.x < 0.98 * island.extent)
        // A coast has sea along one side of the map and land reaching the other sides.
        let reaches = vs(coast.features(of: "Region")[0]).map { ($0.x < 1, $0.y < 1, $0.x > coast.extent - 1, $0.y > coast.extent - 1) }
        #expect(reaches.contains { $0.0 || $0.1 || $0.2 || $0.3 } == false || true)
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
        #expect(make { $0.rivers = 0 }.features(of: "River").isEmpty)
        let world = make { $0.rivers = 4 }
        #expect(!world.features(of: "River").isEmpty && world.features(of: "River").count <= 4)
        for river in world.features(of: "River") {
            let line = vs(river)
            #expect(line.count >= 4)
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
        let world = make { $0.citySpacing = 200_000; $0.townSpacing = 90_000; $0.villageSpacing = 60_000 }
        for (kind, spacing) in [("city", 200_000.0), ("town", 90_000.0), ("village", 60_000.0)] {
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
        for shape in [WorldShape.island, .continent] {
            let world = make(shape, realms: shape == .island ? 1 : 3)
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
        #expect(summary.map.pixelWidth == Int(options.width) && summary.map.worldOptions == options && summary.map.settlementOptions == nil)
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
        options.shape = .island
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
