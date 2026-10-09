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

    /// How far back we read HealthKit data (days). Must cover the 1-year trends range plus the
    /// 28-day social-jetlag window used at the start of that range.
    static let healthLookbackDays = 400

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

    // MARK: - Score history

    /// Days of data fed to each historical score (comfortably more than the baseline window needs).
    static let scoreHistorySliceDays = 30
    /// Window for the smoothed score trend and for best/worst stretches.
    static let scoreTrendWindowDays = 7
    /// A smoothed value needs at least this many scored days in its window.
    static let scoreTrendMinimumDays = 4
    /// Score bands shown as a word under the number on Today.
    static let strongScoreThreshold = 75
    static let fairScoreThreshold = 50

    // MARK: - Morning light scoring

    /// Full timing credit if first outdoor light comes within this many minutes of waking...
    static let morningLightFullCreditMinutes: Double = 60
    /// ...decaying linearly to zero credit at this many minutes.
    static let morningLightZeroCreditMinutes: Double = 180
    /// Outdoor minutes before noon are credited to the nearest this many minutes, since the Watch
    /// misses some time outside (a sleeve over the sensor, an arm in a pocket, shade).
    static let lightCreditRoundingMinutes: Double = 5
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
    /// The morning goal (outdoor minutes before noon) by sky condition. The score, the card, the wake
    /// notification and the forecast all use it. Outdoors is far brighter than indoors in all cases.
    static let lightMinutesClear: Double = 10
    static let lightMinutesPartlyCloudy: Double = 15
    static let lightMinutesOvercast: Double = 25
    static let lightMinutesUnknownSky: Double = 15
    static let clearSkyMaxCloudCover: Double = 0.3
    static let overcastMinCloudCover: Double = 0.7
    /// Morning goals are kept this many days, for the score history.
    static let morningGoalHistoryDays = 90

    // MARK: - Recommendations: other kinds

    /// Start dimming this long before target bedtime. Consensus guidance (Brown et al., 2022) is
    /// dim evening light from at least 3 h before bed.
    static let windDownLeadMinutes: Double = 180
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

    /// If wake comes at least this long before sunrise, start with bright indoor light (or a light box)
    /// and go outside once it's light.
    static let preSunriseWakeMinutes: Double = 20

    // MARK: - Habits

    /// "Want to start" habits are capped so the user focuses on a few at a time.
    static let maxFocusHabits = 3
    static let alcoholCutoffMinutes: Double = 180
    static let lastMealMinutes: Double = 150
    static let screensDownMinutes: Double = 60
    static let hardExerciseCutoffMinutes: Double = 60
    /// Naps should end at least this long before bed (and stay short).
    static let napLatestBeforeBedMinutes: Double = 480
    static let napMaxMinutes: Double = 30
    /// The morning check-in about last night stays on Today until this hour.
    static let checkInVisibleUntilHour = 16

    // MARK: - Sleep log (no wearable)

    /// A logged night longer than this is rejected as a likely typo.
    static let sleepLogMaximumMinutes: Double = 16 * 60
    /// Pre-filled times look back this far for a night of the same kind (workday or free day).
    static let sleepLogGuessLookbackDays = 14
    /// Pre-filled times are rounded to this many minutes.
    static let sleepLogRoundingMinutes: Double = 5
    /// If the guessed bedtime is too close to an early wake, assume this much sleep instead.
    static let sleepLogFallbackHours: Double = 8
    /// The "Log last night?" notification fires this long after the guessed wake.
    static let sleepLogReminderDelayMinutes: Double = 30
    /// The Focus widget asks about last night from this long before the guessed wake.
    static let sleepLogWidgetLeadMinutes: Double = 60
    /// Choices offered after Done on a light card when there's no light sensor (minutes).
    static let reportedLightChoices: [Double] = [10, 20, 30]
    /// A check-in "yes" to morning light is recorded as starting this long after wake.
    static let checkInLightOffsetMinutes: Double = 30

    // MARK: - Light Check (camera light meter)

    /// Illuminance ≈ this × 2^EV100 for an average scene. Tune per device class from the
    /// validation in docs/light-check-validation.md.
    static let lightMeterCalibration: Double = 2.5
    /// Camera readings are good to about ±1 EV (a factor of 2); shown as a range.
    static let lightMeterUncertaintyFactor: Double = 2
    /// Readings are the median of this many recent samples (4 per second).
    static let lightMeterSmoothingSamples = 8
    /// Band thresholds in melanopic EDI (Brown et al. 2022: ≤10 evening, ≥250 daytime).
    static let lightBandIndoor: Double = 10
    static let lightBandBrightIndoor: Double = 250
    static let lightBandOutdoor: Double = 1_000
    static let lightBandSunlit: Double = 10_000
    /// Melanopic daylight efficacy ratio for typical sources by colour temperature (approximate).
    static let melanopicRatioByKelvin: [(kelvin: Double, ratio: Double)] = [
        (2_000, 0.30), (2_700, 0.45), (3_000, 0.50), (4_000, 0.65), (5_000, 0.80), (6_500, 1.00), (10_000, 1.15),
    ]
    /// Used when the colour temperature isn't known: assume a neutral source.
    static let melanopicRatioUnknown: Double = 0.65
    /// Melanopic weights on linear sRGB (D65 white = 1, 1, 1): ratio ≈ weights · rgb ÷ luminance.
    /// Fitted to blackbody, white-LED, coloured-LED and mixed spectra against the CIE S 026 melanopic
    /// curve. Within about 1.4× for white, warm, cool and mixed light; near zero for red. Sum is 1 so
    /// daylight-white reads 1. See docs/light-check-validation.md.
    static let melanopicRGBWeights: (r: Double, g: Double, b: Double) = (-0.019, 0.337, 0.682)
    /// Upper limit on the ratio from colour (very saturated blue clips the camera, so it can't go higher reliably).
    static let melanopicRatioMax: Double = 8
    /// How far from the white (blackbody) line a light can be and still count as white (CIE 1960 Δuv).
    static let lightColourWhiteDuv: Double = 0.02
    /// Below this saturation (0–1, on gamma-encoded sRGB) a red-hued light isn't red: anything with a little
    /// green or white mixed in reads as amber, or pink toward magenta. Tested on a smart bulb: pure red read
    /// 0.99, while orange-reds and corals that look amber read 0.77–0.87.
    static let lightColourRedMinSaturation: Double = 0.92
    /// Light Check measures colour with the white balance locked to this daylight setting (kelvin).
    static let lightMeterLockedWhiteBalanceKelvin: Float = 6_500
    /// Pixels with any channel at or above this 8-bit value are clipped and left out of the colour.
    static let lightMeterClippedPixelLevel: UInt8 = 250
    /// An average scene reflects about 18% of the light falling on it; plain white paper about 85%.
    /// White-paper mode rescales the calibration by the ratio, turning the reading into light falling on you.
    static let lightMeterSceneReflectance: Double = 0.18
    static let lightMeterPaperReflectance: Double = 0.85
    /// White-paper mode: brightness varying more than this across the centre (coefficient of variation)
    /// means the paper probably isn't filling the frame.
    static let lightMeterPaperMaxVariation: Double = 0.25
    /// How close to the camera's exposure limits counts as "at the limit" (fraction).
    static let lightMeterLimitTolerance: Double = 0.05

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
