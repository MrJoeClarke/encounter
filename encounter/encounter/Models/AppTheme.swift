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
    /// The wash behind the chosen row of a list.
    var selection: StyleColor?
    /// The design of the type: all of it, and the titles.
    var bodyDesign: Font.Design?
    var titleDesign: Font.Design?
    /// A font for titles, by its PostScript name, in place of the system's.
    var titleFontName: String?
    /// Whether section labels are in small capitals.
    var smallCapsLabels = false
    /// Light or dark whatever the device is set to, or nil to follow it.
    var scheme: ColorScheme?
    var cornerRadius: Double = 10
    /// Whether the icons in menus and rows sit on a rounded square of the accent colour.
    var tintedIcons = false
    /// Paper grain behind screens.
    var grain = false
    /// Whether panels have a thin border.
    var borderedPanels = false
    /// Flourishes on a world's banner: corners, a rule under its name, and a seal for a world without a picture.
    var ornaments = false
    /// A rule beside each section label.
    var labelRules = false
    /// Rings round the icons of menus and rows.
    var ringedIcons = false

    static let defaultID = "parchment"
    /// The looks to choose from.
    static let all: [AppTheme] = [standard, parchment()]

    /// The theme of an id. Parchment has a darker counterpart for when the device is in dark mode.
    static func theme(id: String, night: Bool = false) -> AppTheme {
        switch id {
        // The variants tried first are all this one now.
        case "parchment", "parchment-plain", "parchment-paper", "parchment-ornate": parchment(night: night)
        default: standard
        }
    }

    private static func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> StyleColor { StyleColor(red: r, green: g, blue: b, alpha: a) }

    /// The platform's own look.
    static let standard = AppTheme(
        id: "standard", title: String(localized: "Standard"), summary: String(localized: "The look of the system: its blue, its type and its greys.")
    )

    /// Cream paper with a grain, ink-dark type, and a deep red, by day; by night dark brown with warm cream ink. Baskerville titles, as on
    /// the parchment map, and flourishes on a world's banner.
    static func parchment(night: Bool = false) -> AppTheme {
        var theme = AppTheme(
            id: "parchment", title: String(localized: "Parchment and Ink"),
            summary: String(localized: "Paper grain, Baskerville and a deep red, like the parchment map, with flourishes on a world’s banner. By night, dark brown with cream ink.")
        )
        if night {
            theme.accent = color(0.92, 0.5, 0.4)
            theme.background = color(0.13, 0.1, 0.08)
            theme.panel = color(0.19, 0.15, 0.12)
            theme.ink = color(0.93, 0.88, 0.78)
            theme.secondaryInk = color(0.72, 0.64, 0.54)
            theme.line = color(0.8, 0.65, 0.45, 0.32)
            theme.selection = color(0.8, 0.6, 0.25, 0.28)
        } else {
            theme.accent = color(0.6, 0.17, 0.15)
            theme.background = color(0.95, 0.91, 0.83)
            theme.panel = color(0.98, 0.95, 0.89)
            theme.ink = color(0.2, 0.15, 0.1)
            theme.secondaryInk = color(0.4, 0.33, 0.27)
            theme.line = color(0.55, 0.45, 0.35, 0.45)
            theme.selection = color(0.85, 0.65, 0.2, 0.3)
        }
        // Titles and names are Baskerville; everything under them is the system sans, so the serif marks the level of a thing.
        theme.bodyDesign = nil
        theme.titleDesign = .serif
        theme.titleFontName = MapStyle.Lettering.baskerville.semibold
        theme.smallCapsLabels = true
        theme.cornerRadius = 6
        theme.grain = true
        theme.ornaments = true
        return theme
    }
}

extension StyleColor {
    var themeColor: Color { Color(red: red, green: green, blue: blue).opacity(alpha) }
}

extension EnvironmentValues {
    @Entry var appTheme: AppTheme = .standard
}

