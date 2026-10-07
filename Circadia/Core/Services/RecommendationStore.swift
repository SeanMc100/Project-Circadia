import Foundation
import SwiftData

/// Persists prescribed recommendations, follow-through, and next-night outcomes.
@MainActor
final class RecommendationStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func record(id: String) -> RecommendationRecord? {
        var descriptor = FetchDescriptor<RecommendationRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func records(on day: Date) -> [RecommendationRecord] {
        let descriptor = FetchDescriptor<RecommendationRecord>(predicate: #Predicate { $0.day == day })
        return (try? context.fetch(descriptor)) ?? []
    }

    func allRecords() -> [RecommendationRecord] {
        let descriptor = FetchDescriptor<RecommendationRecord>(sortBy: [SortDescriptor(\.day)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Kinds the user already followed or skipped on `day` (so the engine doesn't re-suggest them).
    func resolvedKinds(on day: Date) -> Set<RecommendationKind> {
        Set(records(on: day).filter { $0.status == .followed || $0.status == .skipped }.compactMap(\.kind))
    }

    /// Inserts new recommendations, refreshes pending ones, auto-detects light follow-through,
    /// and expires pending records whose window has closed.
    /// - Returns: records that were newly auto-detected as followed during this sync.
    @discardableResult
    func sync(_ recommendations: [Recommendation], day: Date, daylight: [DaylightSample], hasDaylightData: Bool, now: Date) -> [RecommendationRecord] {
        for rec in recommendations where rec.kind != .maintenance {
            if let existing = record(id: rec.id) {
                if existing.status == .pending {
                    existing.title = rec.title
                    existing.windowStart = rec.trackingWindow?.start
                    existing.windowEnd = rec.trackingWindow?.end
                    if case .outdoorLight(let minutes, _) = rec.successCriteria { existing.requiredMinutes = minutes }
                }
            } else {
                context.insert(RecommendationRecord(recommendation: rec, day: day, now: now))
            }
        }

        var newlyFollowed: [RecommendationRecord] = []
        for record in records(on: day) where record.status == .pending {
            if hasDaylightData, record.criteriaRaw == "outdoorLight",
               let start = record.windowStart, let end = record.windowEnd, let required = record.requiredMinutes {
                let logged = DaylightAnalyzer.minutes(of: daylight, in: DateInterval(start: start, end: min(end, now)))
                if logged >= required * CircadianConfig.lightFollowedFraction {
                    record.status = .followed
                    record.detection = .automatic
                    record.completedAt = now
                    newlyFollowed.append(record)
                    continue
                }
            }
            if let end = record.windowEnd, end < now, record.criteriaRaw != "wakeNear" {
                record.status = .expired
            }
        }
        save()
        return newlyFollowed
    }

    func mark(id: String, status: RecommendationStatus, detection: FollowDetection?, at date: Date) {
        guard let record = record(id: id) else { return }
        record.status = status
        record.detection = detection
        record.completedAt = date
        save()
    }

    /// Fills next-night outcomes and judges wake-time anchors once the night is known.
    func fillOutcomes(nights: [NightRecord], calendar: Calendar = .current) {
        let byDay = Dictionary(nights.map { ($0.wakeDay, $0) }, uniquingKeysWith: { a, _ in a })
        for record in allRecords() {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: record.day),
                  let night = byDay[calendar.startOfDay(for: nextDay)] else { continue }
            if record.nextSleepOnset == nil {
                record.nextSleepOnset = night.primary.onset
                record.nextSleepMidpointMinutes = ClockMath.signedMinutes(night.primary.midpoint, calendar: calendar)
            }
            if record.criteriaRaw == "wakeNear", record.status == .pending,
               let start = record.windowStart, let end = record.windowEnd {
                record.status = (start...end).contains(night.primary.wake) ? .followed : .expired
                record.detection = .automatic
                record.completedAt = night.primary.wake
            }
        }
        save()
    }

    func outcomes() -> [RecommendationOutcome] {
        allRecords().compactMap { record in
            guard let kind = record.kind, record.status != .pending else { return nil }
            return RecommendationOutcome(kind: kind, day: record.day, followed: record.status == .followed)
        }
    }

    func deleteAll() {
        try? context.delete(model: RecommendationRecord.self)
        save()
    }

    private func save() {
        try? context.save()
    }
}
