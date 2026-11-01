//
//  SettlementGeneratorTests.swift
//  encounterTests
//

import Testing
import Foundation
@testable import encounter

struct SettlementGeneratorTests {
    private func make(
        _ size: SettlementOptions.Size = .village, layout: SettlementOptions.Layout = .organic, walls: Bool = false, river: Bool = false, seed: UInt64 = 7
    ) -> GeneratedSettlement {
        SettlementGenerator.generate(SettlementOptions(size: size, layout: layout, hasWalls: walls, hasRiver: river, seed: seed))
    }

    private func geometry(_ feature: GeneratedFeature) -> PlaceGeometry {
        switch feature.shape {
        case .polygon(let points): .polygon(points)
        case .line(let points): .line(points)
        }
    }

    private func points(_ feature: GeneratedFeature) -> [GridPoint] {
        switch feature.shape { case .polygon(let p), .line(let p): p }
    }

    @Test func theSameSeedGivesTheSameSettlementAndAnotherSeedGivesAnother() {
        for layout in SettlementOptions.Layout.allCases {
            #expect(make(.town, layout: layout, walls: true, river: true, seed: 42) == make(.town, layout: layout, walls: true, river: true, seed: 42))
            #expect(make(.town, layout: layout, seed: 42) != make(.town, layout: layout, seed: 43))
        }
    }

