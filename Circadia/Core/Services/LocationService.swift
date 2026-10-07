import CoreLocation
import Foundation
import Observation

/// Coarse, when-in-use location. The last fix is cached so sun times work immediately at launch.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var coordinate: Coordinate?
    @ObservationIgnored var onUpdate: (() -> Void)?
    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var authorizationContinuation: CheckedContinuation<Void, Never>?

    private static let cacheKey = "location.lastCoordinate"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let manager = CLLocationManager()
        self.manager = manager
        authorization = manager.authorizationStatus
        if let data = defaults.data(forKey: Self.cacheKey) {
            coordinate = try? JSONDecoder().decode(Coordinate.self, from: data)
        }
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var statusLabel: String {
        switch authorization {
        case .authorizedAlways, .authorizedWhenInUse: "Allowed (approximate)"
        case .denied: "Denied. Sun times are estimated from your time zone"
        case .restricted: "Restricted on this device"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    /// Asks for permission and waits for the user's answer.
    func requestPermission() async {
        guard authorization == .notDetermined else { refresh(); return }
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
        refresh()
    }

    func refresh() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    /// Without location: latitude from config, longitude from the time zone's standard offset.
    static func estimatedCoordinate(for timeZone: TimeZone = .current, at date: Date = Date()) -> Coordinate {
        let standardOffset = Double(timeZone.secondsFromGMT(for: date)) - timeZone.daylightSavingTimeOffset(for: date)
        return Coordinate(latitude: CircadianConfig.fallbackLatitude, longitude: standardOffset / 3600 * 15)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status != .notDetermined, let continuation = self.authorizationContinuation {
                self.authorizationContinuation = nil
                continuation.resume()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let coordinate = Coordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        Task { @MainActor in
            let changed = self.coordinate.map { abs($0.latitude - coordinate.latitude) > 0.2 || abs($0.longitude - coordinate.longitude) > 0.2 } ?? true
            self.coordinate = coordinate
            if let data = try? JSONEncoder().encode(coordinate) { self.defaults.set(data, forKey: Self.cacheKey) }
            if changed { self.onUpdate?() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the cached coordinate; sun times fall back to the time-zone estimate if there is none.
    }

    func clearCache() {
        defaults.removeObject(forKey: Self.cacheKey)
        coordinate = nil
    }
}
