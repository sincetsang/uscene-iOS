import Foundation
import CoreLocation
import Observation

@Observable
@MainActor
final class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    private let manager = CLLocationManager()
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var coordinate: CLLocationCoordinate2D?
    var lastError: String?
    private var lastHeartbeatAt: Date?
    private var isUpdating = false

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermissionAndLocate() {
        lastError = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            startUpdatingIfNeeded()
            manager.requestLocation()
        default:
            lastError = "Location permission denied"
            stopUpdating()
        }
    }

    func startUpdatingIfNeeded() {
        guard !isUpdating else { return }
        guard manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways else { return }
        isUpdating = true
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
    }

    private func reportHeartbeatIfNeeded(_ coordinate: CLLocationCoordinate2D) {
        guard AuthStore.shared.isLoggedIn else { return }
        if let lastHeartbeatAt, Date().timeIntervalSince(lastHeartbeatAt) < 60 {
            return
        }
        lastHeartbeatAt = Date()
        Task {
            try? await UserAPI.updateLatLng(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways {
                self.startUpdatingIfNeeded()
                manager.requestLocation()
            } else if manager.authorizationStatus == .denied
                        || manager.authorizationStatus == .restricted {
                self.stopUpdating()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.coordinate = location.coordinate
            self.reportHeartbeatIfNeeded(location.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // Ignore transient cancel / deferred errors from one-shot requests.
            if let clError = error as? CLError, clError.code == .locationUnknown {
                return
            }
            self.lastError = error.localizedDescription
        }
    }
}
