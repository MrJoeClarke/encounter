//
//  LegacyNotesTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct LegacyNotesTests {
    @Test func notesAnOlderVersionStoredMoveToTheFormCloudKitCanHold() throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        let page = world.addPage(kind: .character, in: context)
        var notes = AttributedString("Met at the harbour, then ")
        var linked = AttributedString("Odric")
        linked.link = URL(string: "encounter://page/1")
        notes.append(linked)
        page.storedBody = notes
        #expect(page.bodyData == nil)
        #expect(String(page.body.characters) == "Met at the harbour, then Odric")

        Page.moveLegacyNotes(in: context)
        #expect(page.storedBody == nil)
        #expect(page.bodyData != nil)
        #expect(String(page.body.characters) == "Met at the harbour, then Odric")
        #expect(page.body.runs.contains { $0.link != nil })
    }

    @Test func notesWrittenNowAreStoredAsDataAndReadBack() throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        let page = world.addPage(kind: .place, in: context)
        #expect(String(page.body.characters).isEmpty)
        page.body = AttributedString("A quiet town.")
        try context.save()
        #expect(page.storedBody == nil)
        #expect(page.bodyData != nil)
        #expect(String(page.body.characters) == "A quiet town.")
    }
}
