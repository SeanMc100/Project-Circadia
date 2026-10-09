import Foundation
import SwiftData

enum RecommendationStatus: String, Codable, Sendable {
    case pending, followed, skipped, expired
}

enum FollowDetection: String, Codable, Sendable {
    case automatic, manual
}

/// A recommendation the app prescribed, whether it was followed, and the next-night outcome.
@Model
final class RecommendationRecord {
    @Attribute(.unique) var id: String
    var kindRaw: String
    /// Start of the (rollover-adjusted) day the recommendation belongs to.
    var day: Date
    var title: String
    var createdAt: Date
    var windowStart: Date?
    var windowEnd: Date?
    var criteriaRaw: String
    /// Minutes of outdoor light required (light kinds only).
    var requiredMinutes: Double?
    var statusRaw: String
    var detectionRaw: String?
    var completedAt: Date?
    // Outcomes, filled in once the following night is available.
    var nextSleepOnset: Date?
    var nextSleepMidpointMinutes: Double?

    init(recommendation: Recommendation, day: Date, now: Date) {
        id = recommendation.id
        kindRaw = recommendation.kind.rawValue
        self.day = day
        title = recommendation.title
        createdAt = now
        windowStart = recommendation.trackingWindow?.start
        windowEnd = recommendation.trackingWindow?.end
        criteriaRaw = recommendation.successCriteria.codeName
        if case .outdoorLight(let minutes, _) = recommendation.successCriteria {
            requiredMinutes = minutes
        }
        statusRaw = RecommendationStatus.pending.rawValue
    }

    var kind: RecommendationKind? { RecommendationKind(rawValue: kindRaw) }

    var status: RecommendationStatus {
        get { RecommendationStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var detection: FollowDetection? {
        get { detectionRaw.flatMap(FollowDetection.init(rawValue:)) }
        set { detectionRaw = newValue?.rawValue }
    }
}

/// One answer from the morning check-in: did the user follow `habit` on `day`?
@Model
final class HabitCheckIn {
    /// "<habit>-<yyyy-MM-dd>".
    @Attribute(.unique) var id: String
    var habitRaw: String
    /// Start of the (rollover-adjusted) day the answer is about.
    var day: Date
    /// nil when the user skipped the question.
    var followed: Bool?
    var answeredAt: Date

    init(habit: HabitKey, day: Date, followed: Bool?, answeredAt: Date, calendar: Calendar = .current) {
        id = Self.id(habit: habit, day: day, calendar: calendar)
        habitRaw = habit.rawValue
        self.day = day
        self.followed = followed
        self.answeredAt = answeredAt
    }

    var habit: HabitKey? { HabitKey(rawValue: habitRaw) }

    static func id(habit: HabitKey, day: Date, calendar: Calendar = .current) -> String {
        "\(habit.rawValue)-\(ClockMath.dayKey(day, calendar: calendar))"
    }
}

/// Outdoor time the user reported (no light sensor): a light card's Done, or a "yes" in the
/// morning check-in. A report of 0 minutes records a known "no".
@Model
final class LightReport {
    /// "light-<recommendation id>" or "light-checkin-<yyyy-MM-dd>".
    @Attribute(.unique) var id: String
    /// Start of the (rollover-adjusted) day it belongs to.
    var day: Date
    var start: Date
    var end: Date
    var minutes: Double
    var reportedAt: Date

    init(id: String, _ light: ReportedLight, reportedAt: Date) {
        self.id = id
        day = light.day
        start = light.start
        end = light.end
        minutes = light.minutes
        self.reportedAt = reportedAt
    }

    var value: ReportedLight { ReportedLight(day: day, start: start, end: end, minutes: minutes) }
}

/// One night the user logged by hand (phone-only mode, or a night the wearable missed).
@Model
final class SleepLogEntry {
    /// "sleeplog-<yyyy-MM-dd>" of the wake day.
    @Attribute(.unique) var id: String
    /// Start of the calendar day the user woke on.
    var wakeDay: Date
    var onset: Date
    var wake: Date
    var loggedAt: Date

    init(_ log: SleepLog, loggedAt: Date, calendar: Calendar = .current) {
        id = Self.id(wakeDay: log.wakeDay, calendar: calendar)
        wakeDay = log.wakeDay
        onset = log.onset
        wake = log.wake
        self.loggedAt = loggedAt
    }

    var value: SleepLog { SleepLog(wakeDay: wakeDay, onset: onset, wake: wake) }

    static func id(wakeDay: Date, calendar: Calendar = .current) -> String {
        "sleeplog-\(ClockMath.dayKey(wakeDay, calendar: calendar))"
    }
}
