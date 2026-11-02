//
//  TownMaker.swift
//  encounter
//

import Foundation

extension SettlementGenerator {
    /// Lays out one settlement. It cuts the area into wards, finds streets from the gates to the main square along the
    /// ward edges, and fills each ward with plots and buildings.
    struct TownMaker {
        let options: SettlementOptions
        var random: SeededRandom
        var names = NameBank()
        let extent: Double
        /// The size the layout is made at: the options' own, or the one nearest an outline's size.
        let size: SettlementOptions.Size
        let centre: V
        let radius: Double
        let hasOutline: Bool
        /// The edge of the settlement, going anticlockwise.
        var boundary: [V] = []
        var river: [V] = []
        var square = V(x: 0, y: 0)
        var gatePoints: [V] = []

        // The wards and the street graph.
        var wards: [Ward] = []
        var vertices: [V] = []
        var edges: [Edge] = []
        var vertexGrid: [Int: [Int]] = [:]
        var edgeIndex: [Int: Int] = [:]
        /// Corners that lie on the river, and the ones among them where a road crosses it.
        var riverNodes = Set<Int>()
        var bridgeNodes = Set<Int>()

        struct Ward {
            var site: V
            var polygon: [V]
            var vertexIDs: [Int] = []
            var isSquare = false
            /// What kind of quarter the ward belongs to, if it has been given one.
            var quarter: Quarter?
            /// A landmark stands in this ward, which takes it over.
            var landmark: Landmark?
        }

        enum Rank: Int { case none, minor, major }

        struct Edge {
            var a: Int
            var b: Int
            var isBoundary: Bool
            /// The river runs along this edge, so no street does.
            var isRiver = false
            var rank = Rank.none
            /// Random wobble in how attractive the edge is to route along, so main streets don't all go the shortest way.
            var cost = 1.0
        }

        /// A street, as the corners of its line and its name.
        struct Street {
            var name: String
            var type: String
            var points: [V]
        }

        init(options: SettlementOptions, outline: [GridPoint]?, extent given: Double?) {
            self.options = options
            if let outline {
                let points = outline.map { V(x: $0.easting, y: $0.northing) }
                let shape = PlaceGeometry.polygon(outline)
                let measured = (shape.area / .pi).squareRoot()
                size = SettlementOptions.Size.nearest(toRadius: measured)
                extent = given ?? SettlementGenerator.extent(for: options, outline: outline)
                radius = measured
                centre = Self.interiorPoint(of: points, near: V(x: shape.centre.easting, y: shape.centre.northing))
                boundary = Plane.anticlockwise(points)
                hasOutline = true
            } else {
                size = options.size
                extent = given ?? options.size.extent
                radius = options.size.radius
                centre = V(x: extent / 2, y: extent / 2)
                hasOutline = false
            }
            random = SeededRandom(seed: options.seed &* 0x2545F4914F6CDD1D &+ UInt64(extent))
        }

        /// The middle of an outline, or when that is outside it (a crescent, say), the spot inside it furthest from its edge.
        static func interiorPoint(of polygon: [V], near middle: V) -> V {
            if SettlementGenerator.contains(polygon, middle) { return middle }
            let bounds = Plane.bounds(polygon)
            var best = middle, bestDistance = -1.0
            let steps = 24
            for i in 0...steps {
                for j in 0...steps {
                    let point = V(x: bounds.min.x + (bounds.max.x - bounds.min.x) * Double(i) / Double(steps), y: bounds.min.y + (bounds.max.y - bounds.min.y) * Double(j) / Double(steps))
                    guard SettlementGenerator.contains(polygon, point) else { continue }
                    let edge = Plane.distanceToEdge(point, polygon)
                    if edge > bestDistance { best = point; bestDistance = edge }
                }
            }
            return best
        }

