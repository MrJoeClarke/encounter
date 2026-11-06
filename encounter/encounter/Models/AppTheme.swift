//
//  AppTheme.swift
//  encounter
//

import SwiftUI

/// How the app looks: colours, type and shapes, as data like a map style, so a look is defined once and shared by every screen. Where a
/// colour is nil the system's own is used, so the Standard theme is the platform's look.
nonisolated struct AppTheme: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let summary: String

    /// The colour of buttons, selections and marks.
    var accent: StyleColor?
    /// What sits behind lists and forms.
    var background: StyleColor?
    /// Rows and panels, on the background.
    var panel: StyleColor?
    /// Text, and the quieter text under it.
    var ink: StyleColor?
    var secondaryInk: StyleColor?
    /// Thin lines: the border of a panel.
    var line: StyleColor?
    /// The design of the type: all of it, and the titles.
    var bodyDesign: Font.Design?
    var titleDesign: Font.Design?
    /// Whether section labels are in small capitals.
    var smallCapsLabels = false
    /// Light or dark whatever the device is set to, or nil to follow it.
    var scheme: ColorScheme?
    var cornerRadius: Double = 10
    /// Whether the icons in menus and rows sit on a rounded square of the accent colour.
    var tintedIcons = false

    static let defaultID = "standard"
    static let all: [AppTheme] = [standard, parchment, tabletop, cartographer]
    static func theme(id: String) -> AppTheme { all.first { $0.id == id } ?? standard }

    private static func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> StyleColor { StyleColor(red: r, green: g, blue: b, alpha: a) }

    /// The platform's own look.
    static let standard = AppTheme(
        id: "standard", title: String(localized: "Standard"), summary: String(localized: "The look of the system: its blue, its type and its greys.")
    )

    /// Warm paper, ink-dark type, a serif, and a deep red.
    static let parchment = AppTheme(
        id: "parchment", title: String(localized: "Parchment and Ink"), summary: String(localized: "Warm paper, serif type and a deep red, like the parchment map."),
        accent: color(0.6, 0.17, 0.15), background: color(0.95, 0.91, 0.83), panel: color(0.98, 0.95, 0.89),
        ink: color(0.2, 0.15, 0.1), secondaryInk: color(0.4, 0.33, 0.27), line: color(0.55, 0.45, 0.35, 0.45),
        bodyDesign: .serif, titleDesign: .serif, smallCapsLabels: true, scheme: .light, cornerRadius: 6, tintedIcons: false
    )

    /// Deep charcoal, warm light type and gold.
    static let tabletop = AppTheme(
        id: "tabletop", title: String(localized: "Dark Tabletop"), summary: String(localized: "Charcoal surfaces, warm light type and gold, like a game master’s screen at night."),
        accent: color(0.9, 0.7, 0.25), background: color(0.09, 0.1, 0.12), panel: color(0.15, 0.16, 0.19),
        ink: color(0.93, 0.91, 0.86), secondaryInk: color(0.65, 0.64, 0.62), line: color(1, 1, 1, 0.12),
        bodyDesign: nil, titleDesign: .serif, smallCapsLabels: true, scheme: .dark, cornerRadius: 12, tintedIcons: true
    )

    /// Clean and light, a muted teal, fine lines and square corners.
    static let cartographer = AppTheme(
        id: "cartographer", title: String(localized: "Modern Cartographer"), summary: String(localized: "Clean and light, with a muted teal, fine lines and square corners, like the survey map."),
        accent: color(0.05, 0.45, 0.5), background: color(0.95, 0.96, 0.96), panel: color(1, 1, 1),
        ink: color(0.1, 0.17, 0.2), secondaryInk: color(0.35, 0.43, 0.46), line: color(0.6, 0.7, 0.72, 0.7),
        bodyDesign: nil, titleDesign: .monospaced, smallCapsLabels: true, scheme: .light, cornerRadius: 3, tintedIcons: true
    )
}

extension StyleColor {
    var themeColor: Color { Color(red: red, green: green, blue: blue).opacity(alpha) }
}

extension EnvironmentValues {
    @Entry var appTheme: AppTheme = .standard
}

/// Puts the chosen theme on everything inside: the accent colour, the type, light or dark, and the theme itself in the environment for
/// the screens that style themselves from it.
struct AppThemeRoot: ViewModifier {
    @AppStorage("appThemeID") private var themeID = AppTheme.defaultID

    func body(content: Content) -> some View {
        content.inTheme(AppTheme.theme(id: themeID))
    }
}

extension View {
    /// Shows this view in a theme: the accent colour, the type, light or dark, and the theme in the environment.
    func inTheme(_ theme: AppTheme) -> some View {
        environment(\.appTheme, theme)
            .tint(theme.accent?.themeColor)
            .fontDesign(theme.bodyDesign)
            .preferredColorScheme(theme.scheme)
    }

    /// Applies the theme the user chose to this view and what is inside it.
    func appTheme() -> some View { modifier(AppThemeRoot()) }
}

// MARK: Styles that screens ask for

