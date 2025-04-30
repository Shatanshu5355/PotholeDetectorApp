//
//  BackendManager.swift
//  PotholeDetector
//
//  Created by Shatanshu Raj on 22/03/25.
//

import Foundation
import Firebase
import FirebaseFirestore
import FirebaseStorage
import CoreLocation
import Combine

class BackendManager {
    static let shared = BackendManager()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    @Published var uploadProgress: Double = 0.0
    @Published var isUploading: Bool = false
    @Published var lastUploadDate: Date?
    @Published var uploadCount: Int = 0
    
    // Log pothole detection
    func logPothole(imagePath: URL, location: CLLocation?) -> AnyPublisher<Bool, Error> {
        let subject = PassthroughSubject<Bool, Error>()
        isUploading = true
        
        // Generate unique ID
        let potholeId = UUID().uuidString
        let imageRef = storage.reference().child("potholes/\(potholeId).jpg")
        
        // Upload image to Firebase Storage
        let uploadTask = imageRef.putFile(from: imagePath, metadata: nil) { [weak self] metadata, error in
            if let error = error {
                print("Failed to upload image: \(error)")
                self?.isUploading = false
                subject.send(completion: .failure(error))
                return
            }
            
            // Save metadata to Firestore
            let locationData: [String: Any] = [
                "timestamp": Timestamp(date: Date()),
                "latitude": location?.coordinate.latitude ?? 0,
                "longitude": location?.coordinate.longitude ?? 0,
                "accuracy": location?.horizontalAccuracy ?? 0,
                "imageUrl": imageRef.fullPath,
                "type": "pothole",
                "deviceId": UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
            ]
            
            self?.db.collection("potholes").document(potholeId).setData(locationData) { error in
                if let error = error {
                    print("Failed to log pothole: \(error)")
                    subject.send(completion: .failure(error))
                } else {
                    print("Pothole logged successfully!")
                    self?.lastUploadDate = Date()
                    self?.uploadCount += 1
                    subject.send(true)
                }
                self?.isUploading = false
                subject.send(completion: .finished)
            }
        }
        
        // Monitor upload progress
        uploadTask.observe(.progress) { [weak self] snapshot in
            guard let percentComplete = snapshot.progress?.fractionCompleted else { return }
            DispatchQueue.main.async {
                self?.uploadProgress = percentComplete
            }
        }
        
        return subject.eraseToAnyPublisher()
    }
    
    // Log anomaly (jerk detection)
    func logAnomaly(location: CLLocation?, severity: Double = 1.0) {
        let anomalyId = UUID().uuidString
        
        db.collection("anomalies").document(anomalyId).setData([
            "timestamp": Timestamp(date: Date()),
            "latitude": location?.coordinate.latitude ?? 0,
            "longitude": location?.coordinate.longitude ?? 0,
            "accuracy": location?.horizontalAccuracy ?? 0,
            "type": "anomaly",
            "severity": severity,
            "deviceId": UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        ]) { error in
            if let error = error {
                print("Failed to log anomaly: \(error)")
            } else {
                print("Anomaly logged successfully!")
            }
        }
    }
    
    // Get statistics
    func getStatistics(completion: @escaping (Int, Int) -> Void) {
        let group = DispatchGroup()
        var potholeCount = 0
        var anomalyCount = 0
        
        group.enter()
        db.collection("potholes")
            .whereField("deviceId", isEqualTo: UIDevice.current.identifierForVendor?.uuidString ?? "unknown")
            .getDocuments { snapshot, error in
                potholeCount = snapshot?.documents.count ?? 0
                group.leave()
            }
        
        group.enter()
        db.collection("anomalies")
            .whereField("deviceId", isEqualTo: UIDevice.current.identifierForVendor?.uuidString ?? "unknown")
            .getDocuments { snapshot, error in
                anomalyCount = snapshot?.documents.count ?? 0
                group.leave()
            }
        
        group.notify(queue: .main) {
            completion(potholeCount, anomalyCount)
        }
    }
}
