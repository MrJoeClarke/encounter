//
//  MapContrastTests.swift
//  encounterTests
//

import Foundation
import Testing
@testable import encounter

/// The text and marks of each map style against the ground they are drawn on, by the web accessibility guidelines' contrast ratio
/// (4.5 to 1 for text, 3 to 1 for marks that must be seen).
struct MapContrastTests {
    private func luminance(_ c: StyleColor) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }

    private func contrast(_ a: StyleColor, _ b: StyleColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    @Test(arguments: MapStyle.all.map(\.id))
    func namesAreReadableOnTheGroundOfEveryStyle(id: String) {
        let style = MapStyle.style(id: id)
        let ratio = contrast(style.ink, style.background)
        print("CONTRAST \(id) ink on ground \(String(format: "%.2f", ratio))")
        #expect(ratio >= 4.5, "\(id): names are \(ratio) to 1 against the ground")
    }

    @Test(arguments: MapStyle.all.map(\.id))
    func pinsAndTheHighlightCanBeSeenOnTheGround(id: String) {
        let style = MapStyle.style(id: id)
        let pin = contrast(style.pin, style.background), capital = contrast(style.capitalPin, style.background), accent = contrast(style.accent, style.background)
        print("CONTRAST \(id) pin \(String(format: "%.2f", pin)) capital \(String(format: "%.2f", capital)) accent \(String(format: "%.2f", accent))")
        #expect(pin >= 3, "\(id): pins are \(pin) to 1")
        #expect(capital >= 3, "\(id): capital pins are \(capital) to 1")
        #expect(accent >= 3, "\(id): the highlight is \(accent) to 1")
    }
}
