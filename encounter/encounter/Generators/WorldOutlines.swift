//
//  WorldOutlines.swift
//  encounter
//

import Foundation

// The outlines of a world's regions. The world is worked out on a coarse grid, but its outlines are drawn from a finer one, cut from the
// coarse one with a little unevenness added, so edges wander like real ones and don't show the grid. The realms, the land beyond them
// and the sea are one partition of that finer grid, and each boundary between two of them is traced once and smoothed once, so the two
// sides of a border, and a realm's coast, are the very same line.

extension WorldMaker {
    /// How many cells of the fine grid make up a cell of the coarse one, along a side.
    static let detail = 4
    /// How many coarse cells the fine grid carries on past each edge of the map, so edges are not rounded off.
    static let margin = 0

    /// What each coarse cell belongs to: 0 for the sea, 1 for land no realm has, then a number for each realm and each piece of the land
    /// beyond the realms. `groups` gives the number of each piece of that land.
    func regionCategories() -> (cells: [Int], groups: [Int: Int]) {
        var groups: [Int: Int] = [:]
        for group in Set(stripGroup).filter({ $0 >= 0 }).sorted() { groups[group] = 2 + realmCount + groups.count }
        let cells = land.indices.map { c -> Int in
            guard land[c] else { return 0 }
            if realmCount == 0 { return 1 }
            if strip[c] { return groups[stripGroup[c]] ?? 1 }
            return realmOf[c] >= 0 && realmOf[c] < realmCount ? 2 + realmOf[c] : 1
        }
        return (cells, groups)
    }

    /// The number of a realm among the regions.
    static func category(ofRealm realm: Int) -> Int { 2 + realm }

    // MARK: The fine grid

    /// The coarse grid's place, in cell-centre units, that a cell of the fine grid is at.
    private func spot(_ h: Int) -> (index: Int, t: Double) {
        let u = (Double(h) + 0.5) / Double(Self.detail) - Double(Self.margin) - 0.5
        let clamped = min(max(u, 0), Double(n - 1))
        let i = min(Int(clamped.rounded(.down)), n - 2)
        return (i, clamped - Double(i))
    }

    /// The fine grid's side, in cells.
    var fineSide: Int { (n + 2 * Self.margin) * Self.detail }

    /// What each cell of the fine grid belongs to: the commonest thing among the coarse cells round it, weighted by how near each
    /// is, with unevenness added where two things meet, so the border between them is smooth but not straight.
    func fineLabels(of categories: [Int]) -> [Int16] {
        let side = fineSide
        var result = [Int16](repeating: 0, count: side * side)
        let unevenness = 1.3
        for hy in 0..<side {
            let (j, ty) = spot(hy)
            for hx in 0..<side {
                let (i, tx) = spot(hx)
                let c00 = categories[j * n + i], c10 = categories[j * n + i + 1]
                let c01 = categories[(j + 1) * n + i], c11 = categories[(j + 1) * n + i + 1]
                if c00 == c10 && c10 == c01 && c01 == c11 { result[hy * side + hx] = Int16(c00); continue }
                let w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty
                let x = Double(i) + tx, y = Double(j) + ty
                var best = c00, bestScore = -Double.infinity
                for candidate in [c00, c10, c01, c11] {
                    let weight = (c00 == candidate ? w00 : 0) + (c10 == candidate ? w10 : 0) + (c01 == candidate ? w01 : 0) + (c11 == candidate ? w11 : 0)
                    let score = weight + unevenness * (noise.fractal(x * 0.9, y * 0.9, octaves: 3, salt: 500 + candidate) - 0.5)
                    if score > bestScore { best = candidate; bestScore = score }
                }
                result[hy * side + hx] = Int16(best)
            }
        }
        return result
    }