/// Puts the chosen theme on everything inside: the accent colour, the type, light or dark, and the theme itself in the environment for
/// the screens that style themselves from it. Parchment follows the device into dark mode, as a darker brown.
struct AppThemeRoot: ViewModifier {
    @AppStorage("appThemeID") private var themeID = AppTheme.defaultID
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.inTheme(AppTheme.theme(id: themeID, night: colorScheme == .dark))
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

// MARK: Paper

/// Paper grain behind a screen: a square of the paper of the parchment map, repeated.
struct PaperBackground: View {
    let ground: StyleColor

    private static let paper = PaperTexture(seed: 0x70A9E5)

    var body: some View {
        if let tile = Self.paper.seamlessTile(ground: (ground.red, ground.green, ground.blue), strength: 0.8) {
            Image(decorative: tile, scale: 2)
                .resizable(resizingMode: .tile)
        } else {
            ground.themeColor
        }
    }
}

// MARK: Styles that screens ask for

/// A list or form on the theme's background.
struct ThemedScreen: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if let background = theme.background {
            content
                .scrollContentBackground(.hidden)
                .background {
                    Group {
                        if theme.grain { PaperBackground(ground: background) } else { background.themeColor }
                    }
                    .ignoresSafeArea()
                }
                .foregroundStyle(theme.ink?.themeColor ?? Color.primary)
        } else {
            content
        }
    }
}

/// A row or section on the theme's panel colour, with the theme's fine line under it, and a border round it where the theme has one.
struct ThemedRow: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if let panel = theme.panel {
            if theme.borderedPanels {
                content
                    .listRowBackground(
                        Rectangle()
                            .fill(panel.themeColor)
                            .overlay(alignment: .top) { Rectangle().fill(theme.line?.themeColor ?? .clear).frame(height: 0.5) }
                            .overlay(alignment: .bottom) { Rectangle().fill(theme.line?.themeColor ?? .clear).frame(height: 0.5) }
                    )
                    .listRowSeparatorTint(theme.line?.themeColor)
            } else {
                content.listRowBackground(panel.themeColor).listRowSeparatorTint(theme.line?.themeColor)
            }
        } else {
            content
        }
    }
}

/// A row of a plain list. The list's own selection highlight is kept, so no row background is set.
struct ThemedListRow: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if theme.panel != nil {
            content
                .listRowSeparatorTint(theme.line?.themeColor)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } else {
            content
        }
    }
}

/// How big a title is, which a theme turns into a font.
enum ThemedTitleStyle {
    case large, title, headline, body

    var size: Double {
        switch self {
        case .large: 34
        case .title: 22
        case .headline: 17
        case .body: 17
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .large: .largeTitle
        case .title: .title2
        case .headline: .headline
        case .body: .body
        }
    }

    var weight: Font.Weight {
        switch self {
        case .large, .title, .headline: .semibold
        case .body: .medium
        }
    }
}

/// A title in the theme's type.
struct ThemedTitle: ViewModifier {
    @Environment(\.appTheme) private var theme
    let style: ThemedTitleStyle

    func body(content: Content) -> some View {
        if let name = theme.titleFontName {
            content.font(.custom(name, size: style.size, relativeTo: style.textStyle))
        } else {
            content.font(.system(style.textStyle).weight(style.weight)).fontDesign(theme.titleDesign ?? theme.bodyDesign)
        }
    }
}

/// A fine rule with a small ornament in the middle, for under a title.
struct OrnamentalRule: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        if theme.ornaments {
            HStack(spacing: 8) {
                Rectangle().fill(theme.line?.themeColor ?? .secondary).frame(height: 0.75)
                Text("❦")
                    .font(.footnote)
                    .foregroundStyle(theme.accent?.themeColor ?? Color.secondary)
                Rectangle().fill(theme.line?.themeColor ?? .secondary).frame(height: 0.75)
            }
            .accessibilityHidden(true)
        }
    }
}

