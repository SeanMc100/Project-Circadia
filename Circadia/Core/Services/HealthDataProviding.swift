import Foundation

enum HealthSourceKind: String {
    case healthKit, mock
}

enum HealthAuthorizationState: Equatable {
    case unavailable
    case notRequested
    /// iOS never reveals whether *read* access was granted, only that the prompt was shown.
    case requested
    case demo

    var label: String {
        switch self {
        case .unavailable: "Health data isn't available on this device"
        case .notRequested: "Not connected yet"
        case .requested: "Requested. iOS doesn't reveal read access, so if data is missing, check Health › Sharing › Apps"
        case .demo: "Using synthetic demo data"
        }
    }
}

/// Every view and engine sees health data only through this protocol, so real HealthKit and
/// the synthetic demo provider are interchangeable.
@MainActor
protocol HealthDataProviding: AnyObject {
    var sourceKind: HealthSourceKind { get }
    var isAvailable: Bool { get }
    func authorizationState() async -> HealthAuthorizationState
    func requestAuthorization() async throws
    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample]
    func daylightSamples(from start: Date, to end: Date) async throws -> [DaylightSample]
    func secondarySamples(_ metric: SecondaryMetric, from start: Date, to end: Date) async throws -> [MetricSample]
    /// Call `onChange` whenever new relevant data arrives (including in the background, where permitted).
    func startObserving(onChange: @escaping @MainActor () -> Void)
}
