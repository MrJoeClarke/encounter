//
//  InWorldDate.swift
//  encounter
//

import Foundation

/// A date in a world's custom calendar. Months and days are 1-based, hours are 0-based.
/// Ordering and validation need the world's `CalendarDefinition`.
nonisolated struct InWorldDate: Codable, Hashable, Sendable {
    var year: Int = 0
    var month: Int = 1
    var day: Int = 1
    var hour: Int = 0
}