/// A label over a section: in small capitals and the quieter ink where the theme says so, with a rule beside it where it has flourishes.
struct ThemedLabel: View {
    @Environment(\.appTheme) private var theme
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }
    /// A heading from data, such as a rule system's attribute group.
    init(resource: LocalizedStringResource) { self.text = LocalizedStringKey(String(localized: resource)) }

    var body: some View {
        if theme.smallCapsLabels {
            HStack(spacing: 8) {
                // Headings are in the title face in ordinary title case, a step below the titles, so the serif marks every level above the body.
                Text(text)
                    .font(theme.titleFontName.map { .custom($0, size: 17, relativeTo: .headline) } ?? .footnote.weight(.semibold))
                    .textCase(nil)
                    .foregroundStyle(theme.ink?.themeColor ?? Color.primary)
                    // A little room before the first row under it.
                    .padding(.bottom, 6)
                if theme.labelRules {
                    Rectangle().fill(theme.line?.themeColor ?? .secondary).frame(height: 0.75).accessibilityHidden(true)
                }
            }
        } else {
            Text(text)
        }
    }
}

/// An icon, on a rounded square of the accent colour where the theme tints its icons, or ringed in ink where it has flourishes.
struct ThemedIcon: View {
    @Environment(\.appTheme) private var theme
    let systemName: String
    var size: Double = 28
    /// Leaves the colour to the system, which tints a sidebar's icons and turns them white on the chosen row.
    var inheritsColour = false

    var body: some View {
        if inheritsColour {
            Image(systemName: systemName)
                .accessibilityHidden(true)
        } else if theme.tintedIcons, let accent = theme.accent {
            Image(systemName: systemName)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(theme.panel?.themeColor ?? Color.white)
                .frame(width: size, height: size)
                .background(accent.themeColor, in: RoundedRectangle(cornerRadius: theme.cornerRadius * 0.6))
                .accessibilityHidden(true)
        } else if theme.ringedIcons {
            Image(systemName: systemName)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(theme.accent?.themeColor ?? Color.accentColor)
                .frame(width: size, height: size)
                .overlay { Circle().strokeBorder(theme.line?.themeColor ?? .secondary, lineWidth: 0.75) }
                .accessibilityHidden(true)
        } else {
            Image(systemName: systemName)
                .foregroundStyle(theme.accent?.themeColor ?? Color.primary)
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
        } else if theme.ornaments {
            SealIcon(systemName: systemName, size: size)
        } else {
            Image(systemName: systemName)
                .accessibilityHidden(true)
                .foregroundStyle(theme.accent?.themeColor ?? Color.secondary)
                .frame(width: size, height: size)
                .background(
                    theme.accent.map { $0.themeColor.opacity(0.14) } ?? Color.secondary.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: theme.cornerRadius * 0.7)
                )
                .overlay {
                    if theme.borderedPanels { RoundedRectangle(cornerRadius: theme.cornerRadius * 0.7).strokeBorder(theme.line?.themeColor ?? .clear, lineWidth: 0.75) }
                }
        }
    }
}

extension View {
    func themedScreen() -> some View { modifier(ThemedScreen()) }
    func themedRow() -> some View { modifier(ThemedRow()) }
    /// A row of a plain list: on the paper itself, with the theme's fine line between rows and no panel block behind it.
    func themedListRow() -> some View { modifier(ThemedListRow()) }
    func themedTitle(_ style: ThemedTitleStyle = .title) -> some View { modifier(ThemedTitle(style: style)) }
}

/// A navigation title in the theme's type and ink, in the middle of the bar, in place of the system's large title.
struct ThemedNavigationTitle: ViewModifier {
    @Environment(\.appTheme) private var theme
    let title: String

    func body(content: Content) -> some View {
        // On the Mac the window already shows the title in its bar, and a toolbar item there is put in a bubble of its own.
        #if os(iOS)
        if theme.titleDesign != nil || theme.ink != nil {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
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
        #else
        content.navigationTitle(title)
        #endif
    }
}

extension View {
    func themedNavigationTitle(_ title: String) -> some View { modifier(ThemedNavigationTitle(title: title)) }
}

/// Fine double lines in the corners of a banner or panel, like the frame of a map.
struct CornerFlourishes: View {
    let colour: Color
    let inset: Double
    var arm = 18.0

