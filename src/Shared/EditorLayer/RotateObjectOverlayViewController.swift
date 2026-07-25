//
//  RotateObjectOverlayViewController.swift
//  Go Map!!
//
//  Transparent full-screen overlay that handles rotating an OSM object.
//  Presented over the map while the user performs a two-finger rotation;
//  a single tap dismisses the overlay.
//

import UIKit

final class RotateObjectOverlayViewController: UIViewController {

	// MARK: Properties

	private let onBegin: () -> Void
	private let onContinue: (_ delta: CGFloat) -> Void
	private let onFinish: () -> Void

	/// Accumulated rotation across all gestures, in radians.
	private var cumulativeRotation: CGFloat = 0

	/// Called (after this VC is dismissed) so MapView can do its own cleanup.
	var onComplete: (() -> Void)?

	// MARK: Init

	init(onBegin: @escaping () -> Void,
	     onContinue: @escaping (_ delta: CGFloat) -> Void,
	     onFinish: @escaping () -> Void)
	{
		self.onBegin = onBegin
		self.onContinue = onContinue
		self.onFinish = onFinish
		super.init(nibName: nil, bundle: nil)
		modalPresentationStyle = .overFullScreen
		modalTransitionStyle = .crossDissolve
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError() }

	// MARK: View lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = .clear

		let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
		view.addGestureRecognizer(rotationGesture)

		let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
		view.addGestureRecognizer(tapGesture)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		onBegin()
	}

	private var graphicLayer: CAShapeLayer?

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		if graphicLayer == nil {
			let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
			let layer = RotateObjectOverlayViewController.buildRotateGraphicLayer(center: center)
			view.layer.addSublayer(layer)
			graphicLayer = layer
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		onFinish()
	}

	// MARK: Rotate graphic

	static func buildRotateGraphicLayer(center: CGPoint) -> CAShapeLayer {
		let radiusInner: CGFloat = 70
		let radiusOuter: CGFloat = 90
		let arrowWidth: CGFloat = 60
		let path = UIBezierPath(
			arcCenter: center,
			radius: radiusInner,
			startAngle: .pi / 2,
			endAngle: .pi,
			clockwise: false)
		path.addLine(to: CGPoint(x: center.x - (radiusOuter + radiusInner) / 2 + arrowWidth / 2, y: center.y))
		path.addLine(to: CGPoint(
			x: center.x - (radiusOuter + radiusInner) / 2,
			y: center.y + arrowWidth / sqrt(2.0)))
		path.addLine(to: CGPoint(x: center.x - (radiusOuter + radiusInner) / 2 - arrowWidth / 2, y: center.y))
		path.addArc(withCenter: center, radius: radiusOuter, startAngle: .pi, endAngle: .pi / 2, clockwise: true)
		path.close()

		let layer = CAShapeLayer()
		layer.path = path.cgPath
		layer.fillColor = UIColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 0.4).cgColor
		return layer
	}

	// MARK: Gesture handlers

	@objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
		switch gesture.state {
		case .changed:
			// onContinue expects the total delta from the initial state,
			// so we pass the sum of all previous gestures plus the current one.
			onContinue(cumulativeRotation + gesture.rotation)
		case .ended, .cancelled, .failed:
			// Bank the rotation and keep the overlay up for more gestures.
			cumulativeRotation += gesture.rotation
		default:
			break
		}
	}

	@objc private func handleTap(_ gesture: UITapGestureRecognizer) {
		completeAndDismiss()
	}

	// MARK: Dismissal

	private func completeAndDismiss() {
		let callback = onComplete
		onComplete = nil
		dismiss(animated: false) {
			callback?()
		}
	}
}
