//
//  NotesSection.swift
//  encounter
//

import SwiftUI
import SwiftData

/// A page's notes. Typing `@` suggests pages to mention, and each mention becomes a link to that page.
struct NotesSection: View {
    @Bindable var page: Page

    @Environment(\.modelContext) private var modelContext
    @Environment(WorldNavigation.self) private var navigation
    @State private var selection = AttributedTextSelection()
    @State private var isPickingMention = false
    /// The notes as last corrected by `Mention.normalize`, so that correction isn't corrected again when
    /// it comes back through `onChange`.
    @State private var correctedBody: AttributedString?

    var body: some View {
        Section("Notes") {
            TextEditor(text: $page.body, selection: $selection)
                .environment(\.openURL, openMention)
                .frame(minHeight: 200)

            if let query = activeQuery, let world = page.world {
                MentionResults(world: world, excluding: page.id, search: query.text, showsWhenEmpty: false) { choice in
                    insert(choice, replacing: query.range)
                }
            }

            Button("Mention…", systemImage: "at") { isPickingMention = true }

            let mentioned = page.mentionedPages
            let mentionedEntries = Mention.mentionedLibraryKeys(in: page.body).compactMap { Library.shared.entry(forKey: $0) }
            if !mentioned.isEmpty || !mentionedEntries.isEmpty {
                Text("Mentions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(mentioned) { target in
                    Button {
                        navigation.open(target)
                    } label: {
                        Label {
                            Text(Mention.displayTitle(of: target.title))
                        } icon: {
                            Image(systemName: target.kind.systemImage)
                        }
                    }
                    .buttonStyle(.plain)
                }
                ForEach(mentionedEntries) { entry in
                    Button {
                        navigation.openLibraryEntry(entry)
                    } label: {
                        Label {
                            Text(entry.name)
                        } icon: {
                            Image(systemName: entry.kind.systemImage)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onChange(of: page.body) { old, new in
            tidyMentions(from: old, to: new)
            // Keep the mention links in step with the text.
            MentionSync.sync(page, in: modelContext)
        }
        .environment(\.openURL, openMention)
        .sheet(isPresented: $isPickingMention) {
            if let world = page.world {
                MentionPickerSheet(world: world, pageID: page.id) { choice in
                    insert(choice, replacing: nil)
                }
            }
        }
    }

    private func insert(_ choice: MentionChoice, replacing range: Range<Int>?) {
        switch choice {
        case .page(let target):
            Mention.insertMention(of: target.id, title: target.title, replacing: range, in: &page.body, selection: &selection)
        case .library(let entry):
            Mention.insertMention(ofLibraryEntry: entry, replacing: range, in: &page.body, selection: &selection)
        }
    }

    // MARK: Mentions behaving as blocks

    /// After an edit, makes mentions behave as single blocks: deleting part of one deletes it all, and text
    /// typed against one doesn't become part of the link.
    private func tidyMentions(from old: AttributedString, to new: AttributedString) {
        if correctedBody == new {
            correctedBody = nil
            return
        }
        correctedBody = nil

        let result = Mention.normalize(old: old, new: new)
        guard result.body != new else { return }

        let caret = result.caret ?? caretOffset(in: new)
        correctedBody = result.body
        page.body = result.body
        selection = caretSelection(at: caret, in: result.body)
    }

    /// The cursor as a character offset, or the end of the text if there's no single cursor.
    private func caretOffset(in text: AttributedString) -> Int {
        let characters = text.characters
        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            return characters.distance(from: characters.startIndex, to: index)
        case .ranges(let ranges):
            guard let last = ranges.ranges.last else { return characters.count }
            return characters.distance(from: characters.startIndex, to: last.upperBound)
        @unknown default:
            return characters.count
        }
    }

    private func caretSelection(at offset: Int, in text: AttributedString) -> AttributedTextSelection {
        let characters = text.characters
        let clamped = min(max(offset, 0), characters.count)
        let index = characters.index(characters.startIndex, offsetBy: clamped)
        return AttributedTextSelection(insertionPoint: index)
    }

    // MARK: Following and suggesting mentions

    /// Opens the page a mention points at, instead of handing its URL to the system.
    private var openMention: OpenURLAction {
        OpenURLAction { url in
            if let key = Mention.libraryKey(from: url) {
                guard let entry = Library.shared.entry(forKey: key) else { return .discarded }
                navigation.openLibraryEntry(entry)
                return .handled
            }
            guard let id = Mention.pageID(from: url) else { return .systemAction }
            guard let target = page.world?.pages?.first(where: { $0.id == id }) else { return .discarded }
            navigation.open(target)
            return .handled
        }
    }

    /// The `@` being typed at the cursor, if any.
    private var activeQuery: Mention.Query? {
        guard case .insertionPoint(let index) = selection.indices(in: page.body) else { return nil }
        let characters = page.body.characters
        let offset = characters.distance(from: characters.startIndex, to: index)
        return Mention.activeQuery(in: String(characters), cursor: offset)
    }
}