        mutating func make() -> GeneratedSettlement {
            if !hasOutline { makeBoundary() }
            if options.hasRiver { makeRiver() }
            placeSquareAndGates()
            makeLayout()
            assignQuarters()
            let streets = chainStreets()

            var features: [GeneratedFeature] = []
            if options.hasWalls { features.append(wall()) }
            if options.hasRiver, !river.isEmpty {
                features.append(GeneratedFeature(name: names.river(using: &random), placeType: "River", summary: String(localized: "A river through the settlement."), shape: .line(river.map(\.grid))))
            }
            for street in streets {
                features.append(GeneratedFeature(
                    name: street.name, placeType: street.type,
                    summary: street.type == "Road" ? String(localized: "A main road.") : String(localized: "A street."), shape: .line(street.points.map(\.grid))
                ))
            }
            features += approachRoadsAndGates()
            if let plaza = wards.first(where: \.isSquare) {
                features.append(GeneratedFeature(name: names.named(String(localized: "Market Square")), placeType: "Square", summary: String(localized: "The open space at the heart of the settlement."), shape: .polygon(plaza.polygon.map(\.grid))))
            }
            let districts = makeDistricts()
            features += districts.features
            let landmarks = placeLandmarks()
            features += landmarks.features
            features += makeVenues(streets: streets, districts: districts.nameOfWard, reserved: landmarks.reserved)
            return GeneratedSettlement(
                options: options, extent: extent, features: features,
                wards: wards.map { $0.polygon.map(\.grid) }, square: square.grid, gates: gatePoints.map(\.grid),
                centre: centre.grid, radius: radius
            )
        }

        // MARK: Edge

        /// An uneven edge: a radius for each direction, smoothed so it has bays and not spikes.
        mutating func makeBoundary() {
            let count = 48
            let wobble = options.layout == .planned ? 0.06 : 0.14
            var radii = (0..<count).map { _ in 1 + random.value(in: -wobble...wobble) }
            for _ in 0..<2 { radii = radii.indices.map { (radii[($0 + count - 1) % count] + radii[$0] * 2 + radii[($0 + 1) % count]) / 4 } }
            boundary = radii.enumerated().map { index, r in
                let angle = Double(index) / Double(count) * 2 * .pi
                return V(x: centre.x + cos(angle) * radius * r, y: centre.y + sin(angle) * radius * r)
            }
        }

        /// The edge's distance from the middle in a direction.
        func edgeRadius(at angle: Double) -> Double {
            var best = radius
            let direction = V(x: cos(angle), y: sin(angle))
            var distance = radius * 0.3
            while distance < radius * 1.6 {
                if !SettlementGenerator.contains(boundary, centre + direction * distance) { best = distance; break }
                distance += 1.5
            }
            return best
        }

        mutating func makeRiver() {
            let startY = centre.y + random.value(in: -radius * 0.45...radius * 0.45)
            let amplitude = random.value(in: radius * 0.1...radius * 0.3)
            let frequency = random.value(in: 1.5...3.5) * .pi / extent
            let phase = random.value(in: 0...(2 * .pi))
            var x = 0.0
            var drift = 0.0
            while x <= extent {
                drift = max(-radius * 0.3, min(radius * 0.3, drift + random.value(in: -6...6)))
                let y = startY + sin(x * frequency + phase) * amplitude + drift
                river.append(V(x: x, y: max(0, min(extent, y))))
                x += 25
            }
            if let last = river.last, last.x < extent { river.append(V(x: extent, y: last.y)) }
        }

        // MARK: The square and the gates

        static func compass(_ bearing: Double) -> String {
            let names = ["East", "North-East", "North", "North-West", "West", "South-West", "South", "South-East"]
            var turns = (bearing / (.pi / 4)).rounded()
            while turns < 0 { turns += 8 }
            return names[Int(turns) % 8]
        }

        mutating func placeSquareAndGates() {
            if let spot = options.square {
                square = V(x: centre.x + spot.east * radius, y: centre.y + spot.north * radius)
            } else {
                square = centre + V(x: random.value(in: -0.08...0.08) * radius, y: random.value(in: -0.08...0.08) * radius)
            }
            if !SettlementGenerator.contains(boundary, square) { square = centre }

            var bearings = options.gates.map(\.bearing)
            if bearings.isEmpty {
                let count = size.gateCount
                let start = random.value(in: 0...(2 * .pi))
                bearings = (0..<count).map { start + (Double($0) + random.value(in: -0.2...0.2)) / Double(count) * 2 * .pi }
            }
            gatePoints = bearings.map { bearing in
                let direction = V(x: cos(bearing), y: sin(bearing))
                return centre + direction * edgeRadius(at: bearing)
            }
        }

