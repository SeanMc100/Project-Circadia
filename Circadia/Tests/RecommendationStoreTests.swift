import XCTest
import SwiftData
@testable import Circadia

@MainActor
final class RecommendationStoreTests: XCTestCase {
    private func makeStore() throws -> RecommendationStore {
        let container = try ModelContainer(for: RecommendationRecord.self, HabitCheckIn.self, SleepLogEntry.self, LightReport.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return RecommendationStore(context: ModelContext(container))
    }

    /// Syncing before a light window opens used to build a reversed DateInterval and trap on launch.
    func testSyncBeforeLightWindowOpensDoesNotCrash() throws {
        let store = try makeStore()
        let sun = SunTimes(sunrise: TestCal.date(2026, 10, 6, 7, 5), sunset: TestCal.date(2026, 10, 6, 18, 30),
                           solarNoon: TestCal.date(2026, 10, 6, 12, 47))
        let ctx = CircadianContext(now: TestCal.date(2026, 10, 6, 7, 20), calendar: TestCal.calendar,
                                   wakeToday: TestCal.date(2026, 10, 6, 7, 0),
                                   targetWakeMinutes: 420, targetBedMinutes: 1380, baselineMidpointMinutes: 180,
                                   light: .empty, hasDaylightData: true,
                                   sunWeather: SunWeatherSnapshot(sun: sun, weather: nil, source: .localSolar, locationIsEstimated: false),
                                   travel: nil)
        let recs = RecommendationEngine.recommendations(for: ctx)
        let light = try XCTUnwrap(recs.first { $0.successCriteria.codeName == "outdoorLight" })
        let beforeWindow = try XCTUnwrap(light.trackingWindow).start.addingTimeInterval(-15 * 60)

        let followed = store.sync(recs, day: ctx.activeDay, daylight: [], hasDaylightData: true, now: beforeWindow)

        XCTAssertTrue(followed.isEmpty)
        XCTAssertEqual(store.record(id: light.id)?.status, .pending)
    }
}