    @Test func everyShapeIsValidAndOnTheMap() {
        for size in SettlementOptions.Size.allCases {
            for layout in SettlementOptions.Layout.allCases {
                let settlement = make(size, layout: layout, walls: true, river: true, seed: 5)
                for feature in settlement.features {
                    #expect(geometry(feature).isValid, "\(size) \(layout) \(feature.name) is not a valid shape")
                    #expect(points(feature).allSatisfy { (0...settlement.extent).contains($0.easting) && (0...settlement.extent).contains($0.northing) },
                            "\(size) \(layout) \(feature.name) leaves the map")
                }
            }
        }
    }

    @Test func eachSizeMakesAboutAsManyBuildingsAsItAimsFor() {
        for size in SettlementOptions.Size.allCases {
            for layout in SettlementOptions.Layout.allCases {
                let count = make(size, layout: layout).features(of: "Building").count
                #expect(count >= size.buildingTarget * 6 / 10, "\(size) \(layout) made only \(count) of \(size.buildingTarget)")
                // Gatehouses are buildings too, but only with a wall, so without one there are no more than the aim.
                #expect(count <= size.buildingTarget)
            }
        }
    }

    @Test func buildingsNeverTouchEachOther() {
        for layout in SettlementOptions.Layout.allCases {
            let buildings = make(.town, layout: layout, seed: 11).features(of: "Building").compactMap { feature -> [SettlementGenerator.V]? in
                guard case .polygon(let corners) = feature.shape else { return nil }
                return corners.map { SettlementGenerator.V(x: $0.easting, y: $0.northing) }
            }
            for i in buildings.indices {
                for j in buildings.indices where j > i {
                    #expect(!SettlementGenerator.overlap(buildings[i], buildings[j]), "\(layout): buildings \(i) and \(j) overlap")
                }
            }
        }
    }

    @Test func wallsAndRiversAreMadeWhenAskedForAndOnlyThen() {
        let plain = make(.town)
        #expect(plain.features(of: "Wall").isEmpty && plain.features(of: "River").isEmpty)
        let full = make(.town, walls: true, river: true)
        #expect(full.features(of: "Wall").count == 1 && full.features(of: "River").count == 1)
        #expect(make(.hamlet, walls: true).features(of: "Wall").first?.name == "Palisade")
        #expect(make(.city, walls: true).features(of: "Wall").first?.name == "City Wall")
    }

    @Test func aWallIsAClosedLoopRoundEveryBuildingExceptTheGatehouses() {
        let settlement = make(.town, walls: true)
        guard case .line(let loop)? = settlement.features(of: "Wall").first?.shape, let first = loop.first, let last = loop.last else {
            Issue.record("Expected a wall")
            return
        }
        #expect(first == last)
        let edge = loop.map { SettlementGenerator.V(x: $0.easting, y: $0.northing) }
        for building in settlement.features(of: "Building") where !building.name.hasSuffix("Gate") {
            #expect(points(building).allSatisfy { SettlementGenerator.contains(edge, SettlementGenerator.V(x: $0.easting, y: $0.northing)) })
        }
    }

    @Test func everyNameIsUniqueAndEverythingHasASummary() {
        for layout in SettlementOptions.Layout.allCases {
            let settlement = make(.city, layout: layout, walls: true, river: true, seed: 99)
            let names = settlement.features.map(\.name)
            #expect(Set(names).count == names.count, "\(layout) repeats a name")
            #expect(settlement.features.allSatisfy { !$0.name.isEmpty && !$0.summary.isEmpty })
        }
    }

    @Test func aSettlementHasItsSpecialBuildings() {
        let town = make(.town, seed: 21)
        let summaries = town.features(of: "Building").map(\.summary)
        #expect(summaries.contains { $0.hasPrefix("An inn and tavern") })
        #expect(summaries.contains { $0.hasPrefix("A smithy") })
        #expect(summaries.contains { $0.hasPrefix("A chapel") })
        #expect(summaries.contains { $0.hasPrefix("The hall where") })
        #expect(summaries.contains { $0.hasPrefix("A house") })
        #expect(!make(.hamlet).features(of: "Building").map(\.summary).contains { $0.hasPrefix("The hall where") })
        #expect(town.features(of: "Building").allSatisfy { $0.summary.contains(" on ") })
    }

    @Test func aBiggerSettlementHasMoreOfEverything() {
        let sizes = SettlementOptions.Size.allCases.map { make($0, seed: 4) }
        #expect(sizes.map { $0.features(of: "Building").count } == sizes.map { $0.features(of: "Building").count }.sorted())
        #expect(sizes.map(\.extent) == sizes.map(\.extent).sorted())
        #expect(sizes.map { $0.wards.count } == sizes.map { $0.wards.count }.sorted())
    }

    @Test func theSeededRandomRepeatsAndSpreads() {
        var a = SeededRandom(seed: 1), b = SeededRandom(seed: 1), c = SeededRandom(seed: 2)
        let first = (0..<20).map { _ in a.next() }
        #expect(first == (0..<20).map { _ in b.next() })
        #expect(first != (0..<20).map { _ in c.next() })
        var r = SeededRandom(seed: 5)
        let values = (0..<500).map { _ in r.value(in: 10...20) }
        #expect(values.allSatisfy { (10...20).contains($0) } && (values.max() ?? 0) - (values.min() ?? 0) > 8)
        #expect((0..<500).filter { _ in r.chance(0.5) }.count > 150)
        #expect(r.pick([("only", 1.0)]) == "only" && r.pick([("a", 0.0), ("b", 1.0)]) == "b")
    }
}

import SwiftData

@MainActor
struct GeneratedSettlementMapTests {
    private func makeTown(at position: GridPoint? = GridPoint(easting: 80_000, northing: 90_000)) throws -> (World, Page, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        world.ensureRootPlace(in: context)
        let town = world.addPage(kind: .place, in: context)
        town.title = "Harrowgate"
        if let position { _ = town.setGeometry(.point(position)) }
        return (world, town, context)
    }

    private func generated(_ world: World, _ map: WorldMap) -> [Page] { (world.pages ?? []).filter { $0.wasGenerated(by: map) && !$0.isDeleted } }

