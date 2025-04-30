//
//  MotionManager.swift
//  PotholeDetector
//
//  Created by Shatanshu Raj on 22/03/25.
//

import Foundation
import CoreMotion
import Combine

class MotionManager: ObservableObject {
    static let shared = MotionManager()
    private let motionManager = CMMotionManager()
    private let updateQueue = OperationQueue()
    private let processQueue = DispatchQueue(label: "com.potholedetector.motionProcessing", qos: .userInitiated)
    
    // Event publishers
    @Published var isJerkDetected = false
    @Published var isMonitoring = false
    @Published var currentJerkMagnitude: Double = 0.0
    @Published var jerkThreshold: Double = 2.0
    
    // Tracking properties
    private var detectionCount = 0
    private var lastJerkTime = Date()
    private var anomalyWindow: TimeInterval = 2.0 // Cooldown period between detections
    private var jerkHistory: [Double] = []
    private let maxHistoryCount = 100
    
    // Motion data for analysis
    @Published var accelerationX: Double = 0
    @Published var accelerationY: Double = 0
    @Published var accelerationZ: Double = 0
    @Published var rotationRate: Double = 0
    
    init() {
        updateQueue.maxConcurrentOperationCount = 1
        updateQueue.qualityOfService = .userInteractive
    }
    
    func startMonitoring() {
        guard motionManager.isDeviceMotionAvailable, !isMonitoring else { return }
        
        // Configure motion updates
        motionManager.deviceMotionUpdateInterval = 0.05 // 20Hz sample rate for smoother detection
        isMonitoring = true
        jerkHistory.removeAll()
        
        motionManager.startDeviceMotionUpdates(to: updateQueue) { [weak self] (data, error) in
            guard let self = self, let data = data else { return }
            
            self.processQueue.async {
                // Extract acceleration data
                let acceleration = data.userAcceleration
                let rotation = data.rotationRate
                
                // Calculate jerk magnitude (rate of change of acceleration)
                let jerkMagnitude = sqrt(pow(acceleration.x, 2) +
                                         pow(acceleration.y, 2) +
                                         pow(acceleration.z, 2))
                
                // Calculate rotation magnitude
                let rotationMagnitude = sqrt(pow(rotation.x, 2) +
                                            pow(rotation.y, 2) +
                                            pow(rotation.z, 2))
                
                // Update published values for UI
                DispatchQueue.main.async {
                    self.accelerationX = acceleration.x
                    self.accelerationY = acceleration.y
                    self.accelerationZ = acceleration.z
                    self.rotationRate = rotationMagnitude
                    self.currentJerkMagnitude = jerkMagnitude
                    
                    // Add to history and maintain maximum size
                    self.jerkHistory.append(jerkMagnitude)
                    if self.jerkHistory.count > self.maxHistoryCount {
                        self.jerkHistory.removeFirst()
                    }
                    
                    // Check if jerk exceeds threshold and enough time has passed since last detection
                    let currentTime = Date()
                    let timeSinceLastJerk = currentTime.timeIntervalSince(self.lastJerkTime)
                    
                    if jerkMagnitude > self.jerkThreshold && timeSinceLastJerk > self.anomalyWindow {
                        self.isJerkDetected = true
                        self.lastJerkTime = currentTime
                        self.detectionCount += 1
                        
                        // Log the anomaly using BackendManager with severity proportional to jerk
                        let normalizedSeverity = min(jerkMagnitude / 10, 1.0) * 5 // Scale 0-5
                        BackendManager.shared.logAnomaly(
                            location: LocationManager.shared.lastLocation,
                            severity: normalizedSeverity
                        )
                        
                        // Reset jerk detected flag after 1 second
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.isJerkDetected = false
                        }
                    }
                }
            }
        }
    }
    
    func stopMonitoring() {
        motionManager.stopDeviceMotionUpdates()
        isMonitoring = false
    }
    
    // Get an array of recent jerk values for visualization
    func getJerkHistory() -> [Double] {
        return jerkHistory
    }
    
    // Get count of detections in current session
    func getDetectionCount() -> Int {
        return detectionCount
    }
    
    // Reset detection count
    func resetDetectionCount() {
        detectionCount = 0
    }
    
    // Adjust sensitivity
    func setThreshold(_ value: Double) {
        jerkThreshold = max(1.0, min(5.0, value))
    }
    
    // Check if device supports motion detection
    var isMotionAvailable: Bool {
        return motionManager.isDeviceMotionAvailable
    }
}
