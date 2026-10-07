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
