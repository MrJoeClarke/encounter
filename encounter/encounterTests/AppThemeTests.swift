//
//  AppThemeTests.swift
//  encounterTests
//

import Foundation
import Testing
@testable import encounter

/// Each theme's text, accent and panels against the surfaces they sit on, by the web accessibility guidelines' contrast ratio.
struct AppThemeTests {
    private func luminance(_ c: StyleColor) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }

    private func contrast(_ a: StyleColor, _ b: StyleColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private var themed: [AppTheme] { AppTheme.all.filter { $0.background != nil } }

    @Test func thereIsAStandardThemeThatChangesNothing() {
        let standard = AppTheme.theme(id: "standard")
        #expect(standard.accent == nil && standard.background == nil && standard.panel == nil && standard.ink == nil)
        #expect(AppTheme.theme(id: "no-such-theme").id == "standard")
        #expect(Set(AppTheme.all.map(\.id)).count == AppTheme.all.count)
    }

    @Test(arguments: ["parchment", "tabletop", "cartographer"])
    func textReadsOnTheBackgroundAndThePanel(id: String) throws {
        let theme = AppTheme.theme(id: id)
        let ink = try #require(theme.ink), secondary = try #require(theme.secondaryInk)
        let background = try #require(theme.background), panel = try #require(theme.panel)
        for (name, text, ground) in [("ink on background", ink, background), ("ink on panel", ink, panel), ("secondary on background", secondary, background), ("secondary on panel", secondary, panel)] {
            let ratio = contrast(text, ground)
            #expect(ratio >= 4.5, "\(id): \(name) is \(ratio) to 1")
        }
    }

    @Test(arguments: ["parchment", "tabletop", "cartographer"])
    func theAccentCanBeReadAsTextOnTheBackgroundAndThePanel(id: String) throws {
        let theme = AppTheme.theme(id: id)
        let accent = try #require(theme.accent), background = try #require(theme.background), panel = try #require(theme.panel)
        #expect(contrast(accent, background) >= 4.5, "\(id): the accent is \(contrast(accent, background)) to 1 on the background")
        #expect(contrast(accent, panel) >= 4.5, "\(id): the accent is \(contrast(accent, panel)) to 1 on the panel")
    }

    @Test(arguments: ["tabletop", "cartographer"])
    func aTintedIconCanBeSeenOnItsSquare(id: String) throws {
        let theme = AppTheme.theme(id: id)
        let accent = try #require(theme.accent), panel = try #require(theme.panel)
        #expect(theme.tintedIcons)
        // The icon is drawn in the panel colour on a square of the accent.
        #expect(contrast(panel, accent) >= 3, "\(id): the icon is \(contrast(panel, accent)) to 1 on its square")
    }
}
