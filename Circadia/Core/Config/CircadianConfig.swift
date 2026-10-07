import Foundation

/// Weights for the three components of the alignment estimate.
/// They do not need to sum to 1; they are normalised over whichever components are available.
struct ScoreWeights: Codable, Equatable, Sendable {
    var consistency: Double
    var morningLight: Double
    var drift: Double

    var total: Double { consistency + morningLight + drift }

    func weight(for component: ScoreComponentKind) -> Double {
        switch component {
        case .consistency: consistency
        case .morningLight: morningLight
        case .drift: drift
        }
    }
}

/// Every tunable number in the circadian model, recommendation engine and insights lives here.
/// Change values here rather than hunting through engines.
enum CircadianConfig {

    // MARK: - Data window

    /// How far back we read HealthKit data (days). Must cover the 90-day trends range plus the
    /// 28-day social-jetlag window used at the start of that range.
    static let healthLookbackDays = 120

    /// A new "day" starts at this hour for recommendations (so 1 AM still belongs to yesterday evening).
    static let dayRolloverHour = 4

    // MARK: - Sleep session assembly

    /// Asleep samples separated by less than this gap are treated as one session.
    static let sessionMergeGapMinutes: Double = 60
    /// The longest session ending on a day must be at least this long to count as the primary night.
    static let minimumPrimarySleepMinutes: Double = 180

    // MARK: - Baseline and consistency

    static let baselineWindowNights = 14
    static let baselineMinimumNights = 5
    static let consistencyWindowNights = 7
    static let consistencyMinimumNights = 3
    static let socialJetlagWindowDays = 28
    static let socialJetlagMinimumNightsPerGroup = 2
    /// A night counts toward the "in rhythm" streak if its midpoint is this close to baseline.
    static let streakToleranceMinutes: Double = 30

    // MARK: - Morning light scoring

    /// Full timing credit if first outdoor light comes within this many minutes of waking...
    static let morningLightFullCreditMinutes: Double = 60
    /// ...decaying linearly to zero credit at this many minutes.
    static let morningLightZeroCreditMinutes: Double = 180
    /// Target minutes of outdoor light before noon.
    static let morningLightTargetMinutes: Double = 20
    /// Share of the light component that comes from timing (the rest is amount before noon).
    static let morningLightTimingShare: Double = 0.5

    // MARK: - Score curves (linear between "perfect" and "zero")

    static let consistencyPerfectSDMinutes: Double = 15
    static let consistencyZeroSDMinutes: Double = 90
    static let driftPerfectMinutes: Double = 15
    static let driftZeroMinutes: Double = 120

    static let defaultWeights = ScoreWeights(consistency: 0.40, morningLight: 0.35, drift: 0.25)

    /// Score at or above which we reinforce rather than prescribe.
    static let alignedScoreThreshold = 75

    // MARK: - Recommendations: morning light

    /// Morning light window length after wake.
    static let morningLightWindowMinutes: Double = 120
    /// Minimum window length once the window has been pushed back to sunrise.
    static let morningLightMinimumWindowMinutes: Double = 60
    /// Show the card this long before the window opens.
    static let morningLightLeadMinutes: Double = 30
    /// Suggested outdoor minutes by sky condition. Outdoors is far brighter than indoors in all cases.
    static let lightMinutesClear: Double = 10
    static let lightMinutesPartlyCloudy: Double = 15
    static let lightMinutesOvercast: Double = 25
    static let lightMinutesUnknownSky: Double = 20
    static let clearSkyMaxCloudCover: Double = 0.3
    static let overcastMinCloudCover: Double = 0.7
    /// Auto-detect "followed" once this fraction of the suggested minutes is seen in the window.
    static let lightFollowedFraction: Double = 0.8

    // MARK: - Recommendations: other kinds

    /// Start winding down this long before target bedtime (2–3 h is typical).
    static let windDownLeadMinutes: Double = 150
    /// Show the wind-down card this long before it starts.
    static let windDownShowAheadMinutes: Double = 60
    static let defaultCaffeineCutoffHours: Double = 9
    static let caffeineCutoffRange: ClosedRange<Double> = 6...12
    /// Caffeine card becomes "soon" this long before the cutoff.
    static let caffeineSoonMinutes: Double = 90
    /// Social jetlag (or today's drift) above this triggers the "anchor your wake time" card.
    static let anchorWakeThresholdMinutes: Double = 60
    /// Tomorrow's wake should land within this many minutes of target.
    static let anchorWakeToleranceMinutes: Double = 60
    /// Morning light counts as "missed" below this fraction of the target.
    static let missedMorningLightFraction: Double = 0.5
    static let lateDayLightMinutes: Double = 30
    /// Late-day light must end at least this long before sunset...
    static let lateDayLightBeforeSunsetMinutes: Double = 60
    /// ...and at least this long before the wind-down starts.
    static let lateDayLightBeforeWindDownMinutes: Double = 60

    // MARK: - Travel

    /// Time-zone change (hours) that triggers travel mode.
    static let travelMinimumShiftHours: Double = 1
    /// Longitude change that triggers travel mode when the time zone did not change.
    static let travelLongitudeShiftDegrees: Double = 15
    /// How fast we plan to shift the clock per day.
    static let travelShiftPerDayHours: Double = 1
    /// For eastward shifts at least this large, start with late-morning light (see MechanismLibrary).
    static let travelLargeEastwardHours: Double = 8

    // MARK: - Notifications

    static let maxNudgesPerDay = 3
    /// Back off a nudge kind after this many consecutive dismissals.
    static let dismissalsBeforeBackoff = 2
    /// Caffeine nudge fires this long before the cutoff.
    static let caffeineNudgeLeadMinutes: Double = 30
    static let defaultQuietStartMinutes: Double = 22 * 60 + 30   // 10:30 PM
    static let defaultQuietEndMinutes: Double = 6 * 60 + 30      // 6:30 AM

    // MARK: - Insights

    static let insightsMinimumDays = 14
    static let insightsMinimumPerGroup = 4
    static let earlyLightThresholdMinutes: Double = 90
    /// Differences smaller than this are reported as "about the same".
    static let insightMeaningfulDifferenceMinutes: Double = 10
    static let wakeOnTargetToleranceMinutes: Double = 30

    // MARK: - Defaults and fallbacks

    static let defaultTargetWakeMinutes: Double = 7 * 60
    static let defaultTargetBedMinutes: Double = 23 * 60
    /// Used to estimate sun times when location is unavailable (longitude comes from the time zone).
    static let fallbackLatitude: Double = 40
    /// After WeatherKit fails, don't retry for this long.
    static let weatherKitRetryInterval: TimeInterval = 6 * 3600
    /// Demo mode: number of synthetic days.
    static let mockDays = 60
}