        // MARK: Wards

        /// The ward sites, with the main square's first.
        mutating func makeSites() -> [V] {
            // A big outline gets bigger wards, not more of them: the work grows with the square of the number.
            let width = max(size.wardWidth, radius * 0.11)
            var sites = [square]
            switch options.layout {
            case .organic:
                // Small wards near the square and bigger ones out towards the edge, by dart throwing.
                func spacing(at point: V) -> Double { width * (0.6 + 0.7 * min(point.distance(to: square) / radius, 1)) }
                let bounds = Plane.bounds(boundary)
                var misses = 0
                while misses < 400, sites.count < 400 {
                    let point = V(x: random.value(in: bounds.min.x...bounds.max.x), y: random.value(in: bounds.min.y...bounds.max.y))
                    guard SettlementGenerator.contains(boundary, point) else { misses += 1; continue }
                    let wanted = spacing(at: point)
                    if sites.allSatisfy({ $0.distance(to: point) >= (wanted + spacing(at: $0)) / 2 }) {
                        sites.append(point)
                        misses = 0
                    } else {
                        misses += 1
                    }
                }
            case .planned:
                let angle = random.value(in: -0.3...0.3)
                let along = V(x: cos(angle), y: sin(angle)), across = along.perpendicular
                let steps = Int(radius * 1.6 / width) + 1
                for i in -steps...steps {
                    for j in -steps...steps {
                        let jitter = V(x: random.value(in: -0.05...0.05) * width, y: random.value(in: -0.05...0.05) * width)
                        let point = square + along * (Double(i) * width) + across * (Double(j) * width) + jitter
                        if SettlementGenerator.contains(boundary, point), point.distance(to: square) > width * 0.55 { sites.append(point) }
                    }
                }
            case .radial:
                var ring = 1
                while Double(ring) * width * 0.9 < radius * 1.6 {
                    let ringRadius = Double(ring) * width * 0.9
                    let count = max(5, Int((2 * .pi * ringRadius / (width * 0.9)).rounded()))
                    let offset = random.value(in: 0...(2 * .pi))
                    for k in 0..<count {
                        let angle = offset + (Double(k) + random.value(in: -0.15...0.15)) / Double(count) * 2 * .pi
                        let point = square + V(x: cos(angle), y: sin(angle)) * ringRadius
                        if SettlementGenerator.contains(boundary, point) { sites.append(point) }
                    }
                    ring += 1
                }
            }
            return sites
        }

        mutating func makeWards() {
            var sites = makeSites()
            if options.layout == .organic {
                // Even the wards out, keeping the square where it was put.
                for _ in 0..<2 {
                    let cells = Voronoi.cells(sites: sites, in: boundary)
                    for index in sites.indices where index > 0 && !cells[index].isEmpty { sites[index] = Plane.centroid(cells[index]) }
                }
            }
            let cells = Voronoi.cells(sites: sites, in: boundary)
            wards = zip(sites, cells).enumerated().compactMap { index, pair in
                // A cell cut by a hollow boundary can come out as two pieces joined by a thread, which is no use as a ward.
                pair.1.count >= 3 && (index == 0 || PlaceGeometry.polygon(pair.1.map(\.grid)).isValid) ? Ward(site: pair.0, polygon: pair.1, isSquare: index == 0) : nil
            }
            // If the square somehow has no cell, make the first ward the square so there is always one.
            if !wards.contains(where: \.isSquare), !wards.isEmpty {
                let nearest = wards.indices.min { wards[$0].site.distance(to: square) < wards[$1].site.distance(to: square) } ?? 0
                wards[nearest].isSquare = true
            }
        }

        // MARK: The street graph

        private mutating func vertexID(for point: V) -> Int {
            let gx = Int(point.x.rounded(.down)), gy = Int(point.y.rounded(.down))
            for dx in -1...1 {
                for dy in -1...1 {
                    for id in vertexGrid[(gx + dx) &* 100_003 &+ (gy + dy)] ?? [] where vertices[id].distance(to: point) < 0.6 { return id }
                }
            }
            vertices.append(point)
            vertexGrid[gx &* 100_003 &+ gy, default: []].append(vertices.count - 1)
            return vertices.count - 1
        }

