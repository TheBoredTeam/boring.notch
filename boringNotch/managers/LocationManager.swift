//
//  LocationManager.swift
//  boringNotch
//
//  Created by John Patch on 4/8/25.
//
import Foundation
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()

    @Published var location: CLLocation? = nil

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization() // Request permission for when the app is in use
    }

    // Request location when needed
    func requestLocation() {
        if CLLocationManager.locationServicesEnabled() {
            locationManager.requestLocation()  // Request a one-time location update
        } else {
            print("Location services are not enabled")
        }
    }

    // Delegate method to handle location updates
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let newLocation = locations.last {
            self.location = newLocation
        }
    }

    // Delegate method to handle authorization status changes
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()  // Start updates once authorized
        case .denied, .restricted:
            print("Location access denied or restricted")
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()  // Request permission when not determined
        @unknown default:
            break
        }
    }

    // Delegate method to handle errors
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Error while fetching location: \(error.localizedDescription)")
    }
}
