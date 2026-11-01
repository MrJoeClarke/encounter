//
//  PageEditorView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Edits a page: header, character role, attributes, tags and notes.
struct PageEditorView: View {
    @Bindable var page: Page

    @State private var newTag = ""
    @FocusState private var titleIsFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $page.title, prompt: Text("Untitled"))
                    .font(.title2.weight(.semibold))
                    .focused($titleIsFocused)
                TextField("Summary", text: $page.summary, axis: .vertical)
                    .lineLimit(1...4)
                LabeledContent("Type") {
                    Label {
                        Text(page.kind.singularTitle)
                    } icon: {
                        Image(systemName: page.kind.systemImage)
                    }
                }
                if page.kind == .character {
                    Picker("Role", selection: roleBinding) {
                        ForEach(CharacterRole.allCases) { role in
                            Text(role.title).tag(role)
                        }
                    }
                }
            }

            if page.kind == .character {
                LevelUpSection(page: page)
            }

            if page.kind == .place {
                PlaceHierarchySection(page: page)
            }

            if page.kind == .event {
                EventSection(page: page)
            }

            if page.kind == .character {
                JourneySection(page: page)
            }

            ForEach(groupedDefinitions, id: \.title) { group in
                Section {
                    ForEach(group.definitions) { definition in
                        AttributeFieldView(definition: definition, page: page)
                    }
                } header: {
                    Text(group.heading)
                }
            }

            ImagesSection(owner: page)

            Section("Tags") {
                ForEach(page.tags, id: \.self) { tag in
                    Text(tag)
                }
                .onDelete { page.tags.remove(atOffsets: $0) }
                TextField("Add Tag", text: $newTag)
                    .onSubmit {
                        page.addTag(newTag)
                        newTag = ""
                    }
            }

            NotesSection(page: page)

            ReferencedBySection(page: page)
        }
        .formStyle(.grouped)
        .navigationTitle(page.title.isEmpty ? String(localized: "Untitled") : page.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if page.title.isEmpty { titleIsFocused = true }
        }
    }

    private var roleBinding: Binding<CharacterRole> {
        Binding(
            get: { page.characterRole ?? .nonPlayable },
            set: { page.characterRole = $0 }
        )
    }

    private struct DefinitionGroup {
        let title: String
        let heading: LocalizedStringResource
        let definitions: [AttributeDefinition]
    }

    /// Attributes for this page's kind under its world's rule system, sectioned by group heading in definition order.
    private var groupedDefinitions: [DefinitionGroup] {
        var groups: [DefinitionGroup] = []
        let system = page.world?.system ?? .none
        for definition in RuleSystems.definitions(for: page.kind, system: system) {
            let title = String(localized: definition.group)
            if let index = groups.firstIndex(where: { $0.title == title }) {
                groups[index] = DefinitionGroup(
                    title: title,
                    heading: definition.group,
                    definitions: groups[index].definitions + [definition]
                )
            } else {
                groups.append(DefinitionGroup(title: title, heading: definition.group, definitions: [definition]))
            }
        }
        return groups
    }
}

#Preview("Aria Vale") {
    previewEditor(titled: "Aria Vale", height: 1900)
}

#Preview("Elf (referenced by others)") {
    previewEditor(titled: "Elf", height: 1500)
}

@MainActor
private func previewEditor(titled title: String, height: CGFloat) -> some View {
    let container = SampleData.makePreviewContainer()
    let page = (try? container.mainContext.fetch(FetchDescriptor<Page>(sortBy: [SortDescriptor(\.title)])))?
        .first { $0.title == title }
    return NavigationStack {
        if let page {
            PageEditorView(page: page)
        }
    }
    .environment(WorldNavigation())
    .frame(width: 600, height: height)
    .modelContainer(container)
}
