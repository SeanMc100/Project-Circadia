import Foundation

struct NotificationPreferences: Equatable {
    var enabledKinds: Set<RecommendationKind>
    var quietStartMinutes: Double
    var quietEndMinutes: Double
    var maxPerDay: Int = CircadianConfig.maxNudgesPerDay
}

struct PlannedNudge: Equatable, Identifiable {
    var id: String { recommendationID }
    let recommendationID: String
    let kind: RecommendationKind
    let fireDate: Date
    let title: String
    let body: String
}

/// Decides which nudges to schedule: at most N per day, outside quiet hours, only enabled kinds,
/// and never a kind the user dismissed twice in a row (back-off). Pure and testable.
enum NotificationPlanner {
    struct Plan: Equatable {
        var nudges: [PlannedNudge]
        /// Kinds skipped because of repeated dismissals.
        var backedOff: [RecommendationKind]
    }

    static func plan(recommendations: [Recommendation],
                     now: Date,
                     calendar: Calendar = .current,
                     preferences: NotificationPreferences,
                     consecutiveDismissals: [RecommendationKind: Int]) -> Plan {
        var backedOff: Set<RecommendationKind> = []
        var candidates: [(Recommendation, Date)] = []
        var seen: Set<String> = []

        for rec in recommendations where rec.kind.isNotifiable && !seen.contains(rec.id) {
            seen.insert(rec.id)
            guard preferences.enabledKinds.contains(rec.kind) else { continue }
            if (consecutiveDismissals[rec.kind] ?? 0) >= CircadianConfig.dismissalsBeforeBackoff {
                backedOff.insert(rec.kind)
                continue
            }
            guard let fire = rec.nudgeDate, fire > now.addingTimeInterval(60) else { continue }
            guard !isInQuietHours(fire, preferences: preferences, calendar: calendar) else { continue }
            candidates.append((rec, fire))
        }

        // Cap per calendar day, keeping the most important kinds.
        let byDay = Dictionary(grouping: candidates) { calendar.startOfDay(for: $0.1) }
        var nudges: [PlannedNudge] = []
        for (_, dayCandidates) in byDay {
            let chosen = dayCandidates
                .sorted { ($0.0.kind.priority, $0.1) < ($1.0.kind.priority, $1.1) }
                .prefix(preferences.maxPerDay)
            nudges += chosen.map { rec, fire in
                PlannedNudge(recommendationID: rec.id, kind: rec.kind, fireDate: fire,
                             title: rec.title, body: notificationBody(for: rec))
            }
        }
        return Plan(nudges: nudges.sorted { $0.fireDate < $1.fireDate },
                    backedOff: backedOff.sorted { $0.priority < $1.priority })
    }

    static func isInQuietHours(_ date: Date, preferences: NotificationPreferences, calendar: Calendar = .current) -> Bool {
        let m = ClockMath.minutesFromMidnight(date, calendar: calendar)
        let start = preferences.quietStartMinutes, end = preferences.quietEndMinutes
        if start == end { return false }
        return start < end ? (m >= start && m < end) : (m >= start || m < end)
    }

    /// Notifications are short; the full explanation lives in the app.
    static func notificationBody(for rec: Recommendation) -> String {
        let firstSentence = rec.body.split(separator: ".", maxSplits: 1).first.map { String($0) + "." } ?? rec.body
        switch rec.kind {
        case .morningLight: return "Your morning light window is open. " + MechanismLibrary.entry(for: rec.mechanismKey).headline
        case .lateDayLight: return "A weaker substitute for missed morning light, but it still helps."
        default: return firstSentence
        }
    }
}

/// Detects time-zone or large longitude changes relative to "home" (where the baseline formed).
enum TravelDetector {
    /// Signed hours `current` is ahead of `home` at the given instant (DST-safe: both evaluated at `date`).
    static func shiftHours(home: TimeZone, current: TimeZone, at date: Date) -> Double {
        var hours = Double(current.secondsFromGMT(for: date) - home.secondsFromGMT(for: date)) / 3600
        if hours > 12 { hours -= 24 }
        if hours < -12 { hours += 24 }
        return hours
    }

    static func evaluate(homeTimeZone: TimeZone, homeLongitude: Double?,
                         currentTimeZone: TimeZone, currentLongitude: Double?,
                         now: Date, existing: TravelState?) -> TravelState? {
        if let existing, existing.isSimulated { return existing }
        var shift = shiftHours(home: homeTimeZone, current: currentTimeZone, at: now)
        if abs(shift) < CircadianConfig.travelMinimumShiftHours, let homeLongitude, let currentLongitude {
            var dLon = currentLongitude - homeLongitude
            if dLon > 180 { dLon -= 360 }
            if dLon < -180 { dLon += 360 }
            if abs(dLon) >= CircadianConfig.travelLongitudeShiftDegrees { shift = (dLon / 15).rounded() }
        }
        guard abs(shift) >= CircadianConfig.travelMinimumShiftHours else { return nil }
        if let existing, existing.shiftHours == shift { return existing }
        return TravelState(shiftHours: shift, detectedAt: now)
    }
}
