//
//  OpeningHoursRecognizerView.swift
//
//  Created by Bryce Cogswell on 4/8/21.
//

import SwiftUI


@available(iOS 13.0, *)
fileprivate extension Button {
	func withMyButtonStyle(enabled:Bool) -> some View {
		self.padding()
			.background(Capsule().fill(enabled ? Color.blue : Color.gray))
			.accentColor(.white)
	}
}

@available(iOS 14.0, *)
public struct OpeningHoursRecognizerView: View {
	public let accepted:((String) -> Void)
	public let cancelled:(() -> Void)

	@State private var restart: Bool = false

	@StateObject public var recognizer = HoursRecognizer()

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
						cancelled()
					}.withMyButtonStyle(enabled: true)
					Spacer()
					Button("Retry") {
						restart = true
					}.withMyButtonStyle(enabled: true)
					Spacer()
					Button("Accept") {
						accepted(recognizer.text)
					}.withMyButtonStyle( enabled: recognizer.finished )
					.disabled( !recognizer.finished )
					Spacer()
				}
			}
			Picker(recognizer.language.rawValue, selection: $recognizer.language) {
				ForEach(HoursRecognizer.Language.allCases) { lang in
					Text( lang.name ).tag( lang )
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
@available(iOS 13.0, *)
struct CameraViewWrapper: UIViewRepresentable {

	@ObservedObject var recognizer: HoursRecognizer
	@Binding var restart: Bool

	func makeUIView(context: Context) -> CameraView {
		let cam = CameraView(frame: .zero)
		cam.observationsCallback = { observations, camera in
			recognizer.updateWithLiveObservations( observations: observations, camera: camera )
		}
		cam.shouldRecordCallback = {
			return !recognizer.finished
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

// This allows SwiftUI to be embedded in a UIKit storyboard
@available(iOS 14.0, *)
@objc public class OpeningHoursRecognizerController: NSObject {
	@objc static func with(accepted: @escaping (String) -> Void,
						   cancelled: @escaping ()-> Void) -> UIViewController {
		let view = OpeningHoursRecognizerView(accepted: accepted, cancelled: cancelled)
		return UIHostingController(rootView: view)
	}
}
