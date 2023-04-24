//
//  PushPinView.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/16/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import QuartzCore
import UIKit

typealias PushPinViewDragCallback = (UIGestureRecognizer.State, CGFloat, CGFloat) -> Void

final class PushPinView: UIButton, CAAnimationDelegate, UIGestureRecognizerDelegate {
	private let shapeLayer: CAShapeLayer // shape for balloon
	private let textLayer: CATextLayer // text in balloon
	private var hittestRect = CGRect.zero
	private let moveButton: CALayer
	public let placeholderLayer: CALayer

	private var buttonList = [UIButton]()
	private var callbackList = [() -> Void]()
	private var lineLayers = [CAShapeLayer]()

	var text: String {
		get {
			return textLayer.string as! String
		}
		set(text) {
			if text == (textLayer.string as! String) {
				return
			}
			textLayer.string = text
			setNeedsLayout()
		}
	}

	var arrowPoint: CGPoint = .zero {
		didSet {
			if arrowPoint.x.isNaN || arrowPoint.y.isNaN {
				DLog("bad arrow location")
				return
			}
			center = CGPoint(x: arrowPoint.x, y: arrowPoint.y + bounds.size.height / 2)
		}
	}

	var dragCallback: PushPinViewDragCallback = { _, _, _ in }

	private var _labelOnBottom = false
	var labelOnBottom: Bool {
		get {
			return _labelOnBottom
		}
		set(labelOnBottom) {
			if labelOnBottom != _labelOnBottom {
				_labelOnBottom = labelOnBottom
				setNeedsLayout()
			}
		}
	}

