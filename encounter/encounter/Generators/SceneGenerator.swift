//
//  SceneGenerator.swift
//  encounter
//

import Foundation

/// What sort of place a scene is.
nonisolated enum SceneKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case dungeon, cave, building, marketSquare, forestClearing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dungeon: String(localized: "Dungeon")
        case .cave: String(localized: "Cave")
        case .building: String(localized: "Building")
        case .marketSquare: String(localized: "Market Square")
        case .forestClearing: String(localized: "Forest Clearing")
        }
    }

    /// Whether the scene is outdoors, with no walls, doors or stairs.
    var isOutdoors: Bool { self == .marketSquare || self == .forestClearing }

    var summary: String {
        switch self {
        case .dungeon: String(localized: "Rooms joined by corridors, with doors where they meet.")
        case .cave: String(localized: "A winding cavern of chambers and passages, with rock standing in it.")
        case .building: String(localized: "Rooms either side of a hall, each with a door. It fills the building’s outline if it has one.")
        case .marketSquare: String(localized: "An open square with stalls, a fountain, and shops and an inn round the edge.")
        case .forestClearing: String(localized: "A clearing among the trees, with a track leading in and rocks about.")
        }
    }
}

/// How much of something there is.
nonisolated enum SceneAmount: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, few, some, many

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: String(localized: "None")
        case .few: String(localized: "Few")
        case .some: String(localized: "Some")
        case .many: String(localized: "Many")
        }
    }

    /// Squares of floor for each room in a dungeon: fewer squares, more rooms.
    var squaresPerRoom: Double {
        switch self {
        case .none, .few: 220
        case .some: 130
        case .many: 80
        }
    }

    /// How wide a room is in a building, from and to.
    var buildingRoomWidth: ClosedRange<Int> {
        switch self {
        case .none, .few: 8...11
        case .some: 5...8
        case .many: 4...6
        }
    }

    /// The extra corridors of a dungeon, as a share of its rooms.
    var loopShare: Double {
        switch self {
        case .none: 0
        case .few: 0.15
        case .some: 0.3
        case .many: 0.5
        }
    }
}

/// What to generate for a scene: what kind, how big, and how it is laid out. The same options (and the same outline) always
/// give the same scene.
nonisolated struct SceneOptions: Codable, Equatable, Sendable {
    /// A square of the grid is five feet.
    static let squareMetres = 1.524
    /// The pixels in a square of a scene's map.
    static let pixelsPerSquare = 10

    var kind = SceneKind.dungeon
    /// Squares across and up.
    var squares = 40
    var seed: UInt64 = 1
    var rooms = SceneAmount.some
    /// How many squares wide a corridor is: one or two.
    var corridorWidth = 1
    var loops = SceneAmount.few
    var secretDoors = false
    var stairs = true
    /// For a building, whether to take its shape from the place's outline if it has one.
    var fitOutline = true
    /// The id of the `RootLanguage` the names of shops and inns are made in.
    var namingStyle = RootLanguages.englishID

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fresh = SceneOptions()
        kind = try container.decodeIfPresent(SceneKind.self, forKey: .kind) ?? fresh.kind
        squares = try container.decodeIfPresent(Int.self, forKey: .squares) ?? fresh.squares
        seed = try container.decodeIfPresent(UInt64.self, forKey: .seed) ?? fresh.seed
        rooms = try container.decodeIfPresent(SceneAmount.self, forKey: .rooms) ?? fresh.rooms
        corridorWidth = try container.decodeIfPresent(Int.self, forKey: .corridorWidth) ?? fresh.corridorWidth
        loops = try container.decodeIfPresent(SceneAmount.self, forKey: .loops) ?? fresh.loops
        secretDoors = try container.decodeIfPresent(Bool.self, forKey: .secretDoors) ?? fresh.secretDoors
        stairs = try container.decodeIfPresent(Bool.self, forKey: .stairs) ?? fresh.stairs
        fitOutline = try container.decodeIfPresent(Bool.self, forKey: .fitOutline) ?? fresh.fitOutline
        namingStyle = try container.decodeIfPresent(String.self, forKey: .namingStyle) ?? fresh.namingStyle
    }
}

/// What a scene generator made, in metres from the south-west corner of the map.
nonisolated struct GeneratedScene: Equatable, Sendable {
    var options: SceneOptions
    /// Squares across and up, and metres.
    var squares: Int
    var extent: Double
    var features: [GeneratedFeature]

    func features(of placeType: String) -> [GeneratedFeature] { features.filter { $0.placeType == placeType } }
}

nonisolated enum SceneGenerator {
    /// The kind of scene a place most likely wants: the inside of it, if it is a building.
    static func defaultKind(forPlaceType type: String?) -> SceneKind { type == "Building" ? .building : .dungeon }

    static func clamped(_ options: SceneOptions) -> SceneOptions {
        var options = options
        options.squares = min(100, max(10, options.squares))
        options.corridorWidth = min(2, max(1, options.corridorWidth))
        return options
    }

    /// The squares across a scene needs to be: the options' own, or for a building with an outline to fill, big enough to hold
    /// the outline centred on the map (up to the biggest a scene can be, in which case the outline is scaled down).
    static func squares(for options: SceneOptions, outline: [GridPoint]?, centre: GridPoint?) -> Int {
        let options = clamped(options)
        guard options.kind == .building, options.fitOutline, let outline, outline.count >= 3, let centre else { return options.squares }
        let half = outline.map { max(abs($0.easting - centre.easting), abs($0.northing - centre.northing)) }.max() ?? 0
        return min(100, max(10, Int((2 * half / SceneOptions.squareMetres).rounded(.up)) + 4))
    }

    /// The scene, made from the options. For a building with an outline, `outline` is that outline in metres from the
    /// south-west corner of the map, and the building fills it.
    static func generate(_ options: SceneOptions, outline: [GridPoint]? = nil) -> GeneratedScene {
        let options = clamped(options)
        var maker = SceneMaker(options: options, outline: outline)
        return maker.make()
    }

    /// The same, worked out away from the main actor, and nil if the work was cancelled.
    static func generateInBackground(_ options: SceneOptions, outline: [GridPoint]? = nil) async -> GeneratedScene? {
        let work = Task.detached(priority: .userInitiated) { generate(options, outline: outline) }
        return await withTaskCancellationHandler {
            let result = await work.value
            return Task.isCancelled ? nil : result
        } onCancel: {
            work.cancel()
        }
    }
}

/// A box of squares: its south-west corner and its size, all whole squares.
nonisolated struct SquareBox: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    var maxX: Int { x + width }
    var maxY: Int { y + height }
    var area: Int { width * height }
    var centre: (x: Double, y: Double) { (Double(x) + Double(width) / 2, Double(y) + Double(height) / 2) }

    func contains(_ cx: Int, _ cy: Int) -> Bool { cx >= x && cx < maxX && cy >= y && cy < maxY }

    /// Whether the boxes share any square, or touch.
    func overlaps(_ other: SquareBox, gap: Int = 0) -> Bool {
        x < other.maxX + gap && other.x < maxX + gap && y < other.maxY + gap && other.y < maxY + gap
    }
}