    var body: some View {
        Canvas { context, size in
            for (x, y, dx, dy) in [(inset, inset, 1.0, 1.0), (size.width - inset, inset, -1.0, 1.0), (inset, size.height - inset, 1.0, -1.0), (size.width - inset, size.height - inset, -1.0, -1.0)] {
                for offset in [0.0, 3.5] {
                    var path = Path()
                    path.move(to: CGPoint(x: x + dx * (arm + offset), y: y + dy * offset))
                    path.addLine(to: CGPoint(x: x + dx * offset, y: y + dy * offset))
                    path.addLine(to: CGPoint(x: x + dx * offset, y: y + dy * (arm + offset)))
                    context.stroke(path, with: .color(colour), lineWidth: offset == 0 ? 1.2 : 0.7)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The top of a world's home page: its picture with its name over it, or a panel with an emblem where it has no picture. Shown only by a
/// theme that has surfaces of its own; the Standard theme has none.
struct WorldBanner: View {
    @Environment(\.appTheme) private var theme
    let name: String
    let detail: String
    let imageData: Data?

    private var hasPicture: Bool { imageData != nil }
    private var titleColour: Color { hasPicture ? .white : (theme.ink?.themeColor ?? Color.primary) }

    var body: some View {
        if theme.background != nil {
            // The picture or panel is the background, so it fills the banner without making it any bigger.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .background {
                    if let imageData {
                        DataImage(data: imageData)
                            .overlay { LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom) }
                    } else {
                        (theme.panel?.themeColor ?? Color.secondary.opacity(0.1))
                            .overlay(alignment: .trailing) { emblem }
                    }
                }
                .overlay { if theme.ornaments { CornerFlourishes(colour: hasPicture ? .white.opacity(0.85) : (theme.accent?.themeColor ?? .secondary), inset: 8) } }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name.isEmpty ? String(localized: "Untitled World") : name)
                            .themedTitle(.large)
                            .foregroundStyle(titleColour)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(hasPicture ? Color.white.opacity(0.85) : (theme.accent?.themeColor ?? Color.secondary))
                        if theme.ornaments {
                            OrnamentalRule()
                                .environment(\.appTheme, hasPicture ? ornamentOverPicture : theme)
                                .frame(maxWidth: 260)
                        }
                    }
                    .padding(EdgeInsets(top: 16, leading: 22, bottom: 20, trailing: 22))
                }
                .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
                .overlay { RoundedRectangle(cornerRadius: theme.cornerRadius).strokeBorder(theme.line?.themeColor ?? .clear, lineWidth: 1) }
                .accessibilityElement(children: .combine)
        }
    }

    /// The theme with its lines and accent pale, for rules over a picture.
    private var ornamentOverPicture: AppTheme {
        var pale = theme
        pale.line = StyleColor(red: 1, green: 1, blue: 1, alpha: 0.6)
        pale.accent = StyleColor(red: 1, green: 1, blue: 1, alpha: 0.9)
        return pale
    }

