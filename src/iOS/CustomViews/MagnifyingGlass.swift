//
//  MagnifyingGlass.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/18/22.
//  Copyright © 2022 Bryce. All rights reserved.
//

import Foundation
import UIKit

final class MagnifyingGlass: UIView {
	let sourceView: UIView
	private var sourceCenter: CGPoint {
		didSet {
			setNeedsLayout()
		}
	}

	let radius: CGFloat
	let scale: CGFloat

	init(sourceView: UIView, radius: CGFloat, scale: CGFloat) {
		self.sourceView = sourceView
		sourceCenter = sourceView.bounds.center()
		self.radius = radius
		self.scale = scale
		let frame = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
		super.init(frame: frame)

		clipsToBounds = true
		layer.cornerRadius = radius
		layer.borderColor = UIColor.white.cgColor
		layer.borderWidth = 5.0
		backgroundColor = .white

		let crosshairs = CrossHairsLayer(radius: 12.0)
		crosshairs.position = bounds.center()
		crosshairs.zPosition = 10.0
		layer.addSublayer(crosshairs)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	enum Position {
		case topLeft
		case topRight
	}

	var position: Position = .topLeft

	private func setPositionImmediately(_ pos: Position) {
		guard let superview = superview else { return }
		translatesAutoresizingMaskIntoConstraints = false

		superview.removeConstraints(superview.constraints.compactMap({
			($0.firstItem as? UIView == self || $0.secondItem as? UIView == self) ? $0 : nil }))
		removeConstraints(constraints)
		if #available(iOS 11.0, *) {
			topAnchor.constraint(equalTo: superview.safeAreaLayoutGuide.topAnchor).isActive = true
			switch pos {
			case .topLeft:
				leftAnchor.constraint(equalTo: superview.safeAreaLayoutGuide.leftAnchor).isActive = true
			case .topRight:
				rightAnchor.constraint(equalTo: superview.safeAreaLayoutGuide.rightAnchor).isActive = true
			}
		} else {
			topAnchor.constraint(equalTo: superview.topAnchor, constant: layoutMargins.top).isActive = true
			switch pos {
			case .topLeft:
				leftAnchor.constraint(equalTo: superview.leftAnchor, constant: layoutMargins.left).isActive = true
			case .topRight:
				rightAnchor.constraint(equalTo: superview.rightAnchor, constant: layoutMargins.right).isActive = true
			}
		}
		widthAnchor.constraint(equalToConstant: 2 * radius).isActive = true
		heightAnchor.constraint(equalToConstant: 2 * radius).isActive = true
	}

	func setPosition(_ pos: Position, animated: Bool) {
		position = pos
		if animated {
			setPositionImmediately(pos)
			UIView.animate(withDuration: 0.6,
			               delay: 0,
			               usingSpringWithDamping: 0.5,
			               initialSpringVelocity: 0.6,
			               options: .beginFromCurrentState,
			               animations: {
			               	self.superview?.layoutIfNeeded()
			               })
		} else {
			setPositionImmediately(pos)
		}
	}

	func setSourceCenter(_ point: CGPoint, in view: UIView, visible: Bool) {
		sourceCenter = point
		let localPoint = convert(point, from: view)
		if bounds.contains(localPoint) {
			let newPos: Position = position == .topLeft ? .topRight : .topLeft
			setPosition(newPos, animated: true)
		}
		isHidden = !visible
	}

	func captureViewAt(_ rect: CGRect) -> UIView {
		let view = sourceView.resizableSnapshotView(from: rect,
		                                            afterScreenUpdates: false,
		                                            withCapInsets: UIEdgeInsets()) ?? UIView()
		return view
	}

	// Copy the contents of the given layer at the given rect and return as a UIView
	func captureLayer(_ layer: CALayer, at rect: CGRect) -> UIView {
		let renderer = UIGraphicsImageRenderer(size: rect.size)
		let image = renderer.image { context in
			context.cgContext.translateBy(x: -rect.origin.x, y: -rect.origin.y)
			return layer.render(in: context.cgContext)
		}
		let view = UIView(frame: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
		view.layer.contents = image.cgImage
		return view
	}

	override func layoutSubviews() {
		// remove all subviews (should only be 1)
		subviews.forEach { $0.removeFromSuperview() }

		let captureRadius = radius / scale
		let rect = CGRect(x: sourceCenter.x - captureRadius,
		                  y: sourceCenter.y - captureRadius,
		                  width: 2 * captureRadius,
		                  height: 2 * captureRadius)
		let image = captureLayer(AppDelegate.shared.mapView.aerialLayer, at: rect)
//		let image = captureViewAt(rect)
		image.frame = bounds
		image.layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
		addSubview(image)
	}
}