    @Test func aPlaceNeedsAPositionAndMustNotBeTheWorld() async throws {
        let (world, town, context) = try makeTown(at: nil)
        #expect(await world.generateSettlement(for: town, options: SettlementOptions(), in: context) == nil)
        let root = try #require(world.rootPlace)
        #expect(await world.generateSettlement(for: root, options: SettlementOptions(), in: context) == nil)
        #expect((world.maps ?? []).isEmpty)
    }

    @Test func aVectorMapAndAPlaceForEverythingAreMade() async throws {
        let (world, town, context) = try makeTown()
        let options = SettlementOptions(size: .town, layout: .organic, hasWalls: true, hasRiver: true, seed: 12)
        let summary = try #require(await world.generateSettlement(for: town, options: options, in: context))
        let expected = SettlementGenerator.generate(options)
        #expect(summary.created == expected.features.count && summary.replaced == 0 && summary.kept == 0)

        let map = summary.map
        #expect(map.isVector && map.isCalibrated && map.place === town && map.kind == .settlement)
        #expect(map.pixelWidth == Int(expected.extent) && map.settlementOptions == options)
        let places = generated(world, map)
        #expect(places.count == expected.features.count)
        // Each is a part of the settlement, and the creator's choice as far as automatic parents go.
        #expect(places.allSatisfy { $0.parent === town && $0.parentSource == .manual })
        world.refreshAutomaticParents()
        #expect(places.allSatisfy { $0.parent === town })
        let types = Set(places.map { $0.attributeText("core.placeType") })
        #expect(types == ["District", "Square", "Building", "Road", "Street", "River", "Wall"])
        #expect(places.allSatisfy { $0.geometry?.isValid == true && !$0.title.isEmpty && !$0.summary.isEmpty })
    }

    @Test func thePlacesLieOnTheMapWhereTheGeneratorPutThem() async throws {
        let (world, town, context) = try makeTown()
        let options = SettlementOptions(size: .village, seed: 3)
        let summary = try #require(await world.generateSettlement(for: town, options: options, in: context))
        let expected = SettlementGenerator.generate(options)
        // The map is centred on the settlement, so a local point is that far from its south-west corner.
        let corner = GridPoint(easting: 80_000 - expected.extent / 2, northing: 90_000 - expected.extent / 2)
        let first = try #require(expected.features(of: "Building").first)
        let page = try #require(generated(world, summary.map).first { $0.title == first.name })
        guard case .polygon(let local) = first.shape, case .polygon(let placed)? = page.geometry else { Issue.record("Expected polygons"); return }
        #expect(zip(local, placed).allSatisfy { abs($0.easting + corner.easting - $1.easting) < 1e-6 && abs($0.northing + corner.northing - $1.northing) < 1e-6 })
    }

