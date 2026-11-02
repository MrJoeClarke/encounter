//
//  EditionTestSupport.swift
//  encounterTests
//

@testable import encounter

extension LibraryEdition {
    /// The D&D editions. Tests of D&D's content go through these, now that other systems have libraries too.
    static let dnd: [LibraryEdition] = [.srd51, .srd52]
}
