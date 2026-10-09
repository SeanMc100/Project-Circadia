import Foundation

struct Insight: Identifiable, Hashable {
    enum Tone: Hashable { case favorable, unfavorable, neutral }

    let id: String
    let headline: String
    let detail: String
    /// Small print: sample sizes and the association caveat.
    let sampleNote: String
    let tone: Tone
    let mechanismKey: MechanismKey?
}

struct InsightsResult: Equatable {
    enum Status: Equatable {
        case notEnoughData(daysHave: Int, daysNeeded: Int)
        case ready
    }

    var status: Status
    var insights: [Insight]

    static let empty = InsightsResult(status: .notEnoughData(daysHave: 0, daysNeeded: CircadianConfig.insightsMinimumDays), insights: [])
}

/// Whether a persisted recommendation was followed, for closed-loop comparisons.
struct RecommendationOutcome: Hashable {
    let kind: RecommendationKind
    let day: Date
    let followed: Bool
}

/// Simple within-person comparisons. Associations only, never guarantees; each group needs a
/// minimum number of observations before anything is shown.
enum InsightsEngine {

    static func compute(days: [DayMetrics], outcomes: [RecommendationOutcome],
                        targetWakeMinutes: Double, calendar: Calendar = .current) -> InsightsResult {
        let nightCount = days.filter { $0.night != nil }.count
        guard nightCount >= CircadianConfig.insightsMinimumDays else {
            return InsightsResult(status: .notEnoughData(daysHave: nightCount, daysNeeded: CircadianConfig.insightsMinimumDays), insights: [])
        }
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        /// Sleep onset of the night that follows `day` (ending the next morning).
        func nextOnset(_ day: Date) -> Double? {
            calendar.date(byAdding: .day, value: 1, to: day).flatMap { byDay[$0]?.onsetMinutes }
        }

        var insights: [Insight] = []

        if days.contains(where: \.hasLightData) {
            // Early outdoor light vs not.
            var early: [Double] = [], notEarly: [Double] = []
            for d in days where d.night != nil && d.hasLightData {
                guard let onset = nextOnset(d.day) else { continue }
                if let first = d.light.firstLightAfterWakeMinutes, first <= CircadianConfig.earlyLightThresholdMinutes {
                    early.append(onset)
                } else {
                    notEarly.append(onset)
                }
            }
            if let i = onsetInsight(id: "earlyLight", withGroup: early, withoutGroup: notEarly,
                                    condition: "you got outdoor light within \(Int(CircadianConfig.earlyLightThresholdMinutes)) minutes of waking",
                                    favorableHeadline: "Earlier light, earlier sleep",
                                    groupNames: ("with early light", "without"), mechanism: .melatoninTiming) {
                insights.append(i)
            }

            // Enough light before noon vs not.
            var enough: [Double] = [], notEnough: [Double] = []
            for d in days where d.hasLightData {
                guard let onset = nextOnset(d.day) else { continue }
                if d.metLightGoal { enough.append(onset) } else { notEnough.append(onset) }
            }
            if let i = onsetInsight(id: "lightAmount", withGroup: enough, withoutGroup: notEnough,
                                    condition: "you met the morning light goal (outdoors before noon)",
                                    favorableHeadline: "More morning light, earlier sleep",
                                    groupNames: ("goal met", "goal missed"), mechanism: .lightAndSCN) {
                insights.append(i)
            }
        }

        if let i = wakeAnchorInsight(days: days, targetWakeMinutes: targetWakeMinutes, nextOnset: nextOnset) {
            insights.append(i)
        }

        // Followed nudges vs not.
        for kind in [RecommendationKind.morningLight, .windDown, .caffeineCutoff] {
            let relevant = outcomes.filter { $0.kind == kind }
            let followed = relevant.filter(\.followed).compactMap { nextOnset(calendar.startOfDay(for: $0.day)) }
            let notFollowed = relevant.filter { !$0.followed }.compactMap { nextOnset(calendar.startOfDay(for: $0.day)) }
            if let i = onsetInsight(id: "followed-\(kind.rawValue)", withGroup: followed, withoutGroup: notFollowed,
                                    condition: "you followed the \(kind.title.lowercased()) suggestion",
                                    favorableHeadline: "\(kind.title) suggestions seem to help",
                                    groupNames: ("followed", "not followed"), mechanism: nil) {
                insights.append(i)
            }
        }

        return InsightsResult(status: .ready, insights: insights)
    }

