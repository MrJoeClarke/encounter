//
//  WorldMaker.swift
//  encounter
//

import Foundation

/// Lays out one world on a coarse grid: land and sea, mountains and forest, rivers, realms and their capitals, the other
/// settlements, and the roads between them.
nonisolated struct WorldMaker {
    let options: WorldOptions
    var random: SeededRandom
    var names = NameBank()
    let noise: ValueNoise
    /// Cells across and up.
    let n: Int
    let extent: Double
    /// Metres across one cell.
    let cell: Double
    let fixed: [FixedSettlement]

    var height: [Double]
    var elevation: [Double]
    var land: [Bool]
    var mountain: [Bool]
    var forest: [Bool]
    var river: [Bool]
    var flowTo: [Int]
    var riverLines: [[Int]] = []

    struct Place {
        var name: String
        var kind: WorldLocation.Kind
        var position: V
        var isCapital: Bool
        var emit: Bool
        var cell: Int
        var realm = -1
    }
    var places: [Place] = []
    var realmOf: [Int]
    var realmCount = 0
    var roadEdges = Set<Int>()
    var roadCell: [Bool]
    /// A little unevenness in how hard each cell is to cross, so borders and roads don't run in straight lines.
    var wobble: [Double]

    init(options: WorldOptions, fixed: [FixedSettlement]) {
        self.options = options
        self.fixed = fixed
        names = NameBank(languages: options.languages(forRealm: -1))
        let size = 160
        n = size
        extent = max(options.width, 1_000)
        cell = max(options.width, 1_000) / Double(size)
        random = SeededRandom(seed: options.seed &* 0x2545F4914F6CDD1D &+ 99)
        noise = ValueNoise(seed: options.seed &* 0x9E3779B1 &+ 12_345)
        height = [Double](repeating: 0, count: size * size)
        elevation = height
        land = [Bool](repeating: false, count: size * size)
        mountain = land
        forest = land
        river = land
        roadCell = land
        wobble = [Double](repeating: 1, count: size * size)
        flowTo = [Int](repeating: -1, count: size * size)
        realmOf = [Int](repeating: -1, count: size * size)
    }

    // MARK: Grid

    func neighbours4(_ i: Int) -> [Int] {
        let x = i % n, y = i / n
        var result: [Int] = []
        if x > 0 { result.append(i - 1) }
        if x < n - 1 { result.append(i + 1) }
        if y > 0 { result.append(i - n) }
        if y < n - 1 { result.append(i + n) }
        return result
    }

    /// The cells round one, with how far each is in cells (a corner is farther).
    func neighbours8(_ i: Int) -> [(cell: Int, distance: Double)] {
        let x = i % n, y = i / n
        var result: [(Int, Double)] = []
        for dy in -1...1 {
            for dx in -1...1 where dx != 0 || dy != 0 {
                let nx = x + dx, ny = y + dy
                if nx >= 0, ny >= 0, nx < n, ny < n { result.append((ny * n + nx, dx != 0 && dy != 0 ? 1.4142 : 1)) }
            }
        }
        return result
    }

    /// Where a cell's line goes through it: near the middle, but each cell a little differently, the same every time, so
    /// that lines which meet in a cell meet at the same point.
    func waypoint(_ i: Int) -> V {
        let x = Double(i % n), y = Double(i / n)
        return centre(of: i) + V(x: (noise.value(x * 1.9 + 0.3, y * 1.9 + 0.7, salt: 11) - 0.5) * 0.6 * cell, y: (noise.value(x * 1.9 + 5.1, y * 1.9 + 2.3, salt: 12) - 0.5) * 0.6 * cell)
    }

    func centre(of i: Int) -> V { V(x: (Double(i % n) + 0.5) * cell, y: (Double(i / n) + 0.5) * cell) }

    func cellIndex(of point: V) -> Int {
        let x = min(max(Int(point.x / cell), 0), n - 1), y = min(max(Int(point.y / cell), 0), n - 1)
        return y * n + x
    }

    /// The cells of a mask in pieces of at least `minimum` cells (or only the biggest piece).
    func filtered(_ mask: [Bool], minimum: Int, onlyLargest: Bool = false) -> [Bool] {
        var seen = [Bool](repeating: false, count: mask.count)
        var pieces: [[Int]] = []
        for start in mask.indices where mask[start] && !seen[start] {
            var piece = [start]
            var queue = [start]
            seen[start] = true
            while let next = queue.popLast() {
                for nb in neighbours4(next) where mask[nb] && !seen[nb] {
                    seen[nb] = true
                    piece.append(nb)
                    queue.append(nb)
                }
            }
            pieces.append(piece)
        }
        var keep = [Bool](repeating: false, count: mask.count)
        if onlyLargest {
            if let biggest = pieces.max(by: { $0.count < $1.count }) { for i in biggest { keep[i] = true } }
        } else {
            for piece in pieces where piece.count >= minimum { for i in piece { keep[i] = true } }
        }
        return keep
    }

    // MARK: Make

    mutating func make() -> GeneratedWorld {
        terrain()
        rivers()
        settle()
        realms()
        roads()
        return GeneratedWorld(options: options, extent: extent, features: features())
    }

    // MARK: Land

    /// A number from 0 to 1 that depends only on the seed and the salt, for the few choices a shape makes (which side, which way).
    private func choice(_ salt: Int) -> Double { noise.value(0.37, 0.61, salt: 100 + salt) }

    /// How much land each cell wants, from the shape: higher is land, lower is sea. The cut that makes it land is made later, so
    /// the share of land is the shape's whatever the numbers are. Every shape bends its outline with a warp, so no two coasts match.
    private func landPotential(side: Int) -> [Double] {
        var potential = [Double](repeating: 0, count: n * n)
        // Islands for an archipelago: where they are and how big.
        let islands = options.shape == .archipelago ? archipelagoIslands() : []
        for y in 0..<n {
            for x in 0..<n {
                let u = (Double(x) + 0.5) / Double(n), v = (Double(y) + 0.5) / Double(n)
                let h = noise.fractal(u * 4, v * 4, octaves: 5, salt: 1)
                // The outline is bent by a slow noise, more for some seeds than others.
                let bend = 0.22 + 0.2 * choice(1)
                let u2 = u + (noise.fractal(u * 2.3 + 3.1, v * 2.3 + 1.7, octaves: 3, salt: 21) - 0.5) * bend * 1.6
                let v2 = v + (noise.fractal(u * 2.3 + 8.4, v * 2.3 + 6.2, octaves: 3, salt: 22) - 0.5) * bend * 1.6
                var value: Double
                switch options.shape {
                case .continent:
                    // A blob that is longer one way than the other, turned to a different angle for each seed.
                    let aspect = 0.8 + 0.45 * choice(2), angle = choice(3) * .pi
                    let px = u2 - 0.5, py = v2 - 0.5
                    let rx = px * cos(angle) + py * sin(angle), ry = -px * sin(angle) + py * cos(angle)
                    let d = hypot(rx * aspect, ry / aspect) * 2
                    value = h * 0.75 - 0.45 * d * d
                case .coast:
                    let e = [v2, 1 - v2, u2, 1 - u2][side]
                    value = h * 0.75 - 0.9 * (1 - e) * (1 - e)
                case .peninsula:
                    // Along the edge (b) and in from it (a), for whichever side the neck is on.
                    let (a, b): (Double, Double) = [(v2, u2), (1 - v2, u2), (u2, v2), (1 - u2, v2)][side]
                    let start = 0.38 + 0.24 * choice(4), sway = 0.05 + 0.07 * choice(5), phase = choice(6) * 6
                    let spine = start + sway * sin(a * 4 + phase)
                    // A narrow neck at the edge, widening to the body, then closing at the tip.
                    let bulge = exp(-pow((a - 0.6) / 0.18, 2))
                    let width = 0.07 + 0.23 * bulge
                    let closeness = (width - abs(b - spine)) / width
                    let tip = a > 0.9 ? -(a - 0.9) * 8 : 0
                    value = h * 0.5 + closeness * 0.8 + tip - 0.15
                case .archipelago:
                    var best = -2.0
                    for island in islands {
                        let d = hypot(u2 - island.x, v2 - island.y)
                        best = max(best, 1 - d / island.radius)
                    }
                    value = h * 0.45 + best * 0.85 - 0.25
                }
                potential[y * n + x] = value
            }
        }
        return potential
    }

    /// Where the islands of an archipelago are, as centres and radii in units of the map's width. Few is one for each realm, spread
    /// out; many is a good many smaller ones, a few of them bigger.
    private func archipelagoIslands() -> [(x: Double, y: Double, radius: Double)] {
        let count: Int
        switch options.islands {
        case .none, .few: count = max(1, min(8, options.realms))
        case .many: count = min(30, max(14, options.realms * 4))
        }
        var rng = SeededRandom(seed: options.seed &* 0x9E3779B97F4A7C15 &+ 77)
        // Roughly the share of the map that is land, divided between the islands, each a little different in size.
        let basic = (options.shape.landShare * 0.9 / (Double(count) * .pi)).squareRoot()
        var spacing = (0.62 * 0.62 / Double(count)).squareRoot()
        var result: [(x: Double, y: Double, radius: Double)] = []
        while result.count < count {
            result = []
            var tries = 0
            while result.count < count, tries < 3_000 {
                tries += 1
                let x = rng.value(in: 0.16...0.84), y = rng.value(in: 0.16...0.84)
                guard result.allSatisfy({ hypot($0.x - x, $0.y - y) > spacing }) else { continue }
                let size = options.islands == .many ? rng.value(in: 0.4...1.25) : rng.value(in: 0.8...1.2)
                result.append((x, y, basic * size))
            }
            // Too tight to fit them all: give each a little more room to be found, and try again.
            if result.count < count { spacing *= 0.9 }
        }
        return result
    }

    /// The pieces of land, each cell numbered by the piece it is in (-1 for sea).
    func landPieces() -> [Int] {
        var label = [Int](repeating: -1, count: n * n)
        var next = 0
        for start in land.indices where land[start] && label[start] < 0 {
            label[start] = next
            var queue = [start]
            while let at = queue.popLast() {
                for nb in neighbours4(at) where land[nb] && label[nb] < 0 { label[nb] = next; queue.append(nb) }
            }
            next += 1
        }
        return label
    }

    private mutating func terrain() {
        let side = Int(options.seed % 4)
        for i in wobble.indices {
            wobble[i] = 1 + 0.7 * noise.value(Double(i % n) / 9, Double(i / n) / 9, salt: 7)
        }
        height = landPotential(side: side)
        let sorted = height.sorted()
        let level = sorted[min(sorted.count - 1, max(0, Int(Double(sorted.count) * (1 - options.shape.landShare))))]
        let margin = 3
        var isLand = height.indices.map { i -> Bool in
            let x = i % n, y = i / n
            guard height[i] > level else { return false }
            let inside = x >= margin && y >= margin && x < n - margin && y < n - margin
            switch options.shape {
            case .continent, .archipelago: return inside
            case .coast:
                // Sea along one side only: the land runs off the map on the others.
                switch side {
                case 0: return y >= margin
                case 1: return y < n - margin
                case 2: return x >= margin
                default: return x < n - margin
                }
            case .peninsula:
                // The neck joins the land to the edge it starts at, and the sea is on the other three sides.
                switch side {
                case 0: return x >= margin && x < n - margin && y < n - margin
                case 1: return x >= margin && x < n - margin && y >= margin
                case 2: return y >= margin && y < n - margin && x < n - margin
                default: return y >= margin && y < n - margin && x >= margin
                }
            }
        }
        // Small bits are left out, except in an archipelago, whose islands may be small; a peninsula is one piece.
        let smallest = options.shape == .archipelago ? 14 : max(12, n * n / 100)
        isLand = filtered(isLand, minimum: smallest, onlyLargest: options.shape == .peninsula)
        // Sea that the sea can't reach is a lake, and is filled in, so every river has the sea to run to.
        var reached = [Bool](repeating: false, count: n * n)
        var queue: [Int] = []
        for i in isLand.indices where !isLand[i] && (i % n == 0 || i / n == 0 || i % n == n - 1 || i / n == n - 1) { reached[i] = true; queue.append(i) }
        while let next = queue.popLast() {
            for nb in neighbours4(next) where !isLand[nb] && !reached[nb] { reached[nb] = true; queue.append(nb) }
        }
        for i in isLand.indices where !isLand[i] && !reached[i] { isLand[i] = true }
        land = isLand
        let top = height.indices.filter { land[$0] }.map { height[$0] }.max() ?? level + 1
        for i in height.indices where land[i] { elevation[i] = min(1, max(0, (height[i] - level) / max(top - level, 1e-9))) }

        let landCells = height.indices.filter { land[$0] }
        // Mountains are the highest and most ridged ground.
        if options.mountains.mountainShare > 0, !landCells.isEmpty {
            var scored: [(Double, Int)] = []
            for i in landCells where elevation[i] > 0.15 {
                let u = (Double(i % n) + 0.5) / Double(n), v = (Double(i / n) + 0.5) / Double(n)
                let ridge = 1 - abs(2 * noise.fractal(u * 6, v * 6, octaves: 4, salt: 2) - 1)
                scored.append((elevation[i] * 0.55 + ridge * 0.45, i))
            }
            scored.sort { ($0.0, $0.1) > ($1.0, $1.1) }
            for (_, i) in scored.prefix(Int(Double(landCells.count) * options.mountains.mountainShare)) { mountain[i] = true }
            mountain = filtered(mountain, minimum: 5)
        }
        // Forest is wet, lower ground.
        if options.forests.forestShare > 0, !landCells.isEmpty {
            var scored: [(Double, Int)] = []
            for i in landCells where !mountain[i] {
                let u = (Double(i % n) + 0.5) / Double(n), v = (Double(i / n) + 0.5) / Double(n)
                scored.append((noise.fractal(u * 5, v * 5, octaves: 4, salt: 3) + (1 - elevation[i]) * 0.25, i))
            }
            scored.sort { ($0.0, $0.1) > ($1.0, $1.1) }
            for (_, i) in scored.prefix(Int(Double(landCells.count) * options.forests.forestShare)) { forest[i] = true }
            forest = filtered(forest, minimum: 8)
        }
    }

    // MARK: Rivers

    /// Rivers run from the highest ground down to the sea, by the way water would flow, and stop where they join another.
    private mutating func rivers() {
        var visited = [Bool](repeating: false, count: n * n)
        var heap = MinHeap()
        for i in land.indices where land[i] {
            let x = i % n, y = i / n
            let atEdge = x == 0 || y == 0 || x == n - 1 || y == n - 1
            if atEdge || neighbours4(i).contains(where: { !land[$0] }) {
                visited[i] = true
                heap.push(i, key: height[i])
            }
        }
        while let popped = heap.pop() {
            for nb in neighbours4(popped.item) where land[nb] && !visited[nb] {
                visited[nb] = true
                flowTo[nb] = popped.item
                heap.push(nb, key: max(height[nb], popped.key + 1e-7))
            }
        }
        guard options.rivers > 0 else { return }
        let byHeight = land.indices.filter { land[$0] }.sorted { (elevation[$0], -$0) > (elevation[$1], -$1) }
        var sources: [Int] = []
        var tries = 0
        for start in byHeight {
            if riverLines.count >= options.rivers || tries > 800 { break }
            tries += 1
            if river[start] { continue }
            let sx = Double(start % n), sy = Double(start / n)
            if sources.contains(where: { hypot(Double($0 % n) - sx, Double($0 / n) - sy) < 12 }) { continue }
            var path = [start]
            var current = start
            var steps = 0
            while steps < n * n {
                steps += 1
                let next = flowTo[current]
                if next < 0 {
                    if let sea = neighbours4(current).first(where: { !land[$0] }) { path.append(sea) }
                    break
                }
                path.append(next)
                if river[next] { break }
                current = next
            }
            guard path.count >= 10 else { continue }
            for c in path where land[c] { river[c] = true }
            sources.append(start)
            riverLines.append(path)
        }
    }

    // MARK: Settlements

    private func riverIsNear(_ i: Int) -> Bool {
        let x = i % n, y = i / n
        for dy in -2...2 {
            for dx in -2...2 {
                let nx = x + dx, ny = y + dy
                if nx >= 0, ny >= 0, nx < n, ny < n, river[ny * n + nx] { return true }
            }
        }
        return false
    }

    /// Lays out the capitals first, spread as far apart as they can be, then the cities, towns and villages round them.
    private mutating func settle() {
        var suit = [Double](repeating: 0, count: n * n)
        for i in land.indices where land[i] && !mountain[i] {
            var s = forest[i] ? 0.5 : 1.0
            if neighbours8(i).contains(where: { !land[$0.cell] }) { s += 0.6 }
            if riverIsNear(i) { s += 0.6 }
            suit[i] = s / 2.2
        }
        let usable = suit.indices.filter { suit[$0] > 0 }
        guard !usable.isEmpty else { return }

        func snapped(_ point: V) -> V {
            let c = cellIndex(of: point)
            if suit[c] > 0 { return point }
            // The nearest cell where something can stand, if there is one near.
            let near = usable.filter { centre(of: $0).distance(to: point) < cell * 12 }
            return near.min { centre(of: $0).distance(to: point) < centre(of: $1).distance(to: point) }.map(centre(of:)) ?? point
        }

        func add(_ name: String, _ kind: WorldLocation.Kind, _ position: V, capital: Bool, emit: Bool) {
            places.append(Place(name: name, kind: kind, position: position, isCapital: capital, emit: emit, cell: cellIndex(of: position)))
        }

        // What is there already, and what the user placed.
        if options.includeExisting {
            for item in fixed where !item.emit { add(item.name, item.kind, V(x: item.position.easting, y: item.position.northing), capital: false, emit: false) }
        }
        var pending: [WorldLocation] = []
        for location in options.locations {
            if let east = location.east, let north = location.north {
                add(location.name, location.kind, snapped(V(x: east * extent, y: north * extent)), capital: location.isCapital && location.kind == .city, emit: true)
            } else {
                pending.append(location)
            }
        }

        // Capitals: the ones asked for, then as many more as the realms need, each as far from the rest as it can be.
        let wanted = min(8, max(1, options.realms))
        var capitalPending = pending.filter { $0.isCapital && $0.kind == .city }
        pending.removeAll { $0.isCapital && $0.kind == .city }
        let landCentre: V = {
            let cells = land.indices.filter { land[$0] }
            guard !cells.isEmpty else { return V(x: extent / 2, y: extent / 2) }
            let sum = cells.reduce(V(x: 0, y: 0)) { $0 + centre(of: $1) }
            return V(x: sum.x / Double(cells.count), y: sum.y / Double(cells.count))
        }()
        // A capital is not put on top of somewhere that is already there.
        let capitalCells = {
            let free = usable.filter { c in !places.contains { !$0.isCapital && $0.position.distance(to: centre(of: c)) < options.citySpacing * 0.4 } }
            return free.isEmpty ? usable : free
        }()
        var capitalPositions = places.filter(\.isCapital).map(\.position)
        // In an archipelago each capital goes on an island of its own while there are islands without one.
        let pieces = options.shape == .archipelago ? landPieces() : []
        while capitalPositions.count < max(wanted, capitalPositions.count + capitalPending.count) {
            var cells = capitalCells
            if !pieces.isEmpty {
                let taken = Set(capitalPositions.map { pieces[cellIndex(of: $0)] })
                let free = capitalCells.filter { !taken.contains(pieces[$0]) }
                if !free.isEmpty { cells = free }
            }
            let choice: Int?
            if capitalPositions.isEmpty {
                choice = cells.min { (centre(of: $0).distance(to: landCentre), $0) < (centre(of: $1).distance(to: landCentre), $1) }
            } else {
                func clearance(_ c: Int) -> Double { capitalPositions.map { centre(of: c).distance(to: $0) }.min() ?? 0 }
                choice = cells.max { (clearance($0) * (0.6 + 0.4 * suit[$0]), -$0) < (clearance($1) * (0.6 + 0.4 * suit[$1]), -$1) }
            }
            guard let choice else { break }
            let position = centre(of: choice)
            let asked = capitalPending.isEmpty ? nil : capitalPending.removeFirst()
            add(asked?.name ?? "", .city, position, capital: true, emit: true)
            capitalPositions.append(position)
        }

        // The other places, a kind at a time, each keeping its distance from others of its kind.
        let kinds: [(kind: WorldLocation.Kind, spacing: Double, limit: Int)] = [
            (.city, options.citySpacing, 40), (.town, options.townSpacing, 120), (.village, options.villageSpacing, 220),
        ]
        func tooClose(_ position: V, kind: WorldLocation.Kind, spacing: Double, strict: Bool) -> Bool {
            places.contains { place in
                let gap = place.position.distance(to: position)
                return place.kind == kind ? gap < spacing * (strict ? 0.8 : 0.4) : gap < spacing * 0.45
            }
        }
        for entry in kinds {
            let spacing = max(entry.spacing, cell * 2)
            // Asked for by name, at no particular spot.
            for location in pending where location.kind == entry.kind {
                var position: V?
                for attempt in 0..<300 {
                    let candidate = usable[Int.random(in: 0..<usable.count, using: &random)]
                    let spot = centre(of: candidate)
                    if !tooClose(spot, kind: entry.kind, spacing: spacing, strict: attempt < 150) { position = spot; break }
                }
                add(location.name, location.kind, position ?? centre(of: usable[Int.random(in: 0..<usable.count, using: &random)]), capital: false, emit: true)
            }
            var count = places.filter { $0.kind == entry.kind }.count
            var misses = 0
            while misses < 400, count < entry.limit {
                let candidate = usable[Int.random(in: 0..<usable.count, using: &random)]
                var position = centre(of: candidate)
                let jitter = V(x: random.value(in: -0.35...0.35) * cell, y: random.value(in: -0.35...0.35) * cell)
                if suit[cellIndex(of: position + jitter)] > 0 { position = position + jitter }
                guard random.chance(suit[candidate]), !tooClose(position, kind: entry.kind, spacing: spacing, strict: true) else { misses += 1; continue }
                add("", entry.kind, position, capital: false, emit: true)
                count += 1
                misses = 0
            }
        }
    }

    // MARK: Realms

    private func terrainCost(_ i: Int) -> Double {
        (mountain[i] ? 6 : forest[i] ? 1.8 : 1) * (river[i] ? 2.5 : 1) * wobble[i]
    }

    /// Gives every land cell to the realm whose capital is cheapest to reach, so borders fall along mountains and rivers.
    private mutating func realms() {
        let capitals = places.indices.filter { places[$0].isCapital }
        realmCount = capitals.count
        guard !capitals.isEmpty else { return }
        var distance = [Double](repeating: .infinity, count: n * n)
        var heap = MinHeap()
        for (realm, p) in capitals.enumerated() {
            let c = places[p].cell
            guard land[c] else { continue }
            distance[c] = 0
            realmOf[c] = realm
            heap.push(c, key: 0)
        }
        while let popped = heap.pop() {
            if popped.key > distance[popped.item] { continue }
            for nb in neighbours8(popped.item) where land[nb.cell] {
                let through = popped.key + nb.distance * terrainCost(nb.cell)
                if through < distance[nb.cell] {
                    distance[nb.cell] = through
                    realmOf[nb.cell] = realmOf[popped.item]
                    heap.push(nb.cell, key: through)
                }
            }
        }
        // Land the capitals can't reach on foot, such as another island, goes to the nearest capital.
        for i in land.indices where land[i] && realmOf[i] < 0 {
            let here = centre(of: i)
            realmOf[i] = capitals.indices.min { here.distance(to: places[capitals[$0]].position) < here.distance(to: places[capitals[$1]].position) } ?? 0
        }
        for p in places.indices {
            let c = places[p].cell
            places[p].realm = realmOf[c] >= 0 ? realmOf[c] : 0
        }
    }

    // MARK: Roads

    /// The cheapest way over the land from one cell to the first cell that `goal` accepts, as the cells along it, or nil if
    /// there is no way. Existing roads are cheap, so new roads join them.
    private func route(from start: Int, to goal: (Int) -> Bool) -> [Int]? {
        var distance = [Double](repeating: .infinity, count: n * n)
        var previous = [Int](repeating: -1, count: n * n)
        var heap = MinHeap()
        distance[start] = 0
        heap.push(start, key: 0)
        while let popped = heap.pop() {
            if popped.key > distance[popped.item] { continue }
            if popped.item != start, goal(popped.item) {
                var path = [popped.item]
                var at = popped.item
                while previous[at] >= 0 { at = previous[at]; path.append(at) }
                return path.reversed()
            }
            for nb in neighbours8(popped.item) where land[nb.cell] {
                var cost = terrainCost(nb.cell) + abs(elevation[nb.cell] - elevation[popped.item]) * 6
                if roadCell[nb.cell] { cost = 0.25 }
                let through = popped.key + nb.distance * cost
                if through < distance[nb.cell] {
                    distance[nb.cell] = through
                    previous[nb.cell] = popped.item
                    heap.push(nb.cell, key: through)
                }
            }
        }
        return nil
    }

    private static func edgeKey(_ a: Int, _ b: Int, _ n: Int) -> Int { min(a, b) * n * n + max(a, b) }

    private mutating func lay(_ path: [Int]) {
        for c in path { roadCell[c] = true }
        for (a, b) in zip(path, path.dropFirst()) { roadEdges.insert(Self.edgeKey(a, b, n)) }
    }

    /// Joins the capitals to each other, and then every other settlement to the nearest road or settlement already joined.
    private mutating func roads() {
        guard places.count > 1 else { return }
        var joined = [Bool](repeating: false, count: n * n)
        let capitals = places.indices.filter { places[$0].isCapital }

        // The capitals, by the shortest ways between them, with a second way out of each when there are enough.
        var inTree: Set<Int> = capitals.first.map { [$0] } ?? []
        var links = Set<Int>()
        while inTree.count < capitals.count {
            var best: (from: Int, to: Int, gap: Double)?
            for a in inTree.sorted() {
                for b in capitals where !inTree.contains(b) {
                    let gap = places[a].position.distance(to: places[b].position)
                    if best == nil || gap < best!.gap { best = (a, b, gap) }
                }
            }
            guard let best else { break }
            let target = places[best.to].cell
            if let path = route(from: places[best.from].cell, to: { $0 == target }) { lay(path) }
            links.insert(min(best.from, best.to) * 1_000 + max(best.from, best.to))
            inTree.insert(best.to)
        }
        if capitals.count >= 3 {
            for a in capitals {
                let others = capitals.filter { $0 != a && !links.contains(min($0, a) * 1_000 + max($0, a)) }
                guard let b = others.min(by: { places[a].position.distance(to: places[$0].position) < places[a].position.distance(to: places[$1].position) }) else { continue }
                links.insert(min(a, b) * 1_000 + max(a, b))
                let target = places[b].cell
                if let path = route(from: places[a].cell, to: { $0 == target }) { lay(path) }
            }
        }
        for p in capitals { joined[places[p].cell] = true }

        // Everyone else, cities then towns then villages, nearest a capital first.
        let capitalPositions = capitals.map { places[$0].position }
        func nearestCapital(_ p: Int) -> Double { capitalPositions.map { places[p].position.distance(to: $0) }.min() ?? 0 }
        for kind in [WorldLocation.Kind.city, .town, .village] {
            let ordered = places.indices.filter { places[$0].kind == kind && !places[$0].isCapital }.sorted { (nearestCapital($0), $0) < (nearestCapital($1), $1) }
            for p in ordered {
                let start = places[p].cell
                guard land[start] else { continue }
                if let path = route(from: start, to: { joined[$0] || roadCell[$0] }) {
                    lay(path)
                    for c in path { joined[c] = true }
                }
                joined[start] = true
            }
        }
    }

    // MARK: Features

    private func rectangle() -> [GridPoint] {
        [GridPoint(easting: 0, northing: 0), GridPoint(easting: extent, northing: 0), GridPoint(easting: extent, northing: extent), GridPoint(easting: 0, northing: extent)]
    }

    /// The outlines of an area of the grid, smoothed, in metres, biggest first.
    private func polygons(of mask: [Bool], minimumCells: Double, limit: Int) -> [[GridPoint]] {
        var found: [(area: Double, points: [GridPoint])] = []
        for loop in Contours.loops(mask: mask, width: n, height: n) {
            let area = Plane.signedArea(loop)
            guard area >= minimumCells else { continue }
            let rounded = Contours.rounded(closed: Contours.simplify(closed: loop, tolerance: 0.6), times: 3)
            let points = rounded.map { GridPoint(easting: min(max($0.x * cell, 0), extent), northing: min(max($0.y * cell, 0), extent)) }
            guard PlaceGeometry.polygon(points).isValid else { continue }
            found.append((area, points))
        }
        return found.sorted { $0.area > $1.area }.prefix(limit).map(\.points)
    }

    /// What the realm's page says: the description the user wrote or had written, or a plain line if there is none.
    private func realmSummary(_ realm: Int) -> String {
        let text = options.description(forRealm: realm).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? String(localized: "A realm.") : text
    }

    private mutating func features() -> [GeneratedFeature] {
        var features: [GeneratedFeature] = []
        features.append(GeneratedFeature(
            name: names.sea(using: &random), placeType: "Water", summary: String(localized: "The sea that the land lies in."), shape: .polygon(rectangle())
        ))

        var realmNames: [String] = []
        for realm in 0..<realmCount {
            names.use(options.languages(forRealm: realm))
            realmNames.append(names.realm(using: &random))
        }
        names.use(options.languages(forRealm: -1))
        for realm in 0..<realmCount {
            var first = true
            let mask = land.indices.map { land[$0] && realmOf[$0] == realm }
            for points in polygons(of: mask, minimumCells: 6, limit: 6) {
                let name = first ? realmNames[realm] : names.named(realmNames[realm])
                first = false
                features.append(GeneratedFeature(name: name, placeType: "Region", summary: realmSummary(realm), shape: .polygon(points), kind: "realm \(realm)"))
            }
        }
        // The coast is smoothed from the grid, so a place on a coastal cell can end up just off the land. Nudge it in.
        let outlines = features.filter { $0.placeType == "Region" }.map { feature -> [V] in
            if case .polygon(let p) = feature.shape { return p.map { V(x: $0.easting, y: $0.northing) } }
            return []
        }
        if !outlines.isEmpty {
            let middle = land.indices.filter { land[$0] }.map { centre(of: $0) }
            let inland = V(x: middle.map(\.x).reduce(0, +) / Double(max(middle.count, 1)), y: middle.map(\.y).reduce(0, +) / Double(max(middle.count, 1)))
            for p in places.indices where places[p].emit {
                var tries = 0
                while tries < 8, !outlines.contains(where: { SettlementGenerator.contains($0, places[p].position) }) {
                    places[p].position = places[p].position + (inland - places[p].position).unit * (cell * 0.5)
                    tries += 1
                }
            }
        }
        if realmCount == 0 {
            for points in polygons(of: land, minimumCells: 6, limit: 6) {
                features.append(GeneratedFeature(name: names.named(String(localized: "The Land")), placeType: "Region", summary: String(localized: "The land."), shape: .polygon(points), kind: "realm 0"))
            }
        }
        for points in polygons(of: forest, minimumCells: 8, limit: 30) {
            features.append(GeneratedFeature(name: names.forest(using: &random), placeType: "Forest", summary: String(localized: "A great forest."), shape: .polygon(points)))
        }
        for points in polygons(of: mountain, minimumCells: 5, limit: 30) {
            features.append(GeneratedFeature(name: names.mountains(using: &random), placeType: "Mountains", summary: String(localized: "A range of mountains."), shape: .polygon(points)))
        }

        for path in riverLines {
            let raw = path.map { waypoint($0) }
            let points = Curves.smooth(Contours.simplify(open: raw, tolerance: 0.7 * cell), steps: 4)
                .map { GridPoint(easting: min(max($0.x, 0), extent), northing: min(max($0.y, 0), extent)) }
            guard points.count >= 2 else { continue }
            features.append(GeneratedFeature(name: names.river(using: &random), placeType: "River", summary: String(localized: "A river that runs to the sea."), shape: .line(points)))
        }

        // The settlements are named now, in a fixed order, so the roads can be named for them.
        // Each is named in the languages of the realm it lies in.
        for p in places.indices where places[p].name.isEmpty {
            names.use(options.languages(forRealm: places[p].realm))
            places[p].name = names.settlement(using: &random)
        }
        names.use(options.languages(forRealm: -1))
        features += roadFeatures()
        for place in places where place.emit {
            let realm = place.realm >= 0 && place.realm < realmNames.count ? realmNames[place.realm] : ""
            let noun = place.kind.title.lowercased()
            let summary = place.isCapital
                ? String(localized: "The capital of the \(realm), a city.")
                : (realm.isEmpty ? String(localized: "A \(noun).") : String(localized: "A \(noun) in the \(realm)."))
            features.append(GeneratedFeature(
                name: place.name, placeType: "Settlement", summary: summary,
                shape: .point(GridPoint(easting: place.position.x, northing: place.position.y)), kind: place.isCapital ? "capital" : place.kind.rawValue
            ))
        }
        return features
    }

    /// The roads as lines: each stretch between two settlements or junctions, smoothed.
    private mutating func roadFeatures() -> [GeneratedFeature] {
        var around: [Int: [Int]] = [:]
        for key in roadEdges.sorted() {
            let a = key / (n * n), b = key % (n * n)
            around[a, default: []].append(b)
            around[b, default: []].append(a)
        }
        var settlementAt: [Int: Int] = [:]
        for p in places.indices where settlementAt[places[p].cell] == nil { settlementAt[places[p].cell] = p }
        func isBreak(_ c: Int) -> Bool { (around[c]?.count ?? 0) != 2 || settlementAt[c] != nil }
        var used = Set<Int>()
        var features: [GeneratedFeature] = []
        for start in around.keys.sorted() where isBreak(start) {
            for first in (around[start] ?? []).sorted() where !used.contains(Self.edgeKey(start, first, n)) {
                var cells = [start]
                var previous = start, current = first
                used.insert(Self.edgeKey(start, first, n))
                cells.append(first)
                while !isBreak(current) {
                    let next = (around[current] ?? []).first { $0 != previous } ?? current
                    guard next != current else { break }
                    used.insert(Self.edgeKey(current, next, n))
                    previous = current
                    current = next
                    cells.append(current)
                }
                let raw = cells.map { c -> V in
                    if let p = settlementAt[c] { return places[p].position }
                    return waypoint(c)
                }
                let points = Curves.smooth(Contours.simplify(open: raw, tolerance: 0.8 * cell), steps: 4)
                    .map { GridPoint(easting: min(max($0.x, 0), extent), northing: min(max($0.y, 0), extent)) }
                guard points.count >= 2, PlaceGeometry.line(points).isValid else { continue }
                let from = settlementAt[cells[0]].map { places[$0].name }, to = settlementAt[cells[cells.count - 1]].map { places[$0].name }
                let name: String
                switch (from, to) {
                case let (a?, b?) where a != b: name = names.named(String(localized: "\(a)–\(b) Road"))
                case let (a?, _), let (_, a?): name = names.named(String(localized: "\(a) Road"))
                default: name = names.named(String(localized: "The Old Road"))
                }
                features.append(GeneratedFeature(name: name, placeType: "Road", summary: String(localized: "A road between settlements."), shape: .line(points)))
            }
        }
        return features
    }
}
