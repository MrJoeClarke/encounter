//
//  TownMaker+Quarters.swift
//  encounter
//

import Foundation

extension SettlementGenerator.TownMaker {
    /// The quarters a settlement has when the creator hasn't chosen: more kinds as it gets bigger.
    static func automaticQuarters(for size: SettlementOptions.Size, hasRiver: Bool) -> [Quarter] {
        switch size {
        case .hamlet: []
        case .village: [.craft, .merchant]
        case .town: [.wealthy, .merchant, .craft, .slum, .temple] + (hasRiver ? [.harbour] : [])
        case .city: [.wealthy, .merchant, .craft, .slum, .temple, .military, .scholars, .gardens] + (hasRiver ? [.harbour] : [])
        }
    }

    /// How much of the settlement's wards each kind of quarter takes.
    private static func share(_ quarter: Quarter) -> Double {
        switch quarter {
        case .wealthy: 0.12
        case .merchant: 0.16
        case .craft: 0.16
        case .slum: 0.16
        case .temple: 0.07
        case .military: 0.07
        case .gardens: 0.08
        case .harbour: 0.12
        case .scholars: 0.08
        }
    }

    /// Gives wards to the quarters asked for. Each quarter takes the wards that suit it best: the temple and the wealthy
    /// near the square, merchants and the military near the gates, craftsmen near the gates and the river, slums out
    /// by the wall, and the harbour on the river. The square and wards left over stay ordinary.
    mutating func assignQuarters() {
        let wanted = options.quarters ?? Self.automaticQuarters(for: size, hasRiver: options.hasRiver)
        let candidates = wards.indices.filter { !wards[$0].isSquare }
        guard !wanted.isEmpty, candidates.count >= 3 else { return }

        func t(_ index: Int) -> Double { min(wards[index].site.distance(to: square) / radius, 1.2) }
        func gate(_ index: Int) -> Double { min((gatePoints.map { wards[index].site.distance(to: $0) }.min() ?? radius) / radius, 1.2) }
        func water(_ index: Int) -> Double {
            river.isEmpty ? 1.2 : min(SettlementGenerator.distance(from: wards[index].site, toPolyline: river) / radius, 1.2)
        }
        // Each quarter's score for a ward: lower is better.
        func score(_ quarter: Quarter, _ index: Int) -> Double {
            switch quarter {
            case .temple: t(index)
            case .wealthy: t(index) + 0.25 * gate(index)
            case .harbour: water(index)
            case .merchant: 0.6 * t(index) + 0.5 * gate(index)
            case .military: gate(index) - 0.5 * t(index)
            case .scholars: abs(t(index) - 0.45)
            case .craft: 0.5 * gate(index) + 0.4 * water(index) + 0.3 * t(index)
            case .slum: -t(index) + 0.3 * water(index)
            case .gardens: -t(index) + random.value(in: 0...0.4)
            }
        }

        // The pickiest quarters choose first.
        let order: [Quarter] = [.temple, .wealthy, .harbour, .merchant, .military, .scholars, .craft, .slum, .gardens]
        var free = Set(candidates)
        let budget = Int((Double(candidates.count) * 0.85).rounded(.down))
        var used = 0
        for quarter in order where wanted.contains(quarter) {
            // A harbour needs water to be on.
            if quarter == .harbour && river.isEmpty { continue }
            let count = max(1, Int((Self.share(quarter) * Double(candidates.count)).rounded()))
            // Scored once each, in order, because a score can use the random numbers and a sort asks for it a varying number of times.
            let scores = Dictionary(uniqueKeysWithValues: free.sorted().map { ($0, score(quarter, $0)) })
            let chosen = free.sorted { (scores[$0] ?? 0, $0) < (scores[$1] ?? 0, $1) }.prefix(min(count, budget - used))
            for index in chosen {
                // A harbour ward has to actually be near the river.
                if quarter == .harbour, water(index) > 0.4 { continue }
                wards[index].quarter = quarter
                free.remove(index)
                used += 1
            }
        }
    }