    /// A world with no picture is marked by a seal where the theme has flourishes, and by a faint globe where it does not.
    @ViewBuilder
    private var emblem: some View {
        if theme.ornaments {
            ZStack {
                Image(systemName: "seal.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(theme.accent?.themeColor ?? Color.secondary)
                Image(systemName: "globe.europe.africa")
                    .resizable()
                    .scaledToFit()
                    .padding(26)
                    .foregroundStyle(theme.panel?.themeColor ?? Color.white)
            }
            .frame(width: 112, height: 112)
            .padding(.trailing, 24)
            .accessibilityHidden(true)
        } else {
            Image(systemName: "globe.europe.africa")
                .resizable()
                .scaledToFit()
                .padding(28)
                .foregroundStyle((theme.accent?.themeColor ?? Color.secondary).opacity(0.18))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}


// MARK: Flourishes

/// A wax seal with a symbol pressed into it: the mark of a page or a screen with nothing in it yet.
struct SealIcon: View {
    @Environment(\.appTheme) private var theme
    let systemName: String
    var size: Double = 36

    var body: some View {
        ZStack {
            Image(systemName: "seal.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(theme.accent?.themeColor ?? Color.secondary)
            Image(systemName: systemName)
                .resizable()
                .scaledToFit()
                .padding(size * 0.26)
                .foregroundStyle(theme.panel?.themeColor ?? Color.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The label of an empty screen: a seal where the theme has flourishes, and the system's own symbol where it has not.
struct ThemedEmptyLabel: View {
    @Environment(\.appTheme) private var theme
    private let title: Text
    let systemImage: String

    init(_ title: LocalizedStringResource, systemImage: String) {
        self.title = Text(title)
        self.systemImage = systemImage
    }

    var body: some View {
        if theme.ornaments {
            VStack(spacing: 10) {
                SealIcon(systemName: systemImage, size: 72)
                title
            }
        } else {
            Label { title } icon: { Image(systemName: systemImage) }
        }
    }
}

/// The mark at the end of a list or a page, like the end mark of a printed page.
struct EndMark: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        if theme.ornaments {
            HStack(spacing: 10) {
                Rectangle().fill(theme.line?.themeColor ?? .secondary).frame(height: 0.75)
                Text("❦")
                    .font(.body)
                    .foregroundStyle(theme.accent?.themeColor ?? Color.secondary)
                Rectangle().fill(theme.line?.themeColor ?? .secondary).frame(height: 0.75)
            }
            .frame(maxWidth: 220)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityHidden(true)
        }
    }
}

/// The end mark as the last row of a list or form.
struct EndMarkRow: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        if theme.ornaments {
            EndMark()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
}

/// A panel of a character sheet: the theme's panel colour with a fine border and corner marks where it has flourishes, or the system's
/// pale fill where it has none.
struct ThemedSheetPanel: ViewModifier {
    @Environment(\.appTheme) private var theme
    var corners = true

    func body(content: Content) -> some View {
        if let panel = theme.panel {
            content
                .background(panel.themeColor, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
                .overlay { RoundedRectangle(cornerRadius: theme.cornerRadius).strokeBorder(theme.line?.themeColor ?? .clear, lineWidth: 0.75) }
                .overlay {
                    if theme.ornaments && corners { CornerFlourishes(colour: (theme.accent?.themeColor ?? .secondary).opacity(0.7), inset: 4, arm: 9) }
                }
        } else {
            content.background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// The theme's paper behind a screen that is not a list or form, such as a character sheet.
struct ThemedBackground: ViewModifier {
    @Environment(\.appTheme) private var theme
    /// Whether text takes the theme's ink: for a sheet of facts, but not for an empty screen, whose prominent button must keep its own text.
    var inksText = false

    func body(content: Content) -> some View {
        if let background = theme.background {
            let painted = content.background {
                Group {
                    if theme.grain { PaperBackground(ground: background) } else { background.themeColor }
                }
                .ignoresSafeArea()
            }
            if inksText {
                painted.foregroundStyle(theme.ink?.themeColor ?? Color.primary)
            } else {
                painted
            }
        } else {
            content
        }
    }
}

extension View {
    /// A character sheet panel; small ones (a single figure) have no corner marks.
    func themedSheetPanel(corners: Bool = true) -> some View { modifier(ThemedSheetPanel(corners: corners)) }
    func themedBackground(inksText: Bool = false) -> some View { modifier(ThemedBackground(inksText: inksText)) }
}

/// A form or list section whose heading is in the theme's lettering. Without a theme, the system's heading.
struct ThemedSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    /// A heading that is already a string, such as one from a rule system's data.
    init<S: StringProtocol>(_ title: S, @ViewBuilder content: @escaping () -> Content) {
        self.title = LocalizedStringKey(String(title))
        self.content = content
    }

    var body: some View {
        Section {
            content()
        } header: {
            ThemedLabel(title)
        }
    }
}
