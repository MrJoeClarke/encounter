//
//  AppCommands.swift
//  encounter
//

import SwiftUI

/// What the screen in front offers the menus. A screen puts these in the focus with `focusedSceneValue`, and the menu items
/// that need them are dimmed when there is none.
struct WorldActions {
    /// "New Character", or whatever kind the list showing would add.
    var newPageTitle: String
    var newPage: () -> Void
}

struct WorldListActions {
    var newWorld: () -> Void
    var importWorld: () -> Void
}

struct SheetActions {
    struct Rest: Identifiable {
        var name: String
        var take: () -> Void
        var id: String { name }
    }

    var rests: [Rest]
    /// Nil when the character can't level up.
    var levelUp: (() -> Void)?
}

extension FocusedValues {
    @Entry var worldNavigation: WorldNavigation?
    @Entry var worldActions: WorldActions?
    @Entry var worldListActions: WorldListActions?
    @Entry var sheetActions: SheetActions?
    @Entry var pageMode: Binding<PageEditorMode>?
}

/// The app's menus: making things, going places, and the character in front.
struct AppCommands: Commands {
    @FocusedValue(\.worldNavigation) private var navigation
    @FocusedValue(\.worldActions) private var world
    @FocusedValue(\.worldListActions) private var list
    @FocusedValue(\.sheetActions) private var sheet
    @FocusedBinding(\.pageMode) private var mode
    @AppStorage("appThemeID") private var themeID = AppTheme.defaultID

    /// The pages that have a shortcut of their own in the Go menu.
    static let shortcutKinds: [PageKind] = [.character, .place, .event, .item, .organisation]

    var body: some Commands {
        // The look of the app, to try them one after another.
        CommandGroup(after: .toolbar) {
            Picker("Theme", selection: $themeID) {
                ForEach(AppTheme.all) { Text($0.title).tag($0.id) }
            }
        }
        CommandGroup(replacing: .newItem) {
            Button(world?.newPageTitle ?? String(localized: "New Page")) { world?.newPage() }
                .keyboardShortcut("n")
                .disabled(world == nil)
            Divider()
            Button("New World…") { list?.newWorld() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(list == nil)
            Button("Import World…") { list?.importWorld() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(list == nil)
        }

        CommandMenu("Go") {
            Button("Back") { navigation?.goBack() }
                .keyboardShortcut("[")
                .disabled(navigation?.canGoBack != true)
            Button("Forward") { navigation?.goForward() }
                .keyboardShortcut("]")
                .disabled(navigation?.canGoForward != true)
            Divider()
            Button("Home") { navigation?.choose(.home) }.keyboardShortcut("1").disabled(navigation == nil)
            Button("World Map") { navigation?.choose(.worldMap) }.keyboardShortcut("2").disabled(navigation == nil)
            Button("Timeline") { navigation?.choose(.timeline) }.keyboardShortcut("3").disabled(navigation == nil)
            Button("Campaigns") { navigation?.choose(.campaigns) }.keyboardShortcut("4").disabled(navigation == nil)
            Divider()
            ForEach(Array(Self.shortcutKinds.enumerated()), id: \.element) { index, kind in
                Button { navigation?.choose(.kind(kind)) } label: { Text(kind.title) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 5)")))
                    .disabled(navigation == nil)
            }
        }

        CommandMenu("Character") {
            Button("Show Page") { mode = .page }
                .keyboardShortcut("1", modifiers: [.command, .option])
                .disabled(mode == nil)
            Button("Show Sheet") { mode = .sheet }
                .keyboardShortcut("2", modifiers: [.command, .option])
                .disabled(mode == nil)
            Divider()
            if let sheet, !sheet.rests.isEmpty {
                ForEach(sheet.rests) { rest in
                    Button(rest.name) { rest.take() }
                }
            } else {
                Button("Rest") {}.disabled(true)
            }
            Button("Level Up…") { sheet?.levelUp?() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(sheet?.levelUp == nil)
        }
    }
}
