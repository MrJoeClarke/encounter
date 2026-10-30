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

            ForEach(groupedDefinitions, id: \.title) { group in
                Section {
                    ForEach(group.definitions) { definition in
                        AttributeFieldView(definition: definition, page: page)
                    }
                } header: {
                    Text(group.heading)
                }
            }

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

            Section("Notes") {
                TextEditor(text: $page.body)
                    .frame(minHeight: 200)
            }
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

    /// Attributes for this page's kind, sectioned by their group heading in definition order.
    private var groupedDefinitions: [DefinitionGroup] {
        var groups: [DefinitionGroup] = []
        for definition in CoreAttributes.definitions(for: page.kind) {
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

#Preview {
    let container = SampleData.makePreviewContainer()
    let page = (try? container.mainContext.fetch(FetchDescriptor<Page>(sortBy: [SortDescriptor(\.title)])))?
        .first { $0.title == "Aria Vale" }
    return NavigationStack {
        if let page {
            PageEditorView(page: page)
        }
    }
    .modelContainer(container)
}
