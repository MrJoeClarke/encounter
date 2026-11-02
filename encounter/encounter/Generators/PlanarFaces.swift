//
//  PlanarFaces.swift
//  encounter
//

import Foundation

/// Finds the areas that a set of lines encloses. Lines that cross, or that end on another line, are joined where they
/// meet, and lines that lead nowhere are dropped, so what is left is a map of closed areas side by side.
nonisolated enum PlanarFaces {
    /// The areas enclosed by the lines, each going anticlockwise. With `inside`, only those within that outline are kept.
    /// The order depends only on the lines, so the same lines always give the same areas in the same order.
    static func faces(of lines: [[V]], inside: [V]? = nil, tolerance tol: Double = 0.05) -> [[V]] {
        var from: [V] = [], to: [V] = []
        for line in lines {
            for i in 0..<max(0, line.count - 1) where line[i].distance(to: line[i + 1]) > tol {
                from.append(line[i])
                to.append(line[i + 1])
            }
        }
        let count = from.count
        guard count >= 3 else { return [] }

        // Which segments could meet, by the squares of a grid they pass through.
        let cellSize = 50.0
        func cells(of i: Int) -> (x: ClosedRange<Int>, y: ClosedRange<Int>) {
            let lowX = min(from[i].x, to[i].x) - tol, highX = max(from[i].x, to[i].x) + tol
            let lowY = min(from[i].y, to[i].y) - tol, highY = max(from[i].y, to[i].y) + tol
            return (Int((lowX / cellSize).rounded(.down))...Int((highX / cellSize).rounded(.down)), Int((lowY / cellSize).rounded(.down))...Int((highY / cellSize).rounded(.down)))
        }
        var buckets: [Int: [Int]] = [:]
        for i in 0..<count {
            let range = cells(of: i)
            for x in range.x { for y in range.y { buckets[x &* 100_003 &+ y, default: []].append(i) } }
        }

        // Where each segment has to be cut: where another crosses it, and where another ends on it.
        var cuts = [[V]](repeating: [], count: count)
        func distance(_ p: V, toSegment i: Int) -> Double { SettlementGenerator.distance(from: p, toSegment: from[i], to[i]) }
        for i in 0..<count {
            var others = Set<Int>()
            let range = cells(of: i)
            for x in range.x { for y in range.y { for j in buckets[x &* 100_003 &+ y] ?? [] where j > i { others.insert(j) } } }
            for j in others.sorted() {
                let r = to[i] - from[i], s = to[j] - from[j]
                let denominator = r.x * s.y - r.y * s.x
                if abs(denominator) > 1e-12 {
                    let q = from[j] - from[i]
                    let t = (q.x * s.y - q.y * s.x) / denominator, u = (q.x * r.y - q.y * r.x) / denominator
                    let lengthI = r.length, lengthJ = s.length
                    if t * lengthI > tol, (1 - t) * lengthI > tol, u * lengthJ > tol, (1 - u) * lengthJ > tol {
                        let point = V(x: from[i].x + r.x * t, y: from[i].y + r.y * t)
                        cuts[i].append(point)
                        cuts[j].append(point)
                    }
                }
                for end in [from[j], to[j]] where distance(end, toSegment: i) < tol && end.distance(to: from[i]) > tol && end.distance(to: to[i]) > tol {
                    cuts[i].append(end)
                }
                for end in [from[i], to[i]] where distance(end, toSegment: j) < tol && end.distance(to: from[j]) > tol && end.distance(to: to[j]) > tol {
                    cuts[j].append(end)
                }
            }
        }

        // The corners, with points that are within the tolerance of each other counted as one.
        var nodes: [V] = []
        var nodeGrid: [Int: [Int]] = [:]
        let nodeCell = tol * 8
        func node(for point: V) -> Int {
            let gx = Int((point.x / nodeCell).rounded(.down)), gy = Int((point.y / nodeCell).rounded(.down))
            for dx in -1...1 {
                for dy in -1...1 {
                    for id in nodeGrid[(gx + dx) &* 100_003 &+ (gy + dy)] ?? [] where nodes[id].distance(to: point) < tol { return id }
                }
            }
            nodes.append(point)
            nodeGrid[gx &* 100_003 &+ gy, default: []].append(nodes.count - 1)
            return nodes.count - 1
        }

        var edgeEnds: [(Int, Int)] = []
        var seen = Set<Int>()
        for i in 0..<count {
            let along = (to[i] - from[i]).unit
            let ordered = cuts[i].sorted { ($0 - from[i]).x * along.x + ($0 - from[i]).y * along.y < ($1 - from[i]).x * along.x + ($1 - from[i]).y * along.y }
            var previous = node(for: from[i])
            for point in ordered + [to[i]] {
                let next = node(for: point)
                if next != previous, seen.insert(min(previous, next) &* 1_000_003 &+ max(previous, next)).inserted { edgeEnds.append((previous, next)) }
                previous = next
            }
        }

        // Drop lines that lead nowhere, again and again until none are left.
        var around = [[Int]](repeating: [], count: nodes.count)
        for (e, ends) in edgeEnds.enumerated() {
            around[ends.0].append(e)
            around[ends.1].append(e)
        }
        var removed = [Bool](repeating: false, count: edgeEnds.count)
        var degree = around.map(\.count)
        var pending = nodes.indices.filter { degree[$0] <= 1 }
        while let n = pending.popLast() {
            for e in around[n] where !removed[e] {
                removed[e] = true
                let other = edgeEnds[e].0 == n ? edgeEnds[e].1 : edgeEnds[e].0
                degree[other] -= 1
                degree[n] -= 1
                if degree[other] <= 1 { pending.append(other) }
            }
        }

        // Each line is two half edges, one each way. Going round an area, at each corner the next half edge is the one
        // that turns furthest left, which keeps the area on the left.
        func head(_ h: Int) -> Int { h % 2 == 0 ? edgeEnds[h / 2].1 : edgeEnds[h / 2].0 }
        func tail(_ h: Int) -> Int { h % 2 == 0 ? edgeEnds[h / 2].0 : edgeEnds[h / 2].1 }
        func heading(_ h: Int) -> Double {
            let a = nodes[tail(h)], b = nodes[head(h)]
            return atan2(b.y - a.y, b.x - a.x)
        }
        var leaving = [[Int]](repeating: [], count: nodes.count)
        for e in edgeEnds.indices where !removed[e] {
            leaving[edgeEnds[e].0].append(e * 2)
            leaving[edgeEnds[e].1].append(e * 2 + 1)
        }
        func next(after h: Int) -> Int? {
            let choices = leaving[head(h)]
            let incoming = heading(h)
            var best: Int?
            var bestTurn = -Double.infinity
            for c in choices {
                var turn = heading(c) - incoming
                while turn > .pi { turn -= 2 * .pi }
                while turn <= -.pi { turn += 2 * .pi }
                // Going back the way it came is the last resort.
                if c == (h ^ 1) { turn = -10 }
                if turn > bestTurn { bestTurn = turn; best = c }
            }
            return best
        }

        var visited = [Bool](repeating: false, count: edgeEnds.count * 2)
        var faces: [[V]] = []
        for start in 0..<(edgeEnds.count * 2) where !visited[start] && !removed[start / 2] {
            var cycle: [Int] = []
            var h = start
            var closed = false
            while cycle.count <= edgeEnds.count * 2 {
                visited[h] = true
                cycle.append(h)
                guard let following = next(after: h) else { break }
                h = following
                if h == start { closed = true; break }
                if visited[h] { break }
            }
            guard closed, cycle.count >= 3 else { continue }
            let polygon = cycle.map { nodes[tail($0)] }
            // Areas go anticlockwise. The one that goes the other way is the outside of everything.
            guard Plane.signedArea(polygon) > 1e-6 else { continue }
            if let inside {
                // A point just inside the first edge.
                let a = polygon[0], b = polygon[1 % polygon.count]
                let probe = V(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) + (b - a).unit.perpendicular * 0.05
                guard SettlementGenerator.contains(inside, probe) else { continue }
            }
            faces.append(polygon)
        }
        return faces
    }
}

