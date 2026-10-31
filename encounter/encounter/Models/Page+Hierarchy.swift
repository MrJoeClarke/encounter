//
//  Page+Hierarchy.swift
//  encounter
//

import Foundation
import SwiftData

extension Page {
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
        guard let candidate else { return true }
        return candidate !== self
            && candidate.kindRaw == kindRaw
            && candidate.world?.id == world?.id
            && !candidate.ancestors.contains { $0 === self }
    }

    /// Sets the parent unless that would break `canHaveParent`. Returns whether it was set.
    @discardableResult
    func setParent(_ candidate: Page?) -> Bool {
        guard canHaveParent(candidate) else { return false }
        parent = candidate
        return true
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
        let names = (ancestors.reversed() + [self]).map { $0.title.isEmpty ? String(localized: "Untitled") : $0.title }
        return names.joined(separator: " › ")
    }
}
