import Foundation

/// Source of sun times and (optionally) weather for a place and date.
protocol SunWeatherService: Sendable {
    func snapshot(for coordinate: Coordinate, date: Date, timeZone: TimeZone, locationIsEstimated: Bool) async throws -> SunWeatherSnapshot
}

/// Offline sunrise/sunset/solar noon using the NOAA solar position algorithm.
/// Cloud cover is unknown in this mode, and the UI says so.
struct LocalSolarProvider: SunWeatherService {
    func snapshot(for coordinate: Coordinate, date: Date, timeZone: TimeZone, locationIsEstimated: Bool) async throws -> SunWeatherSnapshot {
        makeSnapshot(for: coordinate, date: date, timeZone: timeZone, locationIsEstimated: locationIsEstimated)
    }

    func makeSnapshot(for coordinate: Coordinate, date: Date, timeZone: TimeZone, locationIsEstimated: Bool) -> SunWeatherSnapshot {
        let sun = SolarCalculator.sunTimes(latitude: coordinate.latitude, longitude: coordinate.longitude, date: date, timeZone: timeZone)
        return SunWeatherSnapshot(sun: sun, weather: nil, source: .localSolar, locationIsEstimated: locationIsEstimated)
    }
}

/// Tries the primary service (WeatherKit) and falls back to on-device solar math on any error,
/// e.g. no network or a missing WeatherKit entitlement. After a failure, the primary is skipped
/// for a while to avoid repeated slow failures.
actor FallbackSunWeatherService: SunWeatherService {
    private let primary: SunWeatherService
    private let fallback: LocalSolarProvider
    private var primaryDisabledUntil: Date?
    private(set) var lastPrimaryError: String?

    init(primary: SunWeatherService, fallback: LocalSolarProvider = LocalSolarProvider()) {
        self.primary = primary
        self.fallback = fallback
    }

    func snapshot(for coordinate: Coordinate, date: Date, timeZone: TimeZone, locationIsEstimated: Bool) async throws -> SunWeatherSnapshot {
        if primaryDisabledUntil.map({ Date() >= $0 }) ?? true {
            do {
                var result = try await primary.snapshot(for: coordinate, date: date, timeZone: timeZone, locationIsEstimated: locationIsEstimated)
                // Fill any missing sun events from local math.
                let local = fallback.makeSnapshot(for: coordinate, date: date, timeZone: timeZone, locationIsEstimated: locationIsEstimated).sun
                if result.sun.sunrise == nil { result.sun.sunrise = local.sunrise }
                if result.sun.sunset == nil { result.sun.sunset = local.sunset }
                primaryDisabledUntil = nil
                lastPrimaryError = nil
                return result
            } catch {
                lastPrimaryError = error.localizedDescription
                primaryDisabledUntil = Date().addingTimeInterval(CircadianConfig.weatherKitRetryInterval)
            }
        }
        return fallback.makeSnapshot(for: coordinate, date: date, timeZone: timeZone, locationIsEstimated: locationIsEstimated)
    }
}

/// Demo mode only: adds clearly labelled synthetic cloud cover to an on-device solar snapshot,
/// so the clear-vs-overcast logic can be seen without WeatherKit.
enum DemoWeather {
    static func decorate(_ snapshot: SunWeatherSnapshot, date: Date, calendar: Calendar = .current) -> SunWeatherSnapshot {
        guard snapshot.weather == nil else { return snapshot }
        let ordinal = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        var rng = SeededRandom(seed: UInt64(ordinal) &* 7919)
        let cloud = [0.15, 0.5, 0.85][Int(rng.uniform(0...2.999))]
        let sky = SkyCondition(cloudCover: cloud)
        let symbol = switch sky {
        case .clear: "sun.max"
        case .partlyCloudy: "cloud.sun"
        default: "cloud"
        }
        var result = snapshot
        result.source = .demo
        result.weather = WeatherSnapshot(cloudCover: cloud, conditionText: sky.label, symbolName: symbol,
                                         uvIndex: sky == .clear ? 5 : 2, temperatureText: nil, isPrecipitating: false, hourly: [])
        return result
    }
}

