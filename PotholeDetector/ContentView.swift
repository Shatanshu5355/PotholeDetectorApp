//
//  ContentView.swift
//  PotholeDetector
//
//  Created by Shatanshu Raj on 22/03/25.
//

import SwiftUI
import Vision

struct ContentView: View {
    @State private var isDetecting = false
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0.0
    @State private var showResults = false
    @State private var detectedPotholes: [VNObservation] = []
    @State private var totalDetections = 0
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .edgesIgnoringSafeArea(.all)
            
            if isDetecting {
                DetectionView(
                    detectedPotholes: $detectedPotholes,
                    isUploading: $isUploading,
                    uploadProgress: $uploadProgress,
                    totalDetections: $totalDetections,
                    stopAction: stopDetection
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                HomeView(
                    showResults: $showResults,
                    totalDetections: totalDetections,
                    startAction: startDetection
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            if showResults {
                ResultsToast()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.6), value: isDetecting)
        .animation(.spring(response: 0.6), value: showResults)
    }
    
    private func startDetection() {
        isDetecting = true
        showResults = false
        MotionManager.shared.startMonitoring()
        LocationManager.shared.startUpdating()
    }
    
    private func stopDetection() {
        isUploading = true
        MotionManager.shared.stopMonitoring()
        LocationManager.shared.stopUpdating()
        totalDetections += detectedPotholes.count
        simulateUploadProgress()
    }
    
    private func simulateUploadProgress() {
        let totalSteps = 10
        for step in 0...totalSteps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.2) {
                uploadProgress = Double(step) / Double(totalSteps)
                if step == totalSteps {
                    completeUpload()
                }
            }
        }
    }
    
    private func completeUpload() {
        isUploading = false
        isDetecting = false
        showResults = true
        detectedPotholes = []
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showResults = false
        }
    }
}

struct HomeView: View {
    @Binding var showResults: Bool
    let totalDetections: Int
    let startAction: () -> Void
    @State private var animate = false
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // App Logo
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 160, height: 160)
                
                Circle()
                    .stroke(Color.blue, lineWidth: animate ? 1 : 3)
                    .frame(width: animate ? 200 : 140, height: animate ? 200 : 140)
                    .opacity(animate ? 0 : 1)
                
                Image(systemName: "road.lanes")
                    .font(.system(size: 70, weight: .light))
                    .foregroundColor(.blue)
            }
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
            
            // App Title and Description
            VStack(spacing: 10) {
                Text("Pothole Detector")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Detecting and reporting road hazards")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Stats Card
            VStack(spacing: 15) {
                HStack(spacing: 30) {
                    StatView(title: "Potholes", value: "\(totalDetections)", icon: "exclamationmark.triangle.fill", color: .orange)
                    
                    StatView(title: "Coverage", value: LocationManager.shared.lastLocation != nil ? "Active" : "Waiting", icon: "location.fill", color: LocationManager.shared.lastLocation != nil ? .green : .gray)
                }
                
                HStack(spacing: 30) {
                    StatView(title: "Sensor", value: MotionManager.shared.isJerkDetected ? "Active" : "Ready", icon: "gyroscope", color: .blue)
                    
                    StatView(title: "Status", value: "Ready", icon: "checkmark.circle.fill", color: .green)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
            )
            .padding(.horizontal)
            
            Spacer()
            
            // Start Button
            Button(action: startAction) {
                HStack {
                    Image(systemName: "video.fill")
                    Text("Start Detection")
                }
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.blue)
                )
                .foregroundColor(.white)
                .shadow(radius: 5)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .padding()
    }
}

struct StatView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DetectionView: View {
    @Binding var detectedPotholes: [VNObservation]
    @Binding var isUploading: Bool
    @Binding var uploadProgress: Double
    @Binding var totalDetections: Int
    let stopAction: () -> Void
    @State private var showMotionAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Status Bar
            HStack {
                VStack(alignment: .leading) {
                    Text("LIVE DETECTION")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    Text("Scanning for potholes")
                        .font(.headline)
                }
                
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                    
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 12, height: 12)
                        .scaleEffect(showMotionAlert ? 4 : 1)
                        .opacity(showMotionAlert ? 0 : 1)
                        .animation(Animation.easeInOut(duration: 1).repeatForever(autoreverses: false), value: showMotionAlert)
                        .onAppear { showMotionAlert = true }
                }
                
                Text("REC")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom, 10)
            
            // Camera Preview with Detection Overlay
            ZStack(alignment: .top) {
                CameraView(detectedPotholes: $detectedPotholes)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4/3, contentMode: .fit)
                    .cornerRadius(16)
                    .padding(.horizontal)
                
                HStack {
                    // Detection Counter
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("\(detectedPotholes.count) detected")
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(20)
                    .padding(16)
                    
                    Spacer()
                    
                    // Motion Indicator
                    if MotionManager.shared.isJerkDetected {
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundColor(.yellow)
                            Text("Bump detected")
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(20)
                        .padding(16)
                    }
                }
            }
            
            // Information Panel
            VStack(spacing: 20) {
                if isUploading {
                    // Upload Progress
                    VStack(spacing: 15) {
                        Text("Uploading detection data")
                            .font(.headline)
                        
                        ProgressView(value: uploadProgress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: .infinity)
                            .tint(.blue)
                        
                        Text("\(Int(uploadProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .padding(.horizontal)
                } else {
                    // Status Panel
                    HStack(spacing: 30) {
                        // Location Status
                        VStack {
                            Image(systemName: LocationManager.shared.lastLocation != nil ? "location.fill" : "location.slash.fill")
                                .font(.system(size: 24))
                                .foregroundColor(LocationManager.shared.lastLocation != nil ? .green : .gray)
                            
                            Text("GPS")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Motion Status
                        VStack {
                            Image(systemName: "gyroscope")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                            
                            Text("Motion")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Vision Status
                        VStack {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.purple)
                            
                            Text("Camera")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .padding(.horizontal)
                }
                
                // Stop Button
                Button(action: stopAction) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text(isUploading ? "Uploading..." : "Stop Detection")
                    }
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(isUploading ? Color.gray : Color.red)
                    )
                    .foregroundColor(.white)
                    .shadow(radius: 5)
                }
                .disabled(isUploading)
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .padding(.top, 20)
        }
        .background(Color(.systemBackground))
    }
}

struct ResultsToast: View {
    var body: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 15) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Upload Complete")
                        .font(.headline)
                    
                    Text("Data successfully sent to the server")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}
