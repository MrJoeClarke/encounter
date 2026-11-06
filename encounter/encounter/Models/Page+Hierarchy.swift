//
//  Page+Hierarchy.swift
//  encounter
//

import Foundation
import SwiftData

/// Who chose a place's parent.
enum ParentSource: String {
    /// Worked out from where the place sits inside another place's outline. May be recalculated.
    case automatic
    /// Chosen by the creator, including choosing no parent. Never replaced by a calculation.
    case manual
}

extension Page {
    var parentSource: ParentSource? {
        get { parentSourceRaw.flatMap(ParentSource.init(rawValue:)) }
        set { parentSourceRaw = newValue?.rawValue }
    }

    /// The map this place is shown on, if it has a position: the first map of the nearest place above it that has one.
    var mapShowingIt: WorldMap? {
        guard geometry != nil else { return nil }
        for ancestor in ancestors { if let map = ancestor.sortedMaps.first { return map } }
        return nil
    }

    /// The pages above this one, nearest first. Stops if the data somehow contains a loop.
    var ancestors: [Page] {
        var result: [Page] = []
        var current = parent
        while let page = current, !result.contains(where: { $0 === page }), page !== self {
            result.append(page)
            current = page.parent
        }
        return result
    }

    /// Everything inside this page, at any depth.
    var descendants: [Page] {
        var result: [Page] = []
        var queue = childPages
        while let page = queue.popLast() {
            guard page !== self, !result.contains(where: { $0 === page }) else { continue }
            result.append(page)
            queue.append(contentsOf: page.childPages)
        }
        return result
    }

    /// The pages directly inside this one, sorted by title. Only pages of the same kind count, since only
    /// places form a hierarchy in the interface.
    var childPages: [Page] {
        (children ?? [])
            .filter { !$0.isDeleted && $0.kindRaw == kindRaw }
            .sorted { ($0.title.localizedLowercase, $0.id.uuidString) < ($1.title.localizedLowercase, $1.id.uuidString) }
    }

    /// Whether `candidate` may become this page's parent: nothing (a top-level page), or a page of the same
    /// kind and world that isn't this page or inside it, which would make a loop.
    func canHaveParent(_ candidate: Page?) -> Bool {
        // The root place has no parent, and every other place has one once there is a root.
        if isWorldRoot { return candidate == nil }
        guard let candidate else { return world?.rootPlaceID == nil }
        return candidate !== self
            && candidate.kindRaw == kindRaw
            && candidate.world?.id == world?.id
            && !candidate.ancestors.contains { $0 === self }
    }

    /// Sets the parent as the creator's own choice unless that would break `canHaveParent`. Returns whether
    /// it was set. A choice made this way is never replaced by an automatic parent.
    @discardableResult
    func setParent(_ candidate: Page?) -> Bool {
        guard canHaveParent(candidate) else { return false }
        parent = candidate
        parentSource = .manual
        return true
    }

    /// Gives the place a position (or removes it with nil) and brings automatic parents up to date.
    /// Returns false, changing nothing, for a shape that isn't valid or a page that isn't a place.
    @discardableResult
    func setGeometry(_ newGeometry: PlaceGeometry?) -> Bool {
        guard kind == .place, newGeometry?.isValid ?? true else { return false }
        geometry = newGeometry
        world?.refreshAutomaticParents()
        return true
    }

    /// False once the creator has chosen the parent. A parent with no recorded source (from before sources
    /// were kept) is taken to be the creator's choice too.
    var mayHaveAutomaticParent: Bool {
        switch parentSource {
        case .manual: false
        case .automatic: true
        case nil: parent == nil
        }
    }

    /// The smallest outline among `places` that holds this place, if any. Places this one holds, or that
    /// couldn't be its parent, are ignored.
    func enclosingPlace(among places: [Page]) -> Page? {
        guard let geometry else { return nil }
        return places
            .filter { candidate in
                guard let outline = candidate.geometry, canHaveParent(candidate) else { return false }
                return outline.contains(geometry)
            }
            .min { ($0.geometry?.area ?? 0, $0.id.uuidString) < ($1.geometry?.area ?? 0, $1.id.uuidString) }
    }

    /// Moves this page's children up to its own parent, so deleting the page doesn't lose them or leave them
    /// stranded. Call it before deleting.
    func liftChildrenToParent() {
        let newParent = parent
        for child in children ?? [] where !child.isDeleted {
            child.parent = newParent
        }
    }

    /// "Region › Town › Harbour", for pickers that need to tell same-named pages apart.
    var pathTitle: String {
        // The root place is the same for every place, so it isn't repeated in the path.
        let chain = (ancestors.reversed() + [self]).filter { !$0.isWorldRoot || $0 === self }
        let names = chain.map { $0.title.isEmpty ? String(localized: "Untitled") : $0.title }
        return names.joined(separator: " › ")
    }
}

extension World {
    /// Works out parents from positions. A place whose parent was chosen by the creator is left alone. Any
    /// other place with a position gets the smallest place around it, and one that has lost its position
    /// (or its enclosing place) goes back to being directly inside the root place.
    func refreshAutomaticParents() {
        let places = (pages ?? []).filter { $0.kind == .place && !$0.isDeleted }
        let root = rootPlace
        for place in places where place !== root && place.mayHaveAutomaticParent {
            // Inside the smallest outline around it, or else directly inside the root place.
            let target = place.enclosingPlace(among: places) ?? root
            if place.parent !== target { place.parent = target }
            place.parentSource = target == nil ? nil : .automatic
        }
    }
}
