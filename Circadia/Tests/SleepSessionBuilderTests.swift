import XCTest
@testable import Circadia

final class SleepSessionBuilderTests: XCTestCase {
    let cal = TestCal.calendar

    func testSessionCrossingMidnightIsKeyedToWakeDay() {
        let samples: [SleepSample] = [
            .watch(TestCal.date(2026, 3, 2, 23, 10), TestCal.date(2026, 3, 3, 2, 0)),
            .watch(TestCal.date(2026, 3, 3, 2, 0), TestCal.date(2026, 3, 3, 6, 50), .asleepREM),
        ]
        let nights = SleepSessionBuilder.buildNights(from: samples, calendar: cal)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights[0].wakeDay, TestCal.day(2026, 3, 3))
        XCTAssertEqual(nights[0].primary.onset, TestCal.date(2026, 3, 2, 23, 10))
        XCTAssertEqual(nights[0].primary.wake, TestCal.date(2026, 3, 3, 6, 50))
        XCTAssertEqual(nights[0].primary.asleepMinutes, 460, accuracy: 0.1)
    }

    func testOverlappingSamplesAreNotDoubleCounted() {
        let samples: [SleepSample] = [
            .phone(TestCal.date(2026, 3, 2, 23, 0), TestCal.date(2026, 3, 3, 5, 0)),
            .phone(TestCal.date(2026, 3, 3, 1, 0), TestCal.date(2026, 3, 3, 7, 0)),
        ]
        let night = SleepSessionBuilder.buildNights(from: samples, calendar: cal).first
        XCTAssertEqual(night?.primary.asleepMinutes ?? 0, 480, accuracy: 0.1) // 23:00–07:00 union, not 12 h
        XCTAssertEqual(night?.primary.onset, TestCal.date(2026, 3, 2, 23, 0))
    }

    func testWatchDataPreferredOverPhoneInSameCluster() {
        let samples: [SleepSample] = [
            .phone(TestCal.date(2026, 3, 2, 22, 30), TestCal.date(2026, 3, 3, 7, 30)),
            .watch(TestCal.date(2026, 3, 2, 23, 15), TestCal.date(2026, 3, 3, 3, 0)),
            .watch(TestCal.date(2026, 3, 3, 3, 0), TestCal.date(2026, 3, 3, 6, 45), .asleepDeep),
        ]
        let night = SleepSessionBuilder.buildNights(from: samples, calendar: cal).first
        XCTAssertEqual(night?.primary.onset, TestCal.date(2026, 3, 2, 23, 15))
        XCTAssertEqual(night?.primary.wake, TestCal.date(2026, 3, 3, 6, 45))
        XCTAssertEqual(night?.primary.isFromWatch, true)
    }

    func testBriefAwakeningStaysOneSessionButGapExcluded() {
        let samples: [SleepSample] = [
            .watch(TestCal.date(2026, 3, 2, 23, 0), TestCal.date(2026, 3, 3, 3, 0)),
            .watch(TestCal.date(2026, 3, 3, 3, 0), TestCal.date(2026, 3, 3, 3, 20), .awake),
            .watch(TestCal.date(2026, 3, 3, 3, 20), TestCal.date(2026, 3, 3, 7, 0)),
        ]
        let nights = SleepSessionBuilder.buildNights(from: samples, calendar: cal)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights[0].primary.asleepMinutes, 460, accuracy: 0.1)
        XCTAssertEqual(nights[0].primary.spanMinutes, 480, accuracy: 0.1)
    }

    func testNapIsSeparatedFromPrimary() {
        let samples: [SleepSample] = [
            .watch(TestCal.date(2026, 3, 6, 23, 30), TestCal.date(2026, 3, 7, 8, 0)),
            .watch(TestCal.date(2026, 3, 7, 15, 0), TestCal.date(2026, 3, 7, 15, 30)),
        ]
        let nights = SleepSessionBuilder.buildNights(from: samples, calendar: cal)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights[0].primary.wake, TestCal.date(2026, 3, 7, 8, 0))
        XCTAssertEqual(nights[0].naps.count, 1)
        XCTAssertEqual(nights[0].naps[0].asleepMinutes, 30, accuracy: 0.1)
    }

    func testShortSleepAloneIsNotAPrimaryNight() {
        let samples: [SleepSample] = [.watch(TestCal.date(2026, 3, 7, 14, 0), TestCal.date(2026, 3, 7, 15, 0))]
        XCTAssertTrue(SleepSessionBuilder.buildNights(from: samples, calendar: cal).isEmpty)
    }

    func testInBedOnlyNightIsUsedWhenNoAsleepData() {
        let samples: [SleepSample] = [.phone(TestCal.date(2026, 3, 2, 23, 0), TestCal.date(2026, 3, 3, 7, 0), .inBed)]
        let night = SleepSessionBuilder.buildNights(from: samples, calendar: cal).first
        XCTAssertEqual(night?.primary.isInBedOnly, true)
        XCTAssertEqual(night?.wakeDay, TestCal.day(2026, 3, 3))
    }

    func testInBedIgnoredWhenAsleepDataOverlaps() {
        let samples: [SleepSample] = [
            .phone(TestCal.date(2026, 3, 2, 22, 0), TestCal.date(2026, 3, 3, 8, 0), .inBed),
            .watch(TestCal.date(2026, 3, 2, 23, 0), TestCal.date(2026, 3, 3, 7, 0)),
        ]
        let nights = SleepSessionBuilder.buildNights(from: samples, calendar: cal)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights[0].primary.onset, TestCal.date(2026, 3, 2, 23, 0))
        XCTAssertFalse(nights[0].primary.isInBedOnly)
    }

    func testDaylightSummaryProratesAndFindsFirstLight() {
        let day = TestCal.day(2026, 3, 3)
        let wake = TestCal.date(2026, 3, 3, 7, 0)
        let samples = [
            DaylightSample(start: TestCal.date(2026, 3, 3, 7, 40), end: TestCal.date(2026, 3, 3, 7, 50), minutes: 10),
            DaylightSample(start: TestCal.date(2026, 3, 3, 11, 50), end: TestCal.date(2026, 3, 3, 12, 10), minutes: 20),
        ]
        let s = DaylightAnalyzer.summary(samples: samples, day: day, wake: wake, calendar: cal)
        XCTAssertEqual(s.firstLightAfterWakeMinutes ?? -1, 40, accuracy: 0.01)
        XCTAssertEqual(s.minutesBeforeNoon, 20, accuracy: 0.01) // 10 + half of the straddling sample
        XCTAssertEqual(s.totalMinutes, 30, accuracy: 0.01)
    }
}
