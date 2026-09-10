//
//  PushPinView.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/16/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import CoreLocation
import UIKit

typealias PushPinViewDragCallback = (PushPinView, UIGestureRecognizer.State, CGFloat, CGFloat) -> Void

/// A pan gesture recognizer that cancels itself when more than one finger is active anywhere
/// on screen, preventing accidental pin drags during two-finger pinch/rotate gestures.
private class SingleTouchPanGestureRecognizer: UIPanGestureRecognizer {
	private func activeCount(in event: UIEvent) -> Int {
		event.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
	}

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
		guard activeCount(in: event) <= 1 else {
			state = .failed
			return
		}
		super.touchesBegan(touches, with: event)
	}

	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
		guard activeCount(in: event) <= 1 else {
			state = (state == .possible) ? .failed : .cancelled
			return
		}
		super.touchesMoved(touches, with: event)
	}
}

final class PushPinView: UIButton, MapPositionedView, CAAnimationDelegate, UIGestureRecognizerDelegate {
	private let shapeLayer: CAShapeLayer // shape for balloon
	private var textLayers: [CATextLayer] = [] // one text layer per string, stacked vertically
	private var hittestRect = CGRect.zero
	private let moveButton: CALayer
	public let placeholderLayer: CALayer // used for pin tip when no underlying object is selected

	// only move the pin by setting the location, not the arrowPoint
	var location: LatLon = .zero {
		didSet {
			if let point = screenPoint() {
				arrowPoint = point
			}
		}
	}

	var viewPort: MapViewPort? {
		didSet {
			oldValue?.mapTransform.onChange.unsubscribe(self)
			viewPort?.mapTransform.onChange.subscribe(self) { [weak self] in
				self?.updateScreenPosition()
			}
		}
	}

	// This takes the latest location value and uses it to compute the new screen location
	func updateScreenPosition() {
		if let point = screenPoint() {
			arrowPoint = point
		}
	}

	// One string per line, stacked vertically and centered horizontally in the balloon.
	var texts: [String] {
		get { textLayers.map { $0.string as? String ?? "" } }
		set {
			guard newValue != texts else { return }
			textLayers.forEach { $0.removeFromSuperlayer() }
			textLayers = newValue.map { string in
				let layer = makeTextLayer(string: string)
				shapeLayer.addSublayer(layer)
				return layer
			}
			setNeedsLayout()
		}
	}

	private func makeTextLayer(string: String) -> CATextLayer {
		let font = UIFont.preferredFont(forTextStyle: .headline)
		let layer = CATextLayer()
		layer.contentsScale = UIScreen.main.scale
		layer.string = string
		layer.font = font
		layer.fontSize = font.pointSize
		layer.alignmentMode = .center
		layer.truncationMode = .end
		layer.foregroundColor = UIColor.white.cgColor
		return layer
	}

	var arrowPoint: CGPoint = .zero {
		didSet {
			if arrowPoint.x.isNaN || arrowPoint.y.isNaN {
				DLog("bad arrow location")
				return
			}

			center = CGPoint(x: arrowPoint.x, y: arrowPoint.y + bounds.size.height / 2)

			// if the label is covering the crosshairs then decrease our opacity
			let crosshairs = shapeLayer.convert(CGPoint(x: 0, y: 0), from: superview?.layer)
			if shapeLayer.path?.contains(crosshairs) ?? false {
				shapeLayer.opacity = 0.4
			} else {
				shapeLayer.opacity = 1.0
			}
		}
	}

	var dragCallback: PushPinViewDragCallback = { _, _, _, _ in }

