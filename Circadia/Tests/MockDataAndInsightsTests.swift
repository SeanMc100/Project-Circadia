import XCTest
@testable import Circadia

/// End-to-end checks against the synthetic provider: no device needed.
final class MockDataAndInsightsTests: XCTestCase {
    let cal = TestCal.calendar
    let now = TestCal.date(2026, 10, 6, 15, 0)

    private func pipeline() -> (nights: [NightRecord], days: [DayMetrics]) {
        let data = MockHealthDataProvider.generate(endingAt: now, days: CircadianConfig.mockDays, calendar: cal)
        let nights = SleepSessionBuilder.buildNights(from: data.sleep, calendar: cal)
        let days = DayMetricsBuilder.build(nights: nights, daylight: data.daylight, secondary: data.secondary,
                                           from: nights.first!.wakeDay, through: now, calendar: cal)
        return (nights, days)
    }

    func testMockDataIsDeterministic() {
        let a = MockHealthDataProvider.generate(endingAt: now, days: 30, calendar: cal)
        let b = MockHealthDataProvider.generate(endingAt: now, days: 30, calendar: cal)
        XCTAssertEqual(a.sleep, b.sleep)
        XCTAssertEqual(a.daylight, b.daylight)
    }

    func testMockProducesOnePrimaryNightPerDayAndNoFutureData() {
        let data = MockHealthDataProvider.generate(endingAt: now, days: CircadianConfig.mockDays, calendar: cal)
        XCTAssertTrue(data.sleep.allSatisfy { $0.end <= now })
        XCTAssertTrue(data.daylight.allSatisfy { $0.end <= now })
        let (nights, _) = pipeline()
        XCTAssertEqual(nights.count, CircadianConfig.mockDays)
        XCTAssertTrue(nights.allSatisfy(\.primary.isFromWatch), "watch data preferred over overlapping iPhone samples")
        XCTAssertTrue(nights.contains { !$0.naps.isEmpty }, "some weekend naps")
    }

    func testMockShowsWeekendDriftAndAReadySnapshot() {
        let (_, days) = pipeline()
        let snapshot = CircadianModel.snapshot(days: days, now: now, calendar: cal)
        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertGreaterThan(snapshot.socialJetlag ?? 0, 45, "weekends drift later")
        XCTAssertNotNil(snapshot.score)
        XCTAssertNotNil(snapshot.morningLight)
        XCTAssertTrue((0...100).contains(snapshot.score!.value))
    }

    func testInsightsFromMockDataShowEarlyLightAssociation() throws {
        let (_, days) = pipeline()
        let result = InsightsEngine.compute(days: days, outcomes: [], targetWakeMinutes: 420, calendar: cal)
        XCTAssertEqual(result.status, .ready)
        let early = try XCTUnwrap(result.insights.first { $0.id == "earlyLight" })
        XCTAssertEqual(early.tone, .favorable, early.detail)
        XCTAssertTrue(early.sampleNote.contains("Based on"))
    }

    func testInsightsNeedEnoughDays() {
        let (_, days) = pipeline()
        let result = InsightsEngine.compute(days: Array(days.suffix(10)), outcomes: [], targetWakeMinutes: 420, calendar: cal)
        XCTAssertEqual(result.status, .notEnoughData(daysHave: 10, daysNeeded: CircadianConfig.insightsMinimumDays))
        XCTAssertTrue(result.insights.isEmpty)
    }

    func testInsightRequiresMinimumPerGroup() {
        XCTAssertNil(InsightsEngine.onsetInsight(id: "x", withGroup: [0, 10, 20], withoutGroup: [30, 40, 50, 60],
                                                 condition: "c", favorableHeadline: "h", groupNames: ("a", "b"), mechanism: nil))
        let insight = InsightsEngine.onsetInsight(id: "x", withGroup: [-30, -20, -25, -35], withoutGroup: [0, 5, -5, 10],
                                                  condition: "c", favorableHeadline: "h", groupNames: ("a", "b"), mechanism: nil)
        XCTAssertEqual(insight?.tone, .favorable)
        XCTAssertTrue(insight?.detail.contains("30 min earlier") == true, insight?.detail ?? "")
    }

    @MainActor
    func testMockProviderConformsToProtocol() async throws {
        let provider: HealthDataProviding = MockHealthDataProvider(calendar: cal, now: { self.now })
        let start = cal.date(byAdding: .day, value: -7, to: now)!
        let sleep = try await provider.sleepSamples(from: start, to: now)
        let light = try await provider.daylightSamples(from: start, to: now)
        let hrv = try await provider.secondarySamples(.hrv, from: start, to: now)
        XCTAssertFalse(sleep.isEmpty)
        XCTAssertFalse(light.isEmpty)
        XCTAssertFalse(hrv.isEmpty)
        let state = await provider.authorizationState()
        XCTAssertEqual(state, .demo)
    }
}
