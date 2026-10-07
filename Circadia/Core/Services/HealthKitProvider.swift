import Foundation
import HealthKit

/// Read-only HealthKit access with anchored incremental sync and observer-driven updates.
@MainActor
final class HealthKitProvider: HealthDataProviding {
    let sourceKind: HealthSourceKind = .healthKit
    private let store = HKHealthStore()
    private var isObserving = false

    /// Incremental caches, keyed by sample UUID, updated via HKAnchoredObjectQuery.
    private var anchors: [String: HKQueryAnchor] = [:]
    private var sleepCache: [UUID: SleepSample] = [:]
    private var daylightCache: [UUID: DaylightSample] = [:]
    private var secondaryCache: [SecondaryMetric: [UUID: MetricSample]] = [:]
    /// The cache covers samples starting from this date; anything earlier forces a reset.
    private var cacheStart: Date?

    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let daylightType = HKQuantityType(.timeInDaylight)

    private func quantityType(_ metric: SecondaryMetric) -> HKQuantityType {
        switch metric {
        case .hrv: HKQuantityType(.heartRateVariabilitySDNN)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .wristTemperature: HKQuantityType(.appleSleepingWristTemperature)
        }
    }

    private func unit(_ metric: SecondaryMetric) -> HKUnit {
        switch metric {
        case .hrv: .secondUnit(with: .milli)
        case .restingHeartRate: .count().unitDivided(by: .minute())
        case .wristTemperature: .degreeCelsius()
        }
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [sleepType, daylightType]
        for metric in SecondaryMetric.allCases { types.insert(quantityType(metric)) }
        return types
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func authorizationState() async -> HealthAuthorizationState {
        guard isAvailable else { return .unavailable }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
        return status == .unnecessary ? .requested : .notRequested
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Queries

    private func ensureCacheCovers(_ start: Date) {
        if let cacheStart, cacheStart <= start { return }
        anchors = [:]
        sleepCache = [:]
        daylightCache = [:]
        secondaryCache = [:]
        cacheStart = start
    }

    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        guard isAvailable else { return [] }
        ensureCacheCovers(start)
        let predicate = HKQuery.predicateForSamples(withStart: cacheStart, end: nil)
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            anchor: anchors["sleep"])
        let result = try await descriptor.result(for: store)
        for deleted in result.deletedObjects { sleepCache[deleted.uuid] = nil }
        for sample in result.addedSamples {
            guard let stage = Self.stage(for: sample.value) else { continue }
            sleepCache[sample.uuid] = SleepSample(start: sample.startDate, end: sample.endDate, stage: stage,
                                                  sourceName: sample.sourceRevision.source.name,
                                                  isFromWatch: Self.isWatch(sample))
        }
        anchors["sleep"] = result.newAnchor
        return sleepCache.values.filter { $0.end > start && $0.start < end }
    }

    func daylightSamples(from start: Date, to end: Date) async throws -> [DaylightSample] {
        guard isAvailable else { return [] }
        ensureCacheCovers(start)
        let predicate = HKQuery.predicateForSamples(withStart: cacheStart, end: nil)
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: daylightType, predicate: predicate)],
            anchor: anchors["daylight"])
        let result = try await descriptor.result(for: store)
        for deleted in result.deletedObjects { daylightCache[deleted.uuid] = nil }
        for sample in result.addedSamples {
            daylightCache[sample.uuid] = DaylightSample(start: sample.startDate, end: sample.endDate,
                                                        minutes: sample.quantity.doubleValue(for: .minute()))
        }
        anchors["daylight"] = result.newAnchor
        return daylightCache.values.filter { $0.end > start && $0.start < end }
    }

    func secondarySamples(_ metric: SecondaryMetric, from start: Date, to end: Date) async throws -> [MetricSample] {
        guard isAvailable else { return [] }
        ensureCacheCovers(start)
        let predicate = HKQuery.predicateForSamples(withStart: cacheStart, end: nil)
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: quantityType(metric), predicate: predicate)],
            anchor: anchors[metric.rawValue])
        let result = try await descriptor.result(for: store)
        var cache = secondaryCache[metric] ?? [:]
        for deleted in result.deletedObjects { cache[deleted.uuid] = nil }
        let unit = unit(metric)
        for sample in result.addedSamples {
            cache[sample.uuid] = MetricSample(date: sample.endDate, value: sample.quantity.doubleValue(for: unit))
        }
        secondaryCache[metric] = cache
        anchors[metric.rawValue] = result.newAnchor
        return cache.values.filter { $0.date >= start && $0.date <= end }
    }

    // MARK: - Observation

    func startObserving(onChange: @escaping @MainActor () -> Void) {
        guard isAvailable, !isObserving else { return }
        isObserving = true
        for type in [sleepType as HKSampleType, daylightType as HKSampleType] {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                if error == nil {
                    Task { @MainActor in onChange() }
                }
                completion()
            }
            store.execute(query)
            // Requires the HealthKit background-delivery entitlement; harmless if unavailable.
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }

    // MARK: - Mapping

    static func stage(for value: Int) -> SleepStage? {
        guard let v = HKCategoryValueSleepAnalysis(rawValue: value) else { return nil }
        switch v {
        case .inBed: return .inBed
        case .asleepUnspecified: return .asleepUnspecified
        case .asleepCore: return .asleepCore
        case .asleepDeep: return .asleepDeep
        case .asleepREM: return .asleepREM
        case .awake: return .awake
        @unknown default: return nil
        }
    }

    static func isWatch(_ sample: HKSample) -> Bool {
        if let product = sample.sourceRevision.productType, product.hasPrefix("Watch") { return true }
        return sample.device?.model?.localizedCaseInsensitiveContains("watch") == true
    }
}
