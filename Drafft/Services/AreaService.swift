import CoreLocation
import Observation

/// What a profile shows for "where": an area (arrondissement or city), never a street.
struct Area: Hashable, Identifiable {
    let name: String      // "Lyon 4", "Paris 11", "Annecy"
    let city: String
    var id: String { name }
}

/// The contract with the backend. The app only ever sends a blurred position; the server
/// answers with an area name. Same answer on iOS, Android and web, and no street can leak.
protocol AreaResolving: Sendable {
    func area(for blurred: CLLocationCoordinate2D) async -> Area?
}

enum LocationPrivacy {
    /// Snap to the centre of a ~1 km grid cell before anything leaves the device.
    static func blur(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let step = 0.01 // about 1.1 km of latitude, 0.7 to 0.8 km of longitude in France
        return CLLocationCoordinate2D(latitude: (c.latitude / step).rounded(.down) * step + step / 2,
                                      longitude: (c.longitude / step).rounded(.down) * step + step / 2)
    }

    /// Distances are shown rounded, so they can't be triangulated back to a home.
    static func rounded(km: Double) -> String {
        km < 1 ? L("Less than 1 km") : L("\(Int(km.rounded())) km")
    }
}

/// The server's answer (`area_at`): the commune or arrondissement the blurred position falls in,
/// from official boundaries, so every app shows the same name without a geocoder. Offline, outside
/// France, or before the areas are loaded, the server has none: resolved on the device instead.
struct ServerAreaResolver: AreaResolving {
    private let fallback = OnDeviceAreaResolver()

    func area(for blurred: CLLocationCoordinate2D) async -> Area? {
        if let data = try? await Backend.shared.rpc("area_at", ["p_lat": blurred.latitude, "p_lng": blurred.longitude]),
           let found = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String: Any],
           let name = found["name"] as? String, let city = found["city"] as? String {
            return Area(name: name, city: city)
        }
        return await fallback.area(for: blurred)
    }
}

/// Resolved on the device, when the server has no answer: the arrondissements of Paris, Lyon and
/// Marseille are approximated by their centres, and any other place falls back to the city name
/// from the system geocoder, never the street.
struct OnDeviceAreaResolver: AreaResolving {
    private struct City { let name: String; let radiusKm: Double; let centres: [CLLocationCoordinate2D] }

    private static let cities: [City] = [
        City(name: "Paris", radiusKm: 3, centres: [
            .init(latitude: 48.8625, longitude: 2.3363), .init(latitude: 48.8683, longitude: 2.3428),
            .init(latitude: 48.8630, longitude: 2.3600), .init(latitude: 48.8543, longitude: 2.3576),
            .init(latitude: 48.8445, longitude: 2.3507), .init(latitude: 48.8491, longitude: 2.3328),
            .init(latitude: 48.8562, longitude: 2.3121), .init(latitude: 48.8727, longitude: 2.3125),
            .init(latitude: 48.8770, longitude: 2.3375), .init(latitude: 48.8761, longitude: 2.3607),
            .init(latitude: 48.8591, longitude: 2.3800), .init(latitude: 48.8406, longitude: 2.3877),
            .init(latitude: 48.8283, longitude: 2.3623), .init(latitude: 48.8292, longitude: 2.3265),
            .init(latitude: 48.8401, longitude: 2.2929), .init(latitude: 48.8637, longitude: 2.2769),
            .init(latitude: 48.8873, longitude: 2.3067), .init(latitude: 48.8925, longitude: 2.3484),
            .init(latitude: 48.8871, longitude: 2.3848), .init(latitude: 48.8634, longitude: 2.4012)]),
        City(name: "Lyon", radiusKm: 3, centres: [
            .init(latitude: 45.7699, longitude: 4.8292), .init(latitude: 45.7489, longitude: 4.8270),
            .init(latitude: 45.7597, longitude: 4.8506), .init(latitude: 45.7784, longitude: 4.8248),
            .init(latitude: 45.7563, longitude: 4.8030), .init(latitude: 45.7727, longitude: 4.8520),
            .init(latitude: 45.7337, longitude: 4.8398), .init(latitude: 45.7358, longitude: 4.8690),
            .init(latitude: 45.7757, longitude: 4.8047)]),
        City(name: "Marseille", radiusKm: 5, centres: [
            .init(latitude: 43.2999, longitude: 5.3846), .init(latitude: 43.3130, longitude: 5.3637),
            .init(latitude: 43.3122, longitude: 5.3834), .init(latitude: 43.3063, longitude: 5.4007),
            .init(latitude: 43.2926, longitude: 5.3979), .init(latitude: 43.2878, longitude: 5.3808),
            .init(latitude: 43.2839, longitude: 5.3602), .init(latitude: 43.2412, longitude: 5.3801),
            .init(latitude: 43.2505, longitude: 5.4400), .init(latitude: 43.2759, longitude: 5.4262),
            .init(latitude: 43.2878, longitude: 5.4832), .init(latitude: 43.3067, longitude: 5.4432),
            .init(latitude: 43.3496, longitude: 5.4318), .init(latitude: 43.3440, longitude: 5.3900),
            .init(latitude: 43.3584, longitude: 5.3634), .init(latitude: 43.3610, longitude: 5.3228)])
    ]

