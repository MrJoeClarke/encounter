//
//  SceneGeneratorTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

struct SceneGeneratorTests {
    private let square = SceneOptions.squareMetres

    private func make(_ kind: SceneKind = .dungeon, squares: Int = 40, seed: UInt64 = 5, outline: [GridPoint]? = nil, tweak: (inout SceneOptions) -> Void = { _ in }) -> GeneratedScene {
        var options = SceneOptions()
        options.kind = kind
        options.squares = squares
        options.seed = seed
        tweak(&options)
        return SceneGenerator.generate(options, outline: outline)
    }

    private func points(_ feature: GeneratedFeature) -> [V] {
        switch feature.shape {
        case .polygon(let p), .line(let p): p.map { V(x: $0.easting, y: $0.northing) }
        case .point(let p): [V(x: p.easting, y: p.northing)]
        }
    }

    /// The box round a rectangular room, in squares.
    private func box(_ feature: GeneratedFeature) -> (x0: Double, y0: Double, x1: Double, y1: Double) {
        let p = points(feature)
        return ((p.map(\.x).min() ?? 0) / square, (p.map(\.y).min() ?? 0) / square, (p.map(\.x).max() ?? 0) / square, (p.map(\.y).max() ?? 0) / square)
    }

    private func isWhole(_ value: Double) -> Bool { abs(value - value.rounded()) < 1e-6 }

    // MARK: Repeatable

