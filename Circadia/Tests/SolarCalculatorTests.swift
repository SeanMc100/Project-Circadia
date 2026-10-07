import XCTest
@testable import Circadia

final class SolarCalculatorTests: XCTestCase {

    /// Local clock minutes of `date` in `tz`.
    private func localMinutes(_ date: Date?, _ tz: TimeZone) -> Double? {
        guard let date else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return ClockMath.minutesFromMidnight(date, calendar: cal)
    }

    private func check(lat: Double, lon: Double, tzID: String, y: Int, m: Int, d: Int,
                       sunrise: (Int, Int), sunset: (Int, Int), tolerance: Double = 3,
                       file: StaticString = #filePath, line: UInt = #line) {
        let tz = TimeZone(identifier: tzID)!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let date = cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
        let sun = SolarCalculator.sunTimes(latitude: lat, longitude: lon, date: date, timeZone: tz)
        let rise = localMinutes(sun.sunrise, tz)
        let set = localMinutes(sun.sunset, tz)
        XCTAssertNotNil(rise, file: file, line: line)
        XCTAssertNotNil(set, file: file, line: line)
        XCTAssertEqual(rise ?? 0, Double(sunrise.0 * 60 + sunrise.1), accuracy: tolerance, "sunrise", file: file, line: line)
        XCTAssertEqual(set ?? 0, Double(sunset.0 * 60 + sunset.1), accuracy: tolerance, "sunset", file: file, line: line)
        XCTAssertTrue(sun.sunrise! < sun.solarNoon && sun.solarNoon < sun.sunset!, file: file, line: line)
    }

    func testNewYorkSummerSolstice() {
        // Published: sunrise 5:25 AM, sunset 8:31 PM EDT.
        check(lat: 40.7128, lon: -74.0060, tzID: "America/New_York", y: 2024, m: 6, d: 20, sunrise: (5, 25), sunset: (20, 31))
    }

    func testLondonWinterSolstice() {
        // Published: sunrise 8:04 AM, sunset 3:54 PM GMT.
        check(lat: 51.5074, lon: -0.1278, tzID: "Europe/London", y: 2024, m: 12, d: 21, sunrise: (8, 4), sunset: (15, 54))
    }

    func testSydneyNewYear() {
        // Published: sunrise 5:47 AM, sunset 8:09 PM AEDT (southern hemisphere, east of UTC).
        check(lat: -33.8688, lon: 151.2093, tzID: "Australia/Sydney", y: 2024, m: 1, d: 1, sunrise: (5, 47), sunset: (20, 9))
    }

    func testPolarDayHasNoSunriseOrSunset() {
        let tz = TimeZone(identifier: "Europe/Oslo")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let date = cal.date(from: DateComponents(year: 2024, month: 6, day: 21, hour: 12))!
        let sun = SolarCalculator.sunTimes(latitude: 69.6492, longitude: 18.9553, date: date, timeZone: tz) // Tromsø
        XCTAssertNil(sun.sunrise)
        XCTAssertNil(sun.sunset)
    }

    func testLocalSolarProviderReportsUnknownCloudCover() async throws {
        let tz = TimeZone(identifier: "America/New_York")!
        let snapshot = try await LocalSolarProvider().snapshot(for: Coordinate(latitude: 40.7, longitude: -74), date: Date(),
                                                                timeZone: tz, locationIsEstimated: false)
        XCTAssertEqual(snapshot.source, .localSolar)
        XCTAssertNil(snapshot.weather)
        XCTAssertEqual(snapshot.sky, .unknown)
    }

    func testFallbackServiceUsesLocalSolarWhenPrimaryFails() async throws {
        struct Failing: SunWeatherService {
            struct Unentitled: Error {}
            func snapshot(for coordinate: Coordinate, date: Date, timeZone: TimeZone, locationIsEstimated: Bool) async throws -> SunWeatherSnapshot {
                throw Unentitled()
            }
        }
        let service = FallbackSunWeatherService(primary: Failing())
        let snapshot = try await service.snapshot(for: Coordinate(latitude: 40.7, longitude: -74), date: Date(),
                                                  timeZone: TimeZone(identifier: "America/New_York")!, locationIsEstimated: true)
        XCTAssertEqual(snapshot.source, .localSolar)
        XCTAssertNotNil(snapshot.sun.sunrise)
        XCTAssertTrue(snapshot.locationIsEstimated)
    }
}
