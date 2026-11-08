//
//  PageEditorView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Edits a page: header, character role, attributes, tags and notes.
/// A character can be looked at as its page, or as a sheet to play from.
enum PageEditorMode: String, CaseIterable, Identifiable {
    case page, sheet
    var id: String { rawValue }
}

struct PageEditorView: View {
    @Bindable var page: Page

    @State private var newTag = ""
    @FocusState private var titleIsFocused: Bool
    @State private var mode = PageEditorMode.page
    @State private var isConfirmingDelete = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The window's navigation, to carry the page-or-sheet choice into and out of a saved or new window. Absent in previews.
    @Environment(WorldNavigation.self) private var navigation: WorldNavigation?

    private var hasSheet: Bool { page.kind == .character && page.world?.rules.contains(.sheet) == true }

    var body: some View {
        VStack(spacing: 0) {
            if hasSheet {
                // Segments don't wrap, so at the largest text sizes a menu takes their place rather than running off the screen.
                Group {
                    if typeSize.isAccessibilitySize {
                        Picker("View", selection: $mode) {
                            Text("Page").tag(PageEditorMode.page)
                            Text("Sheet").tag(PageEditorMode.sheet)
                        }
                        .pickerStyle(.menu)
                    } else {
                        Picker("View", selection: $mode) {
                            Text("Page").tag(PageEditorMode.page)
                            Text("Sheet").tag(PageEditorMode.sheet)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                .padding([.horizontal, .top])
                .padding(.bottom, 8)
            }
            if hasSheet && mode == .sheet {
                if page.world.map({ RuleSystems.system(forKey: $0.systemRaw).usesGenericScreens }) == true {
                    GenericSheetView(page: page)
                } else {
                    CharacterSheetView(page: page)
                }
            } else {
                form
            }
        }
        // Deleting from the page itself, so it can be found without knowing to right-click a row in the list. The world's top place can't be deleted.
        .toolbar {
            if !page.isWorldRoot {
                ToolbarItem {
                    Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                        .help("Delete this page")
                }
            }
        }
        .alert("Delete Page?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive, action: deletePage)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(page.title.isEmpty ? String(localized: "Untitled") : page.title)” and its links will be deleted. This can’t be undone.")
        }
        // The Character menu switches between the page and the sheet.
        .focusedSceneValue(\.pageMode, hasSheet ? $mode : nil)
        .onAppear { if hasSheet, navigation?.showsSheet == true { mode = .sheet } }
        .onChange(of: mode) { navigation?.showsSheet = (mode == .sheet) }
    }

    private var form: some View {
        Form {
            Section {
                // A fine rule under the title, where the theme has flourishes, in the title's own row so the rows' lines don't double it.
                VStack(spacing: 6) {
                    TextField("Title", text: $page.title, prompt: Text("Untitled"))
                        .themedTitle(.title)
                        .focused($titleIsFocused)
                    OrnamentalRule()
                }
                .listRowSeparator(.hidden, edges: .bottom)
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

            if page.kind == .character, page.world?.rules.contains(.advancement) == true {
                if page.world.map({ RuleSystems.system(forKey: $0.systemRaw).usesGenericScreens }) == true {
                    GenericLevelUpSection(page: page)
                } else {
                    LevelUpSection(page: page)
                }
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
                    ThemedLabel(resource: group.heading)
                }
            }

            ImagesSection(owner: page)

            ThemedSection("Tags") {
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

            EndMarkRow()
        }
        .formStyle(.grouped)
        .themedScreen()
        .themedRow()
        .navigationTitle(page.title.isEmpty ? String(localized: "Untitled") : page.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if page.title.isEmpty { titleIsFocused = true }
        }
    }

    private func deletePage() {
        guard !page.isWorldRoot else { return }
        // Leave the page first so nothing is still showing a deleted page.
        navigation?.selectedPage = nil
        // Places inside a deleted place move up a level rather than being lost.
        page.liftChildrenToParent()
        modelContext.delete(page)
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
        let systemKey = page.world?.systemRaw ?? RuleSystemID.none.rawValue
        for definition in RuleSystems.definitions(for: page.kind, systemKey: systemKey) {
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

#if DEBUG
#Preview("Aria Vale, Parchment and Ink") { previewEditor(titled: "Aria Vale", height: 1200).inTheme(.parchment()) }
#Preview("Aria Vale, Parchment and Ink at night") { previewEditor(titled: "Aria Vale", height: 1200).inTheme(.parchment(night: true)).preferredColorScheme(.dark) }
#endif