        func edgeKey(_ a: Int, _ b: Int) -> Int { min(a, b) &* 1_000_003 &+ max(a, b) }

        mutating func buildGraph() {
            for index in wards.indices {
                let polygon = wards[index].polygon
                let ids = polygon.map { vertexID(for: $0) }
                wards[index].vertexIDs = ids
                for i in ids.indices {
                    let a = ids[i], b = ids[(i + 1) % ids.count]
                    guard a != b, edgeIndex[edgeKey(a, b)] == nil else { continue }
                    let middle = (vertices[a] + vertices[b]) * 0.5
                    let onEdge = Plane.distanceToEdge(vertices[a], boundary) < 0.6 && Plane.distanceToEdge(vertices[b], boundary) < 0.6 && Plane.distanceToEdge(middle, boundary) < 0.6
                    edgeIndex[edgeKey(a, b)] = edges.count
                    edges.append(Edge(a: a, b: b, isBoundary: onEdge, cost: random.value(in: 0.9...1.35)))
                }
            }
        }

        private func crossesRiver(_ a: V, _ b: V) -> Bool {
            guard river.count >= 2 else { return false }
            return zip(river, river.dropFirst()).contains { Self.segmentsCross(a, b, $0.0, $0.1) }
        }

        static func segmentsCross(_ a: V, _ b: V, _ c: V, _ d: V) -> Bool {
            func side(_ p: V, _ q: V, _ r: V) -> Double { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
            let d1 = side(a, b, c), d2 = side(a, b, d), d3 = side(c, d, a), d4 = side(c, d, b)
            return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0))
        }

        /// The edges a street can run along, as the corners they join: not the edge of the settlement and not the river.
        func walkableEdges(excludingSquare: Bool = false) -> [[(vertex: Int, edge: Int)]] {
            let ring = Set(wards.first(where: \.isSquare)?.vertexIDs ?? [])
            var neighbours: [[(vertex: Int, edge: Int)]] = Array(repeating: [], count: vertices.count)
            for (index, edge) in edges.enumerated() where !edge.isBoundary && !edge.isRiver {
                if excludingSquare, ring.contains(edge.a), ring.contains(edge.b) { continue }
                neighbours[edge.a].append((edge.b, index))
                neighbours[edge.b].append((edge.a, index))
            }
            return neighbours
        }

        /// The cheapest way from a corner to any corner that `goal` accepts, as the edges along it. `cost` is what it costs
        /// to go along an edge to a corner, and an edge it returns nil for can't be used.
        func shortestPath(
            from start: Int, to goal: (Int) -> Bool, over neighbours: [[(vertex: Int, edge: Int)]], cost: (Int, Int) -> Double?
        ) -> [Int]? {
            var distance = [Double](repeating: .infinity, count: vertices.count)
            var previous = [(vertex: Int, edge: Int)?](repeating: nil, count: vertices.count)
            var done = [Bool](repeating: false, count: vertices.count)
            distance[start] = 0
            var reached: Int?
            while true {
                var best = -1
                var bestDistance = Double.infinity
                for v in vertices.indices where !done[v] && distance[v] < bestDistance { best = v; bestDistance = distance[v] }
                if best < 0 { break }
                done[best] = true
                if best != start, goal(best) { reached = best; break }
                for (next, edge) in neighbours[best] where !done[next] {
                    guard let step = cost(edge, next) else { continue }
                    let through = distance[best] + step
                    if through < distance[next] { distance[next] = through; previous[next] = (best, edge) }
                }
            }
            guard var at = reached else { return nil }
            var path: [Int] = []
            while let step = previous[at] {
                path.append(step.edge)
                at = step.vertex
            }
            return path
        }

