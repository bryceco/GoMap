//
//  CameraViewController.swift
//
//  Created by Bryce Cogswell on 4/8/21.
//

import AVFoundation
import UIKit
import Vision

@available(iOS 13.0, macCatalyst 14.0, *)
class CameraView: UIView, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
	private var captureSession: AVCaptureSession?
	private var stillImageOutput: AVCapturePhotoOutput?
	private var videoOutput = AVCaptureVideoDataOutput()
	private let videoOutputQueue = DispatchQueue(label: "com.gomaposm.openinghours.VideoOutputQueue")

	var photoCallback: ((CGImage) -> Void)?
	var observationsCallback: (([VNRecognizedTextObservation], CameraView) -> Void)?
	var shouldRecordCallback: (() -> (Bool))?
	var languages: [String] = []

	override func layoutSubviews() {
		super.layoutSubviews()
		for layer in layer.sublayers ?? [] {
			layer.frame = CGRect(origin: layer.bounds.origin, size: self.layer.frame.size)
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)

		// session
		let captureSession = AVCaptureSession()
		self.captureSession = captureSession
		captureSession.sessionPreset = AVCaptureSession.Preset.high

		// input source
		guard let backCamera = AVCaptureDevice.default(for: AVMediaType.video),
		      let input = try? AVCaptureDeviceInput(device: backCamera)
		else { return }
		if captureSession.canAddInput(input) {
			captureSession.addInput(input)
		}

		// video output
		videoOutput.alwaysDiscardsLateVideoFrames = true
		videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
		if captureSession.canAddOutput(videoOutput) {
			captureSession.addOutput(videoOutput)
			videoOutput.connection(with: AVMediaType.video)?.preferredVideoStabilizationMode = .off
		}

		// photo output
		stillImageOutput = AVCapturePhotoOutput()
		if captureSession.canAddOutput(stillImageOutput!) {
			captureSession.addOutput(stillImageOutput!)
		}

		// preview layer
		let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
		previewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
		previewLayer.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
		layer.addSublayer(previewLayer)
	}

	public func startRunning() {
		DispatchQueue.global(qos: .default).async(execute: {
			self.captureSession?.startRunning()
		})
	}

	public func stopRunning() {
		captureSession?.stopRunning()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	internal func photoOutput(_ output: AVCapturePhotoOutput,
	                          didFinishProcessingPhoto photo: AVCapturePhoto,
	                          error: Error?)
	{
		let cgImage: CGImage?

#if targetEnvironment(macCatalyst)
		// FIXME:
		// As of iOS 15 cgImageRepresentation doesn't compile on MacCatalyst.
		// Since few people are going to use the camera on Mac anyhow we can
		// simply have it fail until Apple fixes the SDK.
		cgImage = nil
#else
#if compiler(>=5.5)
		// On newer Xcode cgImageRepresentation is a normal managed object
		cgImage = photo.cgImageRepresentation()
#else
		// On older Xcode cgImageRepresentation is unmanaged
		cgImage = photo.cgImageRepresentation()?.takeUnretainedValue()
#endif
#endif

		if let cgImage = cgImage {
#if true
			photoCallback?(cgImage)
#else
			let orientation = photo.metadata[kCGImagePropertyOrientation as String] as! NSNumber
			let uiOrientation = UIImage.Orientation(rawValue: orientation.intValue)!
			let image = UIImage(cgImage: cgImage, scale: 1, orientation: uiOrientation)
			photoCallback?(image)
#endif
		}
	}

	@IBAction func takePhoto(sender: AnyObject?) {
		if let videoConnection = stillImageOutput!.connection(with: AVMediaType.video) {
			videoConnection.videoOrientation = AVCaptureVideoOrientation.portrait
			stillImageOutput?.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
		}
	}

	private var boxLayers = [CALayer]()
	private var newBoxes = [(UIColor, [CGRect])]()
	public func addBoxes(boxes: [CGRect], color: UIColor) {
		newBoxes.append((color, boxes))
	}

	private func displayBoxes() {
		DispatchQueue.main.async {
			// remove current boxes
			for layer in self.boxLayers {
				layer.removeFromSuperlayer()
			}
			self.boxLayers.removeAll()

			// add new boxes
			let rotationTransform = CGAffineTransform(translationX: 0, y: 1).rotated(by: -CGFloat.pi / 2)
			let bottomToTopTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
			let visionToAVFTransform = CGAffineTransform.identity.concatenating(bottomToTopTransform)
				.concatenating(rotationTransform)

			guard let previewLayer = self.layer.sublayers?.first as? AVCaptureVideoPreviewLayer else { return }
			for (color, boxes) in self.newBoxes {
				for box in boxes {
					let rect = previewLayer
						.layerRectConverted(fromMetadataOutputRect: box.applying(visionToAVFTransform))
					let layer = CAShapeLayer()
					layer.opacity = 1.0
					layer.borderColor = color.cgColor
					layer.borderWidth = 2
					layer.frame = rect
					self.boxLayers.append(layer)
					previewLayer.addSublayer(layer)
				}
			}
			self.newBoxes.removeAll()
		}
	}

	private func addBoxes(forObservations results: [VNRecognizedTextObservation]) {
		var boxes = [CGRect]()
		for result in results {
			if let candidate = result.topCandidates(1).first,
			   let box = try? candidate.boundingBox(for: candidate.string.startIndex..<candidate.string.endIndex)?
			   .boundingBox
			{
				boxes.append(box)
			}
		}
		addBoxes(boxes: boxes, color: UIColor.red)
	}

	internal func captureOutput(_ output: AVCaptureOutput,
	                            didOutput sampleBuffer: CMSampleBuffer,
	                            from connection: AVCaptureConnection)
	{
		guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

		let request = VNRecognizeTextRequest(completionHandler: { [weak self] request, _ in
			guard let weakSelf = self else { return }

			// we need to check this before we tear down the boxes
			if !(weakSelf.shouldRecordCallback?() ?? true) {
				// stop recording
				DispatchQueue.main.sync {
					weakSelf.stopRunning()
				}
				return
			}

			guard let results = request.results as? [VNRecognizedTextObservation] else { return }
			weakSelf.addBoxes(forObservations: results)
			weakSelf.observationsCallback?(results, weakSelf)
			weakSelf.displayBoxes()

			if !(weakSelf.shouldRecordCallback?() ?? true) {
				// stop recording
				DispatchQueue.main.sync {
					weakSelf.stopRunning()
				}
			}
		})
		request.recognitionLevel = .accurate
//		request.usesLanguageCorrection = false
		request.recognitionLanguages = languages

		let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
		                                           orientation: CGImagePropertyOrientation.right,
		                                           options: [:])
		try? requestHandler.perform([request])
	}
}
