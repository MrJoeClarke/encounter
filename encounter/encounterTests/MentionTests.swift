//
//  MentionTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import encounter

@MainActor
struct MentionTests {
    // MARK: Helpers

    private func makeContext() throws -> ModelContext {
        ModelContext(try AppSchema.makeContainer(inMemory: true))
    }

    private func text(_ body: AttributedString) -> String {
        String(body.characters)
    }

    /// "<before>" + mention + "<after>"
    private func body(_ before: String, mention title: String, _ id: UUID, _ after: String = "") -> AttributedString {
        AttributedString(before) + Mention.mention(title: title, pageID: id) + AttributedString(after)
    }

    // MARK: Surviving storage

    @Test func mentionLinksSurviveSavingAndReloading() throws {
        let container = try AppSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let target = UUID()
        let page = Page(title: "A", kind: .character)
        context.insert(page)
        page.body = body("See ", mention: "Elf", target, " for details")
        try context.save()

        let loaded = try #require(try ModelContext(container).fetch(FetchDescriptor<Page>()).first)
        #expect(text(loaded.body) == "See Elf for details")
        #expect(Mention.mentionedIDs(in: loaded.body) == [target])
    }

    @Test func mentionLinksSurviveTheJSONCoderUsedForExport() throws {
        let target = UUID()
        let original = body("See ", mention: "Elf", target)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AttributedString.self, from: data)