    @Test func everythingGeneratedIsShownOnTheSettlementsOwnMap() async throws {
        let (world, town, context) = try makeTown()
        let summary = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .village, hasWalls: true, hasRiver: true, seed: 9), in: context))
        let shown = summary.map.visiblePlaces(among: generated(world, summary.map))
        // Nothing is hidden by another place on this map: the buildings sit beside the districts, not in them.
        #expect(shown.count == summary.created)
    }

    @Test func makingItAgainReplacesWhatWasMadeAndUsesTheSameMap() async throws {
        let (world, town, context) = try makeTown()
        let first = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .village, seed: 1), in: context))
        let second = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .village, seed: 2), in: context))
        #expect(second.map === first.map && (world.maps ?? []).count == 1)
        #expect(second.replaced == first.created && second.kept == 0)
        #expect(generated(world, second.map).count == second.created)
        #expect(second.map.settlementOptions?.seed == 2)
    }

    @Test func aBiggerSizeResizesTheMap() async throws {
        let (world, town, context) = try makeTown()
        let small = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .village), in: context))
        #expect(small.map.pixelWidth == Int(SettlementOptions.Size.village.extent))
        let big = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .town), in: context))
        let bigExtent = Int(SettlementOptions.Size.town.extent)
        #expect(big.map === small.map && big.map.pixelWidth == bigExtent && big.map.pixelHeight == bigExtent)
        let middle = try #require(big.map.calibration).gridPoint(atX: Double(bigExtent) / 2, y: Double(bigExtent) / 2)
        #expect(middle == GridPoint(easting: 80_000, northing: 90_000))
    }

    @Test func aPlaceYouHaveChangedSurvivesBeingMadeAgain() async throws {
        let (world, town, context) = try makeTown()
        let first = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .village, seed: 1), in: context))
        let renamed = try #require(generated(world, first.map).first { $0.attributeText("core.placeType") == "Building" })
        renamed.title = "My Lucky Tavern"
        let moved = try #require(generated(world, first.map).last { $0.attributeText("core.placeType") == "Building" })
        _ = moved.setGeometry(.polygon([GridPoint(easting: 1, northing: 1), GridPoint(easting: 9, northing: 1), GridPoint(easting: 9, northing: 9)]))
        let written = try #require(generated(world, first.map).first { $0.attributeText("core.placeType") == "Square" })
        written.body = AttributedString("The old guard drill here.")

        let second = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .village, seed: 2), in: context))
        #expect(second.kept == 3 && second.replaced == first.created - 3)
        #expect((world.pages ?? []).contains { $0.title == "My Lucky Tavern" && !$0.isDeleted })
        #expect(written.body.characters.contains("g") && !written.isDeleted)
    }

    @Test func aPlaceSomethingIsLinkedToIsKept() async throws {
        let (world, town, context) = try makeTown()
        let first = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .village, seed: 1), in: context))
        let inn = try #require(generated(world, first.map).first { $0.summary.hasPrefix("An inn and tavern") })
        let barkeep = world.addPage(kind: .character, in: context)
        barkeep.title = "Old Hob"
        _ = barkeep.addLink(to: inn, role: LinkRole.home, in: context)
        let second = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .village, seed: 2), in: context))
        #expect(second.kept == 1 && !inn.isDeleted)
        #expect(barkeep.linkedPage(role: LinkRole.home) === inn)
    }

    @Test func anUntouchedGeneratedPlaceCountsAsUnedited() async throws {
        let (world, town, context) = try makeTown()
        let summary = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .hamlet, seed: 6), in: context))
        let page = try #require(generated(world, summary.map).first)
        #expect(page.isUneditedGeneration)
        page.summary += " Changed."
        #expect(!page.isUneditedGeneration)
    }

    @Test func theOptionsSurviveExportAndImport() async throws {
        let (world, town, context) = try makeTown()
        let options = SettlementOptions(size: .town, layout: .radial, hasWalls: true, hasRiver: false, seed: 77)
        _ = try #require(await world.generateSettlement(for: town, options: options, in: context))
        try context.save()
        let wrapper = try WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: world))
        let contents = try WorldPackage.contents(of: wrapper)
        let target = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let (imported, _) = await WorldImporter.importWorld(contents, into: target)
        let map = try #require((imported.maps ?? []).first { $0.isVector })
        #expect(map.settlementOptions == options)
        // The imported places are still marked as made for it, so it can be made again.
        let place = try #require(map.place)
        let again = try #require(await imported.generateSettlement(for: place, options: options, in: target))
        #expect(again.map === map)
    }
}

struct SettlementOutlineTests {
    private func p(_ e: Double, _ n: Double) -> GridPoint { GridPoint(easting: e, northing: n) }

    /// A 600 by 400 metre block, with room round it.
    private var block: [GridPoint] { [p(700, 800), p(1_300, 800), p(1_300, 1_200), p(700, 1_200)] }

    private func inside(_ outline: [GridPoint], _ feature: GeneratedFeature) -> Bool {
        let polygon = outline.map { SettlementGenerator.V(x: $0.easting, y: $0.northing) }
        guard case .polygon(let corners) = feature.shape else { return false }
        return corners.allSatisfy { SettlementGenerator.contains(polygon, SettlementGenerator.V(x: $0.easting, y: $0.northing)) }
    }

