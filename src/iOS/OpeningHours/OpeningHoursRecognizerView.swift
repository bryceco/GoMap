//
//  OpeningHoursRecognizerView.swift
//
//  Created by Bryce Cogswell on 4/8/21.
//

#if arch(arm64) || arch(x86_64) // old architectures don't support SwiftUI

import SwiftUI

@available(iOS 13.0, *)
fileprivate extension Button {
	func withMyButtonStyle(enabled: Bool) -> some View {
		padding()
			.background(Capsule().fill(enabled ? Color.blue : Color.gray))
			.accentColor(.white)
	}
}

@available(iOS 14.0, *)
public struct OpeningHoursRecognizerView: View {
	public let onAccept: (String) -> Void
	public let onCancel: () -> Void

	@StateObject public var recognizer: HoursRecognizer
	@State private var restart = false

	init(
		onAccept: @escaping ((String) -> Void),
		onCancel: @escaping (() -> Void),
		onRecognize: ((String) -> Void)? = nil)
	{
		let recognizer = HoursRecognizer()
		self.onAccept = onAccept
		self.onCancel = onCancel
		_recognizer = StateObject(wrappedValue: recognizer)

		let feedback = UINotificationFeedbackGenerator()
		feedback.prepare()
		recognizer.onRecognize = {
			feedback.notificationOccurred(.success)
			onRecognize?($0)
			feedback.prepare()
		}
	}

	public var body: some View {
		ZStack(alignment: .topLeading) {
			VStack {
				CameraViewWrapper(recognizer: recognizer,
				                  restart: $restart)
					.background(Color.blue)
				Spacer()
				Text(recognizer.text)
					.frame(height: 100.0)
				HStack {
					Spacer()
					Button(NSLocalizedString("Cancel", comment: "")) {
						onCancel()
					}.withMyButtonStyle(enabled: true)
					Spacer()
					Button(NSLocalizedString("Retry", comment: "retry opening hours recognition")) {
						restart = true
					}.withMyButtonStyle(enabled: true)
					Spacer()
					Button(NSLocalizedString("Accept", comment: "")) {
						onAccept(recognizer.text)
					}.withMyButtonStyle(enabled: recognizer.finished)
						.disabled(!recognizer.finished)
					Spacer()
				}
			}
			Picker(recognizer.language.isoCode, selection: $recognizer.language) {
				ForEach(HoursRecognizer.languageList) { lang in
					Text(lang.name).tag(lang)
				}
			}
			.pickerStyle(.menu)
			.background(
				RoundedRectangle(cornerRadius: 50.0, style: .continuous)
					.fill(.white))
		}
	}
}

// Make the UIKit CameraView accessible to SwiftUI
@available(iOS 13.0, macCatalyst 14.0, *)
struct CameraViewWrapper: UIViewRepresentable {
	@ObservedObject var recognizer: HoursRecognizer
	@Binding var restart: Bool

	func makeUIView(context: Context) -> CameraView {
		let cam = CameraView(frame: .zero)
		cam.observationsCallback = { observations, camera in
			recognizer.updateWithLiveObservations(observations: observations, camera: camera)
		}
		cam.shouldRecordCallback = {
			!recognizer.finished
		}
		cam.languages = [recognizer.language.isoCode]
		cam.startRunning()
		return cam
	}

	static func dismantleUIView(_ uiView: Self.UIViewType, coordinator: Self.Coordinator) {
		uiView.stopRunning()
	}

	func updateUIView(_ uiView: CameraView, context: Context) {
		if restart {
			DispatchQueue.main.async {
				restart = false
				recognizer.restart()
				uiView.startRunning()
			}
		}
	}
}

// This allows the SwiftUI view to be embedded by a UIKit app
@available(iOS 14.0, *)
@objc public class OpeningHoursRecognizerController: NSObject {
	@objc static func with(onAccept: @escaping (String) -> Void,
	                       onCancel: @escaping () -> Void,
	                       onRecognize: @escaping (String) -> Void)
		-> UIViewController
	{
		let view = OpeningHoursRecognizerView(onAccept: onAccept, onCancel: onCancel, onRecognize: onRecognize)
		return UIHostingController(rootView: view)
	}
}
#endif
