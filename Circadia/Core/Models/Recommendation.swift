import Foundation

enum RecommendationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case morningLight, anchorWake, windDown, caffeineCutoff, lateDayLight, travelShift, maintenance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morningLight: "Morning light"
        case .anchorWake: "Anchor wake time"
        case .windDown: "Evening wind-down"
        case .caffeineCutoff: "Caffeine cutoff"
        case .lateDayLight: "Afternoon light"
        case .travelShift: "Travel shift"
        case .maintenance: "In rhythm"
        }
    }

    var systemImage: String {
        switch self {
        case .morningLight: "sunrise.fill"
        case .anchorWake: "alarm.fill"
        case .windDown: "lamp.desk.fill"
        case .caffeineCutoff: "cup.and.saucer.fill"
        case .lateDayLight: "sun.max.fill"
        case .travelShift: "airplane"
        case .maintenance: "checkmark.seal.fill"
        }
    }

    /// Lower ranks first among recommendations of equal urgency.
    var priority: Int {
        switch self {
        case .travelShift: 0
        case .morningLight: 1
        case .windDown: 2
        case .lateDayLight: 3
        case .caffeineCutoff: 4
        case .anchorWake: 5
        case .maintenance: 6
        }
    }

    /// Kinds that can be delivered as a local notification.
    var isNotifiable: Bool {
        switch self {
        case .morningLight, .windDown, .caffeineCutoff, .lateDayLight, .travelShift: true
        case .anchorWake, .maintenance: false
        }
    }

    /// Light-exposure kinds get a payoff screen when completed.
    var isLightKind: Bool {
        self == .morningLight || self == .lateDayLight || self == .travelShift
    }

    static var notifiableKinds: [RecommendationKind] { allCases.filter(\.isNotifiable) }
}

enum Urgency: Int, Comparable, Sendable {
    case now = 0, soon, later, info

    static func < (lhs: Urgency, rhs: Urgency) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .now: "Now"
        case .soon: "Soon"
        case .later: "Later today"
        case .info: "Status"
        }
    }
}

/// How the app will later judge whether a recommendation was followed.
enum SuccessCriteria: Hashable, Sendable {
    case outdoorLight(minutes: Double, within: DateInterval)
    case wakeNear(Date, toleranceMinutes: Double)
    case noCaffeineAfter(Date)
    case lightsDimmed(by: Date)
    case keepRoutine

    var summary: String {
        switch self {
        case .outdoorLight(let minutes, let window):
            "About \(Int(minutes)) min of outdoor light before \(ClockMath.timeString(window.end))"
        case .wakeNear(let date, let tolerance):
            "Wake within \(Int(tolerance)) min of \(ClockMath.timeString(date))"
        case .noCaffeineAfter(let date):
            "No caffeine after \(ClockMath.timeString(date))"
        case .lightsDimmed(let date):
            "Lights dimmed by \(ClockMath.timeString(date))"
        case .keepRoutine:
            "Keep your current routine"
        }
    }

    /// Whether HealthKit data can confirm this without a manual tap.
    var isAutoDetectable: Bool {
        switch self {
        case .outdoorLight, .wakeNear: true
        default: false
        }
    }

    var codeName: String {
        switch self {
        case .outdoorLight: "outdoorLight"
        case .wakeNear: "wakeNear"
        case .noCaffeineAfter: "noCaffeineAfter"
        case .lightsDimmed: "lightsDimmed"
        case .keepRoutine: "keepRoutine"
        }
    }
}

struct Recommendation: Identifiable, Hashable, Sendable {
    /// Stable per kind per day, e.g. "morningLight-2026-10-06".
    let id: String
    let kind: RecommendationKind
    let title: String
    let body: String
    let window: DateInterval?
    let urgency: Urgency
    let mechanismKey: MechanismKey
    let successCriteria: SuccessCriteria
    /// When the card should start appearing on Today.
    let visibleFrom: Date
    /// Optional step-by-step plan (travel).
    var steps: [String] = []
    /// When a notification should fire for this recommendation, if any.
    var nudgeDate: Date?

    /// The interval used to judge success: the light window for light kinds, otherwise `window`.
    var trackingWindow: DateInterval? {
        if case .outdoorLight(_, let lightWindow) = successCriteria { return lightWindow }
        return window
    }
}

// MARK: - Circadian snapshot

enum ScoreComponentKind: String, CaseIterable, Identifiable, Sendable {
    case consistency, morningLight, drift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .consistency: "Consistency"
        case .morningLight: "Morning light"
        case .drift: "Timing drift"
        }
    }
}

struct ScoreComponent: Identifiable, Equatable, Sendable {
    var id: ScoreComponentKind { kind }
    let kind: ScoreComponentKind
    /// 0...1, or nil when unavailable (e.g. no daylight data).
    let value: Double?
    /// Normalised weight actually used (0 when unavailable).
    let weight: Double
    let detail: String
}

struct AlignmentScore: Equatable, Sendable {
    let value: Int
    let components: [ScoreComponent]
}

struct MorningLightAssessment: Equatable, Sendable {
    let timingScore: Double
    let amountScore: Double
    let combined: Double
    let firstLightMinutes: Double?
    let minutesBeforeNoon: Double
    /// Whether this assessment is today's (morning complete) or yesterday's.
    let isToday: Bool
}

struct CircadianSnapshot: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case noData
        case calibrating(have: Int, need: Int)
        case ready
    }

    var status: Status
    var latestNight: NightRecord?
    var baselineMidpoint: Double?
    var baselineOnset: Double?
    var baselineWake: Double?
    var latestMidpoint: Double?
    var drift: Double?
    var onsetSD: Double?
    var wakeSD: Double?
    var socialJetlag: Double?
    var morningLight: MorningLightAssessment?
    var score: AlignmentScore?
    var streakDays: Int

    var consistencySD: Double? {
        guard let onsetSD, let wakeSD else { return nil }
        return (onsetSD + wakeSD) / 2
    }

    static let empty = CircadianSnapshot(status: .noData, streakDays: 0)
}
