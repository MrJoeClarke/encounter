//
//  Campaign.swift
//  encounter
//

import Foundation
import SwiftData

/// A campaign run in a world. Events can belong to a campaign or be backstory.
@Model
final class Campaign {
    var id: UUID = UUID()
    var name: String = ""
    var summary: String = ""
    var createdAt: Date = Date()
    var world: World?

    @Relationship(deleteRule: .nullify, inverse: \Page.campaign)
    var events: [Page]?

    init(name: String, summary: String = "") {
        self.name = name
        self.summary = summary
    }
}