    /// The fine grid cells that are part of a coarse mask, with unevenness added at its edge, and not in the sea.
    func fineMask(of mask: [Bool], salt: Int, outsideSea labels: [Int16]) -> [Bool] {
        let side = fineSide
        var result = [Bool](repeating: false, count: side * side)
        for hy in 0..<side {
            let (j, ty) = spot(hy)
            for hx in 0..<side where labels[hy * side + hx] != 0 {
                let (i, tx) = spot(hx)
                let m00 = mask[j * n + i], m10 = mask[j * n + i + 1], m01 = mask[(j + 1) * n + i], m11 = mask[(j + 1) * n + i + 1]
                if m00 == m10 && m10 == m01 && m01 == m11 { result[hy * side + hx] = m00; continue }
                let weight = (m00 ? (1 - tx) * (1 - ty) : 0) + (m10 ? tx * (1 - ty) : 0) + (m01 ? (1 - tx) * ty : 0) + (m11 ? tx * ty : 0)
                let x = Double(i) + tx, y = Double(j) + ty
                result[hy * side + hx] = weight + 1.0 * (noise.fractal(x * 1.1, y * 1.1, octaves: 3, salt: salt) - 0.5) >= 0.5
            }
        }
        return result
    }

    /// A mask grown by `radius` fine cells all round, which is how a margin is kept: what is left outside the grown mask is that far from it.
    func dilated(_ mask: [Bool], radius: Int) -> [Bool] {
        let side = fineSide
        var across = [Bool](repeating: false, count: side * side)
        var prefix = [Int](repeating: 0, count: side + 1)
        for y in 0..<side {
            for x in 0..<side { prefix[x + 1] = prefix[x] + (mask[y * side + x] ? 1 : 0) }
            for x in 0..<side { across[y * side + x] = prefix[min(side - 1, x + radius) + 1] - prefix[max(0, x - radius)] > 0 }
        }
        var result = [Bool](repeating: false, count: side * side)
        for x in 0..<side {
            for y in 0..<side { prefix[y + 1] = prefix[y] + (across[y * side + x] ? 1 : 0) }
            for y in 0..<side { result[y * side + x] = prefix[min(side - 1, y + radius) + 1] - prefix[max(0, y - radius)] > 0 }
        }
        return result
    }

    // MARK: Outlines of one area

    /// Turns a closed loop on the fine grid into a polygon in metres, cut off at the edge of the map, or nil if it is too small or
    /// not a proper outline. `minimumCells` is in coarse cells.
    private func polygon(fromFine loop: [V], minimumCells: Double) -> (area: Double, points: [GridPoint])? {
        let scale = Double(Self.detail)
        let coarse = loop.map { V(x: $0.x / scale - Double(Self.margin), y: $0.y / scale - Double(Self.margin)) }
        guard Plane.signedArea(coarse) >= minimumCells else { return nil }
        // Cutting off at the edge can leave a point twice; a repeat makes an outline that touches itself.
        var clipped: [V] = []
        for point in Self.clip(coarse, toSquareOf: Double(n)) where clipped.last.map({ $0.distance(to: point) > 1e-7 }) ?? true { clipped.append(point) }
        if let first = clipped.first, let last = clipped.last, clipped.count > 1, first.distance(to: last) <= 1e-7 { clipped.removeLast() }
        guard clipped.count >= 3 else { return nil }
        let points = clipped.map { GridPoint(easting: min(max($0.x * cell, 0), extent), northing: min(max($0.y * cell, 0), extent)) }
        guard PlaceGeometry.polygon(points).isValid else { return nil }
        return (Plane.area(clipped), points)
    }

    /// The outlines of an area of the fine grid, smoothed, biggest first.
    func fineOutlines(of mask: [Bool], minimumCells: Double, limit: Int) -> [[GridPoint]] {
        let side = fineSide
        var found: [(area: Double, points: [GridPoint])] = []
        for loop in Contours.loops(mask: mask, width: side, height: side) {
            let smooth = Contours.simplify(closed: Contours.rounded(closed: Contours.simplify(closed: loop, tolerance: 0.5), times: 2), tolerance: 0.1)
            if let made = polygon(fromFine: smooth, minimumCells: minimumCells) { found.append(made) }
        }
        return found.sorted { $0.area > $1.area }.prefix(limit).map(\.points)
    }

    // MARK: Outlines that share their borders

