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

    /// Every look to choose from, by day and by night.
    private var looks: [(name: String, theme: AppTheme)] {
        AppTheme.all.filter { $0.id != "standard" }.flatMap { theme in
            [("\(theme.id) by day", AppTheme.theme(id: theme.id)), ("\(theme.id) by night", AppTheme.theme(id: theme.id, night: true))]
        }
    }

    @Test func thereIsAStandardThemeThatChangesNothing() {
        let standard = AppTheme.theme(id: "standard")
        #expect(standard.accent == nil && standard.background == nil && standard.panel == nil && standard.ink == nil)
        #expect(AppTheme.theme(id: "no-such-theme").id == "standard")
        #expect(Set(AppTheme.all.map(\.id)).count == AppTheme.all.count)
        // Every id offered is one the app can make again.
        #expect(AppTheme.all.allSatisfy { AppTheme.theme(id: $0.id).id == $0.id })
    }

    @Test func textReadsOnTheBackgroundAndThePanel() throws {
        for (name, theme) in looks {
            let ink = try #require(theme.ink), secondary = try #require(theme.secondaryInk)
            let background = try #require(theme.background), panel = try #require(theme.panel)
            for (what, text, ground) in [("ink on background", ink, background), ("ink on panel", ink, panel), ("secondary on background", secondary, background), ("secondary on panel", secondary, panel)] {
                let ratio = contrast(text, ground)
                #expect(ratio >= 4.5, "\(name): \(what) is \(ratio) to 1")
            }
        }
    }

    @Test func theAccentCanBeReadAsTextOnTheBackgroundAndThePanel() throws {
        for (name, theme) in looks {
            let accent = try #require(theme.accent), background = try #require(theme.background), panel = try #require(theme.panel)
            #expect(contrast(accent, background) >= 4.5, "\(name): the accent is \(contrast(accent, background)) to 1 on the background")
            #expect(contrast(accent, panel) >= 4.5, "\(name): the accent is \(contrast(accent, panel)) to 1 on the panel")
        }
    }

    @Test func theNightLookIsDarkAndTheDayLookIsLight() throws {
        for theme in AppTheme.all.filter({ $0.id != "standard" }) {
            let day = try #require(AppTheme.theme(id: theme.id).background), night = try #require(AppTheme.theme(id: theme.id, night: true).background)
            #expect(luminance(day) > 0.5 && luminance(night) < 0.1, "\(theme.id)")
        }
    }
}
