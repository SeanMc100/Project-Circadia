import Foundation
import Observation

/// User preferences and small pieces of app state, persisted in UserDefaults.
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) } }
    var useMockData: Bool { didSet { defaults.set(useMockData, forKey: Keys.mock) } }

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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        #if DEBUG
        let mockDefault = true
        #else
        let mockDefault = false
        #endif
        useMockData = defaults.object(forKey: Keys.mock) as? Bool ?? mockDefault
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

        static let all = [onboarding, mock, targetWake, targetBed, targetsCustom, caffeine, enabledNudges,
                          quietStart, quietEnd, dismissals, weights, homeTZ, homeLongitude, travel, locationSkipped]
    }
}
