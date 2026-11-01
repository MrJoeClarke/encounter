//
//  TownMaker+Blocks.swift
//  encounter
//

import Foundation

extension SettlementGenerator.TownMaker {
    /// Cuts the settlement into wards and works out the streets between them.
    ///
    /// The planned and radial layouts take the cells of a Voronoi diagram as wards. The organic layout makes its main
    /// roads along the edges of those cells, smooths them, and makes new wards from the blocks between the roads. For
    /// every layout the river is a break: a ward is on one side of it or the other, and a road crosses it only at a bridge.
    mutating func makeLayout() {
        if options.layout == .organic, makeOrganicLayout() { return }
        resetGraph()
        makeWards()
        if river.count >= 2 { splitWardsAtRiver() }
        buildGraph()
        classifyEdges()
        routeStreets()
    }

    mutating func resetGraph() {
        wards = []
        vertices = []
        edges = []
        vertexGrid = [:]
        edgeIndex = [:]
        riverNodes = []
        bridgeNodes = []
    }

    private func closed(_ polygon: [V]) -> [V] { polygon + (polygon.first.map { [$0] } ?? []) }

    /// Whether the wards cover the settlement, with none on top of another.
    private func coversSettlement(_ polygons: [[V]]) -> Bool {
        guard polygons.count >= 3 else { return false }
        let total = polygons.reduce(0) { $0 + Plane.area($1) }
        let whole = Plane.area(boundary)
        return total > whole * 0.94 && total < whole * 1.02
    }

    // MARK: The river

    /// Cuts every ward the river runs through into the part on each side.
    mutating func splitWardsAtRiver() {
        var lines = wards.map { closed($0.polygon) }
        lines.append(river)
        lines.append(closed(boundary))
        let faces = PlanarFaces.faces(of: lines, inside: boundary)
        guard coversSettlement(faces), faces.count >= wards.count else { return }
        wards = faces.map { Ward(site: Plane.centroid($0), polygon: Plane.anticlockwise($0), isSquare: SettlementGenerator.contains($0, square)) }
        if !wards.contains(where: \.isSquare) {
            let nearest = wards.indices.min { wards[$0].site.distance(to: square) < wards[$1].site.distance(to: square) } ?? 0
            wards[nearest].isSquare = true
        }
    }

    /// Marks the edges along the river, and the corners on it, and makes the rest side streets. With `roads`, the edges
    /// along them are main streets.
    mutating func classifyEdges(roads: SegmentIndex? = nil) {
        riverNodes = []
        bridgeNodes = []
        if river.count >= 2 {
            let line = SegmentIndex(lines: [river])
            for i in vertices.indices where line.distance(to: vertices[i]) < 0.6 { riverNodes.insert(i) }
            for i in edges.indices where !edges[i].isBoundary {
                let a = vertices[edges[i].a], b = vertices[edges[i].b]
                if line.distance(to: a) < 0.6, line.distance(to: b) < 0.6, line.distance(to: (a + b) * 0.5) < 0.6 { edges[i].isRiver = true }
            }
        }
        for i in edges.indices where !edges[i].isBoundary && !edges[i].isRiver {
            edges[i].rank = .minor
            if let roads {
                let a = vertices[edges[i].a], b = vertices[edges[i].b]
                if roads.distance(to: a) < 0.5, roads.distance(to: b) < 0.5, roads.distance(to: (a + b) * 0.5) < 0.5 { edges[i].rank = .major }
            }
        }
    }

    // MARK: Organic

    /// Makes the wards of an organic settlement in three steps, and returns false (with nothing kept) if they don't come
    /// out right, so the settlement can be made the plain way instead.
    ///
    /// 1. The main roads, along the edges of Voronoi cells: from each gate to the square, and a few more between them.
    /// 2. Each road is smoothed into a curve through its corners.
    /// 3. The wall, the river, the roads and the square cut the settlement into blocks. Big blocks are cut again.
    private mutating func makeOrganicLayout() -> Bool {
        resetGraph()
        makeWards()
        guard wards.count >= 6, let plaza = wards.first(where: \.isSquare)?.polygon else { return false }
        buildGraph()
        routeStreets(ring: false)
        addSecondaryRoutes()
        let skeleton = chains(of: .major).map { line in line.map { vertices[$0] } }
        guard !skeleton.isEmpty else { return false }
        let roads = skeleton.map { Curves.smooth($0) }

        var lines = roads
        lines.append(closed(boundary))
        lines.append(closed(plaza))
        if river.count >= 2 { lines.append(river) }
        let faces = PlanarFaces.faces(of: lines, inside: boundary)
        guard coversSettlement(faces) else { return false }

        // Blocks about as big as a ward are left as they are, and bigger ones cut up.
        let width = max(size.wardWidth, radius * 0.11)
        var squareBlock: [V]?
        var blocks: [[V]] = []
        for face in faces {
            let polygon = Plane.anticlockwise(face)
            if squareBlock == nil, SettlementGenerator.contains(polygon, square) {
                squareBlock = polygon
            } else {
                blocks += cutBlock(polygon, target: width * width, depth: 0)
            }
        }
        guard let squareBlock else { return false }
        let joined = joinCorners(blocks + [squareBlock])
        guard coversSettlement(joined), joined.allSatisfy({ Plane.area($0) > 2 }) else { return false }

        let oldGates = gatePoints
        resetGraph()
        wards = [Ward(site: Plane.centroid(joined[joined.count - 1]), polygon: joined[joined.count - 1], isSquare: true)]
        for polygon in joined.dropLast() { wards.append(Ward(site: Plane.centroid(polygon), polygon: polygon)) }
        buildGraph()
        classifyEdges(roads: SegmentIndex(lines: roads))
        markRingRoundSquare()
        findBridges()
        snapGates(near: oldGates)
        return true
    }

