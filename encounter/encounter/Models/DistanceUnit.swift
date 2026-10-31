//
//  DistanceUnit.swift
//  encounter
//

import Foundation

/// A unit that distances are shown and typed in. Distances are always stored in metres, so changing the unit
/// never changes what is stored.
enum DistanceUnit: String, CaseIterable, Identifiable {
    case miles
    case kilometres
    case feet
    case metres

    var id: String { rawValue }

    /// The unit used throughout the app. This is where a setting for it would go.
    static let preferred: DistanceUnit = .miles

    /// How many metres one of the unit is.
    var metres: Double {
        switch self {
        case .miles: 1609.344
        case .kilometres: 1000
        case .feet: 0.3048
        case .metres: 1
        }
    }

    var symbol: String {
        switch self {
        case .miles: "mi"
        case .kilometres: "km"
        case .feet: "ft"
        case .metres: "m"
        }
    }

    var name: String {
        switch self {
        case .miles: String(localized: "miles")
        case .kilometres: String(localized: "kilometres")
        case .feet: String(localized: "feet")
        case .metres: String(localized: "metres")
        }
    }

    func value(fromMetres metres: Double) -> Double { metres / self.metres }

    func metres(fromValue value: Double) -> Double { value * metres }

    /// "311 mi", with about three significant figures.
    func format(metres: Double) -> String {
        let value = value(fromMetres: metres)
        return value.formatted(.number.precision(.significantDigits(1...3))) + " " + symbol
    }
}