/// Lays out one scene on a grid of squares.
nonisolated struct SceneMaker {
    let options: SceneOptions
    let outline: [GridPoint]?
    var random: SeededRandom
    var names = NameBank()
    let n: Int

    var rooms: [SquareBox] = []
    /// Which rooms are joined by a corridor or a door.
    var links: [(Int, Int)] = []
    var features: [GeneratedFeature] = []
    /// The true shape of each room, when the building is not a rectangle, so doors can be put exactly on its wall.
    var wallShapes: [[GridPoint]]?

    init(options: SceneOptions, outline: [GridPoint]?) {
        self.options = options
        self.outline = outline
        names = NameBank(language: RootLanguages.language(options.namingStyle))
        n = options.squares
        random = SeededRandom(seed: options.seed &* 0x2545F4914F6CDD1D &+ 7)
    }

    // MARK: Grid to metres

    static func metres(_ squares: Double) -> Double { squares * SceneOptions.squareMetres }

    func point(_ x: Double, _ y: Double) -> GridPoint { GridPoint(easting: Self.metres(x), northing: Self.metres(y)) }

    func polygon(_ box: SquareBox) -> [GridPoint] {
        [point(Double(box.x), Double(box.y)), point(Double(box.maxX), Double(box.y)), point(Double(box.maxX), Double(box.maxY)), point(Double(box.x), Double(box.maxY))]
    }

    mutating func make() -> GeneratedScene {
        switch options.kind {
        case .dungeon: makeDungeon()
        case .cave: makeCave()
        case .building: makeBuilding()
        case .marketSquare: makeMarketSquare()
        case .forestClearing: makeForestClearing()
        }
        return GeneratedScene(options: options, squares: n, extent: Self.metres(Double(n)), features: features)
    }

    // MARK: Rooms

    private func description(of box: SquareBox) -> String {
        let size: String
        switch box.area {
        case ..<16: size = String(localized: "closet")
        case ..<30: size = String(localized: "small chamber")
        case ..<60: size = String(localized: "chamber")
        case ..<110: size = String(localized: "large chamber")
        default: size = String(localized: "great hall")
        }
        return String(localized: "A \(size), \(box.width) squares by \(box.height).")
    }

    /// Makes a place for each room, numbered from the north-west, and returns the number each was given.
    private mutating func addRooms(shapes: [[GridPoint]]? = nil) -> [Int] {
        let order = rooms.indices.sorted { (-rooms[$0].maxY, rooms[$0].x, $0) < (-rooms[$1].maxY, rooms[$1].x, $1) }
        var number = [Int](repeating: 0, count: rooms.count)
        for (position, index) in order.enumerated() {
            number[index] = position + 1
            features.append(GeneratedFeature(
                name: names.named(String(localized: "Room \(position + 1)")), placeType: "Room",
                summary: description(of: rooms[index]), shape: .polygon(shapes?[index] ?? polygon(rooms[index]))
            ))
        }
        return number
    }

    /// A door's place moved onto the wall of its room as it really is, if the room has been given the shape of the building.
    private func onWall(_ x: Double, _ y: Double, room: Int) -> (Double, Double) {
        guard let shapes = wallShapes, shapes.indices.contains(room), shapes[room].count >= 3 else { return (x, y) }
        let target = V(x: x * SceneOptions.squareMetres, y: y * SceneOptions.squareMetres)
        let corners = shapes[room].map { V(x: $0.easting, y: $0.northing) }
        var best = target
        var bestDistance = Double.infinity
        for i in corners.indices {
            let a = corners[i], b = corners[(i + 1) % corners.count]
            let ab = b - a
            let lengthSquared = ab.x * ab.x + ab.y * ab.y
            let t = lengthSquared > 0 ? min(1, max(0, ((target.x - a.x) * ab.x + (target.y - a.y) * ab.y) / lengthSquared)) : 0
            let q = V(x: a.x + ab.x * t, y: a.y + ab.y * t)
            if q.distance(to: target) < bestDistance { bestDistance = q.distance(to: target); best = q }
        }
        return (best.x / SceneOptions.squareMetres, best.y / SceneOptions.squareMetres)
    }

    private mutating func addDoor(at x: Double, _ y: Double, into room: Int, number: [Int], secret: Bool) {
        let (x, y) = onWall(x, y, room: room)
        let name = secret ? names.named(String(localized: "Secret door")) : names.named(String(localized: "Door"))
        let summary = secret
            ? String(localized: "A secret door into Room \(number[room]), hidden in the wall.")
            : String(localized: "A door into Room \(number[room]).")
        features.append(GeneratedFeature(name: name, placeType: "Door", summary: summary, shape: .point(point(x, y)), kind: secret ? "secret" : "door"))
    }

    private mutating func addStairs(at x: Double, _ y: Double, up: Bool) {
        features.append(GeneratedFeature(
            name: names.named(up ? String(localized: "Stairs up") : String(localized: "Stairs down")), placeType: "Stairs",
            summary: up ? String(localized: "A stair going up.") : String(localized: "A stair going down."), shape: .point(point(x, y)), kind: up ? "up" : "down"
        ))
    }

    /// The rooms by how many steps through doors and corridors they are from one room, and so the farthest.
    private func farthest(from start: Int) -> Int {
        var distance = [Int](repeating: -1, count: rooms.count)
        distance[start] = 0
        var queue = [start]
        var head = 0
        while head < queue.count {
            let here = queue[head]
            head += 1
            for (a, b) in links {
                let other = a == here ? b : (b == here ? a : -1)
                if other >= 0, distance[other] < 0 { distance[other] = distance[here] + 1; queue.append(other) }
            }
        }
        return rooms.indices.max { (distance[$0], -$0) < (distance[$1], -$1) } ?? start
    }

    // MARK: Dungeon

    private struct Node {
        var box: SquareBox
        var left = -1
        var right = -1
        var room = -1
    }

    private mutating func makeDungeon() {
        let minimum = 7
        var nodes = [Node(box: SquareBox(x: 1, y: 1, width: n - 2, height: n - 2))]
        let target = max(2, Int(Double((n - 2) * (n - 2)) / options.rooms.squaresPerRoom))
        var leaves = [0]
        while leaves.count < target {
            // The biggest leaf that can still be cut.
            let candidates = leaves.filter { nodes[$0].box.width >= minimum * 2 + 1 || nodes[$0].box.height >= minimum * 2 + 1 }
            guard let pick = candidates.max(by: { (nodes[$0].box.area, -$0) < (nodes[$1].box.area, -$1) }) else { break }
            let box = nodes[pick].box
            let horizontal = box.width >= box.height ? box.width >= minimum * 2 + 1 : !(box.height >= minimum * 2 + 1)
            let first: SquareBox, second: SquareBox
            if horizontal {
                let cut = Int(Double(box.width) * random.value(in: 0.4...0.6))
                let at = min(max(cut, minimum), box.width - minimum)
                first = SquareBox(x: box.x, y: box.y, width: at, height: box.height)
                second = SquareBox(x: box.x + at, y: box.y, width: box.width - at, height: box.height)
            } else {
                let cut = Int(Double(box.height) * random.value(in: 0.4...0.6))
                let at = min(max(cut, minimum), box.height - minimum)
                first = SquareBox(x: box.x, y: box.y, width: box.width, height: at)
                second = SquareBox(x: box.x, y: box.y + at, width: box.width, height: box.height - at)
            }
            nodes[pick].left = nodes.count
            nodes.append(Node(box: first))
            nodes[pick].right = nodes.count
            nodes.append(Node(box: second))
            leaves.removeAll { $0 == pick }
            leaves += [nodes.count - 2, nodes.count - 1]
        }

        // A room in each leaf, with a square of wall round it so rooms never touch.
        for leaf in leaves.sorted() {
            let box = nodes[leaf].box
            let widest = box.width - 2, tallest = box.height - 2
            guard widest >= 3, tallest >= 3 else { continue }
            let width = Int.random(in: min(4, widest)...widest, using: &random)
            let height = Int.random(in: min(4, tallest)...tallest, using: &random)
            let x = box.x + 1 + Int.random(in: 0...(widest - width), using: &random)
            let y = box.y + 1 + Int.random(in: 0...(tallest - height), using: &random)
            nodes[leaf].room = rooms.count
            rooms.append(SquareBox(x: x, y: y, width: width, height: height))
        }
        guard !rooms.isEmpty else { return }

        func roomsUnder(_ node: Int) -> [Int] {
            if nodes[node].room >= 0 { return [nodes[node].room] }
            guard nodes[node].left >= 0 else { return [] }
            return roomsUnder(nodes[node].left) + roomsUnder(nodes[node].right)
        }
        // Each pair of sibling regions is joined by the nearest pair of rooms across them.
        var joins: [(Int, Int)] = []
        for node in nodes.indices.reversed() where nodes[node].left >= 0 {
            let left = roomsUnder(nodes[node].left), right = roomsUnder(nodes[node].right)
            var best: (Int, Int, Double)?
            for a in left {
                for b in right {
                    let ca = rooms[a].centre, cb = rooms[b].centre
                    let gap = hypot(ca.x - cb.x, ca.y - cb.y)
                    if best == nil || gap < best!.2 { best = (a, b, gap) }
                }
            }
            if let best { joins.append((best.0, best.1)) }
        }
        // And a few more, so there are loops to go round.
        var extra = Int(Double(rooms.count) * options.loops.loopShare)
        var tries = 0
        while extra > 0, rooms.count > 3, tries < 60 {
            tries += 1
            let a = Int.random(in: 0..<rooms.count, using: &random), b = Int.random(in: 0..<rooms.count, using: &random)
            let ca = rooms[a].centre, cb = rooms[b].centre
            guard a != b, !joins.contains(where: { ($0.0 == a && $0.1 == b) || ($0.0 == b && $0.1 == a) }), hypot(ca.x - cb.x, ca.y - cb.y) < Double(n) * 0.6 else { continue }
            joins.append((a, b))
            extra -= 1
        }
        links = joins

        let number = addRooms()
        var corridorNumber = 0
        var doorSpots: [(x: Double, y: Double, room: Int)] = []
        for (a, b) in joins {
            let path = corridorPath(from: a, to: b)
            // Squares of corridor are the ones that aren't inside a room.
            var cells = Set<Int>()
            for cell in path where !rooms.contains(where: { $0.contains(cell.x, cell.y) }) { cells.insert(cell.y * n + cell.x) }
            var mask = [Bool](repeating: false, count: n * n)
            for c in cells { mask[c] = true }
            for loop in Contours.loops(mask: mask, width: n, height: n) where Plane.signedArea(loop) >= 1 {
                let points = loop.map { point($0.x, $0.y) }
                guard PlaceGeometry.polygon(points).isValid else { continue }
                corridorNumber += 1
                features.append(GeneratedFeature(
                    name: names.named(String(localized: "Corridor \(corridorNumber)")), placeType: "Corridor",
                    summary: String(localized: "A corridor between Room \(number[a]) and Room \(number[b])."), shape: .polygon(points)
                ))
            }
            doorSpots += doors(along: path, cells: cells, from: a, to: b)
        }
        // One door in each place a corridor meets a room, not a second where it runs on beside the wall.
        var placed: [(x: Double, y: Double, room: Int)] = []
        for spot in doorSpots where !placed.contains(where: { $0.room == spot.room && hypot($0.x - spot.x, $0.y - spot.y) < 3 }) {
            placed.append(spot)
            addDoor(at: spot.x, spot.y, into: spot.room, number: number, secret: options.secretDoors && random.chance(0.2))
        }

        if options.stairs {
            // The way in is the room nearest the south-west corner, and the way down the one farthest from it by corridor.
            let entrance = rooms.indices.min { (rooms[$0].x + rooms[$0].y, $0) < (rooms[$1].x + rooms[$1].y, $1) } ?? 0
            addStairs(at: Double(rooms[entrance].x) + 0.5, Double(rooms[entrance].y) + 0.5, up: true)
            let exit = farthest(from: entrance)
            if exit != entrance { addStairs(at: Double(rooms[exit].maxX) - 0.5, Double(rooms[exit].maxY) - 0.5, up: false) }
        }
    }

    /// The squares of a corridor from the middle of one room to the middle of another: along, then across, a corridor-width wide.
    private mutating func corridorPath(from a: Int, to b: Int) -> [(x: Int, y: Int)] {
        let ca = rooms[a].centre, cb = rooms[b].centre
        let ax = Int(ca.x), ay = Int(ca.y), bx = Int(cb.x), by = Int(cb.y)
        let width = options.corridorWidth
        var path: [(x: Int, y: Int)] = []
        func clampedSquare(_ x: Int, _ y: Int) -> (x: Int, y: Int) { (min(max(x, 1), n - 2), min(max(y, 1), n - 2)) }
        func line(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) {
            let steps = max(abs(x2 - x1), abs(y2 - y1))
            for step in 0...steps {
                let t = steps == 0 ? 0 : Double(step) / Double(steps)
                let x = x1 + Int((Double(x2 - x1) * t).rounded()), y = y1 + Int((Double(y2 - y1) * t).rounded())
                for dx in 0..<width { for dy in 0..<width { path.append(clampedSquare(x + dx, y + dy)) } }
            }
        }
        if random.chance(0.5) {
            line(ax, ay, bx, ay)
            line(bx, ay, bx, by)
        } else {
            line(ax, ay, ax, by)
            line(ax, by, bx, by)
        }
        return path
    }

    /// Where a corridor meets the rooms it is for and the ones it passes through: on the edge between the corridor's square
    /// and the room's.
    private func doors(along path: [(x: Int, y: Int)], cells: Set<Int>, from a: Int, to b: Int) -> [(x: Double, y: Double, room: Int)] {
        var events: [(position: Int, room: Int, x: Double, y: Double)] = []
        for (position, cell) in path.enumerated() where cells.contains(cell.y * n + cell.x) {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cell.x + dx, ny = cell.y + dy
                guard let room = rooms.firstIndex(where: { $0.contains(nx, ny) }) else { continue }
                // The middle of the edge between the two squares.
                events.append((position, room, Double(cell.x) + 0.5 + Double(dx) * 0.5, Double(cell.y) + 0.5 + Double(dy) * 0.5))
            }
        }
        var result: [(x: Double, y: Double, room: Int)] = []
        for room in Set(events.map(\.room)).sorted() {
            let mine = events.filter { $0.room == room }
            guard let first = mine.first, let last = mine.last else { continue }
            if room == a, room != b { result.append((first.x, first.y, room)) }
            else if room == b, room != a { result.append((last.x, last.y, room)) }
            else {
                // A room the corridor passes through gets a door each side.
                result.append((first.x, first.y, room))
                if last.position - first.position > 3 { result.append((last.x, last.y, room)) }
            }
        }
        return result
    }

    // MARK: Cave

    private mutating func makeCave() {
        var floor = [Bool](repeating: false, count: n * n)
        var fill = 0.46
        for _ in 0..<8 {
            var wall = [Bool](repeating: true, count: n * n)
            for y in 1..<(n - 1) { for x in 1..<(n - 1) { wall[y * n + x] = random.chance(fill) } }
            for _ in 0..<5 {
                var next = wall
                for y in 1..<(n - 1) {
                    for x in 1..<(n - 1) {
                        var walls = 0
                        for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 { if wall[(y + dy) * n + x + dx] { walls += 1 } } }
                        next[y * n + x] = walls >= 5 || (walls == 4 && wall[y * n + x])
                    }
                }
                wall = next
            }
            floor = largestPiece(of: wall.map { !$0 })
            if floor.filter({ $0 }).count >= n * n / 4 { break }
            fill -= 0.015
        }
        let cells = floor.indices.filter { floor[$0] }
        guard !cells.isEmpty else { return }

        var counter = 0
        for loop in Contours.loops(mask: floor, width: n, height: n) {
            let area = Plane.signedArea(loop)
            let smooth = Contours.rounded(closed: Contours.simplify(closed: loop, tolerance: 0.35), times: 2)
            if area > 0 {
                guard area >= 6 else { continue }
                let points = smooth.map { point(min(max($0.x, 0), Double(n)), min(max($0.y, 0), Double(n))) }
                guard PlaceGeometry.polygon(points).isValid else { continue }
                features.append(GeneratedFeature(name: names.named(String(localized: "The Cavern")), placeType: "Cave", summary: String(localized: "A winding cavern."), shape: .polygon(points)))
            } else if -area >= 3 {
                // Rock left standing in the floor.
                let points = Array(smooth.reversed()).map { point($0.x, $0.y) }
                guard PlaceGeometry.polygon(points).isValid else { continue }
                counter += 1
                features.append(GeneratedFeature(name: names.named(String(localized: "Rock \(counter)")), placeType: "Rock", summary: String(localized: "Rock standing in the cave."), shape: .polygon(points)))
            }
        }

        if options.stairs {
            let entrance = cells.min { (($0 % n) + ($0 / n), $0) < (($1 % n) + ($1 / n), $1) } ?? cells[0]
            addStairs(at: Double(entrance % n) + 0.5, Double(entrance / n) + 0.5, up: true)
            // The way down is the square that takes the most steps to reach from the way in.
            var distance = [Int](repeating: -1, count: n * n)
            distance[entrance] = 0
            var queue = [entrance]
            var head = 0
            while head < queue.count {
                let here = queue[head]
                head += 1
                for nb in [here - 1, here + 1, here - n, here + n] where nb >= 0 && nb < n * n && floor[nb] && distance[nb] < 0 {
                    distance[nb] = distance[here] + 1
                    queue.append(nb)
                }
            }
            if let far = cells.max(by: { (distance[$0], -$0) < (distance[$1], -$1) }), far != entrance {
                addStairs(at: Double(far % n) + 0.5, Double(far / n) + 0.5, up: false)
            }
        }
    }

    private func largestPiece(of mask: [Bool]) -> [Bool] {
        var seen = [Bool](repeating: false, count: mask.count)
        var best: [Int] = []
        for start in mask.indices where mask[start] && !seen[start] {
            var piece = [start]
            var queue = [start]
            seen[start] = true
            while let next = queue.popLast() {
                for nb in [next - 1, next + 1, next - n, next + n] where nb >= 0 && nb < mask.count && mask[nb] && !seen[nb] {
                    // Don't wrap from the end of one row to the start of the next.
                    if abs(nb % n - next % n) > 1 { continue }
                    seen[nb] = true
                    piece.append(nb)
                    queue.append(nb)
                }
            }
            if piece.count > best.count { best = piece }
        }
        var keep = [Bool](repeating: false, count: mask.count)
        for i in best { keep[i] = true }
        return keep
    }

    // MARK: Building

    /// Squares inside a building: those whose middle is inside the outline, or all of a plain rectangle.
    private func footprint() -> [Bool] {
        var inside = [Bool](repeating: false, count: n * n)
        if let outline, outline.count >= 3 {
            let corners = outline.map { V(x: $0.easting / SceneOptions.squareMetres, y: $0.northing / SceneOptions.squareMetres) }
            for y in 0..<n { for x in 0..<n { inside[y * n + x] = SettlementGenerator.contains(corners, V(x: Double(x) + 0.5, y: Double(y) + 0.5)) } }
            if inside.filter({ $0 }).count >= 30 { return inside }
            inside = [Bool](repeating: false, count: n * n)
        }
        let width = n - 2, height = max(12, Int(Double(width) * 0.7))
        let x0 = (n - width) / 2, y0 = (n - min(height, width)) / 2
        for y in y0..<(y0 + min(height, width)) { for x in x0..<(x0 + width) { inside[y * n + x] = true } }
        return inside
    }

    /// A building laid out in whatever shape it is: a hall along its long way, and rooms filling the rest, each with a door
    /// to the hall or to a room that has one.
    private mutating func makeBuilding() {
        let inside = footprint()
        let cells = inside.indices.filter { inside[$0] }
        guard let minX = cells.map({ $0 % n }).min(), let maxX = cells.map({ $0 % n }).max(),
              let minY = cells.map({ $0 / n }).min(), let maxY = cells.map({ $0 / n }).max() else { return }
        let horizontal = maxX - minX >= maxY - minY
        let hallWidth = options.corridorWidth + 1
        let spineStart = horizontal ? minY + (maxY - minY + 1 - hallWidth) / 2 : minX + (maxX - minX + 1 - hallWidth) / 2

        // The hall is the band along the middle, in the pieces big enough to walk down.
        var hall = [Bool](repeating: false, count: n * n)
        for c in cells {
            let along = horizontal ? c / n : c % n
            if along >= spineStart, along < spineStart + hallWidth { hall[c] = true }
        }
        hall = pieces(of: hall, atLeast: 6)

        // The rest is cut into rooms, a row of them at a time, as wide as the amount asked for.
        let range = options.rooms.buildingRoomWidth
        var taken = [Bool](repeating: false, count: n * n)
        for c in cells where hall[c] { taken[c] = true }
        func free(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < n && y < n && inside[y * n + x] && !taken[y * n + x] }
        var found: [SquareBox] = []
        for y in minY...maxY {
            for x in minX...maxX where free(x, y) {
                var run = 0
                while free(x + run, y) { run += 1 }
                var width = Int.random(in: range, using: &random)
                if run - width < range.lowerBound { width = run }
                width = min(width, run)
                var height = 1
                let deepest = Int.random(in: 4...8, using: &random)
                while height < deepest, (0..<width).allSatisfy({ free(x + $0, y + height) }) { height += 1 }
                for dy in 0..<height { for dx in 0..<width { taken[(y + dy) * n + x + dx] = true } }
                // Slivers are left as bare ground.
                if width >= 2, height >= 2, width * height >= 6 { found.append(SquareBox(x: x, y: y, width: width, height: height)) }
            }
        }
        guard !found.isEmpty else { return }

        // Which squares are hall, and which room each is in, so doors can be put where rooms meet.
        func hallEdges(of box: SquareBox) -> [(x: Int, y: Int, dx: Int, dy: Int)] {
            var edges: [(Int, Int, Int, Int)] = []
            for y in box.y..<box.maxY {
                for x in box.x..<box.maxX {
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0, ny >= 0, nx < n, ny < n, hall[ny * n + nx], !box.contains(nx, ny) { edges.append((x, y, dx, dy)) }
                    }
                }
            }
            return edges
        }
        func sharedEdges(_ a: SquareBox, _ b: SquareBox) -> [(x: Int, y: Int, dx: Int, dy: Int)] {
            var edges: [(Int, Int, Int, Int)] = []
            for y in a.y..<a.maxY {
                for x in a.x..<a.maxX {
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where b.contains(x + dx, y + dy) { edges.append((x, y, dx, dy)) }
                }
            }
            return edges
        }
        // Rooms reached from the hall, and then through each other's doors.
        var order: [Int] = []
        var parent = [Int](repeating: -2, count: found.count)
        for (index, box) in found.enumerated() where !hallEdges(of: box).isEmpty { parent[index] = -1; order.append(index) }
        if order.isEmpty { parent[0] = -1; order.append(0) }
        var head = 0
        while head < order.count {
            let here = order[head]
            head += 1
            for other in found.indices where parent[other] == -2 && !sharedEdges(found[here], found[other]).isEmpty {
                parent[other] = here
                order.append(other)
            }
        }
        let kept = order.sorted()
        var newIndex = [Int](repeating: -1, count: found.count)
        for (position, old) in kept.enumerated() { newIndex[old] = position }
        rooms = kept.map { found[$0] }
        // In a building that isn't a rectangle, each room (and the hall) is carried on out to the outline, so that the
        // rooms take the true shape of the building, curved or slanted walls and all.
        let reaching = extendedShapes(hall: hall)
        wallShapes = reaching?.rooms
        let number = addRooms(shapes: reaching?.rooms)

        var halls: [[GridPoint]] = reaching?.halls ?? []
        if reaching == nil {
            for loop in Contours.loops(mask: hall, width: n, height: n) where Plane.signedArea(loop) >= 1 { halls.append(loop.map { point($0.x, $0.y) }) }
        }
        for points in halls where PlaceGeometry.polygon(points).isValid {
            features.append(GeneratedFeature(name: names.named(String(localized: "Hall")), placeType: "Corridor", summary: String(localized: "A hall that the rooms open off."), shape: .polygon(points)))
        }

        // A door from each room to the hall, or to the room it was reached through.
        func midpoint(_ edge: (x: Int, y: Int, dx: Int, dy: Int)) -> (Double, Double) {
            (Double(edge.x) + 0.5 + Double(edge.dx) * 0.5, Double(edge.y) + 0.5 + Double(edge.dy) * 0.5)
        }
        var joined = Set<Int>()
        var depth = [Int](repeating: 0, count: rooms.count)
        for old in kept {
            let index = newIndex[old]
            if parent[old] == -1 {
                let edges = hallEdges(of: found[old])
                if let edge = edges.isEmpty ? nil : edges[Int.random(in: 0..<edges.count, using: &random)] {
                    let spot = midpoint(edge)
                    addDoor(at: spot.0, spot.1, into: index, number: number, secret: false)
                }
            } else {
                let edges = sharedEdges(found[old], found[parent[old]])
                if let edge = edges.isEmpty ? nil : edges[Int.random(in: 0..<edges.count, using: &random)] {
                    let spot = midpoint(edge)
                    addDoor(at: spot.0, spot.1, into: index, number: number, secret: false)
                }
                joined.insert(min(old, parent[old]) * 10_000 + max(old, parent[old]))
                depth[index] = depth[newIndex[parent[old]]] + 1
            }
            links.append((index, parent[old] >= 0 ? newIndex[parent[old]] : index))
        }
        // The way in, at the end of the hall.
        let hallCells = cells.filter { hall[$0] }
        if let end = hallCells.min(by: { (horizontal ? $0 % n : $0 / n, $0) < (horizontal ? $1 % n : $1 / n, $1) }) {
            let at = horizontal ? point(Double(end % n), Double(end / n) + 0.5) : point(Double(end % n) + 0.5, Double(end / n))
            features.append(GeneratedFeature(name: names.named(String(localized: "Entrance")), placeType: "Door", summary: String(localized: "The way into the building."), shape: .point(at), kind: "door"))
        }
        // Secret doors in the wall between rooms that have no door between them.
        if options.secretDoors {
            for a in found.indices where newIndex[a] >= 0 {
                for b in found.indices where b > a && newIndex[b] >= 0 && !joined.contains(a * 10_000 + b) && random.chance(0.35) {
                    let edges = sharedEdges(found[a], found[b])
                    guard !edges.isEmpty else { continue }
                    let spot = midpoint(edges[Int.random(in: 0..<edges.count, using: &random)])
                    addDoor(at: spot.0, spot.1, into: newIndex[b], number: number, secret: true)
                }
            }
        }
        if options.stairs {
            // Stairs up in the room farthest through the doors from the way in, and down in the first by the way in.
            let farthest = rooms.indices.max { (depth[$0], -$0) < (depth[$1], -$1) } ?? 0
            let nearest = rooms.indices.min { (horizontal ? rooms[$0].x : rooms[$0].y, $0) < (horizontal ? rooms[$1].x : rooms[$1].y, $1) } ?? 0
            addStairs(at: Double(rooms[farthest].x) + 0.5, Double(rooms[farthest].y) + 0.5, up: true)
            if nearest != farthest { addStairs(at: Double(rooms[nearest].x) + 0.5, Double(rooms[nearest].y) + 0.5, up: false) }
        }
    }

    /// The rooms and hall carried on out to the outline: each takes the ground nearest it, up to three squares beyond its
    /// rectangle, as far as the building goes. The grid (four to a square) only settles which room each bit of ground belongs
    /// to. The walls then come from the true outline, not from the grid: along the outside of the building a room's edge is
    /// the outline's own points, and between two rooms the wall is a single line that both share, so the rooms fit together
    /// with no gaps. Nil if the building has no outline.
    private func extendedShapes(hall: [Bool]) -> (rooms: [[GridPoint]], halls: [[GridPoint]])? {
        guard let outline, outline.count >= 3 else { return nil }
        let fine = 4
        let m = n * fine
        let ring = outline.map { V(x: $0.easting / SceneOptions.squareMetres * Double(fine), y: $0.northing / SceneOptions.squareMetres * Double(fine)) }
        var inside = [Bool](repeating: false, count: m * m)
        for y in 0..<m { for x in 0..<m { inside[y * m + x] = SettlementGenerator.contains(ring, V(x: Double(x) + 0.5, y: Double(y) + 0.5)) } }
        var owner = [Int](repeating: -1, count: m * m)
        let hallOwner = rooms.count
        for (index, room) in rooms.enumerated() {
            for y in (room.y * fine)..<(room.maxY * fine) { for x in (room.x * fine)..<(room.maxX * fine) where inside[y * m + x] { owner[y * m + x] = index } }
        }
        for c in hall.indices where hall[c] {
            for dy in 0..<fine {
                for dx in 0..<fine {
                    let x = (c % n) * fine + dx, y = (c / n) * fine + dy
                    if inside[y * m + x] { owner[y * m + x] = hallOwner }
                }
            }
        }
        // The ground that is left, taken by whichever room or hall is nearest, a ring at a time.
        var frontier = owner.indices.filter { owner[$0] >= 0 }
        for _ in 0..<(3 * fine) {
            var next: [Int] = []
            for cell in frontier {
                let x = cell % m, y = cell / m
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] where nx >= 0 && ny >= 0 && nx < m && ny < m {
                    let target = ny * m + nx
                    guard owner[target] < 0, inside[target] else { continue }
                    owner[target] = owner[cell]
                    next.append(target)
                }
            }
            frontier = next
            if frontier.isEmpty { break }
        }

        // What is across a wall: the outside of the building, ground nobody has taken, or another room.
        let outsideKey = -1, emptyKey = -2
        func key(_ x: Int, _ y: Int) -> Int {
            guard x >= 0, y >= 0, x < m, y < m, inside[y * m + x] else { return outsideKey }
            return owner[y * m + x] < 0 ? emptyKey : owner[y * m + x]
        }
        func touchesOutside(_ v: V) -> Bool {
            let x = Int(v.x), y = Int(v.y)
            return key(x - 1, y - 1) == outsideKey || key(x, y - 1) == outsideKey || key(x - 1, y) == outsideKey || key(x, y) == outsideKey
        }
        /// The nearest point on the outline, and which of its sides that is on.
        func nearestOnOutline(_ p: V) -> (point: V, side: Int, t: Double) {
            var best = (point: ring[0], side: 0, t: 0.0)
            var bestDistance = Double.infinity
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                let ab = b - a
                let lengthSquared = ab.x * ab.x + ab.y * ab.y
                let t = lengthSquared > 0 ? min(1, max(0, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSquared)) : 0
                let q = V(x: a.x + ab.x * t, y: a.y + ab.y * t)
                if q.distance(to: p) < bestDistance { bestDistance = q.distance(to: p); best = (q, i, t) }
            }
            return best
        }
        /// A corner of the grid, moved onto the outline if it is on the edge of the building. Everything that meets there moves
        /// the same way, so the rooms still meet.
        func snapped(_ v: V) -> V { touchesOutside(v) ? nearestOnOutline(v).point : v }
        /// The way along the outline from one point on it to another, going the way that follows the edge of the ground
        /// in `near`.
        func arc(from start: V, to end: V, near run: [V]) -> [V] {
            let a = nearestOnOutline(start), b = nearestOnOutline(end)
            func path(forward: Bool) -> [V] {
                var points = [a.point]
                var side = a.side
                var first = true
                while side != b.side || (first && (forward ? b.t < a.t : b.t > a.t)) {
                    first = false
                    if forward { side = (side + 1) % ring.count; points.append(ring[side]) } else { points.append(ring[side]); side = (side + ring.count - 1) % ring.count }
                    if points.count > ring.count + 2 { break }
                }
                points.append(b.point)
                return points
            }
            func length(_ p: [V]) -> Double { zip(p, p.dropFirst()).map { $0.distance(to: $1) }.reduce(0, +) }
            func middle(_ p: [V]) -> V {
                var half = length(p) / 2
                for (u, v) in zip(p, p.dropFirst()) {
                    let l = u.distance(to: v)
                    if half <= l, l > 0 { return V(x: u.x + (v.x - u.x) * half / l, y: u.y + (v.y - u.y) * half / l) }
                    half -= l
                }
                return p.last ?? start
            }
            let centre = V(x: run.map(\.x).reduce(0, +) / Double(max(run.count, 1)), y: run.map(\.y).reduce(0, +) / Double(max(run.count, 1)))
            let forward = path(forward: true), backward = path(forward: false)
            return middle(forward).distance(to: centre) <= middle(backward).distance(to: centre) ? forward : backward
        }
        func ordered(_ a: V, _ b: V) -> Bool { (a.x, a.y) <= (b.x, b.y) }

        func shapes(for who: Int) -> [[GridPoint]] {
            var mask = [Bool](repeating: false, count: m * m)
            for i in owner.indices where owner[i] == who { mask[i] = true }
            var result: [[GridPoint]] = []
            for loop in Contours.loops(mask: mask, width: m, height: m) where Plane.signedArea(loop) >= Double(fine * fine) {
                // What is across each step of the loop.
                let count = loop.count
                var across = [Int](repeating: 0, count: count)
                for i in 0..<count {
                    let p = loop[i], q = loop[(i + 1) % count]
                    let x = Int(p.x), y = Int(p.y)
                    switch (Int(q.x) - x, Int(q.y) - y) {
                    case (1, 0): across[i] = key(x, y - 1)
                    case (0, 1): across[i] = key(x, y)
                    case (-1, 0): across[i] = key(x - 1, y)
                    default: across[i] = key(x - 1, y - 1)
                    }
                }
                // Start at a place where what is across changes, so no run is cut in two.
                guard let startAt = (0..<count).first(where: { across[$0] != across[($0 + count - 1) % count] }) else {
                    // The whole edge is one thing.
                    let points = (across[0] == outsideKey ? ring : loop).map { GridPoint(easting: $0.x / Double(fine) * SceneOptions.squareMetres, northing: $0.y / Double(fine) * SceneOptions.squareMetres) }
                    if PlaceGeometry.polygon(points).isValid { result.append(points) }
                    continue
                }
                var polygon: [V] = []
                var i = 0
                while i < count {
                    let from = (startAt + i) % count
                    var length = 1
                    while i + length < count, across[(startAt + i + length) % count] == across[from] { length += 1 }
                    var run: [V] = (0...length).map { loop[(from + $0) % count] }
                    let startPoint = snapped(run[0]), endPoint = snapped(run[length])
                    var points: [V]
                    if across[from] == outsideKey {
                        points = arc(from: startPoint, to: endPoint, near: run)
                    } else {
                        // A wall inside the building, simplified the same way whichever room it is looked at from.
                        run[0] = startPoint
                        run[length] = endPoint
                        let flip = !ordered(run[0], run[length])
                        let canonical = flip ? Array(run.reversed()) : run
                        let simple = Contours.simplify(open: canonical, tolerance: 0.8)
                        points = flip ? Array(simple.reversed()) : simple
                    }
                    polygon += points.dropLast()
                    i += length
                }
                var cleaned: [V] = []
                for p in polygon where cleaned.last.map({ $0.distance(to: p) > 1e-9 }) ?? true { cleaned.append(p) }
                if let first = cleaned.first, let last = cleaned.last, cleaned.count > 1, first.distance(to: last) < 1e-9 { cleaned.removeLast() }
                let points = cleaned.map { point(min(max($0.x / Double(fine), 0), Double(n)), min(max($0.y / Double(fine), 0), Double(n))) }
                if PlaceGeometry.polygon(points).isValid { result.append(points) }
            }
            return result
        }
        var roomShapes: [[GridPoint]] = []
        for index in rooms.indices {
            // The biggest piece, which is the room; a room never comes out as two.
            let best = shapes(for: index).max { Plane.area($0.map { V(x: $0.easting, y: $0.northing) }) < Plane.area($1.map { V(x: $0.easting, y: $0.northing) }) }
            roomShapes.append(best ?? polygon(rooms[index]))
        }
        return (roomShapes, shapes(for: hallOwner))
    }

    /// The pieces of a mask that have at least `atLeast` squares.
    private func pieces(of mask: [Bool], atLeast: Int) -> [Bool] {
        var seen = [Bool](repeating: false, count: mask.count)
        var keep = [Bool](repeating: false, count: mask.count)
        for start in mask.indices where mask[start] && !seen[start] {
            var piece = [start]
            var queue = [start]
            seen[start] = true
            while let next = queue.popLast() {
                for nb in [next - 1, next + 1, next - n, next + n] where nb >= 0 && nb < mask.count && mask[nb] && !seen[nb] && abs(nb % n - next % n) <= 1 {
                    seen[nb] = true
                    piece.append(nb)
                    queue.append(nb)
                }
            }
            if piece.count >= atLeast { for c in piece { keep[c] = true } }
        }
        return keep
    }

    // MARK: Market square

    private static let goods = ["fruit", "cloth", "pots", "fish", "cheese", "trinkets", "spices", "leather goods", "bread", "herbs", "ribbons", "ironmongery"]

    /// Buildings along one side of the square, with a street left between some of them.
    private mutating func buildingRow(from start: Int, to end: Int, make: (Int, Int) -> SquareBox) -> [SquareBox] {
        var row: [SquareBox] = []
        var at = start
        while at < end {
            var width = Int.random(in: 4...8, using: &random)
            if end - at - width < 4 { width = end - at }
            if width < 3 { break }
            if !row.isEmpty, random.chance(0.18) { at += 3; continue }
            row.append(make(at, width))
            at += width
        }
        return row
    }

    /// An open paved square with a fountain in the middle, stalls across it, and shops and an inn round the edge.
    private mutating func makeMarketSquare() {
        let depth = min(8, max(2, n / 8))
        let low = 2, high = n - 2
        let ground = SquareBox(x: low + depth, y: low + depth, width: high - low - 2 * depth, height: high - low - 2 * depth)
        guard ground.width >= 2, ground.height >= 2 else { return }
        features.append(GeneratedFeature(name: names.marketSquare(inScene: true), placeType: "Square", summary: String(localized: "The open paved square, where the market is held."), shape: .polygon(polygon(ground))))

        // The buildings, each with a door on the side facing the square.
        var buildings: [(box: SquareBox, door: (Double, Double))] = []
        for box in buildingRow(from: low, to: high, make: { SquareBox(x: $0, y: low, width: $1, height: depth) }) {
            buildings.append((box, (Double(box.x + box.width / 2) + 0.5, Double(box.maxY))))
        }
        for box in buildingRow(from: low, to: high, make: { SquareBox(x: $0, y: high - depth, width: $1, height: depth) }) {
            buildings.append((box, (Double(box.x + box.width / 2) + 0.5, Double(box.y))))
        }
        for box in buildingRow(from: low + depth, to: high - depth, make: { SquareBox(x: low, y: $0, width: depth, height: $1) }) {
            buildings.append((box, (Double(box.maxX), Double(box.y + box.height / 2) + 0.5)))
        }
        for box in buildingRow(from: low + depth, to: high - depth, make: { SquareBox(x: high - depth, y: $0, width: depth, height: $1) }) {
            buildings.append((box, (Double(box.x), Double(box.y + box.height / 2) + 0.5)))
        }
        buildings.sort { (-$0.box.maxY, $0.box.x) < (-$1.box.maxY, $1.box.x) }
        for (index, building) in buildings.enumerated() {
            let name: String, summary: String
            if index == buildings.count / 2 {
                name = names.inn(using: &random)
                summary = String(localized: "An inn and tavern on the square.")
            } else {
                let shop = names.shop(using: &random)
                name = shop.name
                summary = String(localized: "\(shop.summary) on the square.")
            }
            features.append(GeneratedFeature(name: name, placeType: "Building", summary: summary, shape: .polygon(polygon(building.box))))
            features.append(GeneratedFeature(
                name: names.named(String(localized: "Door of \(name)")), placeType: "Door", summary: String(localized: "The door of \(name)."),
                shape: .point(point(building.door.0, building.door.1)), kind: "door"
            ))
        }

        // The fountain in the middle, and the stalls in rows across the rest.
        let middle = ground.centre
        features.append(GeneratedFeature(name: names.named(String(localized: "The Fountain")), placeType: "Point of Interest", summary: String(localized: "A fountain in the middle of the square."), shape: .point(point(middle.x, middle.y)), kind: "fountain"))
        let share: Double
        switch options.rooms {
        case .none, .few: share = 0.3
        case .some: share = 0.55
        case .many: share = 0.8
        }
        var stallNumber = 0
        var y = ground.y + 1
        while y < ground.maxY - 1 {
            var x = ground.x + 1
            while x < ground.maxX - 3 {
                let width = random.chance(0.5) ? 3 : 2
                let spot = SquareBox(x: x, y: y, width: width, height: 1)
                let farFromFountain = hypot(Double(x) + Double(width) / 2 - middle.x, Double(y) + 0.5 - middle.y) > 3.5
                if farFromFountain, random.chance(share) {
                    stallNumber += 1
                    let goods = Self.goods[Int.random(in: 0..<Self.goods.count, using: &random)]
                    features.append(GeneratedFeature(
                        name: names.named(String(localized: "Stall \(stallNumber)")), placeType: "Stall",
                        summary: String(localized: "A stall selling \(goods)."), shape: .polygon(polygon(spot))
                    ))
                }
                x += width + 2
            }
            y += 3
        }
    }

    // MARK: Forest clearing

    private func regular(_ centre: V, radius: Double, sides: Int, turn: Double = 0) -> [GridPoint] {
        (0..<sides).map { i in
            let angle = turn + Double(i) / Double(sides) * 2 * .pi
            return point(min(max(centre.x + cos(angle) * radius, 0), Double(n)), min(max(centre.y + sin(angle) * radius, 0), Double(n)))
        }
    }

    /// A clearing among the trees, with a track leading in, trees crowding round it, and rocks and a campfire about.
    private mutating func makeForestClearing() {
        let size = Double(n)
        features.append(GeneratedFeature(name: names.named(String(localized: "The Forest")), placeType: "Forest", summary: String(localized: "Woodland all round."), shape: .polygon([point(0, 0), point(size, 0), point(size, size), point(0, size)])))

        // The clearing is a rounded blob: a radius that swells and shrinks as it goes round.
        let centre = V(x: size / 2 + random.value(in: -0.06...0.06) * size, y: size / 2 + random.value(in: -0.06...0.06) * size)
        let base = size * random.value(in: 0.24...0.32)
        let phases = (0..<3).map { _ in random.value(in: 0...(2 * .pi)) }
        func radius(at angle: Double) -> Double {
            base * (1 + 0.14 * sin(2 * angle + phases[0]) + 0.1 * sin(3 * angle + phases[1]) + 0.06 * sin(5 * angle + phases[2]))
        }
        let edge = (0..<56).map { i -> V in
            let angle = Double(i) / 56 * 2 * .pi
            return V(x: centre.x + cos(angle) * radius(at: angle), y: centre.y + sin(angle) * radius(at: angle))
        }
        let clearing = edge.map { point($0.x, $0.y) }
        features.append(GeneratedFeature(name: names.named(String(localized: "The Clearing")), placeType: "Clearing", summary: String(localized: "An open clearing in the forest."), shape: .polygon(clearing)))

        // A track in from the edge of the map, bending as it goes.
        let side = Int.random(in: 0..<4, using: &random)
        let along = random.value(in: 0.25...0.75) * size
        let start: V = [V(x: along, y: 0), V(x: size, y: along), V(x: along, y: size), V(x: 0, y: along)][side]
        let towards = (centre - start).unit
        let meets = start + towards * max(0, (centre - start).length - radius(at: atan2(start.y - centre.y, start.x - centre.x)) + 0.5)
        var track: [V] = []
        for step in 0...5 {
            let t = Double(step) / 5
            let bend = towards.perpendicular * sin(t * .pi) * random.value(in: 1.5...3.5)
            track.append(V(x: start.x + (meets.x - start.x) * t, y: start.y + (meets.y - start.y) * t) + (step == 0 || step == 5 ? V(x: 0, y: 0) : bend))
        }
        let smoothTrack = Curves.smooth(track, steps: 4).map { point(min(max($0.x, 0), size), min(max($0.y, 0), size)) }
        features.append(GeneratedFeature(name: names.named(String(localized: "The Forest Track")), placeType: "Road", summary: String(localized: "A track leading into the clearing."), shape: .line(smoothTrack)))
        let trackLine = Curves.smooth(track, steps: 4)

        // A few rocks in and about the clearing, and a campfire.
        for i in 0..<Int.random(in: 2...5, using: &random) {
            let angle = random.value(in: 0...(2 * .pi))
            let spot = centre + V(x: cos(angle), y: sin(angle)) * (radius(at: angle) * random.value(in: 0.2...1.05))
            let rock = regular(spot, radius: random.value(in: 0.6...1.1), sides: 6, turn: random.value(in: 0...1))
            guard PlaceGeometry.polygon(rock).isValid else { continue }
            features.append(GeneratedFeature(name: names.named(String(localized: "Boulder \(i + 1)")), placeType: "Rock", summary: String(localized: "A boulder."), shape: .polygon(rock)))
        }
        features.append(GeneratedFeature(name: names.named(String(localized: "Campfire")), placeType: "Point of Interest", summary: String(localized: "The ashes of a campfire."), shape: .point(point(centre.x + 1.5, centre.y - 1)), kind: "campfire"))

        // Trees crowd round the edge of the clearing, never on it or on the track.
        let wanted: Int
        switch options.rooms {
        case .none, .few: wanted = 20
        case .some: wanted = 40
        case .many: wanted = 70
        }
        var trees: [(V, Double)] = []
        var tries = 0
        while trees.count < wanted, tries < wanted * 30 {
            tries += 1
            let spot = V(x: random.value(in: 0.5...(size - 0.5)), y: random.value(in: 0.5...(size - 0.5)))
            let angle = atan2(spot.y - centre.y, spot.x - centre.x)
            let treeRadius = random.value(in: 0.8...1.3)
            guard (spot - centre).length > radius(at: angle) + treeRadius * 0.9, spot.x > treeRadius, spot.y > treeRadius, spot.x < size - treeRadius, spot.y < size - treeRadius else { continue }
            guard trackLine.indices.dropLast().allSatisfy({ SettlementGenerator.distance(from: spot, toSegment: trackLine[$0], trackLine[$0 + 1]) > treeRadius + 0.8 }) else { continue }
            guard trees.allSatisfy({ ($0.0 - spot).length > ($0.1 + treeRadius) * 0.95 }) else { continue }
            trees.append((spot, treeRadius))
        }
        for (i, tree) in trees.enumerated() {
            features.append(GeneratedFeature(
                name: names.named(String(localized: "Tree \(i + 1)")), placeType: "Tree", summary: String(localized: "A tree."),
                shape: .polygon(regular(tree.0, radius: tree.1, sides: 8, turn: random.value(in: 0...1)))
            ))
        }
    }
}