/// A list or form on the theme's background.
struct ThemedScreen: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if let background = theme.background {
            content
                .scrollContentBackground(.hidden)
                .background(background.themeColor.ignoresSafeArea())
                .foregroundStyle(theme.ink?.themeColor ?? Color.primary)
        } else {
            content
        }
    }
}

/// A row or section on the theme's panel colour, with the theme's fine line under it.
struct ThemedRow: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if let panel = theme.panel {
            content.listRowBackground(panel.themeColor).listRowSeparatorTint(theme.line?.themeColor)
        } else {
            content
        }
    }
}

/// A title in the theme's type.
struct ThemedTitle: ViewModifier {
    @Environment(\.appTheme) private var theme
    var font: Font

    func body(content: Content) -> some View {
        content.font(font).fontDesign(theme.titleDesign ?? theme.bodyDesign)
    }
}

/// A label over a section: in small capitals and the quieter ink where the theme says so.
struct ThemedLabel: View {
    @Environment(\.appTheme) private var theme
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        if theme.smallCapsLabels {
            Text(text)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(theme.secondaryInk?.themeColor ?? Color.secondary)
        } else {
            Text(text)
        }
    }
}

/// An icon, on a rounded square of the accent colour where the theme tints its icons.
struct ThemedIcon: View {
    @Environment(\.appTheme) private var theme
    let systemName: String
    var size: Double = 28

    var body: some View {
        if theme.tintedIcons, let accent = theme.accent {
            Image(systemName: systemName)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(theme.panel?.themeColor ?? Color.white)
                .frame(width: size, height: size)
                .background(accent.themeColor, in: RoundedRectangle(cornerRadius: theme.cornerRadius * 0.6))
                .accessibilityHidden(true)
        } else {
            Image(systemName: systemName)
                .accessibilityHidden(true)
        }
    }
}

/// The icon standing for a page or a world in a list: its picture's thumbnail, or a symbol on a square the theme colours.
struct ThemedThumbnail: View {
    @Environment(\.appTheme) private var theme
    let data: Data?
    let systemName: String
    var size: Double = 36

    var body: some View {
        if let data {
            DataImage(data: data)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius * 0.7))
                .overlay { RoundedRectangle(cornerRadius: theme.cornerRadius * 0.7).strokeBorder(theme.line?.themeColor ?? .clear) }
        } else {
            Image(systemName: systemName)
                .accessibilityHidden(true)
                .foregroundStyle(theme.accent?.themeColor ?? Color.secondary)
                .frame(width: size, height: size)
                .background(
                    theme.accent.map { $0.themeColor.opacity(0.14) } ?? Color.secondary.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: theme.cornerRadius * 0.7)
                )
        }
    }
}

extension View {
    func themedScreen() -> some View { modifier(ThemedScreen()) }
    func themedRow() -> some View { modifier(ThemedRow()) }
    func themedTitle(_ font: Font = .title2.weight(.semibold)) -> some View { modifier(ThemedTitle(font: font)) }
}

/// A navigation title in the theme's type and ink, in the middle of the bar, in place of the system's large title.
struct ThemedNavigationTitle: ViewModifier {
    @Environment(\.appTheme) private var theme
    let title: String

    func body(content: Content) -> some View {
        if theme.titleDesign != nil || theme.ink != nil {
            content
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(title)
                            .themedTitle(.headline)
                            .foregroundStyle(theme.ink?.themeColor ?? Color.primary)
                    }
                }
        } else {
            content.navigationTitle(title)
        }
    }
}

extension View {
    func themedNavigationTitle(_ title: String) -> some View { modifier(ThemedNavigationTitle(title: title)) }
}

/// The top of a world's home page: its picture with its name over it, or a panel with an emblem where it has no picture. Shown only by a
/// theme that has surfaces of its own; the Standard theme has none.
struct WorldBanner: View {
    @Environment(\.appTheme) private var theme
    let name: String
    let detail: String
    let imageData: Data?

    var body: some View {
        if theme.background != nil {
            // The picture or panel is the background, so it fills the banner without making it any bigger.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .background {
                    if let imageData {
                        DataImage(data: imageData)
                            .overlay { LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom) }
                    } else {
                        (theme.panel?.themeColor ?? Color.secondary.opacity(0.1))
                            .overlay {
                                Image(systemName: "globe.europe.africa")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(28)
                                    .foregroundStyle((theme.accent?.themeColor ?? Color.secondary).opacity(0.18))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name.isEmpty ? String(localized: "Untitled World") : name)
                            .themedTitle(.largeTitle.weight(.semibold))
                            .foregroundStyle(imageData == nil ? (theme.ink?.themeColor ?? Color.primary) : Color.white)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(imageData == nil ? (theme.accent?.themeColor ?? Color.secondary) : Color.white.opacity(0.85))
                    }
                    .padding(16)
                }
            .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: theme.cornerRadius).strokeBorder(theme.line?.themeColor ?? .clear, lineWidth: 1) }
            .accessibilityElement(children: .combine)
        }
    }
}
