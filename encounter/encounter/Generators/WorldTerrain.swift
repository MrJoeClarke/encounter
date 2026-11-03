//
//  WorldTerrain.swift
//  encounter
//

import Foundation

/// Smooth random values that depend only on the seed and the place, so the same seed always makes the same land.
nonisolated struct ValueNoise {
    let seed: UInt64

    private func hash(_ x: Int, _ y: Int, _ salt: Int) -> Double {
        var z = seed &+ UInt64(bitPattern: Int64(x)) &* 0x9E3779B97F4A7C15 &+ UInt64(bitPattern: Int64(y)) &* 0xBF58476D1CE4E5B9 &+ UInt64(bitPattern: Int64(salt)) &* 0x94D049BB133111EB
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }

    /// A value from 0 to 1 that changes smoothly from place to place.
    func value(_ x: Double, _ y: Double, salt: Int) -> Double {
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let fx = x - Double(x0), fy = y - Double(y0)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = hash(x0, y0, salt), b = hash(x0 + 1, y0, salt), c = hash(x0, y0 + 1, salt), d = hash(x0 + 1, y0 + 1, salt)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
    }

    /// Several layers of `value`, each finer and fainter than the one before, from 0 to 1.
    func fractal(_ x: Double, _ y: Double, octaves: Int, salt: Int) -> Double {
        var total = 0.0, amplitude = 1.0, norm = 0.0, frequency = 1.0
        for octave in 0..<octaves {
            total += amplitude * value(x * frequency, y * frequency, salt: salt &* 31 &+ octave)
            norm += amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        return total / norm
    }
}

/// A queue that gives back the smallest key first.
nonisolated struct MinHeap {
    private var keys: [Double] = []
    private var items: [Int] = []

    var isEmpty: Bool { items.isEmpty }

    mutating func push(_ item: Int, key: Double) {
        keys.append(key)
        items.append(item)
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard keys[child] < keys[parent] else { break }
            keys.swapAt(child, parent)
            items.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> (item: Int, key: Double)? {
        guard let first = items.first, let key = keys.first else { return nil }
        let lastItem = items.removeLast(), lastKey = keys.removeLast()
        if !items.isEmpty {
            items[0] = lastItem
            keys[0] = lastKey
            var parent = 0
            while true {
                let left = parent * 2 + 1, right = left + 1
                var smallest = parent
                if left < items.count, keys[left] < keys[smallest] { smallest = left }
                if right < items.count, keys[right] < keys[smallest] { smallest = right }
                if smallest == parent { break }
                keys.swapAt(smallest, parent)
                items.swapAt(smallest, parent)
                parent = smallest
            }
        }
        return (first, key)
    }
}

/// Outlines of areas of a grid, and ways of making them smooth.
nonisolated enum Contours {
    /// The outlines of the true cells of a grid, as corners in grid units. A loop going anticlockwise is the outside of an
    /// area, and one going clockwise is a hole in it. Where two areas touch at a corner they are kept apart.
    static func loops(mask: [Bool], width: Int, height: Int) -> [[V]] {
        func isOn(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height && mask[y * width + x] }
        let stride = width + 1
        var from: [Int] = [], to: [Int] = []
        for y in 0..<height {
            for x in 0..<width where mask[y * width + x] {
                let bl = y * stride + x, br = bl + 1, tl = bl + stride, tr = tl + 1
                if !isOn(x, y - 1) { from.append(bl); to.append(br) }
                if !isOn(x + 1, y) { from.append(br); to.append(tr) }
                if !isOn(x, y + 1) { from.append(tr); to.append(tl) }
                if !isOn(x - 1, y) { from.append(tl); to.append(bl) }
            }
        }
        var leaving: [Int: [Int]] = [:]
        for (e, f) in from.enumerated() { leaving[f, default: []].append(e) }
        func point(_ id: Int) -> V { V(x: Double(id % stride), y: Double(id / stride)) }
        var used = [Bool](repeating: false, count: from.count)
        var result: [[V]] = []
        for start in from.indices where !used[start] {
            var loop: [V] = []
            var edge = start
            while !used[edge] {
                used[edge] = true
                loop.append(point(from[edge]))
                let here = to[edge]
                let heading = point(to[edge]) - point(from[edge])
                // At a corner where two edges leave, turn as far left as possible, which keeps separate areas separate.
                let options = (leaving[here] ?? []).filter { !used[$0] || $0 == start }
                guard let next = options.max(by: { turn(heading, point(to[$0]) - point(from[$0])) < turn(heading, point(to[$1]) - point(from[$1])) }) else { break }
                edge = next
            }
            if loop.count >= 4 { result.append(loop) }
        }
        return result
    }

    private static func turn(_ a: V, _ b: V) -> Double { atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y) }

    /// Fewer points that keep a closed outline's shape to within `tolerance`. Steps of a staircase become a slope.
    static func simplify(closed loop: [V], tolerance: Double) -> [V] {
        guard loop.count > 8 else { return loop }
        // Split at the corner farthest from the first, so both halves are open lines.
        var far = 0, farDistance = 0.0
        for (i, p) in loop.enumerated() where p.distance(to: loop[0]) > farDistance { far = i; farDistance = p.distance(to: loop[0]) }
        let first = Array(loop[0...far])
        let second = Array(loop[far...]) + [loop[0]]
        let a = simplify(open: first, tolerance: tolerance), b = simplify(open: second, tolerance: tolerance)
        return Array(a.dropLast()) + Array(b.dropLast())
    }

    static func simplify(open line: [V], tolerance: Double) -> [V] {
        guard line.count > 2, let first = line.first, let last = line.last else { return line }
        var worst = 0, worstDistance = 0.0
        for i in 1..<(line.count - 1) {
            let d = SettlementGenerator.distance(from: line[i], toSegment: first, last)
            if d > worstDistance { worst = i; worstDistance = d }
        }
        guard worstDistance > tolerance else { return [first, last] }
        let left = simplify(open: Array(line[0...worst]), tolerance: tolerance)
        let right = simplify(open: Array(line[worst...]), tolerance: tolerance)
        return Array(left.dropLast()) + right
    }

    /// A closed outline with points added along any side longer than `step`, so that rounding it later cuts each corner by at most
    /// about a step, however long the sides are.
    static func subdivided(closed loop: [V], step: Double) -> [V] {
        var result: [V] = []
        for i in loop.indices {
            let a = loop[i], b = loop[(i + 1) % loop.count]
            let pieces = max(1, Int((a.distance(to: b) / step).rounded(.up)))
            for k in 0..<pieces { result.append(V(x: a.x + (b.x - a.x) * Double(k) / Double(pieces), y: a.y + (b.y - a.y) * Double(k) / Double(pieces))) }
        }
        return result
    }

    /// Cuts the corners off a closed outline, again and again, to make it round.
    static func rounded(closed loop: [V], times: Int) -> [V] {
        var current = loop
        for _ in 0..<times {
            var next: [V] = []
            for i in current.indices {
                let a = current[i], b = current[(i + 1) % current.count]
                next.append(V(x: a.x * 0.75 + b.x * 0.25, y: a.y * 0.75 + b.y * 0.25))
                next.append(V(x: a.x * 0.25 + b.x * 0.75, y: a.y * 0.25 + b.y * 0.75))
            }
            current = next
        }
        return current
    }
}