        /// Marks the main streets: from each gate to the main square by the cheapest way along the ward edges, and with
        /// `ring`, round the square. Roads share where they can, and cross the river only where they have to, at a bridge.
        /// Everything else that isn't the edge or the river is a side street.
        mutating func routeStreets(ring: Bool = true) {
            guard let plaza = wards.first(where: \.isSquare) else { return }
            let plazaIDs = Set(plaza.vertexIDs)
            let neighbours = walkableEdges()
            for index in edges.indices where !edges[index].isBoundary && !edges[index].isRiver { edges[index].rank = .minor }

            // Each gate goes to the corner on the edge nearest it, where a street can leave, and the gate moves there.
            let boundaryVertices = Set(edges.filter(\.isBoundary).flatMap { [$0.a, $0.b] }.filter { !neighbours[$0].isEmpty })
            let bridgeCost = radius * 0.5
            for (g, gate) in gatePoints.enumerated() {
                guard let start = boundaryVertices.sorted().min(by: { vertices[$0].distance(to: gate) < vertices[$1].distance(to: gate) }) else { continue }
                gatePoints[g] = vertices[start]
                let path = shortestPath(from: start, to: { plazaIDs.contains($0) }, over: neighbours) { index, next in
                    let edge = edges[index]
                    var length = vertices[edge.a].distance(to: vertices[edge.b]) * edge.cost
                    if crossesRiver(vertices[edge.a], vertices[edge.b]) { length *= 12 }
                    if riverNodes.contains(next) { length += bridgeCost }
                    return edge.rank == .major ? length * 0.5 : length
                }
                for index in path ?? [] { edges[index].rank = .major }
            }
            if ring { markRingRoundSquare() }
            findBridges()
        }

        /// The edges round the main square are main streets.
        mutating func markRingRoundSquare() {
            guard let plaza = wards.first(where: \.isSquare) else { return }
            let ids = plaza.vertexIDs
            for i in ids.indices {
                if let index = edgeIndex[edgeKey(ids[i], ids[(i + 1) % ids.count])], !edges[index].isBoundary, !edges[index].isRiver { edges[index].rank = .major }
            }
        }

        /// A few more main roads, joining two of the main roads part of the way out, so the settlement isn't only spokes.
        /// They stay on one side of the river.
        mutating func addSecondaryRoutes() {
            let wanted: Int
            switch size {
            case .hamlet, .village: wanted = 0
            case .town: wanted = 2
            case .city: wanted = 4
            }
            guard wanted > 0 else { return }
            let neighbours = walkableEdges(excludingSquare: true)
            for _ in 0..<wanted {
                var onRoad = Set<Int>()
                for edge in edges where edge.rank == .major { onRoad.insert(edge.a); onRoad.insert(edge.b) }
                let middle = onRoad.sorted().filter { (0.35...0.7).contains(vertices[$0].distance(to: square) / radius) }
                guard let start = middle.isEmpty ? nil : middle[Int.random(in: 0..<middle.count, using: &random)] else { return }
                let far = middle.filter { vertices[$0].distance(to: vertices[start]) > radius * 0.6 }
                guard !far.isEmpty else { continue }
                let goal = far[Int.random(in: 0..<far.count, using: &random)]
                let path = shortestPath(from: start, to: { $0 == goal }, over: neighbours) { index, _ in
                    let edge = edges[index]
                    if crossesRiver(vertices[edge.a], vertices[edge.b]) { return nil }
                    let length = vertices[edge.a].distance(to: vertices[edge.b]) * edge.cost
                    return edge.rank == .major ? length * 0.3 : length
                }
                for index in path ?? [] { edges[index].rank = .major }
            }
        }

        /// The corners on the river where a main road crosses it.
        mutating func findBridges() {
            bridgeNodes = []
            for edge in edges where edge.rank == .major {
                if riverNodes.contains(edge.a) { bridgeNodes.insert(edge.a) }
                if riverNodes.contains(edge.b) { bridgeNodes.insert(edge.b) }
            }
        }

        // MARK: Streets

