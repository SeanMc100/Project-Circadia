import Foundation

/// How many outdoor minutes before noon count as a full morning, set by that morning's sky.
/// One goal per day is shared by the score, the card, the wake notification and the forecast.
struct MorningLightGoal: Codable, Equatable, Sendable {
    var sky: SkyCondition
    var minutes: Double

    init(sky: SkyCondition) {
        self.sky = sky
        minutes = Self.minutes(for: sky)
    }

    static let unknown = MorningLightGoal(sky: .unknown)

    static func minutes(for sky: SkyCondition) -> Double {
        switch sky {
        case .clear: CircadianConfig.lightMinutesClear
        case .partlyCloudy: CircadianConfig.lightMinutesPartlyCloudy
        case .overcast: CircadianConfig.lightMinutesOvercast
        case .unknown: CircadianConfig.lightMinutesUnknownSky
        }
    }

    /// The goal as one sentence, e.g. for the wake notification.
    var sentence: String {
        let m = Int(minutes)
        return switch sky {
        case .clear: "Skies look clear, so aim for at least \(m) minutes of sunlight this morning."
        case .partlyCloudy: "It looks partly cloudy, so aim for about \(m) minutes outside this morning."
        case .overcast: "It looks overcast, so try to get outside for \(m) minutes this morning."
        case .unknown: "Aim for about \(m) minutes outside this morning."
        }
    }

    /// Outdoor minutes as credited: rounded to the nearest 5, since the Watch misses some time outside.
    static func credited(_ minutes: Double) -> Double {
        let step = CircadianConfig.lightCreditRoundingMinutes
        return max(0, (minutes / step).rounded() * step)
    }

    /// The sky over a morning window: the average forecast cloud cover across it. When the forecast
    /// doesn't cover it, the current cloud cover if the window has started (or passed), else unknown:
    /// right-now conditions say nothing about a morning still beyond the forecast.
    static func sky(over window: DateInterval, weather: WeatherSnapshot?, now: Date) -> SkyCondition {
        guard let weather else { return .unknown }
        // Hourly entries are stamped at the start of their hour.
        let hours = weather.hourly.filter { $0.date < window.end && $0.date.addingTimeInterval(3600) > window.start }
        if !hours.isEmpty {
            return SkyCondition(cloudCover: hours.reduce(0) { $0 + $1.cloudCover } / Double(hours.count))
        }
        return window.start <= now ? SkyCondition(cloudCover: weather.cloudCover) : .unknown
    }

    /// Storage key for a day's goal, "yyyy-MM-dd".
    static func key(for day: Date, calendar: Calendar = .current) -> String {
        ClockMath.dayKey(day, calendar: calendar)
    }
}