/// A set of lines that can be asked how far a point is from them, quickly, by looking only at the lines nearby.
nonisolated struct SegmentIndex {
    private let from: [V]
    private let to: [V]
    private var buckets: [Int: [Int]] = [:]
    private let cellSize: Double

    init(lines: [[V]], cellSize: Double = 25) {
        self.cellSize = cellSize
        var from: [V] = [], to: [V] = []
        for line in lines { for i in 0..<max(0, line.count - 1) { from.append(line[i]); to.append(line[i + 1]) } }
        self.from = from
        self.to = to
        for i in from.indices {
            let lowX = Int((min(from[i].x, to[i].x) / cellSize).rounded(.down)), highX = Int((max(from[i].x, to[i].x) / cellSize).rounded(.down))
            let lowY = Int((min(from[i].y, to[i].y) / cellSize).rounded(.down)), highY = Int((max(from[i].y, to[i].y) / cellSize).rounded(.down))
            for x in lowX...highX { for y in lowY...highY { buckets[x &* 100_003 &+ y, default: []].append(i) } }
        }
    }

    /// The distance to the nearest line, as long as it is within the size of a cell; farther than that, infinity.
    func distance(to point: V) -> Double {
        let gx = Int((point.x / cellSize).rounded(.down)), gy = Int((point.y / cellSize).rounded(.down))
        var best = Double.infinity
        for dx in -1...1 {
            for dy in -1...1 {
                for i in buckets[(gx + dx) &* 100_003 &+ (gy + dy)] ?? [] {
                    best = min(best, SettlementGenerator.distance(from: point, toSegment: from[i], to[i]))
                }
            }
        }
        return best
    }
}

/// Smooth lines through points.
nonisolated enum Curves {
    /// A smooth line that goes through every one of the points (a centripetal Catmull-Rom spline, which doesn't loop or
    /// overshoot at uneven spacing), with `steps` points along each stretch. The points themselves are kept exactly,
    /// so a line that ends on another still meets it.
    static func smooth(_ points: [V], steps: Int = 5) -> [V] {
        guard points.count >= 3 else { return points }
        func mix(_ a: V, _ b: V, _ k: Double) -> V { V(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k) }
        var result = [points[0]]
        for i in 0..<(points.count - 1) {
            let p1 = points[i], p2 = points[i + 1]
            let p0 = i > 0 ? points[i - 1] : p1 + (p1 - p2)
            let p3 = i + 2 < points.count ? points[i + 2] : p2 + (p2 - p1)
            func knot(_ a: V, _ b: V) -> Double { max(a.distance(to: b).squareRoot(), 1e-6) }
            let t0 = 0.0, t1 = knot(p0, p1), t2 = t1 + knot(p1, p2), t3 = t2 + knot(p2, p3)
            for s in 1..<steps {
                let t = t1 + (t2 - t1) * Double(s) / Double(steps)
                let a1 = mix(p0, p1, (t - t0) / (t1 - t0))
                let a2 = mix(p1, p2, (t - t1) / (t2 - t1))
                let a3 = mix(p2, p3, (t - t2) / (t3 - t2))
                let b1 = mix(a1, a2, (t - t0) / (t2 - t0))
                let b2 = mix(a2, a3, (t - t1) / (t3 - t1))
                result.append(mix(b1, b2, (t - t1) / (t2 - t1)))
            }
            result.append(p2)
        }
        return result
    }
}
