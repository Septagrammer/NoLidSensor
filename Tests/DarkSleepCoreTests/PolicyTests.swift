import XCTest
@testable import DarkSleepCore

final class PolicyTests: XCTestCase {
    func testOnlyPromptUsesSecondTicks() {
        XCTAssertEqual(EventSchedule.delay(enabled: true, suspended: false, checking: false, prompt: false, snoozeRemaining: 0, checkRemaining: 180), 180)
        XCTAssertEqual(EventSchedule.delay(enabled: true, suspended: false, checking: false, prompt: false, snoozeRemaining: 0, checkRemaining: 300), 300)
        XCTAssertEqual(EventSchedule.delay(enabled: true, suspended: false, checking: false, prompt: true, snoozeRemaining: 0, checkRemaining: 180), 1)
    }
    func testNoTimerWhenDisabledSuspendedOrCapturing() {
        XCTAssertNil(EventSchedule.delay(enabled: false, suspended: false, checking: false, prompt: false, snoozeRemaining: 0, checkRemaining: 180))
        XCTAssertNil(EventSchedule.delay(enabled: true, suspended: true, checking: false, prompt: true, snoozeRemaining: 3600, checkRemaining: 180))
        XCTAssertNil(EventSchedule.delay(enabled: true, suspended: false, checking: true, prompt: false, snoozeRemaining: 0, checkRemaining: 180))
    }
    func testPauseHasOneDeadlineEvenWhenDisabled() {
        XCTAssertEqual(EventSchedule.delay(enabled: false, suspended: false, checking: false, prompt: false, snoozeRemaining: 3600, checkRemaining: 180), 3600)
        XCTAssertEqual(EventSchedule.delay(enabled: true, suspended: false, checking: false, prompt: true, snoozeRemaining: 600, checkRemaining: 180), 600)
        XCTAssertNil(EventSchedule.delay(enabled: false, suspended: false, checking: false, prompt: false, snoozeRemaining: -1, checkRemaining: 180))
        XCTAssertEqual(EventSchedule.delay(enabled: true, suspended: false, checking: false, prompt: false, snoozeRemaining: -1, checkRemaining: -5), 0.01)
    }
    func testActivityBetweenScheduledChecks() {
        var window = ActivityWindow()
        XCTAssertFalse(window.beginCheck(at: 100))
        XCTAssertEqual(window.requiredIdle(at: 100), .infinity)
        XCTAssertTrue(window.beginCheck(at: 280))
        let now = Date()
        // An event halfway through the interval must block, even after 90 idle seconds.
        XCTAssertFalse(SleepPolicy.eligible(enabled: true, now: now, snoozedUntil: .distantPast, idle: 90, requiredIdle: window.requiredIdle(at: 280)))
        XCTAssertTrue(SleepPolicy.eligible(enabled: true, now: now, snoozedUntil: .distantPast, idle: 180, requiredIdle: window.requiredIdle(at: 280)))
        // The next quiet interval can pass; old activity does not permanently block.
        XCTAssertTrue(window.beginCheck(at: 460))
        XCTAssertEqual(window.requiredIdle(at: 460), 180)
        // Delayed timers measure the real interval, not the configured interval.
        XCTAssertTrue(window.beginCheck(at: 700))
        XCTAssertEqual(window.requiredIdle(at: 704), 244)
        window = ActivityWindow()
        XCTAssertFalse(window.beginCheck(at: 900))
    }
    func testSnoozeAndDisabledBlockSleep() {
        let now = Date()
        XCTAssertFalse(SleepPolicy.eligible(enabled: true, now: now, snoozedUntil: now.addingTimeInterval(3600), idle: 900, requiredIdle: 180))
        XCTAssertFalse(SleepPolicy.eligible(enabled: false, now: now, snoozedUntil: .distantPast, idle: 900, requiredIdle: 180))
        XCTAssertTrue(SleepPolicy.eligible(enabled: true, now: now, snoozedUntil: .distantPast, idle: 900, requiredIdle: 180))
        XCTAssertFalse(SleepPolicy.eligible(enabled: true, now: now, snoozedUntil: .distantPast, idle: 2, requiredIdle: 180))
    }
    func testErrorsAndWarmupCannotCountAsDarkness() {
        XCTAssertFalse(SleepPolicy.dark([], threshold: 0.05))
        XCTAssertFalse(SleepPolicy.dark([0, 0, 0, 0], threshold: 0.05))
        XCTAssertFalse(SleepPolicy.dark([0, 0, .nan, 0, 0], threshold: 0.05))
        XCTAssertFalse(SleepPolicy.dark([0.01, 0.01, 0.2, 0.01, 0.01], threshold: 0.05))
        XCTAssertTrue(SleepPolicy.dark(Array(repeating: 0.01, count: 5), threshold: 0.05))
    }
    func testActivityDuringCaptureInvalidatesResult() {
        XCTAssertTrue(SleepPolicy.unchangedActivity(idleBefore: 200, idleAfter: 205, elapsed: 5))
        XCTAssertFalse(SleepPolicy.unchangedActivity(idleBefore: 200, idleAfter: 3, elapsed: 5))
        XCTAssertFalse(SleepPolicy.unchangedActivity(idleBefore: 900, idleAfter: 200, elapsed: 5))
    }
}