	init() {
		shapeLayer = CAShapeLayer()
		shapeLayer.fillColor = UIColor.gray.cgColor
		shapeLayer.strokeColor = UIColor.white.cgColor
		shapeLayer.shadowColor = UIColor.black.cgColor
		shapeLayer.shadowOffset = CGSize(width: 3, height: 3)
		shapeLayer.shadowOpacity = 0.6

		moveButton = CALayer()
		moveButton.frame = CGRect(x: 0, y: 0, width: 25, height: 25)
		let moveImage = UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right")!
			.withTintColor(.white, renderingMode: .alwaysOriginal)
		let format = UIGraphicsImageRendererFormat()
		format.scale = UIScreen.main.scale
		let renderer = UIGraphicsImageRenderer(size: moveImage.size, format: format)
		let tintedImage = renderer.image { _ in
			moveImage.draw(in: CGRect(origin: .zero, size: moveImage.size))
		}
		moveButton.contents = tintedImage.cgImage

		placeholderLayer = CALayer()

		super.init(frame: CGRect.zero)

		shapeLayer.addSublayer(moveButton)

		layer.addSublayer(shapeLayer)
		layer.addSublayer(placeholderLayer)

		let pan = SingleTouchPanGestureRecognizer(target: self, action: #selector(draggingGesture(_:)))
		pan.delegate = self
		addGestureRecognizer(pan)
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		let lineSpacing: CGFloat = 2
		let moveButtonGap: CGFloat = 3.0
		let textAlleyWidth: CGFloat = 5
		let buttonVerticalSpacing: CGFloat = 55
		let arrowHeight = 20 + buttonVerticalSpacing / 2
		let arrowWidth: CGFloat = 20

		// Measure each text layer; find max width and total stacked height.
		var maxTextWidth: CGFloat = 0
		let textSizes: [CGSize] = textLayers.map { layer in
			var size = layer.preferredFrameSize()
			if size.width > 300 { size.width = 300 }
			maxTextWidth = max(maxTextWidth, size.width)
			return size
		}
		let totalTextHeight = textSizes.reduce(0) { $0 + $1.height }
			+ lineSpacing * CGFloat(max(textLayers.count - 1, 0))

		let width = maxTextWidth + 2 * textAlleyWidth + moveButtonGap + moveButton.frame.size.width
		let height: CGFloat = totalTextHeight + 2 * textAlleyWidth
		let boxSize = CGSize(width: width, height: height)

		// Create path with arrow
		let cornerRadius: CGFloat = 4
		let viewPath = CGMutablePath()

		hittestRect = CGRect(x: 0, y: arrowHeight, width: boxSize.width, height: boxSize.height)
		viewPath.move(to: CGPoint(x: boxSize.width / 2, y: 0)) // arrow top
		viewPath.addLine(to: CGPoint(x: boxSize.width / 2 - arrowWidth / 2, y: arrowHeight)) // arrow top-left
		viewPath.addArc(
			tangent1End: CGPoint(x: 0, y: arrowHeight),
			tangent2End: CGPoint(x: 0, y: boxSize.height + arrowHeight),
			radius: cornerRadius)
		viewPath.addArc(
			tangent1End: CGPoint(x: 0, y: boxSize.height + arrowHeight),
			tangent2End: CGPoint(x: boxSize.width, y: boxSize.height + arrowHeight),
			radius: cornerRadius)
		viewPath.addArc(
			tangent1End: CGPoint(x: boxSize.width, y: boxSize.height + arrowHeight),
			tangent2End: CGPoint(x: boxSize.width, y: arrowHeight),
			radius: cornerRadius)
		viewPath.addArc(
			tangent1End: CGPoint(x: boxSize.width, y: arrowHeight),
			tangent2End: CGPoint(x: 0, y: arrowHeight),
			radius: cornerRadius)
		viewPath.addLine(to: CGPoint(x: boxSize.width / 2 + arrowWidth / 2, y: arrowHeight)) // arrow top-right
		viewPath.closeSubpath()

		// Make hit target a little larger
		hittestRect = hittestRect.insetBy(dx: -7, dy: -7)

		let viewRect = viewPath.boundingBoxOfPath
		shapeLayer.frame = CGRect(x: 0, y: 0, width: 20, height: 20) // arbitrary since it is a shape
		shapeLayer.path = viewPath
		shapeLayer.shadowPath = viewPath

		// Stack text layers vertically; each is as wide as the widest line for centering.
		var currentY = arrowHeight + textAlleyWidth
		for (i, layer) in textLayers.enumerated() {
			layer.frame = CGRect(
				x: textAlleyWidth,
				y: currentY,
				width: maxTextWidth,
				height: textSizes[i].height)
			currentY += textSizes[i].height + lineSpacing
		}

		// Center moveButton vertically within the balloon box.
		moveButton.frame = CGRect(
			x: boxSize.width - moveButton.frame.size.width - 3,
			y: arrowHeight + (boxSize.height - moveButton.frame.size.height) / 2,
			width: moveButton.frame.size.width,
			height: moveButton.frame.size.height)

		placeholderLayer.position = CGPoint(x: viewRect.size.width / 2,
		                                    y: 0.0)

		frame = CGRect(x: arrowPoint.x - viewRect.size.width / 2,
		               y: arrowPoint.y,
		               width: viewRect.size.width,
		               height: viewRect.size.height)
	}

	func animateMove(from startPos: CGPoint) {
		layoutIfNeeded()

		let posA = startPos
		let posC = layer.position
		let posB = CGPoint(x: posC.x, y: posA.y)

		let path = CGMutablePath()
		path.move(to: posA)
		path.addQuadCurve(to: posC, control: posB)

		let theAnimation = CAKeyframeAnimation(keyPath: "position")
		theAnimation.path = path
		theAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
		theAnimation.repeatCount = 0
		theAnimation.isRemovedOnCompletion = true
		theAnimation.fillMode = .both
		theAnimation.duration = 0.5

		// let us get notified when animation completes
		theAnimation.delegate = self

		layer.position = posC
		layer.add(theAnimation, forKey: "animatePosition")
	}

	// MARK: - Dragging

	override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
		// test the label box
		if hittestRect.contains(point) {
			return self
		}

		if #available(iOS 13.0, *),
		   // also hit the arrow point if they're using a mouse
		   let isIndirect = (UIApplication.shared as? MyApplication)?.currentEventIsIndirect,
		   isIndirect,
		   abs(point.y) < 12,
		   abs(point.x - hittestRect.origin.x - hittestRect.size.width / 2) < 12
		{
			return self
		}
		return nil
	}

	var initialPosition: CGPoint?
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		if !isDragging {
			// record the initial touch position to increase tracking accuracy
			initialPosition = touches.first?.location(in: self)
		}
	}

	private(set) var isDragging = false
	@objc func draggingGesture(_ gesture: UIPanGestureRecognizer) {
		guard
			let viewPort
		else {
			return
		}

		var delta = gesture.translation(in: self)

		switch gesture.state {
		case .began:
			isDragging = true
			if let initial = initialPosition {
				let beg = gesture.location(in: self)
				delta = delta.minus(initial).plus(beg)
			}
		case .changed:
			isDragging = true
		default:
			isDragging = false
		}

		location = viewPort.mapTransform.latLon(forScreenPoint: arrowPoint.plus(delta))

		dragCallback(self, gesture.state, delta.x, delta.y)

		gesture.setTranslation(.zero, in: self)
	}

	@available(*, unavailable)
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