        #expect(Mention.mentionedIDs(in: decoded) == [target])
        #expect(text(decoded) == "See Elf")
    }

    // MARK: URLs

    @Test func mentionURLsRoundTrip() {
        let id = UUID()
        let url = Mention.url(for: id)
        #expect(url.absoluteString == "encounter://page/\(id.uuidString)")
        #expect(Mention.pageID(from: url) == id)
    }

    @Test func otherURLsAreNotMentions() throws {
        let id = UUID().uuidString
        #expect(Mention.pageID(from: try #require(URL(string: "https://page/\(id)"))) == nil)
        #expect(Mention.pageID(from: try #require(URL(string: "encounter://world/\(id)"))) == nil)
        #expect(Mention.pageID(from: try #require(URL(string: "encounter://page/not-a-uuid"))) == nil)
        #expect(Mention.pageID(from: try #require(URL(string: "https://example.com"))) == nil)
    }

    @Test func mentionedIDsKeepFirstAppearanceOrderAndIgnoreRepeatsAndWebLinks() throws {
        let first = UUID()
        let second = UUID()
        var web = AttributedString("site")
        web.link = try #require(URL(string: "https://example.com"))
        let combined = Mention.mention(title: "B", pageID: second)
            + AttributedString(" and ") + Mention.mention(title: "A", pageID: first)
            + AttributedString(" then ") + Mention.mention(title: "B again", pageID: second)
            + AttributedString(" ") + web

        #expect(Mention.mentionedIDs(in: combined) == [second, first])
        #expect(Mention.mentionedIDs(in: AttributedString("no mentions")).isEmpty)
    }

    @Test func aMentionIsOneLinkedRunWithTheTitleAsItsText() {
        let id = UUID()
        let mention = Mention.mention(title: "Aria Vale", pageID: id)
        #expect(text(mention) == "Aria Vale")
        #expect(mention.runs.count == 1)
        #expect(mention.runs.first?.link == Mention.url(for: id))
        #expect(text(Mention.mention(title: "", pageID: id)) == "Untitled")
    }

    // MARK: Typing @

    @Test func anAtSignStartingTheTextOpensAQuery() {
        #expect(Mention.activeQuery(in: "@", cursor: 1) == Mention.Query(range: 0..<1, text: ""))
        #expect(Mention.activeQuery(in: "@eli", cursor: 4) == Mention.Query(range: 0..<4, text: "eli"))
    }

    @Test func anAtSignAfterWhitespaceOrABracketOpensAQuery() {
        #expect(Mention.activeQuery(in: "Hello @eli", cursor: 10) == Mention.Query(range: 6..<10, text: "eli"))
        #expect(Mention.activeQuery(in: "Line one\n@x", cursor: 11) == Mention.Query(range: 9..<11, text: "x"))
        #expect(Mention.activeQuery(in: "(@x", cursor: 3) == Mention.Query(range: 1..<3, text: "x"))
    }

    @Test func emailAddressesDoNotOpenAQuery() {
        #expect(Mention.activeQuery(in: "mail me@example", cursor: 15) == nil)
        #expect(Mention.activeQuery(in: "a@b", cursor: 3) == nil)
    }

    @Test func queriesMayContainSpacesButNotLineBreaks() {
        #expect(Mention.activeQuery(in: "@Aria V", cursor: 7) == Mention.Query(range: 0..<7, text: "Aria V"))
        #expect(Mention.activeQuery(in: "@Aria\nV", cursor: 7) == nil)
        #expect(Mention.activeQuery(in: "@ later", cursor: 7) == nil)
    }

    @Test func theCursorHasToBeAfterTheAtSign() {
        #expect(Mention.activeQuery(in: "hi @eli", cursor: 2) == nil)
        #expect(Mention.activeQuery(in: "hi @eli", cursor: 4) == Mention.Query(range: 3..<4, text: ""))
        #expect(Mention.activeQuery(in: "hi @eli", cursor: 99) == nil)
        #expect(Mention.activeQuery(in: "plain text", cursor: 10) == nil)
    }

    @Test func aFarAwayAtSignIsIgnored() {
        let long = "@" + String(repeating: "x", count: 60)
        #expect(Mention.activeQuery(in: long, cursor: long.count) == nil)
        #expect(Mention.activeQuery(in: "@" + String(repeating: "x", count: 10), cursor: 11) != nil)
    }

    @Test func theNearestAtSignWins() {
        let result = Mention.activeQuery(in: "@one and @tw", cursor: 12)
        #expect(result == Mention.Query(range: 9..<12, text: "tw"))
    }

    // MARK: Inserting

    @Test func insertingReplacesTheTypedQueryWithAMentionAndASpace() {
        let id = UUID()
        var body = AttributedString("Met @El")
        var selection = AttributedTextSelection()

        Mention.insertMention(of: id, title: "Elf", replacing: 4..<7, in: &body, selection: &selection)

        #expect(text(body) == "Met Elf ")
        #expect(Mention.mentionedIDs(in: body) == [id])
        // Only the title is linked. The trailing space isn't, so typing on doesn't extend the mention.
        let linked = body.runs.filter { $0.link != nil }.map { String(body[$0.range].characters) }
        #expect(linked == ["Elf"])
        // The caret is after the space, with nothing selected, so the next key doesn't replace the mention.
        #expect(caretOffset(of: selection, in: body) == 8)
    }

    /// The offset of the caret, or nil if the selection isn't a bare caret.
    private func caretOffset(of selection: AttributedTextSelection, in body: AttributedString) -> Int? {
        guard case .insertionPoint(let caret) = selection.indices(in: body) else { return nil }
        return body.characters.distance(from: body.startIndex, to: caret)
    }

    @Test func insertingKeepsTextAfterTheQuery() {
        let id = UUID()
        var body = AttributedString("Hi @El there")
        var selection = AttributedTextSelection()

        Mention.insertMention(of: id, title: "Elf", replacing: 3..<6, in: &body, selection: &selection)

        #expect(text(body) == "Hi Elf  there")
    }

    @Test func insertingWithNoRangeUsesTheCursor() {
        let id = UUID()
        var body = AttributedString("AB")
        let middle = body.characters.index(body.startIndex, offsetBy: 1)
        var selection = AttributedTextSelection(insertionPoint: middle)

        Mention.insertMention(of: id, title: "X", replacing: nil, in: &body, selection: &selection)

        #expect(text(body) == "AX B")
        #expect(Mention.mentionedIDs(in: body) == [id])
        #expect(caretOffset(of: selection, in: body) == 3)
    }

    @Test func insertingOverASelectedRangeReplacesItAndPutsTheCursorAfter() {
        let id = UUID()
        var body = AttributedString("one two three")
        let characters = body.characters
        let lower = characters.index(characters.startIndex, offsetBy: 4)
        let upper = characters.index(characters.startIndex, offsetBy: 7)
        var selection = AttributedTextSelection(range: lower..<upper)

        Mention.insertMention(of: id, title: "Two", replacing: nil, in: &body, selection: &selection)

        #expect(text(body) == "one Two  three")
        #expect(caretOffset(of: selection, in: body) == 8)
    }

    @Test func insertingKeepsTheCursorAfterTheMentionWhenTextFollows() {
        var body = AttributedString("Hi @El there")
        var selection = AttributedTextSelection()

        Mention.insertMention(of: UUID(), title: "Elf", replacing: 3..<6, in: &body, selection: &selection)

        #expect(caretOffset(of: selection, in: body) == 7)
    }

    @Test func insertingWithAnOutOfRangeQueryDoesNothing() {
        var body = AttributedString("short")
        var selection = AttributedTextSelection()
        Mention.insertMention(of: UUID(), title: "X", replacing: 10..<20, in: &body, selection: &selection)
        #expect(text(body) == "short")
    }

    // MARK: Mentions as blocks

    /// Edits `before` into `after` the way the text editor would, and normalises.
    private func normalized(_ before: AttributedString, _ after: AttributedString) -> Mention.Normalization {
        Mention.normalize(old: before, new: after)
    }

    private func linkedText(in body: AttributedString) -> [String] {
        body.runs.filter { $0.link != nil }.map { String(body[$0.range].characters) }
    }

    @Test func textTypedAfterAMentionLosesTheLinkAndTheMentionIsIntact() {
        let id = UUID()
        let before = body("See ", mention: "Aria Vale", id)
        // The editor extends the link run with whatever is typed against it.
        let typed = body("See ", mention: "Aria Valexyz", id)

        let result = normalized(before, typed)

        #expect(text(result.body) == "See Aria Valexyz")
        #expect(linkedText(in: result.body) == ["Aria Vale"])
        #expect(result.caret == nil)
    }

    @Test func textTypedBeforeAMentionLosesTheLinkToo() {
        let id = UUID()
        let before = body("See ", mention: "Aria Vale", id)
        let typed = AttributedString("See ") + Mention.mention(title: "xyzAria Vale", pageID: id)

        let result = normalized(before, typed)

        #expect(text(result.body) == "See xyzAria Vale")
        #expect(linkedText(in: result.body) == ["Aria Vale"])
    }

    @Test func deletingTheLastLetterOfAMentionDeletesTheWholeMention() {
        let id = UUID()
        let before = body("See ", mention: "Aria Vale", id, " today")
        let afterBackspace = body("See ", mention: "Aria Val", id, " today")

        let result = normalized(before, afterBackspace)

        #expect(text(result.body) == "See  today")
        #expect(Mention.mentionedIDs(in: result.body).isEmpty)
        #expect(result.caret == 4)
    }

    @Test func deletingTheFirstOrAMiddleLetterDeletesTheWholeMention() {
        let id = UUID()
        let before = body("a ", mention: "Aria Vale", id, " b")

        let firstLetterGone = normalized(before, body("a ", mention: "ria Vale", id, " b"))
        #expect(text(firstLetterGone.body) == "a  b")
        #expect(firstLetterGone.caret == 2)

        let middleLetterGone = normalized(before, body("a ", mention: "Aria ale", id, " b"))
        #expect(text(middleLetterGone.body) == "a  b")
        #expect(Mention.mentionedIDs(in: middleLetterGone.body).isEmpty)
    }

    @Test func deletingTheWholeMentionAtOnceIsLeftAlone() {
        let id = UUID()
        let before = body("a ", mention: "Aria Vale", id, " b")

        let result = normalized(before, AttributedString("a  b"))

        #expect(text(result.body) == "a  b")
        #expect(result.caret == nil)
    }

    @Test func typingInsideAMentionTurnsItIntoPlainTextKeepingWhatWasTyped() {
        let id = UUID()
        let before = body("a ", mention: "Aria Vale", id, " b")
        let inserted = body("a ", mention: "Aria XVale", id, " b")

        let result = normalized(before, inserted)

        #expect(text(result.body) == "a Aria XVale b")
        #expect(Mention.mentionedIDs(in: result.body).isEmpty)
    }

    @Test func aMentionFormattedInSeveralRunsIsOneBlock() {
        let id = UUID()
        var first = Mention.mention(title: "Aria ", pageID: id)
        first.inlinePresentationIntent = nil
        var second = Mention.mention(title: "Vale", pageID: id)
        second.inlinePresentationIntent = .stronglyEmphasized
        let before = AttributedString("x ") + first + second + AttributedString(" y")

        // Deleting a letter from the bold part removes the whole mention, not just the bold part.
        var shorter = Mention.mention(title: "Val", pageID: id)
        shorter.inlinePresentationIntent = .stronglyEmphasized
        let afterBackspace = AttributedString("x ") + first + shorter + AttributedString(" y")

        let result = normalized(before, afterBackspace)

        #expect(text(result.body) == "x  y")
        #expect(result.caret == 2)

        // Unchanged, it's left alone.
        #expect(normalized(before, before).body == before)
    }

    @Test func onlyTheDamagedMentionChangesWhenThereAreSeveral() {
        let one = UUID()
        let two = UUID()
        let before = body("", mention: "Elf", one, " and ") + Mention.mention(title: "Brackwater", pageID: two)
        let after = body("", mention: "Elf", one, " and ") + Mention.mention(title: "Brackwate", pageID: two)

        let result = normalized(before, after)

        #expect(text(result.body) == "Elf and ")
        #expect(Mention.mentionedIDs(in: result.body) == [one])
    }

    @Test func aNewMentionAndUnchangedTextAreLeftAlone() {
        let id = UUID()
        let before = AttributedString("Hello ")
        let after = body("Hello ", mention: "Elf", id, " ")

        #expect(normalized(before, after).body == after)
        #expect(normalized(after, after).body == after)
    }

    @Test func aMentionWhoseTextAlreadyDiffersFromItsTitleIsNotTouchedByUnrelatedEdits() {
        // A mention whose text went stale. Typing elsewhere in the notes mustn't delete it.
        let id = UUID()
        let before = body("Old ", mention: "Stale name", id, " text")
        let after = body("Old ", mention: "Stale name", id, " text, more")

        #expect(normalized(before, after).body == after)
    }

    @Test func correctingTwiceChangesNothingMore() {
        let id = UUID()
        let before = body("See ", mention: "Aria Vale", id)
        let typed = body("See ", mention: "Aria Valex", id)

        let once = normalized(before, typed).body

        #expect(normalized(once, once).body == once)
        #expect(normalized(before, once).body == once)
    }

    // MARK: Refreshing, stripping and remapping

    @Test func refreshingUpdatesMentionTextAndLeavesOtherTextAlone() {
        let id = UUID()
        let other = UUID()
        var notes = body("Met ", mention: "Old Name", id, " and ") + Mention.mention(title: "Bystander", pageID: other)

        Mention.refreshTitles(in: &notes, titles: [id: "New Name"])

        #expect(text(notes) == "Met New Name and Bystander")
        #expect(Mention.mentionedIDs(in: notes) == [id, other])
    }

    @Test func refreshingKeepsTheMentionsFormatting() {
        let id = UUID()
        var mention = Mention.mention(title: "Old", pageID: id)
        mention.inlinePresentationIntent = .stronglyEmphasized
        var notes = AttributedString("x ") + mention

        Mention.refreshTitles(in: &notes, titles: [id: "Newer"])

        #expect(text(notes) == "x Newer")
        let run = notes.runs.first { $0.link != nil }
        #expect(run?.inlinePresentationIntent == .stronglyEmphasized)
        #expect(run?.link == Mention.url(for: id))
    }

    @Test func aMentionSplitIntoFormattedRunsIsRefreshedOnceNotDuplicated() {
        let id = UUID()
        var first = Mention.mention(title: "Aria ", pageID: id)
        first.inlinePresentationIntent = nil
        var second = Mention.mention(title: "Vale", pageID: id)
        second.inlinePresentationIntent = .stronglyEmphasized
        var notes = first + second + AttributedString("!")

        Mention.refreshTitles(in: &notes, titles: [id: "Aria V"])

        #expect(text(notes) == "Aria V!")
    }

    @Test func refreshingWithAnUnchangedTitleChangesNothing() {
        let id = UUID()
        let original = body("a ", mention: "Same", id, " b")
        var notes = original
        Mention.refreshTitles(in: &notes, titles: [id: "Same"])
        #expect(notes == original)
    }

    @Test func refreshingLeavesOrdinaryLinksAlone() throws {
        var web = AttributedString("site")
        web.link = try #require(URL(string: "https://example.com"))
        var notes = web
        Mention.refreshTitles(in: &notes, titles: [UUID(): "Nope"])
        #expect(text(notes) == "site")
        #expect(notes.runs.first?.link == URL(string: "https://example.com"))
    }

    @Test func strippingTurnsMentionsIntoPlainText() {
        let gone = UUID()
        let kept = UUID()
        var notes = body("a ", mention: "Gone", gone, " b ") + Mention.mention(title: "Kept", pageID: kept)

        Mention.stripMentions(of: [gone], from: &notes)

        #expect(text(notes) == "a Gone b Kept")
        #expect(Mention.mentionedIDs(in: notes) == [kept])
    }

    @Test func remappingPointsMentionsAtNewIDsAndStripsUnknownOnes() throws {
        let old = UUID()
        let new = UUID()
        let unknown = UUID()
        var web = AttributedString(" site")
        web.link = try #require(URL(string: "https://example.com"))
        var notes = Mention.mention(title: "A", pageID: old) + AttributedString(" ")
            + Mention.mention(title: "B", pageID: unknown) + web

        Mention.remapMentions(in: &notes, using: [old: new])

        #expect(Mention.mentionedIDs(in: notes) == [new])
        #expect(text(notes) == "A B site")
    }

    // MARK: Keeping PageLinks in step

    private func makeWorld(_ context: ModelContext) -> (world: World, a: Page, b: Page, c: Page) {
        let world = World(name: "W")
        context.insert(world)
        let a = world.addPage(kind: .character, in: context)
        a.title = "Aria"
        let b = world.addPage(kind: .place, in: context)
        b.title = "Brackwater"
        let c = world.addPage(kind: .item, in: context)
        c.title = "Lantern"
        return (world, a, b, c)
    }

    private func mentionLinks(of page: Page) -> [PageLink] {
        (page.outgoingLinks ?? []).filter { $0.role == LinkRole.mention && !$0.isDeleted }
    }

    @Test func syncCreatesOneLinkPerMentionedPage() throws {
        let context = try makeContext()
        let (_, a, b, c) = makeWorld(context)
        a.body = body("At ", mention: "Brackwater", b.id, " with ") + Mention.mention(title: "Lantern", pageID: c.id)
            + AttributedString(" and ") + Mention.mention(title: "Brackwater", pageID: b.id)

        MentionSync.sync(a, in: context)

        let targets = Set(mentionLinks(of: a).compactMap { $0.target?.id })
        #expect(targets == [b.id, c.id])
        #expect(mentionLinks(of: a).count == 2)
        #expect(a.mentionedPages.map(\.title) == ["Brackwater", "Lantern"])
    }

    @Test func syncIsIdempotent() throws {
        let context = try makeContext()
        let (_, a, b, _) = makeWorld(context)
        a.body = body("", mention: "Brackwater", b.id)

        MentionSync.sync(a, in: context)
        MentionSync.sync(a, in: context)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<PageLink>()) == 1)
    }

    @Test func syncRemovesLinksWhenTheMentionIsDeleted() throws {
        let context = try makeContext()
        let (_, a, b, c) = makeWorld(context)
        a.body = body("", mention: "Brackwater", b.id) + AttributedString(" ") + Mention.mention(title: "Lantern", pageID: c.id)
        MentionSync.sync(a, in: context)

        a.body = body("", mention: "Lantern", c.id)
        MentionSync.sync(a, in: context)
        try context.save()

        #expect(mentionLinks(of: a).compactMap { $0.target?.id } == [c.id])
        #expect(try context.fetchCount(FetchDescriptor<PageLink>()) == 1)

        a.body = AttributedString("nothing left")
        MentionSync.sync(a, in: context)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<PageLink>()) == 0)
    }

    @Test func syncLeavesOtherLinkRolesAlone() throws {
        let context = try makeContext()
        let (_, a, b, c) = makeWorld(context)
        a.setLinkedPage(c, role: LinkRole.race, in: context)
        a.body = body("", mention: "Brackwater", b.id)

        MentionSync.sync(a, in: context)
        a.body = AttributedString("cleared")
        MentionSync.sync(a, in: context)
        try context.save()

        #expect(a.linkedPage(role: LinkRole.race) === c)
        #expect(mentionLinks(of: a).isEmpty)
    }

    @Test func syncIgnoresSelfMentionsAndPagesOutsideTheWorld() throws {
        let context = try makeContext()
        let (_, a, _, _) = makeWorld(context)
        let otherWorld = World(name: "Elsewhere")
        context.insert(otherWorld)
        let stranger = otherWorld.addPage(kind: .character, in: context)
        a.body = body("", mention: "Me", a.id) + AttributedString(" ") + Mention.mention(title: "Stranger", pageID: stranger.id)
            + AttributedString(" ") + Mention.mention(title: "Ghost", pageID: UUID())

        MentionSync.sync(a, in: context)

        #expect(mentionLinks(of: a).isEmpty)
    }

    // MARK: Renaming and deleting

    @Test func renamingAPageUpdatesMentionsOfItInOtherPages() throws {
        let context = try makeContext()
        let (_, a, b, c) = makeWorld(context)
        a.body = AttributedString("Went to ") + Mention.mention(title: "Brackwater", pageID: b.id) + AttributedString(".")
        c.body = body("Also ", mention: "Brackwater", b.id)
        MentionSync.sync(a, in: context)
        MentionSync.sync(c, in: context)

        b.title = "New Brackwater"
        MentionSync.refreshMentions(of: b)

        #expect(text(a.body) == "Went to New Brackwater.")
        #expect(text(c.body) == "Also New Brackwater")
        #expect(Mention.mentionedIDs(in: a.body) == [b.id])
    }

    @Test func aBlankTitleDoesNotWipeMentions() throws {
        let context = try makeContext()
        let (_, a, b, _) = makeWorld(context)
        a.body = body("", mention: "Brackwater", b.id)
        MentionSync.sync(a, in: context)

        b.title = ""
        MentionSync.refreshMentions(of: b)

        #expect(text(a.body) == "Brackwater")
    }

    @Test func deletingAPageTurnsMentionsOfItIntoPlainTextAndRemovesItsLinks() throws {
        let context = try makeContext()
        let (_, a, b, c) = makeWorld(context)
        a.body = body("At ", mention: "Brackwater", b.id) + AttributedString(" with ") + Mention.mention(title: "Lantern", pageID: c.id)
        MentionSync.sync(a, in: context)
        try context.save()

        MentionSync.delete(b, in: context)
        try context.save()

        #expect(text(a.body) == "At Brackwater with Lantern")
        #expect(Mention.mentionedIDs(in: a.body) == [c.id])
        #expect(try context.fetchCount(FetchDescriptor<Page>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<PageLink>()) == 1)
        #expect(a.mentionedPages.map(\.title) == ["Lantern"])
    }

    @Test func deletingAPageThatIsMentionedNowhereJustDeletesIt() throws {
        let context = try makeContext()
        let (_, _, b, _) = makeWorld(context)
        MentionSync.delete(b, in: context)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Page>()) == 2)
    }

    // MARK: Backlinks

    @Test func backlinksIncludeMentionsAndStructuredLinksSortedByTitle() throws {
        let context = try makeContext()
        let (world, a, b, _) = makeWorld(context)
        let elf = world.addPage(kind: .race, in: context)
        elf.title = "Elf"
        let event = world.addPage(kind: .event, in: context)
        event.title = "Ambush"
        a.setLinkedPage(elf, role: LinkRole.race, in: context)
        event.setLinkedPage(elf, role: LinkRole.location, in: context)
        b.body = body("Home of ", mention: "Elf", elf.id)
        MentionSync.sync(b, in: context)

        let rows = elf.backlinks.map { ($0.source.title, $0.role) }

        #expect(rows.count == 3)
        #expect(rows.map(\.0) == ["Ambush", "Aria", "Brackwater"])
        #expect(Set(rows.map(\.1)) == [LinkRole.location, LinkRole.race, LinkRole.mention])
    }

    @Test func backlinksAreEmptyForAPageNothingPointsAt() throws {
        let context = try makeContext()
        let (_, a, _, _) = makeWorld(context)
        #expect(a.backlinks.isEmpty)
    }

    @Test func everyKnownRoleHasADescription() {
        for role in [LinkRole.mention, LinkRole.race, LinkRole.participant, LinkRole.location, LinkRole.home, LinkRole.member] {
            #expect(!String(localized: LinkRole.incomingDescription(role)).isEmpty)
        }
        #expect(String(localized: LinkRole.incomingDescription("something else")) == "Linked")
    }

    // MARK: Navigation

    @Test func openingAPageSwitchesTheSidebarToItsKindAndSelectsIt() throws {
        let context = try makeContext()
        let (_, a, b, _) = makeWorld(context)
        let navigation = WorldNavigation()

        navigation.open(a)
        #expect(navigation.selection == .kind(.character))
        #expect(navigation.selectedPage === a)

        navigation.open(b)
        #expect(navigation.selection == .kind(.place))
        #expect(navigation.selectedPage === b)
    }

    @Test func choosingASidebarItemClearsTheOpenPageOnlyWhenItChanges() throws {
        let context = try makeContext()
        let (_, a, _, _) = makeWorld(context)
        let navigation = WorldNavigation()
        navigation.open(a)

        navigation.choose(.kind(.character))
        #expect(navigation.selectedPage === a)

        navigation.choose(.kind(.place))
        #expect(navigation.selectedPage == nil)
        #expect(navigation.selection == .kind(.place))

        navigation.choose(.home)
        #expect(navigation.selection == .home)
    }

    // MARK: Links arriving from the system

    @Test func theBuiltAppRegistersTheEncounterURLScheme() throws {
        // Without this, macOS shows "no application set to open the URL" when a mention is clicked.
        let app = try #require(Bundle(identifier: "com.infography.encounter"))
        let urlTypes = try #require(app.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(Mention.scheme))
    }

    @Test func aMentionURLOpensThePageInTheOpenWorld() throws {
        let context = try makeContext()
        let (world, _, b, _) = makeWorld(context)
        let navigation = WorldNavigation()
        let router = LinkRouter()
        router.activate(world: world, navigation: navigation)

        let handled = router.open(Mention.url(for: b.id))

        #expect(handled)
        #expect(navigation.selectedPage === b)
        #expect(navigation.selection == .kind(.place))
    }

    @Test func urlsThatCantBeOpenedAreReportedAsNotHandled() throws {
        let context = try makeContext()
        let (world, _, _, _) = makeWorld(context)
        let navigation = WorldNavigation()
        let router = LinkRouter()
        router.activate(world: world, navigation: navigation)

        #expect(!router.open(Mention.url(for: UUID())))
        #expect(!router.open(try #require(URL(string: "https://example.com"))))
        #expect(navigation.selectedPage == nil)
        #expect(navigation.selection == .home)
    }

    @Test func aLinkToAPageInAnotherWorldIsNotOpened() throws {
        let context = try makeContext()
        let (world, _, _, _) = makeWorld(context)
        let other = World(name: "Elsewhere")
        context.insert(other)
        let stranger = other.addPage(kind: .character, in: context)
        let navigation = WorldNavigation()
        let router = LinkRouter()
        router.activate(world: world, navigation: navigation)

        #expect(!router.open(Mention.url(for: stranger.id)))
        #expect(navigation.selectedPage == nil)
    }

    @Test func withNoWorldOpenALinkIsNotHandled() throws {
        let context = try makeContext()
        let (_, a, _, _) = makeWorld(context)
        let router = LinkRouter()

        #expect(!router.open(Mention.url(for: a.id)))
    }

    @Test func aWorldThatDisappearsStopsReceivingLinks() throws {
        let context = try makeContext()
        let (world, a, _, _) = makeWorld(context)
        let navigation = WorldNavigation()
        let router = LinkRouter()
        router.activate(world: world, navigation: navigation)

        router.deactivate(navigation: navigation)

        #expect(!router.open(Mention.url(for: a.id)))
    }

    @Test func aStaleWindowDisappearingDoesNotDeactivateTheNewerOne() throws {
        let context = try makeContext()
        let (world, a, _, _) = makeWorld(context)
        let older = WorldNavigation()
        let newer = WorldNavigation()
        let router = LinkRouter()
        router.activate(world: world, navigation: older)
        router.activate(world: world, navigation: newer)

        router.deactivate(navigation: older)

        #expect(router.open(Mention.url(for: a.id)))
        #expect(newer.selectedPage === a)
        #expect(older.selectedPage == nil)
    }

    // MARK: Export and import

    @Test func mentionsSurviveExportAndImportPointingAtTheNewPages() async throws {
        let source = try makeContext()
        let (world, a, b, c) = makeWorld(source)
        a.body = AttributedString("Born in ") + Mention.mention(title: "Brackwater", pageID: b.id)
            + AttributedString(", carries the ") + Mention.mention(title: "Lantern", pageID: c.id)
        MentionSync.sync(a, in: source)
        try source.save()

        let exported = WorldExporter.makeContents(of: world)
        // Mention links are rebuilt from the text, so they aren't stored.
        #expect(!exported.archive.links.contains { $0.role == LinkRole.mention })

        let wrapper = try WorldPackage.fileWrapper(for: exported)
        let reread = try WorldPackage.contents(of: wrapper)
        let target = try makeContext()
        let (imported, summary) = await WorldImporter.importWorld(reread, into: target)

        let pages = Dictionary(uniqueKeysWithValues: (imported.pages ?? []).map { ($0.title, $0) })
        let aria = try #require(pages["Aria"])
        let newBrackwater = try #require(pages["Brackwater"])
        let newLantern = try #require(pages["Lantern"])
        #expect(text(aria.body) == "Born in Brackwater, carries the Lantern")
        #expect(Mention.mentionedIDs(in: aria.body) == [newBrackwater.id, newLantern.id])
        #expect(!Set(Mention.mentionedIDs(in: aria.body)).contains(b.id))
        #expect(Set(aria.mentionedPages.map(\.id)) == [newBrackwater.id, newLantern.id])
        #expect(newBrackwater.backlinks.map(\.source.title) == ["Aria"])
        #expect(summary.links == 0)
    }

    @Test func importingAMentionOfAPageNotInTheFileTurnsItIntoPlainText() async throws {
        let source = try makeContext()
        let (world, a, _, _) = makeWorld(source)
        a.body = body("Knows ", mention: "Stranger", UUID())

        let contents = try WorldPackage.contents(of: WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: world)))
        let (imported, _) = await WorldImporter.importWorld(contents, into: try makeContext())

        let aria = try #require((imported.pages ?? []).first { $0.title == "Aria" })
        #expect(text(aria.body) == "Knows Stranger")
        #expect(Mention.mentionedIDs(in: aria.body).isEmpty)
        #expect(aria.mentionedPages.isEmpty)
    }

    @Test func importIgnoresMentionLinkRecordsInAFileAndRebuildsThemFromText() async throws {
        let source = try makeContext()
        let (world, a, b, _) = makeWorld(source)
        a.body = body("", mention: "Brackwater", b.id)
        var contents = try WorldPackage.contents(of: WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: world)))
        // A stale link record claiming Aria mentions the Lantern, which her notes don't.
        let lantern = try #require(contents.archive.pages.first { $0.title == "Lantern" })
        let aria = try #require(contents.archive.pages.first { $0.title == "Aria" })
        contents.archive.links.append(LinkRecord(id: UUID(), role: LinkRole.mention, sourceID: aria.id, targetID: lantern.id))

        let (imported, summary) = await WorldImporter.importWorld(contents, into: try makeContext())

        let newAria = try #require((imported.pages ?? []).first { $0.title == "Aria" })
        #expect(newAria.mentionedPages.map(\.title) == ["Brackwater"])
        #expect(!summary.skippedAnything)
    }
}
