import XCTest
@testable import Circadia

final class ScoreForecastTests: XCTestCase {
    let cal = TestCal.calendar

    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: TestCal.day(2026, 3, 2))! }

    /// 14 steady nights (11 PM – 7 AM), then whatever `last` is on day 14.
    private func history(lastOnset: Double = -60, lastWake: Double = 420, light: DaylightSummary = .empty,
                         hasLight: Bool = false) -> [DayMetrics] {
        (0..<14).map { makeDay(day($0), onset: -60, wake: 420, hasLight: hasLight) }
            + [makeDay(day(14), onset: lastOnset, wake: lastWake, light: light, hasLight: hasLight)]
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(byAdding: .minute, value: hour * 60 + minute, to: day(14))!
    }

    // MARK: Forecast

    func testLateNightForecastsRecoveryAndStepsAddUp() throws {
        // Last night ran two hours late; back on target tonight should score well above a repeat.
        let days = history(lastOnset: 60, lastWake: 540)
        let f = try XCTUnwrap(ScoreForecaster.make(days: days, now: at(15), targetBedMinutes: 23 * 60,
                                                   targetWakeMinutes: 7 * 60, calendar: cal))
        XCTAssertGreaterThan(f.projected, f.current)
        XCTAssertGreaterThan(f.projected, f.withoutPlan)
        XCTAssertEqual(f.steps.map(\.points).reduce(0, +), f.projected - f.withoutPlan)
        XCTAssertEqual(Set(f.steps.map(\.kind)), [.bedtime, .wake], "no light step without daylight data")
        XCTAssertTrue(f.steps.allSatisfy { $0.points > 0 })
        XCTAssertEqual(f.steps.map(\.points), f.steps.map(\.points).sorted(by: >), "biggest first")
    }

    func testOnTargetNightHasNothingToGainFromSleepSteps() throws {
        let f = try XCTUnwrap(ScoreForecaster.make(days: history(), now: at(15), targetBedMinutes: 23 * 60,
                                                   targetWakeMinutes: 7 * 60, calendar: cal))
        XCTAssertEqual(f.projected, f.withoutPlan)
        XCTAssertTrue(f.steps.allSatisfy { $0.points == 0 })
    }

    func testMorningLightStepOnlyWhileTheMorningCounts() throws {
        let noLight = DaylightSummary(firstLightAfterWakeMinutes: nil, minutesBeforeNoon: 0, totalMinutes: 0)
        let days = history(light: noLight, hasLight: true)

        let morning = try XCTUnwrap(ScoreForecaster.make(days: days, now: at(7, 30), targetBedMinutes: 23 * 60,
                                                         targetWakeMinutes: 7 * 60, calendar: cal))
        let light = try XCTUnwrap(morning.steps.first { $0.kind == .morningLight })
        XCTAssertGreaterThan(light.points, 0)
        XCTAssertTrue(light.text.contains("15 min"), light.text) // unknown-sky goal
        XCTAssertEqual(morning.steps.map(\.points).reduce(0, +), morning.projected - morning.withoutPlan)

        let afternoon = try XCTUnwrap(ScoreForecaster.make(days: days, now: at(14), targetBedMinutes: 23 * 60,
                                                           targetWakeMinutes: 7 * 60, calendar: cal))
        XCTAssertNil(afternoon.steps.first { $0.kind == .morningLight })
    }

    func testBedtimeCantBePlannedInThePast() throws {
        // 1 AM, still up: the planned onset is now, not 11 PM.
        let days = history(lastOnset: 60, lastWake: 540)
        let lateNow = cal.date(byAdding: .minute, value: 25 * 60, to: day(14))!
        let f = try XCTUnwrap(ScoreForecaster.make(days: days, now: lateNow, targetBedMinutes: 23 * 60,
                                                   targetWakeMinutes: 7 * 60, calendar: cal))
        XCTAssertEqual(f.steps.first { $0.kind == .bedtime }?.text, "In bed as soon as you can")
    }

    func testNoForecastWhileCalibrating() {
        let days = (0..<3).map { makeDay(day($0), onset: -60, wake: 420) }
        XCTAssertNil(ScoreForecaster.make(days: days, now: TestCal.date(2026, 3, 4, 15), targetBedMinutes: 23 * 60,
                                          targetWakeMinutes: 7 * 60, calendar: cal))
    }

    func testRoundingKeepsTotal() {
        let rounded = ScoreForecaster.roundedKeepingTotal(["a": 1.4, "b": 1.4, "c": 1.4], total: 4)
        XCTAssertEqual(rounded.values.reduce(0, +), 4)
    }

    // MARK: Recap

    func testRecapExplainsLateNightDrop() throws {
        let days = history(lastOnset: 60, lastWake: 540)
        let now = at(9)
        let snapshot = CircadianModel.snapshot(days: days, now: now, calendar: cal)
        let scores = CircadianModel.scoreHistory(days: days, now: now, calendar: cal)
        let recap = try XCTUnwrap(ScoreRecapBuilder.make(snapshot: snapshot, history: scores, now: now, calendar: cal))

        let change = try XCTUnwrap(recap.change)
        XCTAssertLessThan(change, 0)
        XCTAssertEqual(recap.factors.map(\.points).reduce(0, +), change, "factors add up to the change")
        let drift = try XCTUnwrap(recap.factors.first)
        XCTAssertEqual(drift.kind, .drift, "the late night is the main reason")
        XCTAssertTrue(drift.text.contains("2h later than usual"), drift.text)
    }

    func testNoRecapUntilLastNightIsIn() {
        let days = history()
        let tomorrowMorning = cal.date(byAdding: .hour, value: 33, to: day(14))!
        let snapshot = CircadianModel.snapshot(days: days, now: tomorrowMorning, calendar: cal)
        XCTAssertNil(ScoreRecapBuilder.make(snapshot: snapshot, history: [], now: tomorrowMorning, calendar: cal))
    }
}
