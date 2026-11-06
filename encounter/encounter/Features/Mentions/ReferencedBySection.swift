//
//  ReferencedBySection.swift
//  encounter
//

import SwiftUI

/// Every page that points at this one: mentions in notes, and links such as a character's race or an
/// event's location. Choosing a row opens that page.
struct ReferencedBySection: View {
    let page: Page

    @Environment(WorldNavigation.self) private var navigation

    var body: some View {
        let backlinks = page.backlinks
        if !backlinks.isEmpty {
            ThemedSection("Referenced By") {
                ForEach(backlinks) { backlink in
                    Button {
                        navigation.open(backlink.source)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: backlink.source.kind.systemImage)
                                .accessibilityHidden(true)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Mention.displayTitle(of: backlink.source.title))
                                Text(LinkRole.incomingDescription(backlink.role))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
