//
//  Page+Search.swift
//  encounter
//

import Foundation
import SwiftData

extension Page {
    /// Brings `bodyText` in step with `body`. Call it after changing the notes.
    func updateSearchText() {
        let text = String(body.characters)
        if bodyText != text { bodyText = text }
    }

    /// Moves notes an older version stored as rich text into the form CloudKit can hold. Cheap when there are none.
    static func moveLegacyNotes(in context: ModelContext) {
        let pages = (try? context.fetch(FetchDescriptor<Page>())) ?? []
        var changed = false
        for page in pages {
            guard let legacy = page.storedBody else { continue }
            page.body = legacy
            changed = true
        }
        if changed { try? context.save() }
    }

    /// Fills in the plain text of notes written before it was kept. Cheap when nothing needs doing.
    static func backfillSearchText(in context: ModelContext) {
        let pages = (try? context.fetch(FetchDescriptor<Page>())) ?? []
        var changed = false
        for page in pages where page.bodyText.isEmpty && !page.body.characters.isEmpty {
            page.updateSearchText()
            changed = true
        }
        if changed { try? context.save() }
    }
}
