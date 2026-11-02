//
//  LibraryBrowser.swift
//  encounter
//

import SwiftUI
import SwiftData

/// The library's races or classes for the world's edition: the list beside the selected entry.
struct LibraryBrowser: View {
    let world: World
    let list: LibraryList

    @Environment(WorldNavigation.self) private var navigation

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if showsSideBySide(sizeClass) {
            ListDetailSplit { listView } detail: { detail }
        } else {
            // The entry opens on top of the list, in the navigation stack the world is already in.
            listView
                .navigationDestination(item: openKey) { key in
                    if let entry = Library.shared.entry(forKey: key) {
                        LibraryEntryView(entry: entry, world: world)
                            .id(entry.key)
                            .environment(navigation)
                    }
                }
        }
    }

    private var title: LocalizedStringResource {
        Library.shared.title(of: list, in: world.edition)
    }

    private var entries: [LibraryEntry] {
        Library.shared.topLevelEntries(in: list, edition: world.edition)
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

    /// The entry that is open, which on iOS is the screen on top of the list. It is the entry itself, even a
    /// subrace, where `selection` names the parent that the list highlights.
    private var openKey: Binding<String?> {
        Binding(get: { navigation.selectedLibraryKey }, set: { navigation.selectedLibraryKey = $0 })
    }

    @ViewBuilder
    private var listView: some View {
        let entries = entries
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Library Unavailable",
                    systemImage: "books.vertical",
                    description: Text("The \(String(localized: world.edition.title)) library has no entries of this kind.")
                )
            } else {
                ChoosableList(choice: selection) {
                    ForEach(entries) { entry in
                        LibraryRow(entry: entry, system: RuleSystems.system(forKey: world.systemRaw))
                            .choosable(entry.key, in: selection)
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
    let system: any RuleSystem

    private let iconSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: Library.shared.systemImage(of: LibraryList(of: entry), in: LibraryEdition(key: entry.key) ?? .default))
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

    /// The line under the name, as the world's system gives it.
    private var detail: String? {
        let line = system.libraryDetail(for: entry)
        return line?.isEmpty == false ? line : nil
    }
}