    /// Compares median sleep onset between two groups. Positive difference = group A fell asleep earlier.
    static func onsetInsight(id: String, withGroup a: [Double], withoutGroup b: [Double],
                             condition: String, favorableHeadline: String,
                             groupNames: (String, String), mechanism: MechanismKey?) -> Insight? {
        let minimum = CircadianConfig.insightsMinimumPerGroup
        guard a.count >= minimum, b.count >= minimum else { return nil }
        let unwrapped = ClockMath.unwrap(a + b)
        guard let medianA = ClockMath.median(Array(unwrapped.prefix(a.count))),
              let medianB = ClockMath.median(Array(unwrapped.suffix(b.count))) else { return nil }
        let diff = medianB - medianA
        let note = "Based on \(a.count) days \(groupNames.0) vs \(b.count) \(groupNames.1)."
        let threshold = CircadianConfig.insightMeaningfulDifferenceMinutes
        let amount = ClockMath.durationString(diff)

        if diff >= threshold {
            return Insight(id: id, headline: favorableHeadline,
                           detail: "On days \(condition), you fell asleep about \(amount) earlier that night (median).",
                           sampleNote: note, tone: .favorable, mechanismKey: mechanism)
        } else if diff <= -threshold {
            return Insight(id: id, headline: "No earlier sleep yet",
                           detail: "On days \(condition), you actually fell asleep about \(amount) later that night (median). Other things on those days may be playing a part.",
                           sampleNote: note, tone: .unfavorable, mechanismKey: mechanism)
        } else {
            return Insight(id: id, headline: "About the same so far",
                           detail: "Sleep onset was within \(Int(threshold)) minutes whether or not \(condition).",
                           sampleNote: note, tone: .neutral, mechanismKey: mechanism)
        }
    }

    /// Days with an on-target wake vs not: how close that night's bedtime landed to the usual.
    static func wakeAnchorInsight(days: [DayMetrics], targetWakeMinutes: Double, nextOnset: (Date) -> Double?) -> Insight? {
        let allOnsets = days.compactMap(\.onsetMinutes)
        guard let usualOnset = ClockMath.circularMedian(allOnsets) else { return nil }
        var onTarget: [Double] = [], offTarget: [Double] = []
        for d in days {
            guard let wake = d.wakeMinutes, let onset = nextOnset(d.day) else { continue }
            let deviation = abs(ClockMath.wrapSigned(onset - usualOnset))
            if abs(ClockMath.wrapSigned(wake - targetWakeMinutes)) <= CircadianConfig.wakeOnTargetToleranceMinutes {
                onTarget.append(deviation)
            } else {
                offTarget.append(deviation)
            }
        }
        let minimum = CircadianConfig.insightsMinimumPerGroup
        guard onTarget.count >= minimum, offTarget.count >= minimum,
              let a = ClockMath.median(onTarget), let b = ClockMath.median(offTarget) else { return nil }
        let note = "Based on \(onTarget.count) on-target wake days vs \(offTarget.count) others."
        let tol = Int(CircadianConfig.wakeOnTargetToleranceMinutes)
        let detail = "After days you woke within \(tol) minutes of your \(ClockMath.clockString(targetWakeMinutes)) target, your bedtime that night was typically within \(Int(a.rounded())) min of your usual, vs \(Int(b.rounded())) min on other days."
        let tone: Insight.Tone = b - a >= CircadianConfig.insightMeaningfulDifferenceMinutes ? .favorable
            : (a - b >= CircadianConfig.insightMeaningfulDifferenceMinutes ? .unfavorable : .neutral)
        let headline = tone == .favorable ? "A steady wake time steadies bedtime" : "Wake time and bedtime"
        return Insight(id: "wakeAnchor", headline: headline, detail: detail, sampleNote: note, tone: tone, mechanismKey: .consistency)
    }
}
