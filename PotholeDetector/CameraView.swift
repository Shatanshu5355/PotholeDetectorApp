import SwiftUI
import AVFoundation
import Vision
import CoreLocation
import CoreMotion

struct CameraView: UIViewControllerRepresentable {
    @Binding var detectedPotholes: [VNObservation]
    
    // MARK: - Coordinator for handling camera output
    class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
        var parent: CameraView
        var model: VNCoreMLModel?
        let photoOutput = AVCapturePhotoOutput()
        let locationManager = LocationManager.shared
        let motionManager = MotionManager.shared
        private var lastCaptureTime: Date = Date().addingTimeInterval(-5) // Initialize with a time in the past
        private var processingQueue = DispatchQueue(label: "com.potholedetector.processing", qos: .userInitiated)
        
        init(parent: CameraView) {
            self.parent = parent
            super.init()
            setupModel()
        }
        
        // Load Core ML model
        func setupModel() {
            guard let model = try? VNCoreMLModel(for: best_v2(configuration: MLModelConfiguration()).model) else {
                print("Failed to load Core ML model")
                return
            }
            self.model = model
        }
        
        // Process each video frame
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            // Limit processing rate
            let currentTime = Date()
            guard currentTime.timeIntervalSince(lastCaptureTime) >= 0.5 else { return } // Process at most every 0.5 seconds
            
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                  let model = model else { return }
            
            // Update last capture time
            lastCaptureTime = currentTime
            
            // Create Vision request
            let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                guard let results = request.results as? [VNRecognizedObjectObservation],
                      let self = self else { return }
                
                // Filter high-confidence detections
                let filtered = results.filter { $0.confidence > 0.6 }
                
                DispatchQueue.main.async {
                    self.parent.detectedPotholes = filtered
                    
                    // Capture photo if potholes are detected and not recently captured
                    if !filtered.isEmpty {
                        self.processingQueue.async {
                            self.capturePhoto()
                        }
                    }
                }
            }
            
            // Run inference
            processingQueue.async {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
                try? handler.perform([request])
            }
        }
        
        // Capture photo on detection
        func capturePhoto() {
            // Only capture if we have location data
            guard locationManager.lastLocation != nil else { return }
            
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .auto
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
        
        // Handle captured photo
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            guard let imageData = photo.fileDataRepresentation(),
                  let location = locationManager.lastLocation else { return }
            
            // Save photo to Documents directory with timestamp
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let imageName = "pothole_\(timestamp).jpg"
            let imagePath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(imageName)
            
            do {
                try imageData.write(to: imagePath)
                
                // Log pothole detection
                _ = BackendManager.shared.logPothole(imagePath: imagePath, location: location)
            } catch {
                print("Failed to save image: \(error)")
            }
        }
    }
    
    // MARK: - UIViewController setup
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        let session = AVCaptureSession()
        
        // Use highest possible quality
        if session.canSetSessionPreset(.hd4K3840x2160) {
            session.sessionPreset = .hd4K3840x2160
        } else if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }
        
        // Setup camera input
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return viewController
        }
        
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Error configuring camera: \(error)")
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            // Setup video output
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(context.coordinator, queue: DispatchQueue(label: "videoQueue", qos: .userInteractive))
            output.alwaysDiscardsLateVideoFrames = true
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            // Setup photo output
            if session.canAddOutput(context.coordinator.photoOutput) {
                session.addOutput(context.coordinator.photoOutput)
                
                // Configure after adding to session
                if #available(iOS 16.0, *) {
                    // Simply remove the maxPhotoDimensions setting
                    // This will use the device's default optimal dimensions
                    print("Using default photo dimensions")
                }
            }
            
            // Setup preview layer
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.name = "cameraPreview"
            viewController.view.layer.addSublayer(previewLayer)
            
            // Start session in background
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
                DispatchQueue.main.async {
                    previewLayer.frame = viewController.view.bounds
                }
            }
            
        } catch {
            print("Error setting up camera: \(error)")
        }
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Update preview layer frame
        if let previewLayer = uiViewController.view.layer.sublayers?.first(where: { $0.name == "cameraPreview" }) as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiViewController.view.bounds
        }
        
        // Draw bounding boxes
        drawBoundingBoxes(on: uiViewController.view)
    }
    
    // Draw bounding boxes for detected potholes
    private func drawBoundingBoxes(on view: UIView) {
        // Remove old boxes
        view.layer.sublayers?.filter { $0.name == "potholeBox" || $0.name == "potholeLabel" }.forEach { $0.removeFromSuperlayer() }
        
        for observation in detectedPotholes {
            guard let recognized = observation as? VNRecognizedObjectObservation else { continue }
            
            // Convert normalized coordinates to screen coordinates
            let boundingBox = recognized.boundingBox
            let layerRect = CGRect(
                x: boundingBox.minX * view.bounds.width,
                y: (1 - boundingBox.maxY) * view.bounds.height, // Flip Y-axis
                width: boundingBox.width * view.bounds.width,
                height: boundingBox.height * view.bounds.height
            )
            
            // Create box layer
            let boxLayer = CALayer()
            boxLayer.frame = layerRect
            boxLayer.borderWidth = 3
            boxLayer.borderColor = UIColor.red.cgColor
            boxLayer.cornerRadius = 4
            boxLayer.name = "potholeBox"
            view.layer.addSublayer(boxLayer)
            
            // Create gradient background for the label
            let gradientLayer = CAGradientLayer()
            gradientLayer.frame = CGRect(x: layerRect.minX, y: layerRect.minY - 25, width: layerRect.width, height: 25)
            gradientLayer.colors = [UIColor.red.cgColor, UIColor.red.withAlphaComponent(0.7).cgColor]
            gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
            gradientLayer.cornerRadius = 4
            gradientLayer.name = "potholeLabel"
            view.layer.addSublayer(gradientLayer)
            
            // Create confidence label
            let textLayer = CATextLayer()
            textLayer.frame = gradientLayer.bounds
            textLayer.string = "Pothole \(Int(recognized.confidence * 100))%"
            textLayer.fontSize = 12
            textLayer.alignmentMode = .center
            textLayer.foregroundColor = UIColor.white.cgColor
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.name = "potholeLabel"
            gradientLayer.addSublayer(textLayer)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
}