    @Test func everyBuildingStandsInsideTheOutline() {
        let options = SettlementOptions(size: .village, layout: .planned, seed: 5)
        let extent = SettlementGenerator.extent(for: options, outline: block)
        let settlement = SettlementGenerator.generate(options, outline: block, extent: extent)
        let buildings = settlement.features(of: "Building")
        #expect(buildings.count > 20 && buildings.allSatisfy { inside(block, $0) })
        #expect(settlement.extent == extent)
    }

    @Test func aWallFollowsTheOutlineAndTheSizeInTheOptionsIsNotUsed() {
        var options = SettlementOptions(size: .hamlet, layout: .radial, hasWalls: true, seed: 9)
        let extent = SettlementGenerator.extent(for: options, outline: block)
        let first = SettlementGenerator.generate(options, outline: block, extent: extent)
        options.size = .city
        let second = SettlementGenerator.generate(options, outline: block, extent: SettlementGenerator.extent(for: options, outline: block))
        #expect(first.features == second.features && first.extent == second.extent)
        guard case .line(let loop)? = first.features(of: "Wall").first?.shape else { Issue.record("Expected a wall"); return }
        #expect(Array(loop.dropLast()) == block && loop.first == loop.last)
    }

    @Test func theMapIsBigEnoughToHoldTheOutlineWithRoomRoundIt() {
        let options = SettlementOptions(size: .hamlet)
        let wide = [p(0, 0), p(8_000, 0), p(8_000, 600), p(0, 600)]
        let extent = SettlementGenerator.extent(for: options, outline: wide)
        let middle = PlaceGeometry.polygon(wide).centre
        let farthest = wide.map { $0.distance(to: middle) }.max() ?? 0
        #expect(extent >= farthest * 2.2)
        // Without an outline, or with a useless one, the size's own extent is used.
        #expect(SettlementGenerator.extent(for: options, outline: nil) == SettlementOptions.Size.hamlet.extent)
        #expect(SettlementGenerator.extent(for: options, outline: [p(0, 0), p(1, 1)]) == SettlementOptions.Size.hamlet.extent)
        #expect(SettlementGenerator.extent(for: options, outline: [p(10, 10), p(20, 20), p(30, 30)]) == SettlementOptions.Size.hamlet.extent)
    }

    @Test func aBiggerOutlineHoldsMoreBuildingsAndASmallerOneFewer() {
        let options = SettlementOptions(layout: .planned, seed: 2)
        func count(_ half: Double) -> Int {
            let outline = [p(5_000 - half, 5_000 - half), p(5_000 + half, 5_000 - half), p(5_000 + half, 5_000 + half), p(5_000 - half, 5_000 + half)]
            let extent = SettlementGenerator.extent(for: options, outline: outline)
            // Put the outline where the map is centred, as it would be for a place drawn there.
            let corner = 5_000 - extent / 2
            let local = outline.map { p($0.easting - corner, $0.northing - corner) }
            return SettlementGenerator.generate(options, outline: local, extent: extent).features(of: "Building").count
        }
        let small = count(80), medium = count(250), large = count(600)
        #expect(small < medium && medium < large)
        #expect(small >= 4)
    }

    @Test func aCrescentWithItsMiddleOutsideStillGetsASettlement() {
        // A C shape: the average of its corners lies in the gap.
        let crescent = [p(400, 400), p(1_000, 400), p(1_000, 500), p(500, 500), p(500, 900), p(1_000, 900), p(1_000, 1_000), p(400, 1_000)]
        let options = SettlementOptions(size: .village, seed: 4)
        let extent = SettlementGenerator.extent(for: options, outline: crescent)
        let settlement = SettlementGenerator.generate(options, outline: crescent, extent: extent)
        #expect(settlement.features(of: "Building").count > 0)
        let broken = settlement.features.filter { feature in
            switch feature.shape { case .polygon(let q): !PlaceGeometry.polygon(q).isValid; case .line(let q): !PlaceGeometry.line(q).isValid }
        }.map { "\($0.placeType) \($0.name)" }
        #expect(broken.isEmpty, "\(broken)")
        #expect(settlement.features(of: "Building").allSatisfy { inside(crescent, $0) })
    }

