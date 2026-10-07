import Foundation

/// Presentation logic for the Today screen, derived from AppModel state.
@MainActor
struct TodayViewModel {
    let app: AppModel
    var now = Date()

    var calendar: Calendar { app.calendar }

    var cards: [Recommendation] { Array(app.recommendations.prefix(3)) }

    var isCalibrating: Bool {
        if case .calibrating = app.snapshot.status { return true }
        return false
    }

    var calibrationProgress: (have: Int, need: Int)? {
        if case .calibrating(let have, let need) = app.snapshot.status { return (have, need) }
        return nil
    }

    var hasNoData: Bool { app.snapshot.status == .noData && app.hasLoadedOnce }

    var dateTitle: String {
        now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var ring: RingModel {
        let cal = calendar
        var model = RingModel(nowMinutes: ClockMath.minutesFromMidnight(now, calendar: cal), centerValue: "–", centerCaption: "alignment estimate")

        if let night = app.snapshot.latestNight,
           now.timeIntervalSince(night.primary.wake) < 36 * 3600 {
            model.sleep = .init(start: ClockMath.minutesFromMidnight(night.primary.onset, calendar: cal),
                                end: ClockMath.minutesFromMidnight(night.primary.wake, calendar: cal))
        }
        model.light = SleepSessionBuilder.mergeIntervals(app.todayDaylight.map { DateInterval(start: $0.start, end: $0.end) })
            .map { .init(start: ClockMath.minutesFromMidnight($0.start, calendar: cal), end: ClockMath.minutesFromMidnight($0.end, calendar: cal)) }
        if let sunrise = app.sunWeather?.sun.sunrise, let sunset = app.sunWeather?.sun.sunset {
            model.daylight = .init(start: ClockMath.minutesFromMidnight(sunrise, calendar: cal), end: ClockMath.minutesFromMidnight(sunset, calendar: cal))
        }
        if let window = lightWindow {
            model.lightWindow = .init(start: ClockMath.minutesFromMidnight(window.start, calendar: cal),
                                      end: ClockMath.minutesFromMidnight(window.end, calendar: cal))
        }

        if let score = app.snapshot.score {
            model.centerValue = "\(score.value)"
            model.centerCaption = "alignment estimate"
        } else if let progress = calibrationProgress {
            model.centerValue = "\(progress.have)/\(progress.need)"
            model.centerCaption = "nights calibrating"
        } else if !app.hasLoadedOnce {
            model.centerCaption = "loading"
        } else {
            model.centerCaption = "no sleep data yet"
        }
        return model
    }

    /// The light window currently recommended (morning, afternoon or travel), if any.
    var lightWindow: DateInterval? {
        app.recommendations.first { $0.kind.isLightKind }?.trackingWindow
    }

    var lightWindowText: String {
        guard let window = lightWindow else {
            if app.hasDaylightData, let light = todaysLightSummary, light.minutesBeforeNoon >= CircadianConfig.morningLightTargetMinutes {
                return "Morning light target met"
            }
            return "No light window right now"
        }
        if window.contains(now) { return "Light window open until \(ClockMath.timeString(window.end))" }
        if now < window.start { return "Light window \(ClockMath.timeString(window.start))–\(ClockMath.timeString(window.end))" }
        return "Light window closed"
    }

    var todaysLightSummary: DaylightSummary? {
        app.days.last.flatMap { calendar.isDateInToday($0.day) ? $0.light : nil }
    }

    var dataSourceNote: String? {
        app.settings.useMockData ? "Demo mode: showing synthetic data. Turn it off in Settings to use Apple Health." : nil
    }
}
