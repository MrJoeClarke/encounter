//
//  LibraryBrowser.swift
//  encounter
//

import SwiftUI
import SwiftData

/// An entry in the library list, with the subraces or subclasses that belong to it nested beneath.
private struct LibraryNode: Identifiable, Hashable {
    let entry: LibraryEntry
    let children: [LibraryNode]?

    var id: String { entry.key }
}

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

    private var nodes: [LibraryNode] {
        let library = Library.shared
        return library.topLevelEntries(kind, in: world.edition).map { entry in
            let children = library.children(of: entry, in: world.edition)
            return LibraryNode(
                entry: entry,
                children: children.isEmpty ? nil : children.map { LibraryNode(entry: $0, children: nil) }
            )
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { navigation.selectedLibraryKey },
            set: { navigation.selectedLibraryKey = $0 }
        )
    }

    @ViewBuilder
    private var list: some View {
        let nodes = nodes
        Group {
            if nodes.isEmpty {
                ContentUnavailableView(
                    "Library Unavailable",
                    systemImage: "books.vertical",
                    description: Text("The \(String(localized: world.edition.title)) library has no entries of this kind.")
                )
            } else {
                List(nodes, children: \.children, selection: selection) { node in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.entry.name)
                        if node.entry.parent != nil {
                            Text(node.entry.kind == .subclass ? "Subclass" : "Subrace")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