    @Test func theSameOutlineAndSeedGiveTheSameSettlement() {
        let options = SettlementOptions(layout: .organic, hasRiver: true, seed: 31)
        let extent = SettlementGenerator.extent(for: options, outline: block)
        #expect(SettlementGenerator.generate(options, outline: block, extent: extent) == SettlementGenerator.generate(options, outline: block, extent: extent))
        #expect(SettlementGenerator.generate(options, outline: block, extent: extent) != SettlementGenerator.generate(SettlementOptions(layout: .organic, hasRiver: true, seed: 32), outline: block, extent: extent))
    }
}

@MainActor
struct OutlinedSettlementMapTests {
    private func p(_ e: Double, _ n: Double) -> GridPoint { GridPoint(easting: e, northing: n) }

    private func makeOutlinedTown() throws -> (World, Page, ModelContext, [GridPoint]) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        world.ensureRootPlace(in: context)
        let town = world.addPage(kind: .place, in: context)
        town.title = "Harrowgate"
        let outline = [p(60_000, 70_000), p(60_700, 70_000), p(60_900, 70_450), p(60_300, 70_700), p(60_000, 70_400)]
        _ = town.setGeometry(.polygon(outline))
        return (world, town, context, outline)
    }

    @Test func theSettlementFillsTheOutlineDrawnOnTheLevelAbove() async throws {
        let (world, town, context, outline) = try makeOutlinedTown()
        let summary = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .hamlet, hasWalls: true, seed: 8), in: context))
        let placed = (world.pages ?? []).filter { $0.wasGenerated(by: summary.map) }
        // The wall is the outline, where it is on the world map.
        let wall = try #require(placed.first { $0.attributeText("core.placeType") == "Wall" })
        guard case .line(let loop)? = wall.geometry else { Issue.record("Expected a line"); return }
        #expect(Array(loop.dropLast()) == outline)
        // Every building is inside it.
        let shape = PlaceGeometry.polygon(outline)
        // (A gatehouse stands on the wall, half in and half out.)
        let buildings = placed.filter { $0.attributeText("core.placeType") == "Building" && !$0.title.hasSuffix("Gate") }
        #expect(buildings.count > 5 && buildings.allSatisfy { page in page.geometry.map { shape.contains($0) } == true })
        // The outline is left as it was drawn, and the map is centred on it.
        #expect(town.geometry == .polygon(outline))
        let middle = try #require(summary.map.calibration).gridPoint(atX: Double(summary.map.pixelWidth) / 2, y: Double(summary.map.pixelHeight) / 2)
        #expect(abs(middle.easting - shape.centre.easting) < 1 && abs(middle.northing - shape.centre.northing) < 1)
        #expect(summary.map.pixelWidth >= Int(SettlementGenerator.extent(for: SettlementOptions(), outline: outline)))
    }

    @Test func thePreviewAndTheMapAgreeOnTheSettlement() async throws {
        let (world, town, context, _) = try makeOutlinedTown()
        let options = SettlementOptions(size: .village, layout: .radial, seed: 15)
        let plan = World.settlementPlan(for: town, options: options)
        let preview = SettlementGenerator.generate(options, outline: plan.outline, extent: plan.extent)
        let summary = try #require(await world.generateSettlement(for: town, options: options, in: context))
        #expect(summary.created == preview.features.count)
        #expect(Double(summary.map.pixelWidth) == plan.extent.rounded())
    }

    @Test func aPlaceWithOnlyAPointMakesItsOwnEdge() async throws {
        let (world, town, context, _) = try makeOutlinedTown()
        _ = town.setGeometry(.point(p(60_000, 70_000)))
        #expect(town.drawnOutline == nil)
        let summary = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .village, seed: 1), in: context))
        #expect(summary.map.pixelWidth == Int(SettlementOptions.Size.village.extent))
    }

    @Test func drawingAnOutlineAfterwardsAndMakingItAgainFillsIt() async throws {
        let (world, town, context, outline) = try makeOutlinedTown()
        _ = town.setGeometry(.point(PlaceGeometry.polygon(outline).centre))
        let first = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .village, seed: 1), in: context))
        #expect(first.map.pixelWidth == Int(SettlementOptions.Size.village.extent))
        _ = town.setGeometry(.polygon(outline))
        let second = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .village, seed: 1), in: context))
        #expect(second.map === first.map && second.replaced == first.created && second.kept == 0)
        let shape = PlaceGeometry.polygon(outline)
        let buildings = (world.pages ?? []).filter { $0.wasGenerated(by: second.map) && $0.attributeText("core.placeType") == "Building" && !$0.isDeleted }
        #expect(buildings.allSatisfy { page in page.geometry.map { shape.contains($0) } == true })
    }
}

