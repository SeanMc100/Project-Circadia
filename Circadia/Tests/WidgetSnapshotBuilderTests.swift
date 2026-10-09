import XCTest
@testable import Circadia

final class WidgetSnapshotBuilderTests: XCTestCase {
    let cal = TestCal.calendar

    /// Tuesday 6 Oct 2026, woke 7:00, sunrise 7:05, sunset 18:30, targets 7:00 / 23:00.
    private func context(now: Date) -> CircadianContext {
        let sun = SunTimes(sunrise: TestCal.date(2026, 10, 6, 7, 5), sunset: TestCal.date(2026, 10, 6, 18, 30),
                           solarNoon: TestCal.date(2026, 10, 6, 12, 47))
        return CircadianContext(now: now, calendar: cal, wakeToday: TestCal.date(2026, 10, 6, 7, 0),
                                targetWakeMinutes: 420, targetBedMinutes: 1380, baselineMidpointMinutes: 180,
                                hasDaylightData: true,
                                sunWeather: SunWeatherSnapshot(sun: sun, weather: nil, source: .localSolar, locationIsEstimated: false))
    }

    private func build(at now: Date) -> WidgetSnapshot {
        WidgetSnapshotBuilder.make(snapshot: .empty, contexts: [context(now: now)], now: now)
    }

    func testEntriesCoverTheActiveDayInOrderWithoutRepeats() throws {
        let snapshot = build(at: TestCal.date(2026, 10, 6, 7, 20))
        let first = try XCTUnwrap(snapshot.focus.first)
        XCTAssertEqual(first.start, TestCal.date(2026, 10, 6, 4, 0))
        XCTAssertEqual(snapshot.validUntil, TestCal.date(2026, 10, 7, 4, 0))
        XCTAssertEqual(snapshot.focus.map(\.start), snapshot.focus.map(\.start).sorted())
        for (a, b) in zip(snapshot.focus, snapshot.focus.dropFirst()) {
            XCTAssertNotEqual(a.items, b.items, "consecutive entries must differ")
        }
        XCTAssertTrue(snapshot.focus.allSatisfy { $0.items.count <= WidgetSnapshotBuilder.maxItems })
    }

    func testEachEntryMatchesWhatTheAppShowsAtThatMoment() {
        let snapshot = build(at: TestCal.date(2026, 10, 6, 7, 20))
        for hour in [5, 7, 9, 12, 15, 21, 23] {
            let moment = TestCal.date(2026, 10, 6, hour, 10)
            let entry = snapshot.focus.last { $0.start <= moment }
            let expected = RecommendationEngine.recommendations(for: context(now: moment)).first?.id
            XCTAssertEqual(entry?.items.first?.id, expected, "at \(hour):10")
        }
    }

    func testMorningLightSwitchesExactlyWhenTheWindowOpens() throws {
        let snapshot = build(at: TestCal.date(2026, 10, 6, 6, 0))
        let opening = try XCTUnwrap(snapshot.focus.first { $0.start == TestCal.date(2026, 10, 6, 7, 5) })
        XCTAssertEqual(opening.items.first?.kind, RecommendationKind.morningLight.rawValue)
        XCTAssertTrue(opening.items.first?.title.hasPrefix("Go outside now") == true)
    }

    func testRebuildingLaterTheSameDayIsUnchanged() {
        // Identical content must compare equal so the app doesn't reload the widgets for nothing.
        let early = build(at: TestCal.date(2026, 10, 6, 7, 20))
        let later = build(at: TestCal.date(2026, 10, 6, 14, 45))
        XCTAssertNotEqual(early.generatedAt, later.generatedAt)
        XCTAssertEqual(early, later)
    }

    func testCompletedKindsDropOutOfTheTimeline() {
        var ctx = context(now: TestCal.date(2026, 10, 6, 9, 0))
        ctx.completedKinds = [.caffeineCutoff]
        let snapshot = WidgetSnapshotBuilder.make(snapshot: .empty, contexts: [ctx], now: ctx.now)
        XCTAssertFalse(snapshot.focus.flatMap(\.items).contains { $0.kind == RecommendationKind.caffeineCutoff.rawValue })
    }
}
