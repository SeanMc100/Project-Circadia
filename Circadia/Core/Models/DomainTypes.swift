import Foundation

// MARK: - Sleep

enum SleepStage: String, Codable, CaseIterable, Sendable {
    case inBed, asleepUnspecified, asleepCore, asleepDeep, asleepREM, awake

    var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: true
        case .inBed, .awake: false
        }
    }
}

/// One raw sleep-analysis sample, independent of HealthKit.
struct SleepSample: Hashable, Sendable {
    var start: Date
    var end: Date
    var stage: SleepStage
    var sourceName: String
    var isFromWatch: Bool
}

/// A continuous block of sleep assembled from (possibly overlapping, multi-source) samples.
struct SleepSession: Hashable, Sendable {
    /// First asleep moment.
    let onset: Date
    /// Final wake.
    let wake: Date
    /// Minutes actually asleep (union of asleep intervals, gaps excluded).
    let asleepMinutes: Double
    let isFromWatch: Bool
    /// True when no asleep-stage data existed and the session was built from in-bed samples.
    let isInBedOnly: Bool
    let intervals: [DateInterval]

    var midpoint: Date { onset.addingTimeInterval(wake.timeIntervalSince(onset) / 2) }
    var spanMinutes: Double { wake.timeIntervalSince(onset) / 60 }

    func overlaps(_ other: SleepSession) -> Bool {
        onset < other.wake && other.onset < wake
    }
}

/// The primary sleep that ended on `wakeDay`, plus any naps that ended that day.
struct NightRecord: Hashable, Sendable {
    /// Start of the calendar day on which the primary sleep ended.
    let wakeDay: Date
    let primary: SleepSession
    let naps: [SleepSession]
}

// MARK: - Light and secondary signals

/// One `timeInDaylight` sample: `minutes` of outdoor light recorded between start and end.
struct DaylightSample: Hashable, Sendable {
    var start: Date
    var end: Date
    var minutes: Double
}

struct MetricSample: Hashable, Sendable {
    var date: Date
    var value: Double
}

enum SecondaryMetric: String, CaseIterable, Identifiable, Sendable {
    case hrv, restingHeartRate, wristTemperature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hrv: "Heart rate variability"
        case .restingHeartRate: "Resting heart rate"
        case .wristTemperature: "Sleeping wrist temperature"
        }
    }

    var shortTitle: String {
        switch self {
        case .hrv: "HRV"
        case .restingHeartRate: "Resting HR"
        case .wristTemperature: "Wrist temp"
        }
    }

    var unit: String {
        switch self {
        case .hrv: "ms"
        case .restingHeartRate: "bpm"
        case .wristTemperature: "°C vs typical"
        }
    }
}

struct DaylightSummary: Equatable, Sendable {
    /// Minutes from wake to the first outdoor-light sample after wake (nil if none that day).
    var firstLightAfterWakeMinutes: Double?
    var minutesBeforeNoon: Double
    var totalMinutes: Double

    static let empty = DaylightSummary(firstLightAfterWakeMinutes: nil, minutesBeforeNoon: 0, totalMinutes: 0)
}

/// Everything we know about one calendar day. `night` is the sleep that ended on this day.
struct DayMetrics: Identifiable, Sendable {
    var id: Date { day }
    let day: Date
    let isFreeDay: Bool
    let night: NightRecord?
    let light: DaylightSummary
    /// True when the user has any daylight data at all (i.e. zero minutes means zero, not unknown).
    let hasLightData: Bool
    let onsetMinutes: Double?
    let wakeMinutes: Double?
    let midpointMinutes: Double?
    var hrv: Double?
    var restingHeartRate: Double?
    var wristTemperature: Double?

    func secondaryValue(_ metric: SecondaryMetric) -> Double? {
        switch metric {
        case .hrv: hrv
        case .restingHeartRate: restingHeartRate
        case .wristTemperature: wristTemperature
        }
    }
}

// MARK: - Sun, weather, location

struct Coordinate: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
}

struct SunTimes: Equatable, Sendable {
    /// nil during polar day/night.
    var sunrise: Date?
    var sunset: Date?
    var solarNoon: Date

    func shifted(byDays days: Int) -> SunTimes {
        let dt = TimeInterval(days) * 86_400
        return SunTimes(sunrise: sunrise?.addingTimeInterval(dt), sunset: sunset?.addingTimeInterval(dt), solarNoon: solarNoon.addingTimeInterval(dt))
    }
}

enum SkyCondition: String, Sendable {
    case clear, partlyCloudy, overcast, unknown

    init(cloudCover: Double?) {
        guard let cloudCover else { self = .unknown; return }
        if cloudCover < CircadianConfig.clearSkyMaxCloudCover { self = .clear }
        else if cloudCover < CircadianConfig.overcastMinCloudCover { self = .partlyCloudy }
        else { self = .overcast }
    }

    var label: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly cloudy"
        case .overcast: "Overcast"
        case .unknown: "Cloud cover unknown"
        }
    }
}

struct HourlyWeather: Equatable, Sendable {
    var date: Date
    var cloudCover: Double
    var uvIndex: Int
    var isDaylight: Bool
}

struct WeatherSnapshot: Equatable, Sendable {
    var cloudCover: Double?
    var conditionText: String
    var symbolName: String
    var uvIndex: Int?
    var temperatureText: String?
    var isPrecipitating: Bool
    var hourly: [HourlyWeather]
}

enum SunWeatherSource: String, Sendable {
    case weatherKit, localSolar, demo

    var label: String {
        switch self {
        case .weatherKit: "Apple Weather"
        case .localSolar: "Calculated on device (no weather)"
        case .demo: "Demo weather (synthetic)"
        }
    }
}

struct SunWeatherSnapshot: Equatable, Sendable {
    var sun: SunTimes
    var weather: WeatherSnapshot?
    var source: SunWeatherSource
    /// True when the coordinate came from the time zone rather than the device location.
    var locationIsEstimated: Bool

    var sky: SkyCondition { SkyCondition(cloudCover: weather?.cloudCover) }
}

// MARK: - Travel

enum TravelDirection: String, Codable, Sendable {
    case east, west

    var label: String { self == .east ? "eastward" : "westward" }
}

struct TravelState: Codable, Equatable, Sendable {
    /// Signed hours local time is ahead of home time (positive = east).
    var shiftHours: Double
    var detectedAt: Date
    /// Set when the user triggered travel from the demo controls; auto-detection won't clear it.
    var isSimulated: Bool = false

    var direction: TravelDirection { shiftHours >= 0 ? .east : .west }

    var planDays: Int {
        max(1, Int((abs(shiftHours) / CircadianConfig.travelShiftPerDayHours).rounded(.up)))
    }

    /// 1-based day index of the plan for `day`.
    func dayIndex(on day: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: detectedAt)
        let d = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: day)).day ?? 0
        return max(1, d + 1)
    }

    func remainingHours(on day: Date, calendar: Calendar) -> Double {
        max(0, abs(shiftHours) - Double(dayIndex(on: day, calendar: calendar) - 1) * CircadianConfig.travelShiftPerDayHours)
    }
}
