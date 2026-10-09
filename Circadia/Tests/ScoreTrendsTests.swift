import XCTest
@testable import Circadia

final class ScoreTrendsTests: XCTestCase {
    let cal = TestCal.calendar

    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: TestCal.day(2026, 3, 2))! }

    private func point(_ offset: Int, _ value: Int, consistency: Double = 0.5, light: Double = 0.5, drift: Double = 0.5,
                       lightMinutes: Double = 10) -> ScorePoint {
        ScorePoint(day: day(offset), value: value,
                   components: [.consistency: consistency, .morningLight: light, .drift: drift],
                   consistencySD: 40, drift: 30, lightMinutesBeforeNoon: lightMinutes)
    }

    // MARK: Score history

    func testHistoryStartsAfterCalibrationAndOnlyUsesPastData() {
        var days = (0..<20).map { makeDay(day($0), onset: -60, wake: 420) }
        days.append(makeDay(day(20), onset: 60, wake: 540)) // a late night at the end
        let history = CircadianModel.scoreHistory(days: days, now: TestCal.date(2026, 3, 30, 9), calendar: cal)

        // First score once the baseline has its minimum nights before the latest one.
        XCTAssertEqual(history.first?.day, day(CircadianConfig.baselineMinimumNights))
        XCTAssertEqual(history.count, 21 - CircadianConfig.baselineMinimumNights)

        // Steady nights score the same; the late night is lower and doesn't leak backwards.
        let steady = history.dropLast()
        XCTAssertEqual(Set(steady.map(\.value)).count, 1)
        XCTAssertLessThan(history.last!.value, steady.last!.value)
        XCTAssertEqual(history.last!.drift ?? 0, 120, accuracy: 0.01)

        // The latest point matches the live snapshot.
        let live = CircadianModel.snapshot(days: days, now: TestCal.date(2026, 3, 22, 9), calendar: cal)
        XCTAssertEqual(history.last?.value, live.score?.value)
    }

    // MARK: Smoothing

    func testSmoothedIsTrailingAverageAndNeedsMinimumDays() {
        let points = (0..<10).map { point($0, $0 * 10) }
        let smooth = ScoreTrends.smoothed(points, windowDays: 7, calendar: cal)
        // Needs scoreTrendMinimumDays points before the first value.
        XCTAssertEqual(smooth.first?.day, day(CircadianConfig.scoreTrendMinimumDays - 1))
        // Last value: average of days 3...9 → (30+...+90)/7 = 60.
        XCTAssertEqual(smooth.last?.value ?? 0, 60, accuracy: 0.001)
    }

    func testSmoothedHandlesGaps() {
        // Days 0-4, then a gap, then 20-24: the window after the gap only sees the new days.
        let points = (0..<5).map { point($0, 50) } + (20..<25).map { point($0, 90) }
        let smooth = ScoreTrends.smoothed(points, windowDays: 7, calendar: cal)
        XCTAssertEqual(smooth.last?.value ?? 0, 90, accuracy: 0.001)
        XCTAssertNil(smooth.first { $0.day == day(20) }, "only one day in the window right after the gap")
    }

    // MARK: Extremes and reasons

    func testExtremesFindBestAndWorstStretchesWithReason() throws {
        let weights = CircadianConfig.defaultWeights
        var points: [ScorePoint] = []
        for i in 0..<10 { points.append(point(i, 60)) }
        for i in 10..<17 { points.append(point(i, 85, light: 1, lightMinutes: 30)) }   // great light week
        for i in 17..<27 { points.append(point(i, 60)) }
        for i in 27..<34 { points.append(point(i, 35, consistency: 0.1)) }            // erratic week
        for i in 34..<40 { points.append(point(i, 60)) }

        let ext = try XCTUnwrap(ScoreTrends.extremes(points, windowDays: 7, calendar: cal))
        XCTAssertEqual(ext.best.end, day(16))
        XCTAssertEqual(ext.best.average, 85, accuracy: 0.001)
        XCTAssertEqual(ext.worst.end, day(33))
        XCTAssertEqual(ext.worst.average, 35, accuracy: 0.001)

        let typical = try XCTUnwrap(ScoreTrends.period(points, from: day(0), to: day(39)))
        XCTAssertEqual(ScoreTrends.mainReason(for: ext.best, versus: typical, weights: weights)?.kind, .morningLight)
        XCTAssertEqual(ScoreTrends.mainReason(for: ext.worst, versus: typical, weights: weights)?.kind, .consistency)
    }

    func testNoExtremesForAFlatShortHistory() {
        let points = (0..<8).map { point($0, 70) }
        XCTAssertNil(ScoreTrends.extremes(points, windowDays: 7, calendar: cal))
    }
}
