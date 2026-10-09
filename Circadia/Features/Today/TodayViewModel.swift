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

    /// Scored against "Your usual sleep" until enough nights are logged.
    var provisionalProgress: (have: Int, need: Int)? {
        if case .provisional(let have, let need) = app.snapshot.status { return (have, need) }
        return nil
    }

    var hasNoData: Bool { app.snapshot.status == .noData && app.hasLoadedOnce }

    var dateTitle: String {
        now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// The ideal day for the user's targets, with today's score in the middle.
    var ring: RingModel {
        var model = RingModel(timing: app.settings.timing, nowMinutes: ClockMath.minutesFromMidnight(now, calendar: calendar))
        if let score = app.snapshot.score {
            model.centerValue = "\(score.value)"
            model.centerBand = score.bandTitle
        } else if let progress = calibrationProgress {
            model.centerValue = "\(progress.have)/\(progress.need)"
            model.centerCaption = "nights calibrating"
        } else if !app.hasLoadedOnce {
            model.centerCaption = "loading"
        } else {
            model.centerCaption = isPhoneOnly ? "log last night to start" : "no sleep data yet"
        }
        return model
    }

    /// The light window currently recommended (morning, afternoon or travel), if any.
    var lightWindow: DateInterval? {
        app.recommendations.first { $0.kind.isLightKind }?.trackingWindow
    }

    var lightWindowText: String {
        guard let window = lightWindow else {
            if app.canSenseLight, let today = app.days.last, calendar.isDateInToday(today.day), today.metLightGoal {
                return "Morning light target met"
            }
            return "No light window right now"
        }
        if window.contains(now) { return "Light window open until \(ClockMath.timeString(window.end))" }
        if now < window.start { return "Light window \(ClockMath.timeString(window.start))–\(ClockMath.timeString(window.end))" }
        return "Light window closed"
    }

    var isDemoData: Bool { app.settings.useMockData }

    /// "Tuesday night" for the night that ended on `wakeDay`.
    func nightName(_ wakeDay: Date) -> String {
        let evening = calendar.date(byAdding: .day, value: -1, to: wakeDay) ?? wakeDay
        return "\(evening.formatted(.dateTime.weekday(.wide))) night"
    }

    var isPhoneOnly: Bool { app.settings.trackingMode == .phoneOnly }
}
