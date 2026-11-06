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

    /// The outlines of every region of the partition, by region number, biggest first. Each border between two regions is smoothed
    /// once and used by both, so they fit exactly.
    func partitionOutlines(_ labels: [Int16], minimumCells: Double) -> [Int: [[GridPoint]]] {
        let traced = RasterPartition.trace(labels: labels, width: fineSide, height: fineSide) { loop in
            if let made = polygon(fromFine: loop, minimumCells: minimumCells) { return .made(area: made.area, points: made.points) }
            if Plane.signedArea(loop.map { V(x: $0.x / Double(Self.detail), y: $0.y / Double(Self.detail)) }) < minimumCells { return .tooSmall }
            return .invalid
        }
        return traced.mapValues { $0.map(\.points) }
    }

    /// Cuts the corners off an open line, again and again, but keeps its two ends where they are.
    static func roundedOpen(_ line: [V], times: Int) -> [V] { RasterPartition.roundedOpen(line, times: times) }
}