    /// Puts each gate on the corner of the edge nearest where it was that a main road comes to.
    private mutating func snapGates(near old: [V]) {
        var roadEnds = Set<Int>()
        for edge in edges where edge.rank == .major { roadEnds.insert(edge.a); roadEnds.insert(edge.b) }
        let onEdge = Set(edges.filter(\.isBoundary).flatMap { [$0.a, $0.b] })
        let candidates = roadEnds.intersection(onEdge).sorted()
        guard !candidates.isEmpty else { return }
        gatePoints = old.map { gate in
            vertices[candidates.min { vertices[$0].distance(to: gate) < vertices[$1].distance(to: gate) } ?? candidates[0]]
        }
    }

    /// Cuts a block across its long way, a little off square, again and again until the pieces are about the size of a
    /// ward. The cuts become side streets. A cut that would make a bad shape is left out.
    private mutating func cutBlock(_ polygon: [V], target: Double, depth: Int) -> [[V]] {
        let area = Plane.area(polygon)
        guard area > target * 1.6, depth < 7 else { return [polygon] }
        let along = Plane.longestEdgeDirection(polygon)
        let reach = Plane.extent(of: polygon, along: along)
        let at = reach.low + (reach.high - reach.low) * random.value(in: 0.4...0.6)
        let tilt = random.value(in: -0.35...0.35)
        let across = along.perpendicular
        let direction = V(x: across.x * cos(tilt) - across.y * sin(tilt), y: across.x * sin(tilt) + across.y * cos(tilt))
        // The line goes through a point of the block at that distance along it, so tilting it turns it about the block.
        let middle = Plane.centroid(polygon)
        let through = middle + along * (at - (middle.x * along.x + middle.y * along.y))
        guard let pieces = Plane.cut(polygon, through: through, direction: direction) else { return [polygon] }
        let left = Plane.area(pieces.first), right = Plane.area(pieces.second)
        // The pieces have to add up to the block, or the cut has gone wrong.
        guard left > target * 0.3, right > target * 0.3, abs(left + right - area) < area * 0.01 else { return [polygon] }
        return cutBlock(pieces.first, target: target, depth: depth + 1) + cutBlock(pieces.second, target: target, depth: depth + 1)
    }

    /// Where a corner of one ward falls on the side of another, adds it to that ward, so wards that meet share the same corners.
    private func joinCorners(_ polygons: [[V]]) -> [[V]] {
        let cell = 25.0
        var grid: [Int: [V]] = [:]
        for polygon in polygons {
            for corner in polygon {
                grid[Int((corner.x / cell).rounded(.down)) &* 100_003 &+ Int((corner.y / cell).rounded(.down)), default: []].append(corner)
            }
        }
        return polygons.map { polygon in
            var result: [V] = []
            for i in polygon.indices {
                let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                result.append(a)
                let lowX = Int((min(a.x, b.x) / cell).rounded(.down)) - 1, highX = Int((max(a.x, b.x) / cell).rounded(.down)) + 1
                let lowY = Int((min(a.y, b.y) / cell).rounded(.down)) - 1, highY = Int((max(a.y, b.y) / cell).rounded(.down)) + 1
                let along = (b - a).unit
                var onSide: [(t: Double, point: V)] = []
                for x in lowX...highX {
                    for y in lowY...highY {
                        for corner in grid[x &* 100_003 &+ y] ?? [] where corner.distance(to: a) > 0.05 && corner.distance(to: b) > 0.05 {
                            if SettlementGenerator.distance(from: corner, toSegment: a, b) < 0.05 {
                                onSide.append(((corner - a).x * along.x + (corner - a).y * along.y, corner))
                            }
                        }
                    }
                }
                // The same corner can be found in more than one place.
                var added: [V] = []
                for item in onSide.sorted(by: { $0.t < $1.t }) where !added.contains(where: { $0.distance(to: item.point) < 0.05 }) {
                    added.append(item.point)
                }
                result += added
            }
            return result
        }
    }
}