    @Test(arguments: SceneKind.allCases)
    func theSameSeedMakesTheSameSceneAndAnotherMakesAnother(kind: SceneKind) {
        let first = make(kind, seed: 8)
        for _ in 0..<5 { #expect(make(kind, seed: 8) == first) }
        #expect(make(kind, seed: 9) != first)
    }

    @Test(arguments: SceneKind.allCases)
    func everythingStaysOnTheMapAndIsValid(kind: SceneKind) {
        for seed in UInt64(1)...6 {
            let scene = make(kind, seed: seed) { $0.secretDoors = true }
            #expect(scene.extent == 40 * square)
            for feature in scene.features {
                #expect(points(feature).allSatisfy { (-1e-9...scene.extent + 1e-9).contains($0.x) && (-1e-9...scene.extent + 1e-9).contains($0.y) }, "\(kind) seed \(seed): \(feature.name) leaves the map")
                let geometry: PlaceGeometry = { switch feature.shape { case .polygon(let p): .polygon(p); case .line(let p): .line(p); case .point(let p): .point(p) } }()
                #expect(geometry.isValid, "\(kind) seed \(seed): \(feature.name) is not valid")
            }
            let names = scene.features.map(\.name)
            #expect(Set(names).count == names.count && scene.features.allSatisfy { !$0.name.isEmpty && !$0.summary.isEmpty })
        }
    }

    // MARK: Dungeon and building

    @Test(arguments: [SceneKind.dungeon, .building])
    func roomsAndCorridorsFollowTheGridAndRoomsNeverOverlap(kind: SceneKind) {
        for seed in UInt64(1)...6 {
            let scene = make(kind, seed: seed)
            let rooms = scene.features(of: "Room")
            #expect(rooms.count >= 2, "\(kind) seed \(seed): \(rooms.count) rooms")
            for feature in rooms + scene.features(of: "Corridor") {
                #expect(points(feature).allSatisfy { isWhole($0.x / square) && isWhole($0.y / square) }, "\(feature.name) is off the grid")
            }
            let boxes = rooms.map(box)
            for (i, a) in boxes.enumerated() {
                for b in boxes[(i + 1)...] {
                    let overlapX = min(a.x1, b.x1) - max(a.x0, b.x0), overlapY = min(a.y1, b.y1) - max(a.y0, b.y0)
                    #expect(!(overlapX > 1e-6 && overlapY > 1e-6), "\(kind) seed \(seed): two rooms overlap")
                }
            }
        }
    }

    @Test func everyRoomOfADungeonCanBeReachedFromTheFirst() {
        for seed in UInt64(1)...8 {
            for squares in [20, 40, 80] {
                let scene = make(.dungeon, squares: squares, seed: seed) { $0.loops = .none }
                var floor = Set<Int>()
                func cells(of feature: GeneratedFeature) -> [Int] {
                    let p = points(feature)
                    let b = box(feature)
                    var result: [Int] = []
                    for y in Int(b.y0.rounded(.down))..<Int(b.y1.rounded(.up)) {
                        for x in Int(b.x0.rounded(.down))..<Int(b.x1.rounded(.up)) where SettlementGenerator.contains(p, V(x: (Double(x) + 0.5) * square, y: (Double(y) + 0.5) * square)) { result.append(y * squares + x) }
                    }
                    return result
                }
                let rooms = scene.features(of: "Room")
                let roomCells = rooms.map(cells)
                for feature in rooms + scene.features(of: "Corridor") { floor.formUnion(cells(of: feature)) }
                guard let start = roomCells.first?.first else { Issue.record("no rooms"); return }
                var seen: Set<Int> = [start]
                var queue = [start]
                while let next = queue.popLast() {
                    for nb in [next - 1, next + 1, next - squares, next + squares] where floor.contains(nb) && !seen.contains(nb) && abs(nb % squares - next % squares) <= 1 {
                        seen.insert(nb)
                        queue.append(nb)
                    }
                }
                for (index, room) in roomCells.enumerated() { #expect(room.allSatisfy { seen.contains($0) }, "squares \(squares) seed \(seed): room \(index + 1) is cut off") }
            }
        }
    }

    @Test func everyDoorIsOnTheEdgeOfARoomAndOpensIntoOne() {
        for kind in [SceneKind.dungeon, .building] {
            for seed in UInt64(1)...5 {
                let scene = make(kind, seed: seed) { $0.secretDoors = true }
                let rooms = scene.features(of: "Room")
                let doors = scene.features(of: "Door")
                #expect(!doors.isEmpty)
                for door in doors {
                    let at = points(door)[0]
                    let onEdge = rooms.contains { Plane.distanceToEdge(at, points($0)) < 1e-6 }
                    // The way into a building is on the hall, not a room.
                    #expect(onEdge || door.name.hasPrefix("Entrance"), "\(kind) seed \(seed): \(door.name) is not on a wall")
                    // On the edge between two squares: a whole number one way and a half the other.
                    let x = at.x / square, y = at.y / square
                    #expect((isWhole(x) && isWhole(y - 0.5)) || (isWhole(y) && isWhole(x - 0.5)), "\(door.name) is not on the edge of a square")
                }
                if kind == .building {
                    // Each room has a way to the hall.
                    for (index, _) in rooms.enumerated() { #expect(doors.contains { $0.summary.contains("Room \(index + 1).") || $0.summary.contains("Room \(index + 1),") }, "room \(index + 1) has no door") }
                }
            }
        }
    }

    @Test func secretDoorsAreOnlyMadeWhenAskedFor() {
        for kind in [SceneKind.dungeon, .building] {
            #expect(!make(kind, squares: 60).features(of: "Door").contains { $0.kind == "secret" })
            let found = (UInt64(1)...6).contains { seed in make(kind, squares: 60, seed: seed) { $0.secretDoors = true }.features(of: "Door").contains { $0.kind == "secret" } }
            #expect(found, "\(kind) never made a secret door")
        }
    }

    @Test func theAmountOfRoomsFollowsTheChoice() {
        for kind in [SceneKind.dungeon, .building] {
            func count(_ amount: SceneAmount) -> Int { make(kind, squares: 70, seed: 3) { $0.rooms = amount }.features(of: "Room").count }
            #expect(count(.few) < count(.some) && count(.some) < count(.many), "\(kind): \(count(.few)) \(count(.some)) \(count(.many))")
        }
    }

    @Test func widerCorridorsAreWider() {
        func narrowest(_ width: Int) -> Double {
            let scene = make(.dungeon, squares: 50, seed: 4) { $0.corridorWidth = width }
            return scene.features(of: "Corridor").map { feature -> Double in let b = box(feature); return min(b.x1 - b.x0, b.y1 - b.y0) }.min() ?? 0
        }
        #expect(narrowest(1) <= 1.0001 && narrowest(2) >= 2 - 0.0001)
    }

    @Test func loopsAddCorridors() {
        func corridors(_ loops: SceneAmount) -> Int { make(.dungeon, squares: 60, seed: 6) { $0.loops = loops }.features(of: "Corridor").count }
        #expect(corridors(.none) < corridors(.many))
    }

    // MARK: Stairs

    @Test(arguments: [SceneKind.dungeon, .cave, .building])
    func stairsAreMadeWhenAskedForAndAreInsideTheScene(kind: SceneKind) {
        let with = make(kind)
        let stairs = with.features(of: "Stairs")
        #expect(stairs.count == 2 && Set(stairs.map(\.kind)) == ["up", "down"], "\(kind): \(stairs.count) stairs")
        #expect(make(kind) { $0.stairs = false }.features(of: "Stairs").isEmpty)
        let floors = with.features(of: "Room") + with.features(of: "Cave") + with.features(of: "Corridor")
        for stair in stairs {
            let at = points(stair)[0]
            #expect(floors.contains { SettlementGenerator.contains(points($0), at) || Plane.distanceToEdge(at, points($0)) < 1e-6 }, "\(kind): \(stair.name) is not on a floor")
        }
    }

    // MARK: Cave

    @Test func aCaveIsOneBigFloorWithRockInIt() {
        for seed in UInt64(1)...6 {
            let scene = make(.cave, seed: seed)
            let caves = scene.features(of: "Cave")
            #expect(caves.count == 1, "seed \(seed): \(caves.count) caves")
            let area = Plane.area(points(caves[0])) / (square * square)
            #expect(area > 40 * 40 * 0.2 && area < 40 * 40 * 0.9, "seed \(seed): the floor is \(area) squares")
            // Rock stands inside the floor, and is made smaller than it.
            for rock in scene.features(of: "Rock") {
                #expect(SettlementGenerator.contains(points(caves[0]), Plane.centroid(points(rock))), "seed \(seed): rock outside the cave")
            }
        }
    }

    // MARK: Building

    private func rectangle(_ width: Double, _ height: Double, at origin: Double = 4) -> [GridPoint] {
        [(0.0, 0.0), (width, 0), (width, height), (0, height)].map { GridPoint(easting: (origin + $0.0) * square, northing: (origin + $0.1) * square) }
    }

    private func lShape() -> [GridPoint] {
        [(6.0, 8.0), (34, 8), (34, 20), (22, 20), (22, 33), (6, 33)].map { GridPoint(easting: $0.0 * square, northing: $0.1 * square) }
    }

    @Test func aBuildingFillsTheShapeOfItsOutline() {
        func extent(_ outline: [GridPoint]?) -> (width: Double, height: Double) {
            let scene = make(.building, squares: 60, seed: 2, outline: outline)
            let boxes = (scene.features(of: "Room") + scene.features(of: "Corridor")).map(box)
            return ((boxes.map(\.x1).max() ?? 0) - (boxes.map(\.x0).min() ?? 0), (boxes.map(\.y1).max() ?? 0) - (boxes.map(\.y0).min() ?? 0))
        }
        let wide = extent(rectangle(40, 20)), tall = extent(rectangle(20, 40))
        #expect(wide.width / wide.height > 1.5 && tall.height / tall.width > 1.5)
        // The size is the outline's, not the options'.
        #expect(wide.width > 33 && wide.width <= 40)
        // And the outline can be ignored.
        let ignored = make(.building, squares: 60, seed: 2, outline: rectangle(40, 20)) { $0.fitOutline = true }
        #expect(!ignored.features.isEmpty)
    }

    @Test func aBuildingThatIsNotARectangleKeepsEveryRoomInsideIt() {
        for seed in UInt64(1)...8 {
            let outline = lShape().map { V(x: $0.easting, y: $0.northing) }
            let scene = make(.building, squares: 40, seed: seed, outline: lShape()) { $0.secretDoors = true }
            let rooms = scene.features(of: "Room")
            #expect(rooms.count >= 4, "seed \(seed): \(rooms.count) rooms")
            let middle = Plane.centroid(outline)
            for room in rooms {
                // Every corner is inside, or on, the outline: pulled a hair towards the middle so the edge counts.
                #expect(points(room).allSatisfy { SettlementGenerator.contains(outline, $0 + (middle - $0) * 0.001) || Plane.distanceToEdge($0, outline) < 0.5 * square }, "seed \(seed): \(room.name) is outside the building")
            }
            // Nothing is made in the notch that the L leaves out.
            let notch = V(x: 28 * square, y: 27 * square)
            #expect(!rooms.contains { SettlementGenerator.contains(points($0), notch) })
            // Every room can be got into, through the hall or through other rooms.
            let doors = scene.features(of: "Door")
            for index in rooms.indices { #expect(doors.contains { $0.summary.contains("Room \(index + 1).") || $0.summary.contains("Room \(index + 1),") }, "seed \(seed): room \(index + 1) has no door") }
            #expect(scene.features(of: "Door").contains { $0.name == "Entrance" })
        }
    }

    private func circle(radius: Double, sides: Int = 48) -> [GridPoint] {
        (0..<sides).map { i in
            let angle = Double(i) / Double(sides) * 2 * .pi
            return GridPoint(easting: (20 + cos(angle) * radius) * square, northing: (20 + sin(angle) * radius) * square)
        }
    }

    @Test func aCurvedBuildingHasRoomsThatFollowItsWall() {
        for seed in UInt64(1)...6 {
            let outline = circle(radius: 16)
            let scene = make(.building, squares: 40, seed: seed, outline: outline)
            let round = outline.map { V(x: $0.easting, y: $0.northing) }
            let rooms = scene.features(of: "Room"), halls = scene.features(of: "Corridor")
            #expect(rooms.count >= 4, "seed \(seed): \(rooms.count) rooms")
            // Between them the rooms and the hall fill nearly all of the building, which rectangles alone didn't.
            let filled = (rooms + halls).map { Plane.area(points($0)) }.reduce(0, +)
            #expect(filled > Plane.area(round) * 0.85 && filled < Plane.area(round) * 1.02, "seed \(seed): the rooms fill \(filled / Plane.area(round))")
            // Rooms at the wall are not rectangles: their outer side follows the curve.
            #expect(rooms.contains { points($0).count > 4 }, "seed \(seed): every room is a rectangle")
            #expect(rooms.allSatisfy { points($0).allSatisfy { SettlementGenerator.contains(round, $0 + (Plane.centroid(round) - $0) * 0.001) || Plane.distanceToEdge($0, round) < 0.5 * square } })
            // Doors are still on the wall of a room.
            for door in scene.features(of: "Door") where door.name != "Entrance" {
                #expect(rooms.contains { Plane.distanceToEdge(points(door)[0], points($0)) < 1e-6 }, "seed \(seed): a door is not on a wall")
            }
        }
    }

    @Test func aBuildingHasAHallAndAnEntranceAndRoomsOffIt() {
        let scene = make(.building)
        let halls = scene.features(of: "Corridor")
        #expect(!halls.isEmpty && halls.allSatisfy { $0.name.hasPrefix("Hall") })
        #expect(scene.features(of: "Door").contains { $0.name == "Entrance" })
        // The hall is clear of the rooms.
        let hallBoxes = halls.map(box)
        for room in scene.features(of: "Room").map(box) {
            for hall in hallBoxes {
                let overlapX = min(room.x1, hall.x1) - max(room.x0, hall.x0), overlapY = min(room.y1, hall.y1) - max(room.y0, hall.y0)
                #expect(!(overlapX > 1e-6 && overlapY > 1e-6), "a room is on the hall")
            }
        }
    }

    // MARK: Outdoors

    @Test func aMarketSquareHasABuildingRoundEdgeAnInnStallsAndAFountain() {
        for seed in UInt64(1)...5 {
            let scene = make(.marketSquare, squares: 50, seed: seed)
            let ground = scene.features(of: "Square")
            #expect(ground.count == 1)
            let paving = points(ground[0])
            let buildings = scene.features(of: "Building")
            #expect(buildings.count >= 8, "seed \(seed): \(buildings.count) buildings")
            #expect(buildings.filter { $0.summary.hasPrefix("An inn") }.count == 1)
            // Buildings stand round the square and not on it.
            for building in buildings { #expect(!SettlementGenerator.contains(paving, Plane.centroid(points(building))), "a building is on the square") }
            // Each has a door.
            #expect(scene.features(of: "Door").count == buildings.count)
            // The stalls are on the square, apart from each other and the fountain.
            let stalls = scene.features(of: "Stall")
            #expect(!stalls.isEmpty)
            let fountain = points(scene.features(of: "Point of Interest")[0])[0]
            for (i, stall) in stalls.enumerated() {
                #expect(points(stall).allSatisfy { SettlementGenerator.contains(paving, $0 + (Plane.centroid(paving) - $0) * 0.001) }, "a stall is off the square")
                #expect(Plane.centroid(points(stall)).distance(to: fountain) > 3 * square)
                for other in stalls[(i + 1)...] {
                    let a = box(stall), b = box(other)
                    #expect(!(min(a.x1, b.x1) - max(a.x0, b.x0) > 1e-6 && min(a.y1, b.y1) - max(a.y0, b.y0) > 1e-6), "two stalls overlap")
                }
            }
        }
    }

    @Test func theAmountOfStallsAndTreesFollowsTheChoice() {
        func stalls(_ amount: SceneAmount) -> Int { make(.marketSquare, squares: 60, seed: 4) { $0.rooms = amount }.features(of: "Stall").count }
        #expect(stalls(.few) < stalls(.some) && stalls(.some) < stalls(.many))
        func trees(_ amount: SceneAmount) -> Int { make(.forestClearing, squares: 60, seed: 4) { $0.rooms = amount }.features(of: "Tree").count }
        #expect(trees(.few) < trees(.some) && trees(.some) < trees(.many))
    }

    @Test func aForestClearingHasTreesRoundAClearingAndATrackIn() {
        for seed in UInt64(1)...5 {
            let scene = make(.forestClearing, seed: seed)
            #expect(scene.features(of: "Forest").count == 1 && Plane.area(points(scene.features(of: "Forest")[0])) == scene.extent * scene.extent)
            let clearing = points(scene.features(of: "Clearing")[0])
            #expect(Plane.area(clearing) > scene.extent * scene.extent * 0.1)
            let trees = scene.features(of: "Tree")
            #expect(trees.count >= 10)
            for tree in trees { #expect(!SettlementGenerator.contains(clearing, Plane.centroid(points(tree))), "a tree is in the clearing") }
            // The track comes in from the edge of the map and ends at the clearing, and no tree is on it.
            let track = points(scene.features(of: "Road")[0])
            let first = track[0]
            #expect(first.x < 1e-6 || first.y < 1e-6 || abs(first.x - scene.extent) < 1e-6 || abs(first.y - scene.extent) < 1e-6)
            #expect(Plane.distanceToEdge(track[track.count - 1], clearing) < 2 * square)
            for tree in trees {
                let middle = Plane.centroid(points(tree))
                let nearest = zip(track, track.dropFirst()).map { SettlementGenerator.distance(from: middle, toSegment: $0, $1) }.min() ?? .infinity
                #expect(nearest > 0.8 * square, "a tree is on the track")
            }
            #expect(scene.features(of: "Door").isEmpty && scene.features(of: "Stairs").isEmpty)
        }
    }

    // MARK: Plan

    @MainActor
    @Test func theOutlineOfABuildingSetsTheSizeOfItsSceneMap() throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        world.ensureRootPlace(in: context)
        let hall = world.addPage(kind: .place, in: context)
        hall.attributes["core.placeType"] = .text("Building")
        // A 60 by 30 metre building, which is about 40 by 20 squares.
        let outline = [GridPoint(easting: 5_000, northing: 5_000), GridPoint(easting: 5_060, northing: 5_000), GridPoint(easting: 5_060, northing: 5_030), GridPoint(easting: 5_000, northing: 5_030)]
        _ = hall.setGeometry(.polygon(outline))
        var options = SceneOptions()
        options.kind = .building
        options.squares = 25
        let plan = World.scenePlan(for: hall, options: options)
        let centre = try #require(hall.geometry?.centre)
        let half = outline.map { max(abs($0.easting - centre.easting), abs($0.northing - centre.northing)) }.max() ?? 0
        #expect(plan.squares == Int((2 * half / square).rounded(.up)) + 4)
        #expect(plan.squares > options.squares)
        // The outline is in metres from the map's corner, centred as the place is.
        let local = try #require(plan.outline)
        let middle = Plane.centroid(local.map { V(x: $0.easting, y: $0.northing) })
        #expect(abs(middle.x - Double(plan.squares) * square / 2) < 1e-6 && abs(middle.y - Double(plan.squares) * square / 2) < 1e-6)
        // Not taking the outline, or not a building, the size is the options'.
        options.fitOutline = false
        #expect(World.scenePlan(for: hall, options: options).squares == 25 && World.scenePlan(for: hall, options: options).outline == nil)
        options.fitOutline = true
        options.kind = .dungeon
        #expect(World.scenePlan(for: hall, options: options).squares == 25)
        // A building too big for the biggest scene is shrunk to fit.
        let huge = [GridPoint(easting: 1_000, northing: 1_000), GridPoint(easting: 1_400, northing: 1_000), GridPoint(easting: 1_400, northing: 1_200), GridPoint(easting: 1_000, northing: 1_200)]
        let castle = world.addPage(kind: .place, in: context)
        _ = castle.setGeometry(.polygon(huge))
        options.kind = .building
        let big = World.scenePlan(for: castle, options: options)
        #expect(big.squares == 100)
        let bigLocal = try #require(big.outline)
        #expect(bigLocal.allSatisfy { (0...100 * square).contains($0.easting) && (0...100 * square).contains($0.northing) })
    }

    @MainActor
    @Test func aSettlementIsNotOfferedForABuildingAndAScenesDefaultIsItsInside() throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        let inn = world.addPage(kind: .place, in: context)
        inn.attributes["core.placeType"] = .text("Building")
        let village = world.addPage(kind: .place, in: context)
        village.attributes["core.placeType"] = .text("Settlement")
        let untyped = world.addPage(kind: .place, in: context)
        #expect(!inn.canHaveSettlementMap && village.canHaveSettlementMap && untyped.canHaveSettlementMap)
        #expect(SceneGenerator.defaultKind(forPlaceType: "Building") == .building)
        #expect(SceneGenerator.defaultKind(forPlaceType: "Settlement") == .dungeon && SceneGenerator.defaultKind(forPlaceType: nil) == .dungeon)
    }

    // MARK: Sizes

    @Test(arguments: SceneKind.allCases, [10, 25, 100])
    func everyKindWorksAtSmallAndLargeSizes(kind: SceneKind, squares: Int) {
        let started = Date()
        let scene = make(kind, squares: squares) { $0.secretDoors = true }
        #expect(!scene.features.isEmpty && scene.squares == squares)
        #expect(Date().timeIntervalSince(started) < 30)
    }

    @Test func sizesOutsideTheRangeAreHeldToIt() {
        #expect(make(.dungeon, squares: 3).squares == 10)
        #expect(make(.dungeon, squares: 5_000).squares == 100)
    }

    // MARK: Options

    @Test func theOptionsSurviveBeingSavedAndOldOnesStillOpen() throws {
        var options = SceneOptions()
        options.kind = .building
        options.squares = 55
        options.seed = 42
        options.rooms = .many
        options.corridorWidth = 2
        options.loops = .none
        options.secretDoors = true
        options.stairs = false
        options.fitOutline = false
        let decoded = try JSONDecoder().decode(SceneOptions.self, from: JSONEncoder().encode(options))
        #expect(decoded == options)
        let opened = try JSONDecoder().decode(SceneOptions.self, from: Data(#"{"seed":3}"#.utf8))
        #expect(opened.seed == 3 && opened.kind == .dungeon && opened.squares == 40 && opened.stairs)
    }

    @Test func thePlaceTypesTheSceneUsesHaveStyles() {
        for type in ["Room", "Corridor", "Cave", "Rock", "Door", "Stairs", "Stall", "Tree", "Clearing"] {
            #expect(PlaceStyle.types.contains(type) && PlaceStyle.style(forPlaceType: type) != .plain)
        }
    }
}

@MainActor
struct GeneratedSceneMapTests {
    private func makeBuilding() throws -> (World, Page, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        world.ensureRootPlace(in: context)
        let place = world.addPage(kind: .place, in: context)
        place.title = "The Gilded Gull"
        _ = place.setGeometry(.point(GridPoint(easting: 80_000, northing: 90_000)))
        return (world, place, context)
    }

    private func generated(_ world: World, _ map: WorldMap) -> [Page] { (world.pages ?? []).filter { $0.wasGenerated(by: map) && !$0.isDeleted } }

    @Test func aSceneMapOnTheGridAndAPlaceForEverythingAreMade() async throws {
        let (world, place, context) = try makeBuilding()
        var options = SceneOptions()
        options.squares = 30
        options.seed = 9
        let summary = try #require(await world.generateScene(for: place, options: options, in: context))
        let map = summary.map
        #expect(map.kind == .scene && map.isVector && map.place === place)
        #expect(map.gridColumns == 30 && map.gridRows == 30 && map.pixelWidth == 300 && map.pixelHeight == 300)
        // A square is five feet, so a pixel is a tenth of one.
        let calibration = try #require(map.calibration)
        #expect(abs(calibration.metresPerPixel * 10 - SceneOptions.squareMetres) < 1e-9)
        // And it is centred on the place.
        let middle = calibration.gridPoint(atX: 150, y: 150)
        #expect(abs(middle.easting - 80_000) < 1e-6 && abs(middle.northing - 90_000) < 1e-6)
        let expected = SceneGenerator.generate(options)
        let places = generated(world, map)
        #expect(places.count == expected.features.count && summary.created == places.count)
        #expect(places.allSatisfy { $0.parent === place && $0.parentSource == .manual && $0.geometry?.isValid == true })
        #expect(map.sceneOptions == options && map.settlementOptions == nil && map.worldOptions == nil)
        // The scene's places lie round the place, a few metres away.
        #expect(places.allSatisfy { ($0.geometry?.centre).map { $0.distance(to: GridPoint(easting: 80_000, northing: 90_000)) < 60 } ?? false })
        // None is hidden on its own map.
        #expect(map.visiblePlaces(among: places).count == places.count)
    }

    @Test func makingItAgainReplacesWhatWasMadeAndKeepsWhatWasEdited() async throws {
        let (world, place, context) = try makeBuilding()
        var options = SceneOptions()
        options.seed = 2
        let first = try #require(await world.generateScene(for: place, options: options, in: context))
        let before = generated(world, first.map)
        before.first { $0.attributeText("core.placeType") == "Room" }?.title = "The Cellar"
        let second = try #require(await world.generateScene(for: place, options: options, in: context))
        #expect(second.map === first.map && second.kept == 1 && second.replaced == before.count - 1)
        #expect((world.maps ?? []).filter { $0.kind == .scene }.count == 1)
    }

    @Test func theSceneOfABuildingFillsItsOutlineOnTheMapAbove() async throws {
        let (world, place, context) = try makeBuilding()
        place.attributes["core.placeType"] = .text("Building")
        // An L-shaped building about 45 by 40 metres.
        let corner = GridPoint(easting: 80_000, northing: 90_000)
        let outline = [(0.0, 0.0), (45, 0), (45, 18), (28, 18), (28, 40), (0, 40)].map { GridPoint(easting: corner.easting + $0.0, northing: corner.northing + $0.1) }
        _ = place.setGeometry(.polygon(outline))
        var options = SceneOptions()
        options.kind = .building
        options.seed = 6
        let summary = try #require(await world.generateScene(for: place, options: options, in: context))
        let plan = World.scenePlan(for: place, options: options)
        #expect(summary.map.gridColumns == plan.squares && summary.map.pixelWidth == plan.squares * 10)
        let rooms = generated(world, summary.map).filter { $0.attributeText("core.placeType") == "Room" }
        #expect(rooms.count >= 4)
        // The rooms are inside the building as it is on the map above, not just inside the scene's own grid.
        let building = PlaceGeometry.polygon(outline)
        for room in rooms {
            guard case .polygon(let corners)? = room.geometry else { Issue.record("a room is not an area"); continue }
            let middle = Plane.centroid(corners.map { V(x: $0.easting, y: $0.northing) })
            #expect(building.contains(GridPoint(easting: middle.x, northing: middle.y)), "\(room.title) is outside the building")
        }
    }

    @Test func aSettlementMapAndASceneMapOfTheSamePlaceDoNotClash() async throws {
        let (world, place, context) = try makeBuilding()
        let settlement = try #require(await world.generateSettlement(for: place, options: SettlementOptions(size: .hamlet, seed: 3), in: context))
        var options = SceneOptions()
        options.seed = 4
        let scene = try #require(await world.generateScene(for: place, options: options, in: context))
        #expect(settlement.map !== scene.map && settlement.map.kind == .settlement && scene.map.kind == .scene)
        // Each is made again on its own map, and neither takes the other's places.
        let again = try #require(await world.generateScene(for: place, options: options, in: context))
        #expect(again.map === scene.map)
        let settlementAgain = try #require(await world.generateSettlement(for: place, options: SettlementOptions(size: .hamlet, seed: 3), in: context))
        #expect(settlementAgain.map === settlement.map)
        #expect(settlement.map.settlementOptions != nil && settlement.map.sceneOptions == nil && scene.map.sceneOptions == options)
    }

    @Test func aPlaceNeedsAPositionAndMustNotBeTheWorld() async throws {
        let (world, place, context) = try makeBuilding()
        _ = place.setGeometry(nil)
        #expect(await world.generateScene(for: place, options: SceneOptions(), in: context) == nil)
        #expect(await world.generateScene(for: try #require(world.rootPlace), options: SceneOptions(), in: context) == nil)
    }

    @Test func theOptionsAndGridSurviveExportAndImport() async throws {
        let (world, place, context) = try makeBuilding()
        var options = SceneOptions()
        options.kind = .cave
        options.squares = 35
        options.seed = 12
        _ = try #require(await world.generateScene(for: place, options: options, in: context))
        try context.save()
        let wrapper = try WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: world))
        let contents = try WorldPackage.contents(of: wrapper)
        let target = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let (imported, _) = await WorldImporter.importWorld(contents, into: target)
        let map = try #require((imported.maps ?? []).first { $0.kind == .scene })
        #expect(map.sceneOptions == options && map.gridColumns == 35 && map.settlementOptions == nil)
        let importedPlace = try #require(map.place)
        let again = try #require(await imported.generateScene(for: importedPlace, options: options, in: target))
        #expect(again.map === map)
    }
}