        /// Joins the edges of a rank into long lines of corners: at every junction a line carries straight on if the way
        /// ahead bends less than a limit, so side streets end at the street they meet. A line also stops at the river
        /// unless it is a main road at a bridge.
        func chains(of rank: Rank) -> [[Int]] {
            var lines: [[Int]] = []
            let ranked = edges.indices.filter { edges[$0].rank == rank }
            var adjacency: [Int: [Int]] = [:]
            for index in ranked {
                adjacency[edges[index].a, default: []].append(index)
                adjacency[edges[index].b, default: []].append(index)
            }
            var used = Set<Int>()
            for start in ranked where !used.contains(start) {
                used.insert(start)
                var line = [edges[start].a, edges[start].b]
                // Grow from the far end, then from the near end.
                for _ in 0..<2 {
                    while let last = line.last, line.count >= 2 {
                        if riverNodes.contains(last), rank != .major || !bridgeNodes.contains(last) { break }
                        let before = line[line.count - 2]
                        let heading = (vertices[last] - vertices[before]).unit
                        let candidates = (adjacency[last] ?? []).filter { !used.contains($0) }
                        func other(_ index: Int) -> Int { edges[index].a == last ? edges[index].b : edges[index].a }
                        func turn(_ index: Int) -> Double {
                            let direction = (vertices[other(index)] - vertices[last]).unit
                            return acos(max(-1, min(1, heading.x * direction.x + heading.y * direction.y)))
                        }
                        guard let next = candidates.min(by: { turn($0) < turn($1) }), turn(next) < 0.95 else { break }
                        used.insert(next)
                        line.append(other(next))
                    }
                    line.reverse()
                }
                lines.append(line)
            }
            return lines
        }

        /// The streets: the main roads, then the side streets, each named. A road that comes from a gate is named for it.
        mutating func chainStreets() -> [Street] {
            var streets: [Street] = []
            for rank in [Rank.major, .minor] {
                for line in chains(of: rank) {
                    let gateIndex = gatePoints.indices.first { gate in line.contains { vertices[$0].distance(to: gatePoints[gate]) < 0.7 } }
                    let name: String
                    if rank == .major, let gateIndex {
                        let bearing = atan2(gatePoints[gateIndex].y - centre.y, gatePoints[gateIndex].x - centre.x)
                        name = names.named(String(localized: "\(Self.compass(bearing)) Gate Road"))
                    } else {
                        name = names.street(using: &random)
                    }
                    streets.append(Street(name: name, type: rank == .major ? "Road" : "Street", points: line.map { vertices[$0] }))
                }
            }
            return streets
        }

        mutating func wall() -> GeneratedFeature {
            var loop = boundary
            if let first = loop.first { loop.append(first) }
            let name = size == .hamlet || size == .village ? String(localized: "Palisade") : String(localized: "City Wall")
            return GeneratedFeature(name: names.named(name), placeType: "Wall", summary: String(localized: "The wall round the settlement."), shape: .line(loop.map(\.grid)))
        }

        /// The road that carries on from each gate, and with a wall, a gatehouse on it.
        mutating func approachRoadsAndGates() -> [GeneratedFeature] {
            var features: [GeneratedFeature] = []
            for gate in gatePoints {
                let direction = (gate - centre).unit
                let bearing = atan2(direction.y, direction.x)
                let compass = Self.compass(bearing)
                // Out towards the edge of the map, bending a little, but staying on it.
                var length = radius * 0.4
                while length > 5 {
                    let end = gate + direction * length
                    if end.x > 5, end.x < extent - 5, end.y > 5, end.y < extent - 5 { break }
                    length -= 5
                }
                guard length > 5 else { continue }
                let bend = direction.perpendicular * random.value(in: -0.15...0.15) * length
                let points = [gate, gate + direction * (length * 0.5) + bend, gate + direction * length]
                features.append(GeneratedFeature(
                    name: names.named(String(localized: "\(compass) Road")), placeType: "Road",
                    summary: String(localized: "The road that leaves the \(compass) gate."), shape: .line(points.map(\.grid))
                ))
                if options.hasWalls {
                    let corners = SettlementGenerator.rectangle(centre: gate, direction: direction.perpendicular, width: 14, depth: 9)
                    features.append(GeneratedFeature(
                        name: names.named(String(localized: "\(compass) Gate")), placeType: "Building",
                        summary: String(localized: "A gate in the wall, where the \(compass) road comes in."), shape: .polygon(corners.map(\.grid))
                    ))
                }
            }
            return features
        }
    }
}
