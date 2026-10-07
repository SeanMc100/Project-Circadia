import CoreLocation
import Foundation
import WeatherKit

/// Sun times, cloud cover, UV and hourly forecast from Apple Weather.
/// Requires the WeatherKit capability and an App ID with WeatherKit enabled; otherwise it throws
/// and `FallbackSunWeatherService` switches to on-device solar math.
struct WeatherKitProvider: SunWeatherService {
    func snapshot(for coordinate: Coordinate, date: Date, timeZone: TimeZone, locationIsEstimated: Bool) async throws -> SunWeatherSnapshot {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let (current, hourly, daily) = try await WeatherService.shared.weather(for: location, including: .current, .hourly, .daily)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = daily.forecast.first { calendar.isDate($0.date, inSameDayAs: date) } ?? daily.forecast.first
        let solarNoon = day?.sun.solarNoon
            ?? SolarCalculator.sunTimes(latitude: coordinate.latitude, longitude: coordinate.longitude, date: date, timeZone: timeZone).solarNoon
        let sun = SunTimes(sunrise: day?.sun.sunrise, sunset: day?.sun.sunset, solarNoon: solarNoon)

        let next24 = hourly.forecast
            .filter { $0.date >= date.addingTimeInterval(-3600) && $0.date <= date.addingTimeInterval(24 * 3600) }
            .map { HourlyWeather(date: $0.date, cloudCover: $0.cloudCover, uvIndex: $0.uvIndex.value, isDaylight: $0.isDaylight) }

        let weather = WeatherSnapshot(
            cloudCover: current.cloudCover,
            conditionText: current.condition.description,
            symbolName: current.symbolName,
            uvIndex: current.uvIndex.value,
            temperatureText: current.temperature.formatted(.measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(0)))),
            isPrecipitating: current.precipitationIntensity.value > 0,
            hourly: next24)

        return SunWeatherSnapshot(sun: sun, weather: weather, source: .weatherKit, locationIsEstimated: locationIsEstimated)
    }

    /// Apple Weather attribution (required wherever WeatherKit data is shown).
    static func attributionLegalURL() async -> URL? {
        try? await WeatherService.shared.attribution.legalPageURL
    }
}
