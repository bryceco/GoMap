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
	@State private var restart: Bool = false

	init(onAccept: @escaping ((String) -> Void), onCancel: @escaping (() -> Void), onRecognize: ((String) -> Void)? = nil) {
		let recognizer = HoursRecognizer()
		recognizer.onRecognize = onRecognize

		self.onAccept = onAccept
		self.onCancel = onCancel
		_recognizer = StateObject(wrappedValue: recognizer)
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
					Button("Cancel") {
						onCancel()
					}.withMyButtonStyle(enabled: true)
					Spacer()
					Button("Retry") {
						restart = true
					}.withMyButtonStyle(enabled: true)
					Spacer()
					Button("Accept") {
						onAccept(recognizer.text)
					}.withMyButtonStyle(enabled: recognizer.finished)
						.disabled(!recognizer.finished)
					Spacer()
				}
			}
			Picker(recognizer.language.rawValue, selection: $recognizer.language) {
				ForEach(HoursRecognizer.Language.allCases) { lang in
					Text(lang.name).tag(lang)
				}
			}
			.pickerStyle(MenuPickerStyle())
			.foregroundColor(.white)
			.padding()
			.overlay(Capsule(style: .continuous)
				.stroke(Color.white, lineWidth: 2.0))
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
		return cam
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