    /// The districts: wards of the same quarter that touch are joined into one outline and named for it, and the ordinary
    /// wards round the square become the old town. Returns the districts as features, and the name of each ward's.
    mutating func makeDistricts() -> (features: [GeneratedFeature], nameOfWard: [Int: String]) {
        let wanted = options.quarters ?? Self.automaticQuarters(for: size, hasRiver: options.hasRiver)
        guard !wanted.isEmpty else { return ([], [:]) }

        // Wards that share an edge are neighbours.
        var edgeOwners: [Int: [Int]] = [:]
        for index in wards.indices {
            let ids = wards[index].vertexIDs
            for i in ids.indices { edgeOwners[edgeKey(ids[i], ids[(i + 1) % ids.count]), default: []].append(index) }
        }
        // Wards either side of the river share its edges, but they are not neighbours.
        var neighbours: [Int: Set<Int>] = [:]
        for (key, owners) in edgeOwners.sorted(by: { $0.key < $1.key }) where owners.count == 2 && !(edgeIndex[key].map { edges[$0].isRiver } ?? false) {
            neighbours[owners[0], default: []].insert(owners[1])
            neighbours[owners[1], default: []].insert(owners[0])
        }

        func group(of index: Int) -> String? {
            if wards[index].isSquare { return nil }
            if let quarter = wards[index].quarter { return quarter.rawValue }
            return "old"
        }

        var seen = Set<Int>()
        var features: [GeneratedFeature] = []
        var nameOfWard: [Int: String] = [:]
        for start in wards.indices where !seen.contains(start) {
            guard let kind = group(of: start) else { continue }
            // The connected run of wards of this kind.
            var component: [Int] = []
            var queue = [start]
            seen.insert(start)
            while let next = queue.popLast() {
                component.append(next)
                for other in (neighbours[next] ?? []).sorted() where !seen.contains(other) && group(of: other) == kind {
                    seen.insert(other)
                    queue.append(other)
                }
            }
            component.sort()
            // Where the outline pinches or crosses itself (as at an odd-shaped boundary) the biggest ward stands for it.
            var outline = outerOutline(of: component, edgeOwners: edgeOwners) ?? []
            if outline.count < 3 || !PlaceGeometry.polygon(outline.map(\.grid)).isValid,
               let biggest = component.max(by: { Plane.area(wards[$0].polygon) < Plane.area(wards[$1].polygon) }) {
                outline = wards[biggest].polygon
            }
            guard outline.count >= 3 else { continue }
            let quarter = wards[start].quarter
            let name = names.named(quarter?.districtName ?? String(localized: "Old Town"))
            for index in component { nameOfWard[index] = name }
            features.append(GeneratedFeature(
                name: name, placeType: quarter == .gardens ? "Garden" : "District",
                summary: quarter.map { String(localized: "The \($0.title.lowercased()) quarter.") } ?? String(localized: "The oldest part of the settlement, round the square."),
                shape: .polygon(outline.map(\.grid))
            ))
        }
        return (features, nameOfWard)
    }

    /// The outline round a group of wards: the edges that belong to only one of them, joined up, taking the biggest loop.
    private func outerOutline(of component: [Int], edgeOwners: [Int: [Int]]) -> [V]? {
        let members = Set(component)
        // Directed edges with the group on their left, whichever way round each ward is wound.
        var out: [Int: [Int]] = [:]
        for index in component {
            var ids = wards[index].vertexIDs
            if Plane.signedArea(ids.map { vertices[$0] }) < 0 { ids.reverse() }
            for i in ids.indices {
                let a = ids[i], b = ids[(i + 1) % ids.count]
                guard a != b else { continue }
                // An edge between two wards of the group is inside it.
                if (edgeOwners[edgeKey(a, b)] ?? []).filter({ members.contains($0) }).count > 1 { continue }
                out[a, default: []].append(b)
            }
        }
        // Follow the edges round, turning as far left as possible where the outline pinches, so that two lobes that
        // meet at one corner come out as two loops instead of one that crosses itself.
        var loops: [[V]] = []
        for start in out.keys.sorted() {
            while let first = out[start]?.first {
                out[start]?.removeFirst()
                var loop = [start], current = first, previous = start
                while current != start {
                    loop.append(current)
                    guard let choices = out[current], !choices.isEmpty else { break }
                    let heading = vertices[current] - vertices[previous]
                    let pick = choices.max { turn(heading, vertices[$0] - vertices[current]) < turn(heading, vertices[$1] - vertices[current]) } ?? choices[0]
                    if let at = choices.firstIndex(of: pick) { out[current]?.remove(at: at) }
                    previous = current
                    current = pick
                }
                if current == start, loop.count >= 3 { loops.append(loop.map { vertices[$0] }) }
            }
        }
        return loops.max { Plane.area($0) < Plane.area($1) }
    }

    /// How far to the left the second direction turns from the first, in radians.
    private func turn(_ from: V, _ to: V) -> Double {
        atan2(from.x * to.y - from.y * to.x, from.x * to.x + from.y * to.y)
    }
}
