//
//  LibraryEntryView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// A library entry, read-only. Create Custom Version makes an editable copy in the world.
struct LibraryEntryView: View {
    let entry: LibraryEntry
    let world: World

    @Environment(\.modelContext) private var modelContext
    @Environment(WorldNavigation.self) private var navigation

    private struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(.title2.weight(.semibold))
                    Text(entry.kindTitle)
                        .foregroundStyle(.secondary)
                    if !entry.summary.isEmpty {
                        Text(entry.summary)
                            .padding(.top, 4)
                    }
                }
                .textSelection(.enabled)

                if let parentKey = entry.parent, let parent = Library.shared.entry(forKey: parentKey) {
                    Button {
                        navigation.openLibraryEntry(parent)
                    } label: {
                        Label("Part of \(parent.name)", systemImage: "arrow.up.left")
                    }
                }
            }

            let rows = attributeRows
            if !rows.isEmpty {
                Section("Details") {
                    ForEach(rows) { row in
                        LabeledContent(row.label) {
                            Text(row.value)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if !entry.entries.isEmpty {
                Section(entry.kind == .race ? "Traits" : "Features") {
                    ForEach(entry.entries.indices, id: \.self) { index in
                        EntryText(entry: entry.entries[index])
                    }
                }
            }

            let children = Library.shared.children(of: entry, in: LibraryEdition(key: entry.key) ?? world.edition)
            if !children.isEmpty {
                Section(entry.kind == .class ? "Subclasses" : "Subraces") {
                    ForEach(children) { child in
                        Button {
                            navigation.openLibraryEntry(child)
                        } label: {
                            Label(child.name, systemImage: "chevron.right")
                        }
                    }
                }
            }

            if entry.kind.pageKind != nil {
                Section {
                    Button("Create Custom Version", systemImage: "square.on.square", action: createCustomVersion)
                } footer: {
                    Text("Makes an editable copy in this world. The library entry itself never changes.")
                }
            }

            if let attribution {
                Section("Source") {
                    Text(attribution)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(entry.name)
    }

    private var attribution: String? {
        LibraryEdition(key: entry.key).flatMap { Library.shared.attribution(for: $0) }
    }

    /// The entry's plain attributes in the order the editor shows them, then any the editor has no label for.
    private var attributeRows: [Row] {
        let pageKind = entry.kind.pageKind ?? .characterClass
        let definitions = RuleSystems.definitions(for: pageKind, system: .dnd5e)
        var rows: [Row] = []
        var shown = Set<String>()

        for definition in definitions {
            guard let value = entry.attributes[definition.key], let text = displayText(for: value) else { continue }
            rows.append(Row(label: String(localized: definition.label), value: text))
            shown.insert(definition.key)
        }
        for (key, value) in entry.attributes.sorted(by: { $0.key < $1.key }) where !shown.contains(key) {
            if let text = displayText(for: value) {
                rows.append(Row(label: key, value: text))
            }
        }
        return rows
    }

    private func displayText(for value: AttributeValue) -> String? {
        switch value {
        case .text(let text): text.isEmpty ? nil : text
        case .number(let number): number.formatted()
        case .bool(let flag): flag ? String(localized: "Yes") : String(localized: "No")
        case .list(let items): items.isEmpty ? nil : items.joined(separator: ", ")
        case .entries: nil
        }
    }

    private func createCustomVersion() {
        if let page = Library.shared.makeCustomVersion(of: entry, in: world, context: modelContext) {
            navigation.open(page)
        }
    }
}

/// One trait or feature: its name, the level it's gained at if any, and its text.
private struct EntryText: View {
    let entry: EntryValue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.name)
                    .font(.headline)
                Spacer()
                if let level = entry.level {
                    Text("Level \(level)")
                        .foregroundStyle(.secondary)
                }
            }
            Text(entry.text)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}
