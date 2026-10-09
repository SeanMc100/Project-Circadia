import SwiftData
import XCTest
@testable import Circadia

/// Phase 2 of phone-only mode: usual sleep, the provisional baseline, self-reported light, which
/// nights to ask about, the morning reminder and the widget question.
final class SelfReportTests: XCTestCase {
    let cal = TestCal.calendar
    /// Tuesday.
    let today = TestCal.day(2026, 10, 6)
    /// Workdays 23:00–7:00, days off 00:00–9:00.
    let usual = UsualSleep(workdayOnset: 23 * 60, workdayWake: 7 * 60, freeDayOnset: 0, freeDayWake: 9 * 60)

    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }

    // MARK: - Usual sleep (MCTQ)

    func testUsualSleepMidpointsAndSocialJetlag() {
        XCTAssertEqual(usual.midpoint(isFreeDay: false), 180, accuracy: 0.01, "23:00–7:00 → 3:00")
        XCTAssertEqual(usual.midpoint(isFreeDay: true), 270, accuracy: 0.01, "00:00–9:00 → 4:30")
        XCTAssertEqual(usual.socialJetlag, 90, accuracy: 0.01)
    }

    // MARK: - Provisional baseline

    func testFirstLoggedNightGetsAProvisionalScore() {
        let now = TestCal.date(2026, 10, 6, 15, 0)
        let days = [makeDay(today, onset: -60, wake: 420)]

        let without = CircadianModel.snapshot(days: days, now: now, calendar: cal)
        guard case .calibrating = without.status else { return XCTFail("no usual sleep: still calibrating") }
        XCTAssertNil(without.score)

        let with = CircadianModel.snapshot(days: days, now: now, calendar: cal, usual: usual)
        XCTAssertEqual(with.status, .provisional(have: 1, need: CircadianConfig.baselineMinimumNights + 1))
        XCTAssertEqual(with.score?.value, 100, "matches the usual workday timing exactly; drift is the only component")
        XCTAssertNil(with.score?.components.first { $0.kind == .consistency }?.value, "consistency is never padded")
        XCTAssertEqual(with.socialJetlag ?? 0, 90, accuracy: 0.01, "MCTQ social jetlag until there are enough weekends")
        XCTAssertEqual(with.streakDays, 0)
    }

    func testRealNightsReplaceTheUsualSleepOnceThereAreEnough() {
        let now = TestCal.date(2026, 10, 6, 15, 0)
        let days = (0..<6).map { makeDay(day(-$0), onset: 60, wake: 540) }.reversed() // 1:00–9:00 → 5:00
        let snapshot = CircadianModel.snapshot(days: Array(days), now: now, calendar: cal, usual: usual)
        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertEqual(snapshot.baselineMidpoint ?? 0, 300, accuracy: 0.01, "real nights only")
    }

    // MARK: - Light: unknown is not zero

    func testUnansweredLightDayIsUnknown() {
        let built = DayMetricsBuilder.build(nights: [], daylight: [], secondary: [:], from: day(-2), through: today,
                                            lightKnownDays: [day(-1)], calendar: cal)
        XCTAssertEqual(built.map(\.hasLightData), [false, true, false])
    }

    func testMorningLightAssessmentSkipsAnUnknownMorning() {
        let morning = TestCal.date(2026, 10, 6, 9, 0) // before noon: judges yesterday
        let known = [makeDay(day(-2), onset: -60, wake: 420, hasLight: true),
                     makeDay(day(-1), onset: -60, wake: 420, hasLight: false)]
        XCTAssertNil(CircadianModel.morningLightAssessment(days: known, now: morning, calendar: cal))

        let zero = [makeDay(day(-1), onset: -60, wake: 420, hasLight: true)]
        XCTAssertEqual(CircadianModel.morningLightAssessment(days: zero, now: morning, calendar: cal)?.combined, 0,
                       "an answered 'no' counts as zero")
    }

    func testReportedLightPlacement() {
        let wake = TestCal.date(2026, 10, 6, 7, 0)
        let yes = ReportedLight.checkInYes(day: today, wake: wake, minutes: 25)
        XCTAssertEqual(yes.start, TestCal.date(2026, 10, 6, 7, 30))
        XCTAssertEqual(yes.minutes, 25)

        let done = ReportedLight.done(day: today, minutes: 20, at: TestCal.date(2026, 10, 6, 8, 0))
        XCTAssertEqual(done.start, TestCal.date(2026, 10, 6, 7, 40))
        XCTAssertEqual(ReportedLight.none(day: today, at: wake).minutes, 0)

        // Checked off after the window closed: placed at the end of the window, not after noon.
        let window = DateInterval(start: TestCal.date(2026, 10, 6, 10, 0), end: TestCal.date(2026, 10, 6, 12, 0))
        let late = ReportedLight.done(day: today, minutes: 30, at: TestCal.date(2026, 10, 6, 12, 10), window: window)
        XCTAssertEqual(late.start, TestCal.date(2026, 10, 6, 11, 30))
        XCTAssertEqual(late.end, window.end)
        let inside = ReportedLight.done(day: today, minutes: 30, at: TestCal.date(2026, 10, 6, 11, 0), window: window)
        XCTAssertEqual(inside.end, TestCal.date(2026, 10, 6, 11, 0))
    }

    func testMorningLightIsAskedInTheCheckInOnlyWithoutASensor() {
        let t = HabitTiming(wakeMinutes: 420, bedMinutes: 1380)
        XCTAssertNil(HabitKey.morningLight.checkInPrompt(t))
        XCTAssertNotNil(HabitKey.morningLight.checkInPrompt(t, canSenseLight: false))
        XCTAssertEqual(HabitCatalog.checkInHabits(for: [.morningLight: .wantToStart], timing: t, canSenseLight: false), [.morningLight])
    }

    // MARK: - Which nights to ask about

    private func asks(_ mode: TrackingMode = .phoneOnly, since: Date? = nil, health: Set<Date> = [],
                      logged: Set<Date> = [], skipped: Set<Date> = []) -> SleepLogPlanner.Asks {
        SleepLogPlanner.asks(mode: mode, activeDay: today, phoneOnlySince: since ?? day(-5), healthNightDays: health,
                             loggedDays: logged, isSkipped: { skipped.contains($0) }, calendar: cal)
    }

    func testPhoneOnlyAsksAboutLastNightAndAMissedNight() {
        XCTAssertEqual(asks(), .init(today: true, yesterday: true))
        XCTAssertFalse(asks(since: today).yesterday, "never asks about nights before switching")
        XCTAssertFalse(asks(logged: [day(-1)]).yesterday)
        XCTAssertFalse(asks(skipped: [day(-1)]).yesterday)
        XCTAssertFalse(asks(health: [day(-1)]).yesterday, "a sleep app already has it")
        XCTAssertFalse(asks(skipped: [today]).today)
        XCTAssertTrue(asks(logged: [today], skipped: [today]).today, "a logged night stays editable")
    }

    func testWearableAsksOnlyWhenTheWatchHasGoneQuiet() {
        XCTAssertEqual(asks(.wearable, health: [day(-1)]), .init(), "missed only last night: wait")
        XCTAssertEqual(asks(.wearable), .init(), "never had data: the empty state handles it")
        XCTAssertEqual(asks(.wearable, health: [day(-3)]), .init(today: true, gapSince: day(-3)))
    }

    func testGuessFallsBackToUsualSleepByDayType() {
        let now = TestCal.date(2026, 10, 6, 12, 0)
        let tuesday = SleepLogGuess.make(wakeDay: today, logged: nil, days: [], usual: usual, targetBedMinutes: 22 * 60,
                                         targetWakeMinutes: 6 * 60, now: now, calendar: cal)
        XCTAssertEqual(tuesday.onset, TestCal.date(2026, 10, 5, 23, 0))
        XCTAssertEqual(tuesday.wake, TestCal.date(2026, 10, 6, 7, 0))

        let sunday = SleepLogGuess.make(wakeDay: day(-2), logged: nil, days: [], usual: usual, targetBedMinutes: 22 * 60,
                                        targetWakeMinutes: 6 * 60, now: now, calendar: cal)
        XCTAssertEqual(sunday.onset, TestCal.date(2026, 10, 4, 0, 0))
        XCTAssertEqual(sunday.wake, TestCal.date(2026, 10, 4, 9, 0))
    }

    // MARK: - Morning reminder

    private func prompt(wake: Date, logged: Bool = false) -> SleepLogPrompt {
        SleepLogPrompt(wakeDay: cal.startOfDay(for: wake), onset: wake.adding(minutes: -480), wake: wake, isLogged: logged)
    }

    private func prefs(quietEnd: Double = 6 * 60 + 30) -> NotificationPreferences {
        NotificationPreferences(enabledKinds: [], quietStartMinutes: 22 * 60 + 30, quietEndMinutes: quietEnd)
    }

    func testReminderFiresHalfAnHourAfterTheGuessedWake() {
        let now = TestCal.date(2026, 10, 5, 21, 0)
        let wake = TestCal.date(2026, 10, 6, 7, 0)
        let plan = SleepLogReminderPlanner.plan([prompt(wake: wake)], now: now, preferences: prefs(), calendar: cal)
        XCTAssertEqual(plan.map(\.fireDate), [TestCal.date(2026, 10, 6, 7, 30)])
        XCTAssertEqual(plan.first?.id, "sleepLog-2026-10-06")

        XCTAssertTrue(SleepLogReminderPlanner.plan([prompt(wake: wake, logged: true)], now: now, preferences: prefs(), calendar: cal).isEmpty)
        XCTAssertTrue(SleepLogReminderPlanner.plan([prompt(wake: wake)], now: TestCal.date(2026, 10, 6, 8, 0),
                                                   preferences: prefs(), calendar: cal).isEmpty, "already past")
    }

    func testReminderWaitsForQuietHoursToEnd() {
        let plan = SleepLogReminderPlanner.plan([prompt(wake: TestCal.date(2026, 10, 6, 7, 0))], now: TestCal.date(2026, 10, 5, 21, 0),
                                                preferences: prefs(quietEnd: 8 * 60), calendar: cal)
        XCTAssertEqual(plan.first?.fireDate, TestCal.date(2026, 10, 6, 8, 0))
    }

    func testReminderTakesASlotFromTheDailyCap() {
        func rec(_ kind: RecommendationKind, at hour: Int) -> Recommendation {
            let fire = TestCal.date(2026, 10, 6, hour, 0)
            return Recommendation(id: "\(kind.rawValue)-2026-10-06", kind: kind, title: kind.title, body: "Body.",
                                  window: DateInterval(start: fire, duration: 3600), urgency: .soon, mechanismKey: .lightAndSCN,
                                  successCriteria: .keepRoutine, visibleFrom: fire, nudgeDate: fire)
        }
        let recs = [rec(.morningLight, at: 8), rec(.caffeineCutoff, at: 13), rec(.windDown, at: 20)]
        var preferences = prefs()
        preferences.enabledKinds = Set(RecommendationKind.notifiableKinds)
        let plan = NotificationPlanner.plan(recommendations: recs, now: TestCal.date(2026, 10, 6, 6, 0), calendar: cal,
                                            preferences: preferences, consecutiveDismissals: [:], reservedPerDay: [today: 1])
        XCTAssertEqual(plan.nudges.count, CircadianConfig.maxNudgesPerDay - 1)
    }

    // MARK: - Focus widget

    func testWidgetLeadsWithTheSleepQuestionThroughTheMorning() {
        let ctx = CircadianContext(now: TestCal.date(2026, 10, 6, 5, 0), calendar: cal, targetWakeMinutes: 420,
                                   targetBedMinutes: 1380, hasDaylightData: false, habits: [:])
        let question = prompt(wake: TestCal.date(2026, 10, 6, 7, 0))
        let snapshot = WidgetSnapshotBuilder.make(snapshot: .empty, contexts: [ctx], now: ctx.now, sleepPrompts: [question])

        func items(at hour: Int) -> [WidgetSnapshot.FocusItem] {
            snapshot.focus.last { $0.start <= TestCal.date(2026, 10, 6, hour, 0) }?.items ?? []
        }
        XCTAssertTrue(items(at: 5).isEmpty, "not before an hour ahead of the guessed wake")
        let item = items(at: 8).first
        XCTAssertEqual(item?.id, "sleepLog-2026-10-06")
        XCTAssertEqual(item?.isSleepLog, true)
        XCTAssertEqual(item?.sleepOnset, question.onset)
        XCTAssertEqual(item?.sleepWake, question.wake)
        XCTAssertTrue(items(at: 17).isEmpty, "gone once the check-in closes")

        let logged = WidgetSnapshotBuilder.make(snapshot: .empty, contexts: [ctx], now: ctx.now,
                                                sleepPrompts: [prompt(wake: question.wake, logged: true)])
        XCTAssertFalse(logged.focus.flatMap(\.items).contains { $0.isSleepLog })
    }

    // MARK: - Persistence

    @MainActor
    func testLightReportsReplaceByID() throws {
        let container = try ModelContainer(for: SleepLogEntry.self, LightReport.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = SelfReportStore(context: container.mainContext)
        let at = TestCal.date(2026, 10, 6, 8, 0)
        store.saveLight(.done(day: today, minutes: 10, at: at), id: "light-a", at: at)
        store.saveLight(.done(day: today, minutes: 30, at: at), id: "light-a", at: at)
        XCTAssertEqual(store.lightReports().map(\.minutes), [30])
        store.deleteLight(id: "light-a")
        XCTAssertTrue(store.lightReports().isEmpty)
    }
}
