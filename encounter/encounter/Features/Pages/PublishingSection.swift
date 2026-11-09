//
//  PublishingSection.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Whether players can see a page, and the actions that change it, with the DM's own notes beneath.
struct PublishingSection: View {
    @Bindable var page: Page
    @Environment(\.isPlayerPreview) private var isPlayerPreview

    var body: some View {
        if !isPlayerPreview {
        ThemedSection("Publishing") {
            if page.isWorldRoot {
                Label("Always shown to players", systemImage: "eye")
            } else {
                let state = page.publishState
                Label(String(localized: state.title), systemImage: state.systemImage)
                    .foregroundStyle(state == .publishedWithChanges ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                switch state {
                case .hidden:
                    Button("Publish", systemImage: "eye") { page.publish() }
                case .published:
                    Button("Unpublish", systemImage: "eye.slash") { page.unpublish() }
                case .publishedWithChanges:
                    Button("Publish Changes", systemImage: "eye") { page.publish() }
                    Button("Revert to Published", systemImage: "arrow.uturn.backward") { page.revertToPublished() }
                    Button("Unpublish", systemImage: "eye.slash") { page.unpublish() }
                }
            }
        }
        }
    }
}

/// The DM's own notes on a page, which are never published.
struct DMNotesSection: View {
    @Bindable var page: Page
    @Environment(\.isPlayerPreview) private var isPlayerPreview

    var body: some View {
        if !isPlayerPreview {
        Section {
            TextEditor(text: $page.dmNotes)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100)
        } header: {
            ThemedLabel("DM Notes")
        } footer: {
            Text("Players never see these, whether or not the page is published.")
        }
        }
    }
}

/// A small mark on a page's row for where it stands with players.
struct PublishMark: View {
    let page: Page
    @Environment(\.isPlayerPreview) private var isPlayerPreview

    var body: some View {
        if !page.isWorldRoot && !isPlayerPreview {
            let state = page.publishState
            Image(systemName: state.systemImage)
                .font(.footnote)
                .foregroundStyle(state == .publishedWithChanges ? Color.orange : Color.secondary)
                .accessibilityLabel(Text(state.title))
        }
    }
}