@MainActor
struct BackgroundGenerationTests {
    private func makeTown() throws -> (World, Page, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        world.ensureRootPlace(in: context)
        let town = world.addPage(kind: .place, in: context)
        _ = town.setGeometry(.point(GridPoint(easting: 80_000, northing: 90_000)))
        return (world, town, context)
    }

    @Test func workDoneAwayFromTheScreenGivesTheSameSettlement() async {
        for layout in SettlementOptions.Layout.allCases {
            let options = SettlementOptions(size: .town, layout: layout, hasWalls: true, hasRiver: true, seed: 17)
            let background = await SettlementGenerator.generateInBackground(options)
            #expect(background == SettlementGenerator.generate(options))
        }
    }

    @Test func aCancelledRunGivesNothing() async {
        let options = SettlementOptions(size: .city, layout: .radial, seed: 3)
        let task = Task { await SettlementGenerator.generateInBackground(options) }
        task.cancel()
        let result = await task.value
        #expect(result == nil)
    }

    @Test func aCancelledRunMakesNoMapAndNoPlaces() async throws {
        let (world, town, context) = try makeTown()
        let task = Task { await world.generateSettlement(for: town, options: SettlementOptions(size: .city, seed: 5), in: context) }
        task.cancel()
        let summary = await task.value
        #expect(summary == nil && (world.maps ?? []).isEmpty)
        // Only the root place and the settlement itself.
        #expect((world.pages ?? []).filter { $0.kind == .place }.count == 2)
    }

    @Test func progressIsToldAsPlacesAreMadeFromNothingToAll() async throws {
        let (world, town, context) = try makeTown()
        var reports: [(Int, Int)] = []
        let summary = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .town, seed: 2), in: context) { made, total in
            reports.append((made, total))
        })
        #expect(reports.first?.0 == 0 && reports.last?.0 == summary.created && reports.last?.1 == summary.created)
        #expect(reports.count > 3)
        #expect(zip(reports, reports.dropFirst()).allSatisfy { $0.0 <= $1.0 })
        #expect(reports.allSatisfy { $0.1 == summary.created })
    }

    @Test func theScreenGetsATurnWhilePlacesAreBeingMade() async throws {
        let (world, town, context) = try makeTown()
        var turns = 0
        // Something else queued on the main actor runs between batches of places, which is what keeps the app responsive.
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                turns += 1
                await Task.yield()
            }
        }
        _ = try #require(await world.generateSettlement(for: town, options: SettlementOptions(size: .city, seed: 4), in: context))
        ticker.cancel()
        #expect(turns > 5)
    }
}
