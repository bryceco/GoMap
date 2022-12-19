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
			isHidden = false
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

	func setSourceCenter(_ point: CGPoint, in view: UIView) {
		sourceCenter = point
	}

	func captureViewAt(_ rect: CGRect) -> UIView {
		let view = sourceView.resizableSnapshotView(from: rect,
		                                            afterScreenUpdates: false,
		                                            withCapInsets: UIEdgeInsets()) ?? UIView()
		return view
	}

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
		let captureRadius = radius / scale
		let rect = CGRect(x: sourceCenter.x - captureRadius,
		                  y: sourceCenter.y - captureRadius,
		                  width: 2 * captureRadius,
		                  height: 2 * captureRadius)
		let image = captureLayer(AppDelegate.shared.mapView.aerialLayer, at: rect)
//		let image = captureViewAt(rect)
		image.frame = bounds
		image.layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
		subviews.forEach { $0.removeFromSuperview() }
		addSubview(image)
	}
}
