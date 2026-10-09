import Foundation

/// This morning's score and what moved it since yesterday, one line per component.
struct ScoreRecap: Equatable, Sendable {
    struct Factor: Identifiable, Equatable, Sendable {
        var id: ScoreComponentKind { kind }
        let kind: ScoreComponentKind
        let text: String
        /// Points this component added (or cost) since yesterday. The factors add up to `change`.
        let points: Int

        var systemImage: String {
            switch kind {
            case .consistency: "repeat"
            case .morningLight: "sunrise.fill"
            case .drift: "bed.double.fill"
            }
        }
    }

    /// The day whose morning this recaps.
    let day: Date
    let score: Int
    /// Yesterday's score (or the last day that had one). Nil for the very first score.
    let previous: Int?
    /// Biggest effect first. Empty when there's nothing to compare with.
    let factors: [Factor]

    var change: Int? { previous.map { score - $0 } }
}

/// Explains the change in score since the previous day. Pure; unit-testable.
enum ScoreRecapBuilder {

    /// A recap once last night's sleep is in and there's a score. Nil otherwise.
    static func make(snapshot: CircadianSnapshot, history: [ScorePoint], now: Date, calendar: Calendar = .current,
                     weights: ScoreWeights = CircadianConfig.defaultWeights) -> ScoreRecap? {
        let today = calendar.startOfDay(for: now)
        guard let score = snapshot.score, let night = snapshot.latestNight,
              calendar.isDate(night.wakeDay, inSameDayAs: today) else { return nil }
        guard let previous = history.last(where: { $0.day < today }) else {
            return ScoreRecap(day: today, score: score.value, previous: nil, factors: [])
        }

        // Each component's points = its normalised weight × its value. The same split applied to
        // yesterday's components gives a per-component change that sums to the total change.
        let available = ScoreComponentKind.allCases.filter { previous.components[$0] != nil }
        let previousTotalWeight = available.reduce(0) { $0 + weights.weight(for: $1) }
        var deltas: [ScoreComponentKind: Double] = [:]
        for component in score.components {
            let now = component.weight * (component.value ?? 0) * 100
            var before = 0.0
            if let value = previous.components[component.kind], previousTotalWeight > 0 {
                before = weights.weight(for: component.kind) / previousTotalWeight * value * 100
            }
            guard component.value != nil || previous.components[component.kind] != nil else { continue }
            deltas[component.kind] = now - before
        }
        let points = ScoreForecaster.roundedKeepingTotal(deltas, total: score.value - previous.value)

        let factors = deltas.keys.compactMap { kind -> ScoreRecap.Factor? in
            guard let text = text(for: kind, snapshot: snapshot, previous: previous, calendar: calendar) else { return nil }
            return ScoreRecap.Factor(kind: kind, text: text, points: points[kind] ?? 0)
        }
        .sorted { (abs($0.points), $1.kind.order) > (abs($1.points), $0.kind.order) }

        return ScoreRecap(day: today, score: score.value, previous: previous.value, factors: factors)
    }

    // MARK: - Wording

    private static func text(for kind: ScoreComponentKind, snapshot: CircadianSnapshot, previous: ScorePoint,
                             calendar: Calendar) -> String? {
        func m(_ v: Double) -> String { "\(Int(v.rounded())) min" }
        switch kind {
        case .drift:
            guard let night = snapshot.latestNight?.primary else { return nil }
            let times = "Asleep \(ClockMath.timeString(night.onset)), up \(ClockMath.timeString(night.wake))"
            guard let drift = snapshot.drift else { return times }
            if abs(drift) <= CircadianConfig.driftPerfectMinutes { return "\(times), right on your usual timing" }
            return "\(times), about \(ClockMath.durationString(drift)) \(drift > 0 ? "later" : "earlier") than usual"
        case .consistency:
            guard let sd = snapshot.consistencySD else { return nil }
            let base = "Bed and wake times vary ±\(m(sd)) over \(CircadianConfig.consistencyWindowNights) nights"
            guard let before = previous.consistencySD, abs(before - sd) >= 1 else { return base }
            return "\(base) (was ±\(m(before)))"
        case .morningLight:
            guard let light = snapshot.morningLight else {
                return previous.components[.morningLight] != nil ? "No outdoor-light data for this morning" : nil
            }
            let when = light.isToday ? "This morning" : "Yesterday"
            if light.minutesBeforeNoon < 1 { return "\(when): no outdoor light before noon" }
            var text = "\(when): \(m(light.minutesBeforeNoon)) outside before noon"
            if let first = light.firstLightMinutes {
                text += ", first light \(ClockMath.durationString(first)) after waking"
            }
            return text
        }
    }
}

private extension ScoreComponentKind {
    /// Tie-break order: sleep timing first.
    var order: Int {
        switch self {
        case .drift: 0
        case .consistency: 1
        case .morningLight: 2
        }
    }
}
