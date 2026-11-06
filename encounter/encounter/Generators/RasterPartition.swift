//
//  RasterPartition.swift
//  encounter
//

import Foundation

/// The outlines of the regions of a raster in which every cell belongs to one region (a world's land, sea and realms, or the colours of a map
/// picture). Each border between two regions is traced once, smoothed once and used by both, so neighbours fit exactly, and where regions
/// touch themselves at a corner their outlines are cut apart there.
nonisolated enum RasterPartition {
    /// How the traced borders are smoothed, in cells.
    struct Smoothing {
        /// How far from a border's staircase a straight run may be, before it is rounded.
        var simplify = 0.5
        /// How far from the rounded border the final points may be, so that no more are kept than the shape needs.
        var finalSimplify = 0.1
        /// How many times the corners of a border are cut off.
        var rounding = 2
        /// If set, the longest a straight run may be before it is rounded, so a sharp corner between long runs is only rounded where it
        /// is (within about a quarter of this) instead of for a quarter of the length of each run. Left alone, the borders of a world
        /// are rounded all over, as a coast is.
        var longestRun: Double? = nil
    }

    /// What was made of a loop of cells' corners.
    enum Conversion {
        /// An outline, with its area for sorting.
        case made(area: Double, points: [GridPoint])
        /// Not a proper outline (it crosses itself): the plain, unsmoothed one is tried.
        case invalid
        /// Too small to keep, so there is no point trying the plain one.
        case tooSmall
    }

    /// A border between two regions, from a place where three or more meet (or round a region with nothing to share it with) to the next.
    /// `left` is the region on its left going the way the points run.
    private struct Chain {
        var points: [V]
        var left: Int
        var right: Int
        var start: Int
        var end: Int
    }

    /// The outlines of each region, biggest first, by region number, which must not be negative. `labels` has `width` by `height` cells, row
    /// by row from the bottom, as the loops' points do (a point is the corner of a cell, from 0 to the width and height). `convert` is given
    /// each loop and turns it into the outline that is wanted, or says why not. Regions in `skipping` are not made into outlines.
    static func trace(labels: [Int16], width: Int, height: Int, smoothing: Smoothing = Smoothing(), skipping: Set<Int> = [], convert: ([V]) -> Conversion) -> [Int: [(area: Double, points: [GridPoint])]] {
        let stride = width + 1
        var from: [Int] = [], to: [Int] = [], left: [Int] = [], right: [Int] = []
        for y in 0..<height {
            for x in 0..<width {
                let a = Int(labels[y * width + x])
                if x + 1 < width {
                    let b = Int(labels[y * width + x + 1])
                    if a != b { from.append(y * stride + x + 1); to.append((y + 1) * stride + x + 1); left.append(a); right.append(b) }
                }
                if y + 1 < height {
                    let b = Int(labels[(y + 1) * width + x])
                    if a != b { from.append((y + 1) * stride + x); to.append((y + 1) * stride + x + 1); left.append(b); right.append(a) }
                }
            }
        }
        // The edge of the grid is a border too, with nothing (-1) beyond it, so that a region that reaches it is closed.
        for y in 0..<height {
            from.append((y + 1) * stride); to.append(y * stride); left.append(Int(labels[y * width])); right.append(-1)
            from.append(y * stride + width); to.append((y + 1) * stride + width); left.append(Int(labels[y * width + width - 1])); right.append(-1)
        }
        for x in 0..<width {
            from.append(x); to.append(x + 1); left.append(Int(labels[x])); right.append(-1)
            from.append(height * stride + x + 1); to.append(height * stride + x); left.append(Int(labels[(height - 1) * width + x])); right.append(-1)
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
                let simple = Contours.simplify(closed: Array(chain.points.dropLast()), tolerance: smoothing.simplify)
                let round = Contours.rounded(closed: smoothing.longestRun.map { subdivided(simple, closed: true, longest: $0) } ?? simple, times: smoothing.rounding)
                return Contours.simplify(closed: round, tolerance: smoothing.finalSimplify) + [chain.points[0]]
            }
            let simple = Contours.simplify(open: chain.points, tolerance: smoothing.simplify)
            return Contours.simplify(open: roundedOpen(smoothing.longestRun.map { subdivided(simple, closed: false, longest: $0) } ?? simple, times: smoothing.rounding), tolerance: smoothing.finalSimplify)
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
        var result: [Int: [(area: Double, points: [GridPoint])]] = [:]
        for region in pieces.keys.sorted() where region >= 0 && !skipping.contains(region) {
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
                        switch convert(loop) {
                        case .made(let area, let outline): found.append((area, outline))
                        case .tooSmall: break
                        case .invalid: continue
                        }
                        break
                    }
                }
            }
            result[region] = found.sorted { $0.area > $1.area }
        }
        return result
    }

    /// A line with points added so that no run between two is longer than `longest`.
    static func subdivided(_ line: [V], closed: Bool, longest: Double) -> [V] {
        guard line.count > 1 else { return line }
        var result: [V] = []
        let last = closed ? line.count : line.count - 1
        for i in 0..<last {
            let a = line[i], b = line[(i + 1) % line.count]
            result.append(a)
            let pieces = Int((a.distance(to: b) / longest).rounded(.up))
            if pieces > 1 {
                for k in 1..<pieces {
                    let t = Double(k) / Double(pieces)
                    result.append(V(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
        }
        if !closed { result.append(line[line.count - 1]) }
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