    /// A boundary between two things on the fine grid, from a place where three or more meet (or round a thing with nothing to
    /// share it with) to the next. `left` is the thing on its left going the way the points run.
    private struct Chain {
        var points: [V]
        var left: Int
        var right: Int
        var start: Int
        var end: Int
    }

    /// The outlines of every region of the partition, by region number, biggest first. Each border between two regions is smoothed
    /// once and used by both, so they fit exactly.
    func partitionOutlines(_ labels: [Int16], minimumCells: Double) -> [Int: [[GridPoint]]] {
        let side = fineSide
        let stride = side + 1
        var from: [Int] = [], to: [Int] = [], left: [Int] = [], right: [Int] = []
        for y in 0..<side {
            for x in 0..<side {
                let a = Int(labels[y * side + x])
                if x + 1 < side {
                    let b = Int(labels[y * side + x + 1])
                    if a != b { from.append(y * stride + x + 1); to.append((y + 1) * stride + x + 1); left.append(a); right.append(b) }
                }
                if y + 1 < side {
                    let b = Int(labels[(y + 1) * side + x])
                    if a != b { from.append((y + 1) * stride + x); to.append((y + 1) * stride + x + 1); left.append(b); right.append(a) }
                }
            }
        }
        // The edge of the grid is a border too, with nothing (-1) beyond it, so that a region that reaches it is closed.
        for k in 0..<side {
            let leftCell = Int(labels[k * side]), rightCell = Int(labels[k * side + side - 1])
            let bottomCell = Int(labels[k]), topCell = Int(labels[(side - 1) * side + k])
            from.append((k + 1) * stride); to.append(k * stride); left.append(leftCell); right.append(-1)
            from.append(k * stride + side); to.append((k + 1) * stride + side); left.append(rightCell); right.append(-1)
            from.append(k); to.append(k + 1); left.append(bottomCell); right.append(-1)
            from.append(side * stride + k + 1); to.append(side * stride + k); left.append(topCell); right.append(-1)
        }
        var incident: [Int: [Int]] = [:]
        for e in from.indices {
            incident[from[e], default: []].append(e)
            incident[to[e], default: []].append(e)
        }
        func point(_ id: Int) -> V { V(x: Double(id % stride), y: Double(id / stride)) }

        var used = [Bool](repeating: false, count: from.count)
        var chains: [Chain] = []
        func walk(from startVertex: Int, along first: Int) {
            var vertex = startVertex, edge = first
            let a = from[edge] == vertex ? left[edge] : right[edge]
            let b = from[edge] == vertex ? right[edge] : left[edge]
            var points = [point(vertex)]
            while true {
                used[edge] = true
                let next = from[edge] == vertex ? to[edge] : from[edge]
                points.append(point(next))
                let around = incident[next] ?? []
                guard around.count == 2, next != startVertex, let following = around.first(where: { !used[$0] }) else {
                    chains.append(Chain(points: points, left: a, right: b, start: startVertex, end: next))
                    return
                }
                vertex = next
                edge = following
            }
        }
        // From every place where borders meet, then round whatever is left, which are borders that close on themselves.
        let vertices = incident.keys.sorted()
        for vertex in vertices where incident[vertex]?.count != 2 {
            for edge in incident[vertex] ?? [] where !used[edge] { walk(from: vertex, along: edge) }
        }
        for edge in from.indices where !used[edge] { walk(from: from[edge], along: edge) }

        // Each border is smoothed once, keeping its ends where they are.
        let smoothed = chains.map { chain -> [V] in
            // The edge of the map stays square: only the points along its straight runs are dropped.
            if chain.left < 0 || chain.right < 0 { return Contours.simplify(open: chain.points, tolerance: 0.01) }
            if chain.start == chain.end {
                let round = Contours.rounded(closed: Contours.simplify(closed: Array(chain.points.dropLast()), tolerance: 0.5), times: 2)
                return Contours.simplify(closed: round, tolerance: 0.1) + [chain.points[0]]
            }
            return Contours.simplify(open: Self.roundedOpen(Contours.simplify(open: chain.points, tolerance: 0.5), times: 2), tolerance: 0.1)
        }

        // Each region takes the borders it has on its left, and joins them end to end into outlines.
        struct Piece { var chain: Int; var reversed: Bool; var start: Int; var end: Int }
        var pieces: [Int: [Piece]] = [:]
        for (index, chain) in chains.enumerated() {
            pieces[chain.left, default: []].append(Piece(chain: index, reversed: false, start: chain.start, end: chain.end))
            pieces[chain.right, default: []].append(Piece(chain: index, reversed: true, start: chain.end, end: chain.start))
        }
        func turn(_ a: V, _ b: V) -> Double { atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y) }
        /// The points of a piece, from the smoothed borders or the plain ones.
        func points(_ piece: Piece, plain: Bool) -> [V] {
            let line = plain ? chains[piece.chain].points : smoothed[piece.chain]
            return piece.reversed ? line.reversed() : line
        }
        var result: [Int: [[GridPoint]]] = [:]
        for region in pieces.keys.sorted() where region >= 0 {
            let all = pieces[region] ?? []
            var taken = [Bool](repeating: false, count: all.count)
            var byStart: [Int: [Int]] = [:]
            for (i, piece) in all.enumerated() { byStart[piece.start, default: []].append(i) }
            var found: [(area: Double, points: [GridPoint])] = []
            for first in all.indices where !taken[first] {
                taken[first] = true
                var order = [first]
                var end = all[first].end
                var closed = true
                while end != all[first].start {
                    let last = points(all[order[order.count - 1]], plain: false)
                    let heading = last[last.count - 1] - last[last.count - 2]
                    let options = (byStart[end] ?? []).filter { !taken[$0] }
                    func direction(_ i: Int) -> V { let line = points(all[i], plain: false); return line[1] - line[0] }
                    guard let next = options.max(by: { turn(heading, direction($0)) < turn(heading, direction($1)) }) else {
                        closed = false
                        break
                    }
                    taken[next] = true
                    order.append(next)
                    end = all[next].end
                }
                guard closed else { continue }
                // Where the region touches itself at a single corner, the outline passes that corner twice; it is cut there into
                // separate outlines, so none of them touches itself.
                var parts: [[Int]] = []
                var stack: [Int] = []
                var position: [Int: Int] = [:]
                for piece in order {
                    let node = all[piece].start
                    if let at = position[node] {
                        parts.append(Array(stack[at...]))
                        for removed in stack[at...] { position[all[removed].start] = nil }
                        stack.removeSubrange(at...)
                    }
                    position[node] = stack.count
                    stack.append(piece)
                }
                parts.append(stack)
                for part in parts {
                    // Smoothed, or if that has crossed itself where a region is very thin, as the grid drew it.
                    for plain in [false, true] {
                        var loop: [V] = []
                        for i in part { loop.append(contentsOf: points(all[i], plain: plain).dropLast()) }
                        guard loop.count > 3 else { break }
                        if let made = polygon(fromFine: loop, minimumCells: minimumCells) { found.append(made); break }
                        if Plane.signedArea(loop.map { V(x: $0.x / Double(Self.detail), y: $0.y / Double(Self.detail)) }) < minimumCells { break }
                    }
                }
            }
            result[region] = found.sorted { $0.area > $1.area }.map(\.points)
        }
        return result
    }

    /// Cuts the corners off an open line, again and again, but keeps its two ends where they are.
    static func roundedOpen(_ line: [V], times: Int) -> [V] {
        var current = line
        for _ in 0..<times {
            guard current.count > 2 else { return current }
            var next = [current[0]]
            for i in 0..<(current.count - 1) {
                let a = current[i], b = current[i + 1]
                if i > 0 { next.append(V(x: a.x * 0.75 + b.x * 0.25, y: a.y * 0.75 + b.y * 0.25)) }
                if i < current.count - 2 { next.append(V(x: a.x * 0.25 + b.x * 0.75, y: a.y * 0.25 + b.y * 0.75)) }
            }
            next.append(current[current.count - 1])
            current = next
        }
        return current
    }
}
