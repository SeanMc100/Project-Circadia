import XCTest
@testable import Circadia

final class CircadianModelTests: XCTestCase {
    let cal = TestCal.calendar

    // MARK: Clock math

    func testSignedMinutesWrapAroundMidnight() {
        XCTAssertEqual(ClockMath.signedMinutes(TestCal.date(2026, 3, 2, 23, 15), calendar: cal), -45, accuracy: 0.01)
        XCTAssertEqual(ClockMath.signedMinutes(TestCal.date(2026, 3, 3, 3, 30), calendar: cal), 210, accuracy: 0.01)
        XCTAssertEqual(ClockMath.wrapSigned(1430), -10, accuracy: 0.01)
        XCTAssertEqual(ClockMath.wrapSigned(-730), 710, accuracy: 0.01)
    }

    func testSleepMidpointAcrossMidnight() {
        let day = makeDay(TestCal.day(2026, 3, 3), onset: -60, wake: 420) // 23:00 → 07:00
        XCTAssertEqual(day.midpointMinutes ?? 0, 180, accuracy: 0.01) // 03:00
        XCTAssertEqual(ClockMath.signedMinutes(day.night!.primary.midpoint, calendar: cal), 180, accuracy: 0.01)
    }

    func testCircularMedianHandlesValuesStraddlingMidnight() {
        // 23:50, 23:55, 00:05, 00:10, 00:20 → median 00:05, not ~12:00.
        let values: [Double] = [-10, -5, 5, 10, 20]
        XCTAssertEqual(ClockMath.circularMedian(values) ?? 999, 5, accuracy: 0.01)
        let wrapped: [Double] = [1430, 1435, 5, 10, 20] // same times, positive form
        XCTAssertEqual(ClockMath.circularMedian(wrapped) ?? 999, 5, accuracy: 0.01)
    }

    // MARK: Baseline and drift

    func testBaselineIsMedianAndRobustToOutlier() {
        let midpoints: [Double] = [180, 185, 175, 190, 182, 400] // one very late night
        XCTAssertEqual(CircadianModel.baselineMidpoint(midpoints) ?? 0, 183.5, accuracy: 0.01)
    }

    func testBaselineNeedsMinimumNights() {
        XCTAssertNil(CircadianModel.baselineMidpoint([180, 190, 200, 210]))
        XCTAssertNotNil(CircadianModel.baselineMidpoint([180, 190, 200, 210, 220]))
    }

    func testSnapshotCalibratingThenReadyWithDrift() {
        var days: [DayMetrics] = []
        for i in 0..<4 {
            days.append(makeDay(cal.date(byAdding: .day, value: i, to: TestCal.day(2026, 3, 2))!, onset: -60, wake: 420))
        }
        let early = CircadianModel.snapshot(days: days, now: TestCal.date(2026, 3, 5, 9), calendar: cal)
        guard case .calibrating(let have, let need) = early.status else { return XCTFail("expected calibrating") }
        XCTAssertEqual(have, 4)
        XCTAssertEqual(need, CircadianConfig.baselineMinimumNights + 1)

        for i in 4..<8 {
            days.append(makeDay(cal.date(byAdding: .day, value: i, to: TestCal.day(2026, 3, 2))!, onset: -60, wake: 420))
        }
        // Latest night 1 hour later than usual.
        days.append(makeDay(TestCal.day(2026, 3, 10), onset: 0, wake: 480))
        let ready = CircadianModel.snapshot(days: days, now: TestCal.date(2026, 3, 10, 9), calendar: cal)
        XCTAssertEqual(ready.status, .ready)
        XCTAssertEqual(ready.baselineMidpoint ?? 0, 180, accuracy: 0.01)
        XCTAssertEqual(ready.drift ?? 0, 60, accuracy: 0.01)
        XCTAssertNotNil(ready.score)
    }

    // MARK: Consistency and social jetlag

