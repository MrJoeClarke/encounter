//
//  LegacyNotesTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct NotesStorageTests {
    @Test func notesWrittenNowAreStoredAsDataAndReadBack() throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        let page = world.addPage(kind: .place, in: context)
        #expect(String(page.body.characters).isEmpty)
        page.body = AttributedString("A quiet town.")
        try context.save()
        #expect(page.bodyData != nil)
        #expect(String(page.body.characters) == "A quiet town.")
    }
}
