import XCTest
@testable import Chiron

/// Guards the audio coaching output against simile / figurative phrasing
/// leaking past the prompt rule. Each case here is a real failure mode
/// we've seen or expect to see from the LLM.
final class StripSimilesTests: XCTestCase {

    // MARK: - Specific user-flagged examples

    func testStripsMedalSimile() {
        let input  = "You're dialled in, like you're showing off a medal."
        let output = OpenAICoachingManager.stripSimiles(input)
        XCTAssertFalse(output.lowercased().contains("medal"))
        XCTAssertFalse(output.lowercased().contains("like"))
        XCTAssertEqual(output, "You're dialled in.")
    }

    // MARK: - Simile introducer coverage

    func testStripsLikeYoureClause() {
        let input  = "Great set, like you're a machine."
        let output = OpenAICoachingManager.stripSimiles(input)
        XCTAssertFalse(output.lowercased().contains("like"))
        XCTAssertFalse(output.lowercased().contains("machine"))
    }

    func testStripsLikeAClause() {
        let input  = "Chest up, like a proud lion."
        let output = OpenAICoachingManager.stripSimiles(input)
        XCTAssertFalse(output.lowercased().contains("lion"))
    }

    func testStripsAsIfClause() {
        let input  = "Lock it out as if you're standing at attention."
        let output = OpenAICoachingManager.stripSimiles(input)
        XCTAssertFalse(output.lowercased().contains("as if"))
        XCTAssertFalse(output.lowercased().contains("attention"))
        XCTAssertTrue(output.lowercased().contains("lock it out"))
    }

    func testStripsAsThoughClause() {
        let input  = "Push the floor as though it might break."
        let output = OpenAICoachingManager.stripSimiles(input)
        XCTAssertFalse(output.lowercased().contains("as though"))
        XCTAssertFalse(output.lowercased().contains("break"))
    }

    func testStripsAsXAsYClause() {
        let input  = "Stand as tall as a flagpole."
        let output = OpenAICoachingManager.stripSimiles(input)
        XCTAssertFalse(output.lowercased().contains("flagpole"))
        XCTAssertTrue(output.lowercased().contains("stand"))
    }

    // MARK: - No-op path

    func testLeavesLiteralCueUnchanged() {
        let input  = "Nice depth — now push your knees out a bit more."
        let output = OpenAICoachingManager.stripSimiles(input)
        XCTAssertEqual(output, input)
    }

    func testHandlesMultipleSimilesInOneSentence() {
        let input  = "You're dialled in, like a rocket, as if you're flying."
        let output = OpenAICoachingManager.stripSimiles(input)
        XCTAssertFalse(output.lowercased().contains("rocket"))
        XCTAssertFalse(output.lowercased().contains("flying"))
        XCTAssertTrue(output.lowercased().contains("dialled in"))
    }

    func testSentenceEndSimileLeavesCleanPunctuation() {
        // Clipping a trailing-simile clause must not leave ".!" or " ." residue.
        let input  = "That set was great. Like a rocket!"
        let output = OpenAICoachingManager.stripSimiles(input)
        XCTAssertFalse(output.contains(".!"))
        XCTAssertFalse(output.contains(" ."))
    }
}
