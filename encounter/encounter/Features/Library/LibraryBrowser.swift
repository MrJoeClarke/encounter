//
//  LibraryBrowser.swift
//  encounter
//

import SwiftUI
import SwiftData

/// The library's races or classes for the world's edition: the list beside the selected entry.
struct LibraryBrowser: View {
    let world: World
    let kind: LibraryKind

    @Environment(WorldNavigation.self) private var navigation

    var body: some View {
        #if os(macOS)
        HSplitView {
            list
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 420, maxHeight: .infinity)
                .layoutPriority(-1)
            detail
                .frame(minWidth: 360, idealWidth: 800, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        NavigationSplitView {
            list
        } detail: {
            detail
        }
        #endif
    }

    private var title: LocalizedStringResource {
        kind == .race ? world.edition.raceTermPlural : "Classes"
    }

    private var entries: [LibraryEntry] {
        Library.shared.topLevelEntries(kind, in: world.edition)
    }

    /// A subrace or subclass is opened from its parent's page, so the list highlights the parent.
    private var selection: Binding<String?> {
        Binding(
            get: {
                guard let key = navigation.selectedLibraryKey else { return nil }
                return Library.shared.entry(forKey: key)?.parent ?? key
            },
            set: { navigation.selectedLibraryKey = $0 }
        )
    }

    @ViewBuilder
    private var list: some View {
        let entries = entries
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Library Unavailable",
                    systemImage: "books.vertical",
                    description: Text("The \(String(localized: world.edition.title)) library has no entries of this kind.")
                )
            } else {
                List(selection: selection) {
                    ForEach(entries) { entry in
                        LibraryRow(entry: entry)
                            .tag(entry.key)
                    }
                }
            }
        }
        .navigationTitle(Text(title))
    }

    @ViewBuilder
    private var detail: some View {
        if let key = navigation.selectedLibraryKey, let entry = Library.shared.entry(forKey: key) {
            LibraryEntryView(entry: entry, world: world)
                .id(entry.key)
        } else {
            ContentUnavailableView("No Entry Selected", systemImage: "books.vertical")
        }
    }
}

/// A row in the library list, in the same style as the world's page lists: an icon and the name, with a line
/// of detail beneath.
private struct LibraryRow: View {
    let entry: LibraryEntry

    private let iconSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: (entry.kind.pageKind ?? .characterClass).systemImage)
                .foregroundStyle(.secondary)
                .frame(width: iconSize, height: iconSize)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// For a class, its hit die and primary ability; for a race or species, its size and speed.
    private var detail: String? {
        func text(_ key: String) -> String? {
            if case .text(let value)? = entry.attributes[key], !value.isEmpty { value } else { nil }
        }
        let parts: [String?]
        switch entry.kind {
        case .class: parts = [text("dnd5e.hitDie").map { String(localized: "Hit die \($0)") }, text("dnd5e.primaryAbility")]
        case .race, .subclass: parts = [text("core.raceSize"), text("dnd5e.speed")]
        }
        let joined = parts.compactMap { $0 }.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }
}
