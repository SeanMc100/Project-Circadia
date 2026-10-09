import SwiftData
import XCTest
@testable import Circadia

/// Phone-only mode: logged nights, the Health-wins merge, the pre-filled guess and the demo variant.
final class SleepLogTests: XCTestCase {
    let cal = TestCal.calendar
    /// Tuesday.
    let wakeDay = TestCal.day(2026, 10, 6)

    private func log(_ onset: Double, _ wake: Double, on day: Date? = nil) -> SleepLog {
        SleepLog.make(wakeDay: day ?? wakeDay, onsetClockMinutes: onset, wakeClockMinutes: wake, calendar: cal)
    }

    // MARK: - Building a night

    func testLogBeforeMidnightBuildsNightOnWakeDay() {
        let entry = log(23 * 60 + 15, 6 * 60 + 50)
        XCTAssertEqual(entry.onset, TestCal.date(2026, 10, 5, 23, 15))
        XCTAssertEqual(entry.wake, TestCal.date(2026, 10, 6, 6, 50))

        let nights = SleepSessionBuilder.buildNights(from: SleepLogMerger.merge(health: [], logs: [entry]), calendar: cal)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights[0].wakeDay, wakeDay)
        XCTAssertEqual(nights[0].primary.onset, entry.onset)
        XCTAssertEqual(nights[0].primary.wake, entry.wake)
        XCTAssertFalse(nights[0].primary.isFromWatch)
    }

    func testOnsetAfterMidnightStaysOnWakeDay() {
        XCTAssertEqual(log(30, 8 * 60).onset, TestCal.date(2026, 10, 6, 0, 30))
    }

    func testProblemsRejectNapsTyposAndTheFuture() {
        let now = TestCal.date(2026, 10, 6, 9, 0)
        XCTAssertNil(log(23 * 60, 7 * 60).problem(now: now))
        XCTAssertNotNil(log(5 * 60, 7 * 60).problem(now: now), "2 h is a nap")
        XCTAssertNotNil(log(13 * 60, 7 * 60).problem(now: now), "18 h is a typo")
        XCTAssertNotNil(log(23 * 60, 10 * 60).problem(now: now), "wake after now")
    }

    // MARK: - Health wins

    func testHealthNightWinsOverOverlappingLog() {
        let health: [SleepSample] = [.watch(TestCal.date(2026, 10, 5, 23, 0), TestCal.date(2026, 10, 6, 7, 0))]
        let merged = SleepLogMerger.merge(health: health, logs: [log(22 * 60, 8 * 60)])
        XCTAssertEqual(merged, health)
        let night = SleepSessionBuilder.buildNights(from: merged, calendar: cal).first
        XCTAssertEqual(night?.primary.onset, TestCal.date(2026, 10, 5, 23, 0))
    }

    func testInBedOnlyHealthNightAlsoWins() {
        let health: [SleepSample] = [.phone(TestCal.date(2026, 10, 5, 22, 45), TestCal.date(2026, 10, 6, 7, 10), .inBed)]
        XCTAssertTrue(SleepLogMerger.unrecorded([log(23 * 60, 7 * 60)], health: health).isEmpty)
    }

    func testLogFillsANightHealthMissed() {
        let health: [SleepSample] = [.watch(TestCal.date(2026, 10, 4, 23, 0), TestCal.date(2026, 10, 5, 7, 0))]
        let merged = SleepLogMerger.merge(health: health, logs: [log(23 * 60, 7 * 60)])
        let nights = SleepSessionBuilder.buildNights(from: merged, calendar: cal)
        XCTAssertEqual(nights.map(\.wakeDay), [TestCal.day(2026, 10, 5), wakeDay])
    }

    // MARK: - Pre-filled guess

    func testGuessReturnsTheLoggedNight() {
        let logged = log(23 * 60 + 40, 6 * 60 + 20)
        let prompt = SleepLogGuess.make(wakeDay: wakeDay, logged: logged, days: [], targetBedMinutes: 23 * 60,
                                        targetWakeMinutes: 7 * 60, now: TestCal.date(2026, 10, 6, 9, 0), calendar: cal)
        XCTAssertTrue(prompt.isLogged)
        XCTAssertEqual(prompt.log, logged)
    }

    func testGuessFallsBackToTargets() {
        let now = TestCal.date(2026, 10, 6, 9, 0)
        let prompt = SleepLogGuess.make(wakeDay: wakeDay, logged: nil, days: [], targetBedMinutes: 23 * 60,
                                        targetWakeMinutes: 7 * 60, now: now, calendar: cal)
        XCTAssertFalse(prompt.isLogged)
        XCTAssertEqual(prompt.onset, TestCal.date(2026, 10, 5, 23, 0))
        XCTAssertEqual(prompt.wake, TestCal.date(2026, 10, 6, 7, 0))

        let late = SleepLogGuess.make(wakeDay: wakeDay, logged: nil, days: [], targetBedMinutes: 30,
                                      targetWakeMinutes: 8 * 60, now: now, calendar: cal)
        XCTAssertEqual(late.onset, TestCal.date(2026, 10, 6, 0, 30), "a bedtime after midnight stays on the wake day")
    }

    func testGuessUsesTheLatestNightOfTheSameKind() {
        let days = [
            makeDay(TestCal.day(2026, 10, 4), onset: 60, wake: 9 * 60),      // Sunday: free day
            makeDay(TestCal.day(2026, 10, 5), onset: -30, wake: 6 * 60 + 40), // Monday: workday
        ]
        let prompt = SleepLogGuess.make(wakeDay: wakeDay, logged: nil, days: days, targetBedMinutes: 22 * 60,
                                        targetWakeMinutes: 6 * 60, now: TestCal.date(2026, 10, 6, 9, 0), calendar: cal)
        XCTAssertEqual(prompt.onset, TestCal.date(2026, 10, 5, 23, 30))
        XCTAssertEqual(prompt.wake, TestCal.date(2026, 10, 6, 6, 40))
    }

    func testGuessNeverPutsWakeInTheFuture() {
        let prompt = SleepLogGuess.make(wakeDay: wakeDay, logged: nil, days: [], targetBedMinutes: 23 * 60,
                                        targetWakeMinutes: 7 * 60, now: TestCal.date(2026, 10, 6, 6, 12), calendar: cal)
        XCTAssertEqual(prompt.wake, TestCal.date(2026, 10, 6, 6, 10))
        XCTAssertEqual(prompt.onset, TestCal.date(2026, 10, 5, 23, 0))
    }

    // MARK: - Pipeline

    func testLoggedNightsProduceAScoreWithoutLight() {
        let now = TestCal.date(2026, 10, 6, 15, 0)
        let logs = (0..<7).map { i -> SleepLog in
            let day = cal.date(byAdding: .day, value: -i, to: wakeDay)!
            return log(23 * 60 + Double(i % 3) * 10, 7 * 60 - Double(i % 2) * 10, on: day)
        }
        let nights = SleepSessionBuilder.buildNights(from: SleepLogMerger.merge(health: [], logs: logs), calendar: cal)
        let days = DayMetricsBuilder.build(nights: nights, daylight: [], secondary: [:],
                                           from: nights.first!.wakeDay, through: now, calendar: cal)
        let snapshot = CircadianModel.snapshot(days: days, now: now, calendar: cal)
        XCTAssertEqual(snapshot.status, .ready)
        let score = try? XCTUnwrap(snapshot.score)
        XCTAssertGreaterThan(score?.value ?? 0, 75, "steady logged nights score well")
        XCTAssertNil(score?.components.first { $0.kind == .morningLight }?.value, "no light data: component left out")
    }

    // MARK: - Demo without a wearable

    @MainActor
    func testNoWearableDemoLooksLikeASleepLog() async throws {
        let now = TestCal.date(2026, 10, 6, 15, 0)
        let provider = MockHealthDataProvider(calendar: cal, now: { now })
        provider.includesWearableData = false
        let start = cal.date(byAdding: .day, value: -CircadianConfig.mockDays, to: now)!

        let sleep = try await provider.sleepSamples(from: start, to: now)
        XCTAssertTrue(sleep.allSatisfy { $0.sourceName == SleepLogMerger.sourceName && !$0.isFromWatch })
        XCTAssertTrue(sleep.allSatisfy { Int($0.start.timeIntervalSince1970) % 300 == 0 }, "rounded like typed times")
        let nights = SleepSessionBuilder.buildNights(from: sleep, calendar: cal)
        XCTAssertEqual(nights.count, CircadianConfig.mockDays - 1, "last night is left for the user to log")
        XCTAssertFalse(nights.contains { cal.isDate($0.wakeDay, inSameDayAs: now) })

        let daylight = try await provider.daylightSamples(from: start, to: now)
        XCTAssertTrue(daylight.isEmpty)
        let hrv = try await provider.secondarySamples(.hrv, from: start, to: now)
        XCTAssertTrue(hrv.isEmpty)
    }

    // MARK: - Persistence

    @MainActor
    func testStoreReplacesAndDeletesByWakeDay() throws {
        let container = try ModelContainer(for: SleepLogEntry.self, LightReport.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = SelfReportStore(context: container.mainContext)
        store.save(log(23 * 60, 7 * 60), at: Date(), calendar: cal)
        store.save(log(23 * 60 + 30, 7 * 60), at: Date(), calendar: cal)
        XCTAssertEqual(store.all().count, 1, "same wake day replaces")
        XCTAssertEqual(store.log(wakeDay: wakeDay, calendar: cal)?.onset, TestCal.date(2026, 10, 5, 23, 30))

        store.delete(wakeDay: wakeDay, calendar: cal)
        XCTAssertTrue(store.all().isEmpty)
    }

    func testTrackingModePersistsAndResets() {
        let suite = "SleepLogTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.trackingMode, .wearable)
        settings.trackingMode = .phoneOnly
        XCTAssertEqual(AppSettings(defaults: defaults).trackingMode, .phoneOnly)
        settings.resetAll()
        XCTAssertEqual(AppSettings(defaults: defaults).trackingMode, .wearable)
    }
}