    func testConsistencyStandardDeviation() {
        let sds = CircadianModel.consistency(onsets: [-60, -30, -60, -30], wakes: [420, 420, 420, 420])
        XCTAssertEqual(sds?.onset ?? 0, 17.32, accuracy: 0.01)
        XCTAssertEqual(sds?.wake ?? -1, 0, accuracy: 0.01)
    }

    func testConsistencyAcrossMidnightIsSmall() {
        // Onsets at 23:50 and 00:10 alternate: spread should be ~10 min, not ~12 h.
        let sds = CircadianModel.consistency(onsets: [-10, 10, -10, 10], wakes: [420, 420, 420, 420])
        XCTAssertEqual(sds?.onset ?? 0, 11.55, accuracy: 0.01)
    }

    func testSocialJetlag() {
        let nights: [(isFreeDay: Bool, midpoint: Double)] = [
            (false, 180), (false, 190), (false, 170), (true, 270), (true, 290),
        ]
        XCTAssertEqual(CircadianModel.socialJetlag(nights) ?? 0, 100, accuracy: 0.01)
        XCTAssertNil(CircadianModel.socialJetlag([(false, 180), (true, 270)]))
    }

    func testSocialJetlagFromWeekdayPattern() {
        // Mar 2 2026 is a Monday. Weekdays 23:00–07:00, weekends 00:30–09:00.
        var days: [DayMetrics] = []
        for i in 0..<14 {
            let d = cal.date(byAdding: .day, value: i, to: TestCal.day(2026, 3, 2))!
            days.append(cal.isDateInWeekend(d) ? makeDay(d, onset: 30, wake: 540) : makeDay(d, onset: -60, wake: 420))
        }
        let snapshot = CircadianModel.snapshot(days: days, now: TestCal.date(2026, 3, 15, 12), calendar: cal)
        // Weekend midpoint 04:45 (285) vs weekday 03:00 (180) → 105 min.
        XCTAssertEqual(snapshot.socialJetlag ?? 0, 105, accuracy: 0.01)
    }

    // MARK: Score components

    func testMorningLightScoreCurve() {
        XCTAssertEqual(CircadianModel.lightTimingScore(firstLightMinutes: 30), 1)
        XCTAssertEqual(CircadianModel.lightTimingScore(firstLightMinutes: 60), 1)
        XCTAssertEqual(CircadianModel.lightTimingScore(firstLightMinutes: 120), 0.5, accuracy: 0.001)
        XCTAssertEqual(CircadianModel.lightTimingScore(firstLightMinutes: 180), 0)
        XCTAssertEqual(CircadianModel.lightTimingScore(firstLightMinutes: nil), 0)
        // Square-root curve: half the goal earns about 71%.
        XCTAssertEqual(CircadianModel.lightAmountScore(minutesBeforeNoon: 10, goalMinutes: 20), 0.7071, accuracy: 0.001)
        XCTAssertEqual(CircadianModel.lightAmountScore(minutesBeforeNoon: 45, goalMinutes: 20), 1)
        XCTAssertEqual(CircadianModel.lightAmountScore(minutesBeforeNoon: 0, goalMinutes: 20), 0)
        let s = CircadianModel.morningLightScore(firstLightMinutes: 120, minutesBeforeNoon: 10, goalMinutes: 20)
        XCTAssertEqual(s.combined, 0.5 * 0.5 + 0.5 * 0.7071, accuracy: 0.001)
    }

    func testLightMinutesRoundToNearestFive() {
        XCTAssertEqual(MorningLightGoal.credited(17.4), 15)
        XCTAssertEqual(MorningLightGoal.credited(17.5), 20)
        XCTAssertEqual(MorningLightGoal.credited(2), 0)
        // 8.5 Watch minutes on a clear morning (goal 10) round to full credit.
        XCTAssertEqual(CircadianModel.lightAmountScore(minutesBeforeNoon: 8.5, goalMinutes: 10), 1)
        XCTAssertEqual(CircadianModel.lightAmountScore(minutesBeforeNoon: 18, goalMinutes: 20), 1)
    }