    /// Every arrondissement, for picking an area by hand.
    static var allAreas: [Area] {
        cities.flatMap { c in c.centres.indices.map { Area(name: "\(c.name) \($0 + 1)", city: c.name) } }
    }

    func area(for blurred: CLLocationCoordinate2D) async -> Area? {
        let here = CLLocation(latitude: blurred.latitude, longitude: blurred.longitude)
        var best: (area: Area, km: Double)?
        for city in Self.cities {
            for (i, c) in city.centres.enumerated() {
                let km = here.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) / 1000
                if km <= city.radiusKm, km < (best?.km ?? .infinity) {
                    best = (Area(name: "\(city.name) \(i + 1)", city: city.name), km)
                }
            }
        }
        if let best { return best.area }
        // Elsewhere: the city only. Street fields (name, thoroughfare) are never read.
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(here).first
        guard let city = placemark?.locality else { return nil }
        return Area(name: city, city: city)
    }
}

/// One-shot, reduced-accuracy location, asked only while the app is in use.
@MainActor
@Observable
final class AreaLocator: NSObject, CLLocationManagerDelegate {
    enum State: Equatable { case idle, locating, found(Area), denied, failed }

    private(set) var state: State = .idle
    /// The last position found, already blurred (~1 km): what may be sent to the server.
    private(set) var blurred: CLLocationCoordinate2D?
    /// Made on the first request: SwiftUI builds a view's `@State` default each time the view is
    /// re-created, so the locator itself must be cheap.
    @ObservationIgnored private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        return manager
    }()
    private let server: AreaResolving

    init(server: AreaResolving = ServerAreaResolver()) {
        self.server = server
        super.init()
    }

    func locate() {
        state = .locating
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: state = .denied
        default: manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard state == .locating else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: state = .denied
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        let blurred = LocationPrivacy.blur(c)
        Task { @MainActor in
            self.blurred = blurred
            if let area = await server.area(for: blurred) { state = .found(area) } else { state = .failed }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in state = .failed }
    }
}

/// Location is required to use Drafft (at least "While using the app"). Watches the permission;
/// when it's off, the app shows a blocking screen until it's back on.
@MainActor
@Observable
final class LocationGate: NSObject, CLLocationManagerDelegate {
    /// One for the app: the permission is the phone's, and a view's `@State` default is rebuilt on
    /// every re-render of its parent (a location manager each time).
    static let shared = LocationGate()

    private(set) var status: CLAuthorizationStatus
    private let manager = CLLocationManager()

    override private init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isAllowed: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var isBlocked: Bool { status == .denied || status == .restricted }

    /// Re-read on launch and each time the app comes back (e.g. from Settings).
    func refresh() {
        status = manager.authorizationStatus
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        MainActor.assumeIsolated { status = s }
    }
}