	init() {
		shapeLayer = CAShapeLayer()
		shapeLayer.fillColor = UIColor.gray.cgColor
		shapeLayer.strokeColor = UIColor.white.cgColor
		shapeLayer.shadowColor = UIColor.black.cgColor
		shapeLayer.shadowOffset = CGSize(width: 3, height: 3)
		shapeLayer.shadowOpacity = 0.6

		// text layer
		textLayer = CATextLayer()
		textLayer.contentsScale = UIScreen.main.scale
		textLayer.string = ""

		moveButton = CALayer()
		moveButton.frame = CGRect(x: 0, y: 0, width: 25, height: 25)
		moveButton.contents = UIImage(named: "move.png")!.cgImage

		placeholderLayer = CALayer()

		super.init(frame: CGRect.zero)

		labelOnBottom = true

		let font = UIFont.preferredFont(forTextStyle: .headline)
		textLayer.font = font
		textLayer.fontSize = font.pointSize
		textLayer.alignmentMode = .left
		textLayer.truncationMode = .end
		textLayer.foregroundColor = UIColor.white.cgColor
		shapeLayer.addSublayer(textLayer)

		shapeLayer.addSublayer(moveButton)
		shapeLayer.addSublayer(placeholderLayer)

		layer.addSublayer(shapeLayer)

		let pan = UIPanGestureRecognizer(target: self, action: #selector(draggingGesture(_:)))
		pan.delegate = self
		addGestureRecognizer(pan)
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		var textSize = textLayer.preferredFrameSize()
		if textSize.width > 300 {
			textSize.width = 300
		}

		let buttonCount = Int(max(buttonList.count, 1))
		let moveButtonGap: CGFloat = 3.0
		let buttonVerticalSpacing: CGFloat = 55
		let textAlleyWidth: CGFloat = 5
		let width = textSize.width + 2 * textAlleyWidth + moveButtonGap + moveButton.frame.size.width
		let height: CGFloat = textSize.height + 2 * textAlleyWidth
		let boxSize = CGSize(width: width, height: height)
		let arrowHeight = 20 + (CGFloat(buttonCount) * buttonVerticalSpacing) / 2
		let arrowWidth: CGFloat = 20
		let buttonHorzOffset: CGFloat = 44
		let buttonHeight: CGFloat = (buttonList.count != 0 ? buttonList[0].frame.size.height : 0.0)

		let topGap = buttonHeight / 2 + CGFloat(buttonCount - 1) * buttonVerticalSpacing / 2

		// creat path with arrow
		let cornerRadius: CGFloat = 4
		let viewPath = CGMutablePath()
		if labelOnBottom {
			hittestRect = CGRect(x: 0, y: arrowHeight, width: boxSize.width, height: boxSize.height)
			viewPath.move(to: CGPoint(x: boxSize.width / 2, y: 0)) // arrow top
			viewPath.addLine(to: CGPoint(x: boxSize.width / 2 - arrowWidth / 2, y: arrowHeight)) // arrow top-left
			viewPath.addArc(
				tangent1End: CGPoint(x: 0, y: arrowHeight),
				tangent2End: CGPoint(x: 0, y: boxSize.height + arrowHeight),
				radius: cornerRadius) // bottom right corner
			viewPath.addArc(
				tangent1End: CGPoint(x: 0, y: boxSize.height + arrowHeight),
				tangent2End: CGPoint(x: boxSize.width, y: boxSize.height + arrowHeight),
				radius: cornerRadius) // top left corner
			viewPath.addArc(
				tangent1End: CGPoint(x: boxSize.width, y: boxSize.height + arrowHeight),
				tangent2End: CGPoint(x: boxSize.width, y: arrowHeight),
				radius: cornerRadius) // top right corner
			viewPath.addArc(
				tangent1End: CGPoint(x: boxSize.width, y: arrowHeight),
				tangent2End: CGPoint(x: 0, y: arrowHeight),
				radius: cornerRadius) // bottom right corner
			viewPath.addLine(to: CGPoint(x: boxSize.width / 2 + arrowWidth / 2, y: arrowHeight)) // arrow top-right
			viewPath.closeSubpath()
		} else {
			viewPath.move(to: CGPoint(x: boxSize.width / 2, y: boxSize.height + arrowHeight)) // arrow bottom
			viewPath.addLine(to: CGPoint(x: boxSize.width / 2 - arrowWidth / 2, y: boxSize.height)) // arrow top-left
			viewPath.addArc(
				tangent1End: CGPoint(x: 0, y: boxSize.height),
				tangent2End: CGPoint(x: 0, y: 0),
				radius: cornerRadius) // bottom right corner
			viewPath.addArc(
				tangent1End: CGPoint(x: 0, y: 0),
				tangent2End: CGPoint(x: boxSize.width, y: 0),
				radius: cornerRadius) // top left corner
			viewPath.addArc(
				tangent1End: CGPoint(x: boxSize.width, y: 0),
				tangent2End: CGPoint(x: boxSize.width, y: boxSize.height),
				radius: cornerRadius) // top right corner
			viewPath.addArc(
				tangent1End: CGPoint(x: boxSize.width, y: boxSize.height),
				tangent2End: CGPoint(x: 0, y: boxSize.height),
				radius: cornerRadius) // bottom right corner
			viewPath.addLine(to: CGPoint(x: boxSize.width / 2 + arrowWidth / 2, y: boxSize.height)) // arrow top-right
			viewPath.closeSubpath()
		}

		// make hit target a little larger
		hittestRect = hittestRect.insetBy(dx: -7, dy: -7)

		let viewRect = viewPath.boundingBoxOfPath
		shapeLayer.frame = CGRect(x: 0, y: 0, width: 20, height: 20) // arbitrary since it is a shape
		shapeLayer.path = viewPath
		shapeLayer.shadowPath = viewPath

		if labelOnBottom {
			textLayer.frame = CGRect(
				x: textAlleyWidth,
				y: topGap + arrowHeight + textAlleyWidth,
				width: boxSize.width - textAlleyWidth,
				height: textSize.height)
			moveButton.frame = CGRect(
				x: boxSize.width - moveButton.frame.size.width - 3,
				y: topGap + arrowHeight + (boxSize.height - moveButton.frame.size.height) / 2,
				width: moveButton.frame.size.width,
				height: moveButton.frame.size.height)
		} else {
			textLayer.frame = CGRect(
				x: textAlleyWidth,
				y: textAlleyWidth,
				width: boxSize.width - textAlleyWidth,
				height: boxSize.height - textAlleyWidth)
		}

		// place buttons
		var rc = viewRect
		for i in 0..<buttonList.count {
			// place button
			let button = buttonList[i]
			var buttonRect: CGRect = .zero
			buttonRect.size = button.frame.size
			if labelOnBottom {
				buttonRect.origin = CGPoint(
					x: viewRect.size.width / 2 + buttonHorzOffset,
					y: CGFloat(i) * buttonVerticalSpacing)
			} else {
				let x = viewRect.size.width / 2 + buttonHorzOffset
				let y = viewRect.size.height + CGFloat(i - buttonList.count / 2) * buttonVerticalSpacing + 5
				buttonRect.origin = CGPoint(x: x, y: y)
			}
			button.frame = buttonRect

			// place line to button
			let line = lineLayers[i]
			let buttonPath = CGMutablePath()
			var start = CGPoint(
				x: viewRect.size.width / 2,
				y: labelOnBottom ? topGap : viewRect.size.height)
			var end = CGPoint(
				x: buttonRect.origin.x + buttonRect.size.width / 2,
				y: buttonRect.origin.y + buttonRect.size.height / 2)
			let dx = end.x - start.x
			let dy = end.y - start.y
			let dist = hypot(dx, dy)
			start.x += 15 * dx / dist
			start.y += 15 * dy / dist
			end.x -= 15 * dx / dist
			end.y -= 15 * dy / dist
			buttonPath.move(to: CGPoint(x: start.x, y: start.y))
			buttonPath.addLine(to: CGPoint(x: end.x, y: end.y))
			line.path = buttonPath

			// get union of subviews
			rc = rc.union(buttonRect)
		}

		placeholderLayer.position = CGPoint(x: viewRect.size.width / 2,
		                                    y: labelOnBottom ? topGap : viewRect.size.height)

		if labelOnBottom {
			frame = CGRect(x: arrowPoint.x - viewRect.size.width / 2,
			               y: arrowPoint.y - topGap, width: rc.size.width, height: rc.size.height)
		} else {
			frame = CGRect(x: arrowPoint.x - viewRect.size.width / 2,
			               y: arrowPoint.y - viewRect.size.height, width: rc.size.width, height: rc.size.height)
		}
	}

	@objc func buttonPress(_ sender: UIButton) {
		let index = buttonList.firstIndex(of: sender)!
		let callback: (() -> Void) = callbackList[index]
		callback()
	}

	func add(_ button: UIButton, callback: @escaping () -> Void) {
		let line = CAShapeLayer()
		line.lineWidth = 2.0
		line.strokeColor = UIColor.white.cgColor
		line.shadowColor = UIColor.black.cgColor
		line.shadowRadius = 5
		shapeLayer.addSublayer(line)

		buttonList.append(button)
		callbackList.append(callback)
		lineLayers.append(line)

		addSubview(button)

		button.addTarget(self, action: #selector(buttonPress(_:)), for: .touchUpInside)
		setNeedsLayout()
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

		if #available(iOS 13.0, macCatalyst 13.0, *),
		   // also hit the arrow point if they're using a mouse
		   let isIndirect = (UIApplication.shared as? MyApplication)?.currentEventIsIndirect,
		   isIndirect,
		   abs(point.y) < 12,
		   abs(point.x - hittestRect.origin.x - hittestRect.size.width / 2) < 12
		{
			return self
		}

		// and any buttons connected to us
		for button in buttonList {
			let point2 = button.convert(point, from: self)
			let hit = button.hitTest(point2, with: event)
			if let hit = hit {
				return hit
			}
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

		arrowPoint = arrowPoint.plus(delta)
		dragCallback(gesture.state, delta.x, delta.y)

		gesture.setTranslation(.zero, in: self)
	}

	@available(*, unavailable)
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