/// NOAA solar calculations (after the NOAA Global Monitoring Laboratory spreadsheet).
/// Accuracy is typically within a minute or two for latitudes between ±72°.
enum SolarCalculator {
    /// Official sunrise/sunset zenith including refraction and solar disc radius.
    static let zenith = 90.833

    static func sunTimes(latitude: Double, longitude: Double, date: Date, timeZone: TimeZone) -> SunTimes {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let c = local.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let dayStartUTC = utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? date
        let jdDay = julianDay(dayStartUTC)

        let noonMinutes = solarNoonMinutesUTC(jdDay: jdDay, longitude: longitude)
        let sunrise = eventMinutesUTC(jdDay: jdDay, latitude: latitude, longitude: longitude, rising: true)
        let sunset = eventMinutesUTC(jdDay: jdDay, latitude: latitude, longitude: longitude, rising: false)
        return SunTimes(sunrise: sunrise.map { dayStartUTC.addingTimeInterval($0 * 60) },
                        sunset: sunset.map { dayStartUTC.addingTimeInterval($0 * 60) },
                        solarNoon: dayStartUTC.addingTimeInterval(noonMinutes * 60))
    }

    static func julianDay(_ date: Date) -> Double { date.timeIntervalSince1970 / 86_400 + 2_440_587.5 }

    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }

    /// Equation of time (minutes) and solar declination (degrees) at Julian day `jd`.
    static func solarParameters(jd: Double) -> (equationOfTime: Double, declination: Double) {
        let t = (jd - 2_451_545) / 36_525
        let l0 = (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let center = sin(rad(m)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(rad(2 * m)) * (0.019993 - 0.000101 * t)
            + sin(rad(3 * m)) * 0.000289
        let trueLong = l0 + center
        let omega = 125.04 - 1934.136 * t
        let lambda = trueLong - 0.00569 - 0.00478 * sin(rad(omega))
        let seconds = 21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))
        let eps0 = 23 + (26 + seconds / 60) / 60
        let eps = eps0 + 0.00256 * cos(rad(omega))
        let declination = deg(asin(sin(rad(eps)) * sin(rad(lambda))))
        let y = pow(tan(rad(eps / 2)), 2)
        let eqTime = 4 * deg(y * sin(2 * rad(l0)) - 2 * e * sin(rad(m))
                             + 4 * e * y * sin(rad(m)) * cos(2 * rad(l0))
                             - 0.5 * y * y * sin(4 * rad(l0)) - 1.25 * e * e * sin(2 * rad(m)))
        return (eqTime, declination)
    }

    /// Hour angle (degrees) of sunrise; nil during polar day or polar night.
    static func hourAngle(latitude: Double, declination: Double) -> Double? {
        let cosHA = cos(rad(zenith)) / (cos(rad(latitude)) * cos(rad(declination))) - tan(rad(latitude)) * tan(rad(declination))
        guard cosHA >= -1, cosHA <= 1 else { return nil }
        return deg(acos(cosHA))
    }

    /// Longitude is positive east.
    static func solarNoonMinutesUTC(jdDay: Double, longitude: Double) -> Double {
        var minutes = 720 - 4 * longitude
        for _ in 0..<2 {
            let eq = solarParameters(jd: jdDay + minutes / 1440).equationOfTime
            minutes = 720 - 4 * longitude - eq
        }
        return minutes
    }

    static func eventMinutesUTC(jdDay: Double, latitude: Double, longitude: Double, rising: Bool) -> Double? {
        var minutes = solarNoonMinutesUTC(jdDay: jdDay, longitude: longitude)
        for _ in 0..<3 {
            let p = solarParameters(jd: jdDay + minutes / 1440)
            guard let ha = hourAngle(latitude: latitude, declination: p.declination) else { return nil }
            minutes = 720 - 4 * (longitude + (rising ? ha : -ha)) - p.equationOfTime
        }
        return minutes
    }
}