    func testGoalFollowsSky() {
        XCTAssertEqual(MorningLightGoal(sky: .clear).minutes, 10)
        XCTAssertEqual(MorningLightGoal(sky: .partlyCloudy).minutes, 15)
        XCTAssertEqual(MorningLightGoal(sky: .overcast).minutes, 25)
        XCTAssertEqual(MorningLightGoal.unknown.minutes, 15)
        XCTAssertTrue(MorningLightGoal(sky: .overcast).sentence.contains("25 minutes"))

        let start = TestCal.date(2026, 10, 6, 8, 0)
        let window = DateInterval(start: start, duration: 2 * 3600)
        let hourly = [0.1, 0.9, 0.9].enumerated().map { i, cover in
            HourlyWeather(date: start.addingTimeInterval(Double(i) * 3600), cloudCover: cover, uvIndex: 1, isDaylight: true)
        }
        let weather = WeatherSnapshot(cloudCover: 0.0, conditionText: "", symbolName: "", uvIndex: nil,
                                      temperatureText: nil, isPrecipitating: false, hourly: hourly)
        // 8:00 and 9:00 overlap the window (average 0.5), 10:00 doesn't.
        XCTAssertEqual(MorningLightGoal.sky(over: window, weather: weather, now: start), .partlyCloudy)
        XCTAssertEqual(MorningLightGoal.sky(over: window, weather: nil, now: start), .unknown)

        // Beyond the forecast: a future morning is unknown, not today's sky; a passed one uses the current sky.
        let later = DateInterval(start: start.addingTimeInterval(2 * 86_400), duration: 2 * 3600)
        XCTAssertEqual(MorningLightGoal.sky(over: later, weather: weather, now: start), .unknown)
        let earlier = DateInterval(start: start.addingTimeInterval(-86_400), duration: 2 * 3600)
        XCTAssertEqual(MorningLightGoal.sky(over: earlier, weather: weather, now: start), .clear)
    }

    func testConsistencyAndDriftScores() {
        XCTAssertEqual(CircadianModel.consistencyScore(sd: 10), 1)
        XCTAssertEqual(CircadianModel.consistencyScore(sd: 52.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(CircadianModel.consistencyScore(sd: 100), 0)
        XCTAssertEqual(CircadianModel.driftScore(drift: -15), 1)
        XCTAssertEqual(CircadianModel.driftScore(drift: -67.5), 0.5, accuracy: 0.001)
    }

    func testAlignmentWeightsAndComponents() {
        let light = MorningLightAssessment(timingScore: 1, amountScore: 0.2, combined: 0.6, firstLightMinutes: 30, minutesBeforeNoon: 4, goalMinutes: 20, isToday: true)
        // consistency SD 15 → 1.0; light 0.6; drift 0 → 1.0 → 0.40 + 0.21 + 0.25 = 0.86
        let score = CircadianModel.alignment(onsetSD: 15, wakeSD: 15, light: light, drift: 0, weights: CircadianConfig.defaultWeights)
        XCTAssertEqual(score?.value, 86)
        XCTAssertEqual(score?.components.count, 3)
        XCTAssertEqual(score?.components.map(\.kind), [.consistency, .morningLight, .drift])
    }

    func testAlignmentRenormalisesWhenLightUnavailable() {
        let score = CircadianModel.alignment(onsetSD: 15, wakeSD: 15, light: nil, drift: 120, weights: CircadianConfig.defaultWeights)
        // consistency 1.0 at 0.40/0.65, drift 0 at 0.25/0.65 → 61.5 → 62
        XCTAssertEqual(score?.value, 62)
        let lightComponent = score?.components.first { $0.kind == .morningLight }
        XCTAssertNil(lightComponent?.value)
        XCTAssertEqual(lightComponent?.weight, 0)
    }
}
