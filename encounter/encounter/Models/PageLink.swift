//
//  PageLink.swift
//  encounter
//

import Foundation
import SwiftData

/// A directed reference from one page to another, such as a participant in an event.
/// Rebuilt from `@` mentions and structured fields in the links milestone.
@Model
final class PageLink {
    var id: UUID = UUID()
    /// How the source relates to the target, e.g. "participant", "location", "member".
    var role: String = ""
    var source: Page?
    var target: Page?

    init(source: Page, target: Page, role: String = "") {
        self.source = source
        self.target = target
        self.role = role
    }
}
