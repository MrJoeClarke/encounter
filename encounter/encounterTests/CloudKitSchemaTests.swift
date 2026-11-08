//
//  CloudKitSchemaTests.swift
//  encounterTests
//

import Testing
import SwiftData
@testable import encounter

/// The rules a SwiftData schema must keep to be mirrored by CloudKit: nothing unique, every attribute optional or with a default,
/// every relationship optional with an inverse, and no relationship that denies deletion.
struct CloudKitSchemaTests {
    private var entities: [Schema.Entity] { Schema(AppSchema.models).entities }

    @Test func everyModelIsInTheSchema() {
        #expect(entities.count == AppSchema.models.count)
    }

    @Test func noModelHasAUniqueConstraint() {
        for entity in entities {
            #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name)")
            for attribute in entity.attributes {
                #expect(!attribute.options.contains(.unique), "\(entity.name).\(attribute.name)")
            }
        }
    }

    @Test func everyAttributeIsOptionalOrHasADefault() {
        for entity in entities {
            for attribute in entity.attributes {
                #expect(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name).\(attribute.name)")
            }
        }
    }

    @Test func everyRelationshipIsOptionalHasAnInverseAndNeverDeniesDeletion() {
        for entity in entities {
            for relationship in entity.relationships {
                #expect(relationship.isOptional, "\(entity.name).\(relationship.name) is not optional")
                #expect(relationship.inverseName != nil, "\(entity.name).\(relationship.name) has no inverse")
                #expect(relationship.deleteRule != .deny, "\(entity.name).\(relationship.name) denies deletion")
            }
        }
    }
}
