import Foundation
import Observation

/// Where sleep timing comes from.
enum TrackingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Apple Watch, another tracker or a sleep app, read from Apple Health.
    case wearable
    /// The user logs each night in the app.
    case phoneOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wearable: "From a wearable"
        case .phoneOnly: "I'll log it"
        }
    }
}

/// User preferences and small pieces of app state, persisted in UserDefaults.
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) } }
    var useMockData: Bool { didSet { defaults.set(useMockData, forKey: Keys.mock) } }
    var trackingMode: TrackingMode { didSet { defaults.set(trackingMode.rawValue, forKey: Keys.trackingMode) } }
    /// When the user switched to logging sleep; nights before this are never asked about.
    var phoneOnlySince: Date? { didSet { defaults.set(phoneOnlySince, forKey: Keys.phoneOnlySince) } }
    /// Wake days whose sleep-log question the user dismissed ("Not sure"). Only the last week is kept.
    var sleepLogSkippedDays: [Date] { didSet { defaults.set(sleepLogSkippedDays, forKey: Keys.sleepLogSkippedDays) } }
    /// The morning "Log last night?" notification (phone-only mode).
    var sleepLogReminderEnabled: Bool { didSet { defaults.set(sleepLogReminderEnabled, forKey: Keys.sleepLogReminder) } }
    /// Answers to "Your usual sleep" (phone-only onboarding). Gives a provisional baseline.
    var usualSleep: UsualSleep? { didSet { save(usualSleep, forKey: Keys.usualSleep) } }

    /// Minutes after midnight, 0..<1440.
    var targetWakeMinutes: Double { didSet { defaults.set(targetWakeMinutes, forKey: Keys.targetWake) } }
    /// Minutes after midnight, 0..<1440 (e.g. 30 = 12:30 AM).
    var targetBedMinutes: Double { didSet { defaults.set(targetBedMinutes, forKey: Keys.targetBed) } }
    /// False until the user picks targets; until then targets follow the detected baseline.
    var targetsAreCustom: Bool { didSet { defaults.set(targetsAreCustom, forKey: Keys.targetsCustom) } }

    var caffeineCutoffHours: Double { didSet { defaults.set(caffeineCutoffHours, forKey: Keys.caffeine) } }

    var enabledNudgeKinds: Set<RecommendationKind> {
        didSet { defaults.set(enabledNudgeKinds.map(\.rawValue), forKey: Keys.enabledNudges) }
    }
    var quietStartMinutes: Double { didSet { defaults.set(quietStartMinutes, forKey: Keys.quietStart) } }
    var quietEndMinutes: Double { didSet { defaults.set(quietEndMinutes, forKey: Keys.quietEnd) } }
    /// Consecutive dismissals per nudge kind (reset when a nudge is opened or acted on).
    var dismissalCounts: [String: Int] { didSet { defaults.set(dismissalCounts, forKey: Keys.dismissals) } }

    var weights: ScoreWeights { didSet { save(weights, forKey: Keys.weights) } }

    var homeTimeZoneID: String? { didSet { defaults.set(homeTimeZoneID, forKey: Keys.homeTZ) } }
    var homeLongitude: Double? { didSet { defaults.set(homeLongitude, forKey: Keys.homeLongitude) } }
    var travelState: TravelState? { didSet { save(travelState, forKey: Keys.travel) } }

    var locationSkipped: Bool { didSet { defaults.set(locationSkipped, forKey: Keys.locationSkipped) } }

    /// The user's answer per habit. Missing means not chosen (inactive).
    var habitStatuses: [HabitKey: HabitStatus] {
        didSet {
            defaults.set(Dictionary(uniqueKeysWithValues: habitStatuses.map { ($0.key.rawValue, $0.value.rawValue) }),
                         forKey: Keys.habits)
        }
    }
    /// When habits were first chosen; the morning check-in only asks about nights after this.
    var habitsChosenAt: Date? { didSet { defaults.set(habitsChosenAt, forKey: Keys.habitsChosenAt) } }
    /// The last day the morning recap opened by itself (it opens once a day).
    var lastRecapDay: Date? { didSet { defaults.set(lastRecapDay, forKey: Keys.lastRecapDay) } }
    /// Each morning's light goal, keyed "yyyy-MM-dd" (see `MorningLightGoal.key`).
    var morningLightGoals: [String: MorningLightGoal] { didSet { save(morningLightGoals, forKey: Keys.morningLightGoals) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        #if DEBUG
        let mockDefault = true
        #else
        let mockDefault = false
        #endif
        useMockData = defaults.object(forKey: Keys.mock) as? Bool ?? mockDefault
        trackingMode = defaults.string(forKey: Keys.trackingMode).flatMap(TrackingMode.init(rawValue:)) ?? .wearable
        phoneOnlySince = defaults.object(forKey: Keys.phoneOnlySince) as? Date
        sleepLogSkippedDays = defaults.array(forKey: Keys.sleepLogSkippedDays) as? [Date] ?? []
        sleepLogReminderEnabled = defaults.object(forKey: Keys.sleepLogReminder) as? Bool ?? true
        usualSleep = Self.load(UsualSleep.self, from: defaults, forKey: Keys.usualSleep)
        targetWakeMinutes = defaults.object(forKey: Keys.targetWake) as? Double ?? CircadianConfig.defaultTargetWakeMinutes
        targetBedMinutes = defaults.object(forKey: Keys.targetBed) as? Double ?? CircadianConfig.defaultTargetBedMinutes
        targetsAreCustom = defaults.bool(forKey: Keys.targetsCustom)
        caffeineCutoffHours = defaults.object(forKey: Keys.caffeine) as? Double ?? CircadianConfig.defaultCaffeineCutoffHours
        if let raw = defaults.stringArray(forKey: Keys.enabledNudges) {
            enabledNudgeKinds = Set(raw.compactMap(RecommendationKind.init(rawValue:)))
        } else {
            enabledNudgeKinds = Set(RecommendationKind.notifiableKinds)
        }
        quietStartMinutes = defaults.object(forKey: Keys.quietStart) as? Double ?? CircadianConfig.defaultQuietStartMinutes
        quietEndMinutes = defaults.object(forKey: Keys.quietEnd) as? Double ?? CircadianConfig.defaultQuietEndMinutes
        dismissalCounts = defaults.dictionary(forKey: Keys.dismissals) as? [String: Int] ?? [:]
        weights = Self.load(ScoreWeights.self, from: defaults, forKey: Keys.weights) ?? CircadianConfig.defaultWeights
        homeTimeZoneID = defaults.string(forKey: Keys.homeTZ)
        homeLongitude = defaults.object(forKey: Keys.homeLongitude) as? Double
        travelState = Self.load(TravelState.self, from: defaults, forKey: Keys.travel)
        locationSkipped = defaults.bool(forKey: Keys.locationSkipped)
        lastRecapDay = defaults.object(forKey: Keys.lastRecapDay) as? Date
        morningLightGoals = Self.load([String: MorningLightGoal].self, from: defaults, forKey: Keys.morningLightGoals) ?? [:]
        if let raw = defaults.dictionary(forKey: Keys.habits) as? [String: String] {
            habitStatuses = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                guard let habit = HabitKey(rawValue: key), let status = HabitStatus(rawValue: value) else { return nil }
                return (habit, status)
            })
            habitsChosenAt = defaults.object(forKey: Keys.habitsChosenAt) as? Date
        } else if defaults.bool(forKey: Keys.onboarding) {
            // Set up before habits existed: keep the four core cards they already had.
            habitStatuses = HabitCatalog.legacyDefaults
            habitsChosenAt = .distantPast
        } else {
            habitStatuses = [:]
            habitsChosenAt = nil
        }
    }

    // MARK: - Habits

    func status(for habit: HabitKey) -> HabitStatus? { habitStatuses[habit] }

    // MARK: - Sleep log

    func isSleepLogSkipped(_ day: Date, calendar: Calendar = .current) -> Bool {
        sleepLogSkippedDays.contains { calendar.isDate($0, inSameDayAs: day) }
    }

    func skipSleepLog(_ day: Date, calendar: Calendar = .current) {
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: day) ?? day
        sleepLogSkippedDays = sleepLogSkippedDays.filter { $0 > weekAgo } + [calendar.startOfDay(for: day)]
    }

    var focusHabitCount: Int { habitStatuses.values.filter { $0 == .wantToStart }.count }

    var timing: HabitTiming {
        HabitTiming(wakeMinutes: targetWakeMinutes, bedMinutes: targetBedMinutes, caffeineCutoffHours: caffeineCutoffHours)
    }

    // MARK: - Morning light goals

    func morningLightGoal(for day: Date, calendar: Calendar = .current) -> MorningLightGoal? {
        morningLightGoals[MorningLightGoal.key(for: day, calendar: calendar)]
    }

    /// Stores a day's goal and drops goals older than the score history needs.
    func setMorningLightGoal(_ goal: MorningLightGoal, for day: Date, calendar: Calendar = .current) {
        let key = MorningLightGoal.key(for: day, calendar: calendar)
        guard morningLightGoals[key] != goal else { return }
        let oldest = calendar.date(byAdding: .day, value: -CircadianConfig.morningGoalHistoryDays, to: day) ?? day
        let cutoff = MorningLightGoal.key(for: oldest, calendar: calendar)
        var goals = morningLightGoals.filter { $0.key >= cutoff }
        goals[key] = goal
        morningLightGoals = goals
    }

    // MARK: - Nudge back-off

    func dismissals(for kind: RecommendationKind) -> Int { dismissalCounts[kind.rawValue] ?? 0 }

    func recordDismissal(_ kind: RecommendationKind) {
        dismissalCounts[kind.rawValue, default: 0] += 1
    }

    func resetDismissals(_ kind: RecommendationKind) {
        dismissalCounts[kind.rawValue] = 0
    }

    var backedOffKinds: [RecommendationKind] {
        RecommendationKind.notifiableKinds.filter { dismissals(for: $0) >= CircadianConfig.dismissalsBeforeBackoff }
    }

    var consecutiveDismissals: [RecommendationKind: Int] {
        Dictionary(uniqueKeysWithValues: RecommendationKind.allCases.map { ($0, dismissals(for: $0)) })
    }

    // MARK: - Reset

    /// Restores defaults and clears onboarding. Demo mode keeps its build default.
    func resetAll() {
        for key in Keys.all { defaults.removeObject(forKey: key) }
        let fresh = AppSettings(defaults: defaults)
        hasCompletedOnboarding = fresh.hasCompletedOnboarding
        useMockData = fresh.useMockData
        trackingMode = .wearable
        phoneOnlySince = nil
        sleepLogSkippedDays = []
        sleepLogReminderEnabled = true
        usualSleep = nil
        targetWakeMinutes = fresh.targetWakeMinutes
        targetBedMinutes = fresh.targetBedMinutes
        targetsAreCustom = false
        caffeineCutoffHours = fresh.caffeineCutoffHours
        enabledNudgeKinds = fresh.enabledNudgeKinds
        quietStartMinutes = fresh.quietStartMinutes
        quietEndMinutes = fresh.quietEndMinutes
        dismissalCounts = [:]
        weights = fresh.weights
        homeTimeZoneID = nil
        homeLongitude = nil
        travelState = nil
        locationSkipped = false
        habitStatuses = [:]
        habitsChosenAt = nil
        lastRecapDay = nil
        morningLightGoals = [:]
    }

    // MARK: - Persistence helpers

    private func save<T: Encodable>(_ value: T?, forKey key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private enum Keys {
        static let onboarding = "settings.onboardingComplete"
        static let mock = "settings.useMockData"
        static let trackingMode = "settings.trackingMode"
        static let phoneOnlySince = "settings.phoneOnlySince"
        static let sleepLogSkippedDays = "settings.sleepLogSkippedDays"
        static let sleepLogReminder = "settings.sleepLogReminder"
        static let usualSleep = "settings.usualSleep"
        static let targetWake = "settings.targetWake"
        static let targetBed = "settings.targetBed"
        static let targetsCustom = "settings.targetsCustom"
        static let caffeine = "settings.caffeineCutoffHours"
        static let enabledNudges = "settings.enabledNudges"
        static let quietStart = "settings.quietStart"
        static let quietEnd = "settings.quietEnd"
        static let dismissals = "settings.dismissals"
        static let weights = "settings.weights"
        static let homeTZ = "settings.homeTimeZone"
        static let homeLongitude = "settings.homeLongitude"
        static let travel = "settings.travelState"
        static let locationSkipped = "settings.locationSkipped"
        static let habits = "settings.habitStatuses"
        static let habitsChosenAt = "settings.habitsChosenAt"
        static let lastRecapDay = "settings.lastRecapDay"
        static let morningLightGoals = "settings.morningLightGoals"

        static let all = [onboarding, mock, trackingMode, phoneOnlySince, sleepLogSkippedDays, sleepLogReminder, usualSleep, targetWake, targetBed, targetsCustom, caffeine, enabledNudges,
                          quietStart, quietEnd, dismissals, weights, homeTZ, homeLongitude, travel, locationSkipped,
                          habits, habitsChosenAt, lastRecapDay, morningLightGoals]
    }
}
