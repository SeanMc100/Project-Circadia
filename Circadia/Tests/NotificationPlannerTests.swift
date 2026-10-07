import XCTest
@testable import Circadia

final class NotificationPlannerTests: XCTestCase {
    let cal = TestCal.calendar
    let now = TestCal.date(2026, 10, 6, 6, 0)

    private var prefs: NotificationPreferences {
        NotificationPreferences(enabledKinds: Set(RecommendationKind.notifiableKinds),
                                quietStartMinutes: 22 * 60 + 30, quietEndMinutes: 6 * 60 + 30)
    }

    private func rec(_ kind: RecommendationKind, at hour: Int, _ minute: Int = 0) -> Recommendation {
        let fire = TestCal.date(2026, 10, 6, hour, minute)
        return Recommendation(id: "\(kind.rawValue)-2026-10-06", kind: kind, title: kind.title, body: "Body. More.",
                              window: DateInterval(start: fire, duration: 3600), urgency: .soon, mechanismKey: .lightAndSCN,
                              successCriteria: .keepRoutine, visibleFrom: fire, nudgeDate: fire)
    }

    func testCapsAtThreePerDayKeepingHighestPriority() {
        let recs = [rec(.caffeineCutoff, at: 13, 30), rec(.lateDayLight, at: 14), rec(.windDown, at: 20, 30),
                    rec(.morningLight, at: 7), rec(.travelShift, at: 8)]
        let plan = NotificationPlanner.plan(recommendations: recs, now: now, calendar: cal, preferences: prefs, consecutiveDismissals: [:])
        XCTAssertEqual(plan.nudges.count, 3)
        XCTAssertEqual(Set(plan.nudges.map(\.kind)), [.travelShift, .morningLight, .windDown])
        XCTAssertEqual(plan.nudges.map(\.fireDate), plan.nudges.map(\.fireDate).sorted(), "sorted by time")
    }

    func testRespectsQuietHours() {
        let recs = [rec(.windDown, at: 22, 45), rec(.morningLight, at: 6, 15), rec(.caffeineCutoff, at: 13)]
        let plan = NotificationPlanner.plan(recommendations: recs, now: TestCal.date(2026, 10, 6, 5, 0), calendar: cal,
                                            preferences: prefs, consecutiveDismissals: [:])
        XCTAssertEqual(plan.nudges.map(\.kind), [.caffeineCutoff])
    }

    func testQuietHoursWrapMidnight() {
        XCTAssertTrue(NotificationPlanner.isInQuietHours(TestCal.date(2026, 10, 6, 23, 0), preferences: prefs, calendar: cal))
        XCTAssertTrue(NotificationPlanner.isInQuietHours(TestCal.date(2026, 10, 6, 3, 0), preferences: prefs, calendar: cal))
        XCTAssertFalse(NotificationPlanner.isInQuietHours(TestCal.date(2026, 10, 6, 12, 0), preferences: prefs, calendar: cal))
    }

    func testBacksOffAfterTwoConsecutiveDismissals() {
        let recs = [rec(.morningLight, at: 7), rec(.windDown, at: 20, 30)]
        let once = NotificationPlanner.plan(recommendations: recs, now: now, calendar: cal, preferences: prefs, consecutiveDismissals: [.windDown: 1])
        XCTAssertEqual(once.nudges.count, 2)
        XCTAssertTrue(once.backedOff.isEmpty)
        let twice = NotificationPlanner.plan(recommendations: recs, now: now, calendar: cal, preferences: prefs, consecutiveDismissals: [.windDown: 2])
        XCTAssertEqual(twice.nudges.map(\.kind), [.morningLight])
        XCTAssertEqual(twice.backedOff, [.windDown])
    }

    func testDisabledKindsPastTimesAndNonNotifiableKindsSkipped() {
        var p = prefs
        p.enabledKinds.remove(.caffeineCutoff)
        let recs = [rec(.caffeineCutoff, at: 13), rec(.morningLight, at: 5, 30), rec(.anchorWake, at: 18), rec(.windDown, at: 20, 30)]
        let plan = NotificationPlanner.plan(recommendations: recs, now: now, calendar: cal, preferences: p, consecutiveDismissals: [:])
        XCTAssertEqual(plan.nudges.map(\.kind), [.windDown])
    }

    func testEngineOutputSchedulesAtMostThreeNudges() {
        let ctx = CircadianContext(now: TestCal.date(2026, 10, 6, 6, 45), calendar: cal, wakeToday: TestCal.date(2026, 10, 6, 6, 40),
                                   targetWakeMinutes: 420, targetBedMinutes: 1380, light: .empty, hasDaylightData: true,
                                   travel: TravelState(shiftHours: 5, detectedAt: TestCal.date(2026, 10, 6, 1, 0)))
        let plan = NotificationPlanner.plan(recommendations: RecommendationEngine.dailyPlan(for: ctx), now: ctx.now, calendar: cal,
                                            preferences: prefs, consecutiveDismissals: [:])
        XCTAssertLessThanOrEqual(plan.nudges.count, CircadianConfig.maxNudgesPerDay)
        XCTAssertFalse(plan.nudges.isEmpty)
    }
}
