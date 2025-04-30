//
//  LocationManager.swift
//  PotholeDetector
//
//  Created by Shatanshu Raj on 22/03/25.
//

import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    private let manager = CLLocationManager()
    
    // Published properties for SwiftUI
    @Published var lastLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationAccuracy: Double = 0
    @Published var isUpdating: Bool = false
    
    // Location history
    private var locationHistory: [CLLocation] = []
    private let maxHistoryCount = 20
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5 // Update when moved 5 meters
        manager.activityType = .automotiveNavigation
        authorizationStatus = manager.authorizationStatus
    }
    
    func requestAuthorization() {
        // Check if we already have permissions
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            // Handle denied permission case
            print("Location services permission denied")
            // You could notify the user or trigger an alert here
        }
    }
    
    
    func startUpdating() {
        manager.startUpdatingLocation()
        isUpdating = true
    }
    
    func stopUpdating() {
        manager.stopUpdatingLocation()
        isUpdating = false
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        // Auto-start if authorized
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startUpdating()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Update location and accuracy
        lastLocation = location
        locationAccuracy = location.horizontalAccuracy
        
        // Add to history and maintain maximum size
        locationHistory.append(location)
        if locationHistory.count > maxHistoryCount {
            locationHistory.removeFirst()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }
    
    // MARK: - Helper Methods
    
    func getDistanceTraveled() -> Double {
        guard locationHistory.count > 1 else { return 0 }
        
        var totalDistance = 0.0
        for i in 1..<locationHistory.count {
            totalDistance += locationHistory[i].distance(from: locationHistory[i-1])
        }
        
        return totalDistance
    }
    
    func getLocationString() -> String {
        guard let location = lastLocation else { return "Unavailable" }
        
        let latitude = String(format: "%.4f", location.coordinate.latitude)
        let longitude = String(format: "%.4f", location.coordinate.longitude)
        return "\(latitude), \(longitude)"
    }
    
    func getAccuracyDescription() -> String {
        guard let accuracy = lastLocation?.horizontalAccuracy else { return "Unknown" }
        
        if accuracy < 10 {
            return "High"
        } else if accuracy < 50 {
            return "Medium"
        } else {
            return "Low"
        }
    }
    
    // Checks if location services are available
    var servicesEnabled: Bool {
        return CLLocationManager.locationServicesEnabled()
    }
}
