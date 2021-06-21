//
//  RulerLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/11/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit

func roundToEvenValue(_ value: Double) -> Double {
	var scale: Double = 1

	while true {
		if value < scale * 10 {
			if floor(value / scale) < 2 {
				return 1 * scale
			}
			if floor(value / scale) < 5 {
				return 2 * scale
			}
			return 5 * scale
		}
		scale *= 10
	}
}

class RulerView: UIView {
	var _shapeLayer: CAShapeLayer
	var _metricTextLayer: CATextLayer
	var _britishTextLayer: CATextLayer
	var mapView: MapView? {
		didSet {
			mapView?.mapTransform.observe(by: self, callback: { self.setNeedsLayout() })
		}
	}

	required init?(coder: NSCoder) {
		_shapeLayer = CAShapeLayer()
		_metricTextLayer = CATextLayer()
		_britishTextLayer = CATextLayer()

		super.init(coder: coder)
		backgroundColor = nil

		_shapeLayer.lineWidth = 2
		_shapeLayer.strokeColor = UIColor.black.cgColor
		_shapeLayer.fillColor = nil

#if os(iOS)
		let font = UIFont.preferredFont(forTextStyle: .caption2)
#else
		let font = NSFont.labelFont(ofSize: 12)
#endif

		_metricTextLayer.font = font
		_britishTextLayer.font = font
		_metricTextLayer.fontSize = 12 // font.pointSize;
		_britishTextLayer.fontSize = 12 // font.pointSize;
		_metricTextLayer.foregroundColor = UIColor.black.cgColor
		_britishTextLayer.foregroundColor = UIColor.black.cgColor
		_metricTextLayer.alignmentMode = .center
		_britishTextLayer.alignmentMode = .center
		_metricTextLayer.contentsScale = UIScreen.main.scale
		_britishTextLayer.contentsScale = UIScreen.main.scale

		layer.shadowColor = UIColor.white.cgColor
		layer.shadowRadius = 0.0
		layer.shadowOpacity = 0.4
		layer.shadowOffset = CGSize(width: 0, height: 0)

		_shapeLayer.shadowOpacity = 0.0
		_metricTextLayer.shadowOpacity = 0.0
		_britishTextLayer.shadowOpacity = 0.0

		layer.addSublayer(_shapeLayer)
		layer.addSublayer(_metricTextLayer)
		layer.addSublayer(_britishTextLayer)
	}

	override var frame: CGRect {
		get {
			return super.frame
		}
		set(frame) {
			super.frame = frame

			_shapeLayer.frame = bounds

			setNeedsLayout()
		}
	}

	override func layoutSubviews() {
		let rc = bounds
		if rc.size.width <= 1 || rc.size.height <= 1 {
			return
		}

		let metersPerPixel = mapView?.metersPerPixel() ?? 0.0
		if metersPerPixel == 0 {
			return
		}

		var metricWide = Double(rc.size.width) * metersPerPixel
		var britishWide = metricWide * 3.28084 // feet per meter

		var metricUnit = "meter"
		var metricSuffix = "s"
		if metricWide >= 1000 {
			metricWide /= 1000
			metricUnit = "km"
			metricSuffix = ""
		} else if metricWide < 1.0 {
			metricWide *= 100
			metricUnit = "cm"
			metricSuffix = ""
		}
		var britishUnit = "feet"
		var britishSuffix = ""
		if britishWide >= 5280 {
			britishWide /= 5280
			britishUnit = "mile"
			britishSuffix = "s"
		} else if britishWide < 1.0 {
			britishWide *= 12
			britishUnit = "inch"
			britishSuffix = "es"
		}
		let metricPerPixel = metricWide / Double(rc.size.width)
		let britishPerPixel = britishWide / Double(rc.size.width)

		metricWide = roundToEvenValue(metricWide)
		britishWide = roundToEvenValue(britishWide)

		let metricPixels = round(metricWide / metricPerPixel)
		let britishPixels = round(britishWide / britishPerPixel)

		// metric bar on bottom
		let path = CGMutablePath()
		path.move(to: CGPoint(x: rc.origin.x, y: rc.origin.y + rc.size.height))
		path.addLine(to: CGPoint(x: rc.origin.x, y: rc.origin.y + rc.size.height / 2))
		path.addLine(to: CGPoint(x: CGFloat(Double(rc.origin.x) + metricPixels), y: rc.origin.y + rc.size.height / 2))
		path.addLine(to: CGPoint(x: CGFloat(Double(rc.origin.x) + metricPixels), y: rc.origin.y + rc.size.height))

		// british bar on top
		path.move(to: CGPoint(x: rc.origin.x, y: rc.origin.y))
		path.addLine(to: CGPoint(x: rc.origin.x, y: rc.origin.y + rc.size.height / 2))
		path.addLine(to: CGPoint(x: CGFloat(Double(rc.origin.x) + britishPixels),
		                         y: rc.origin.y + rc.size.height / 2))
		path.addLine(to: CGPoint(x: CGFloat(Double(rc.origin.x) + britishPixels),
		                         y: rc.origin.y))

		_shapeLayer.path = path

		var rect = bounds
		rect.size.width = CGFloat(metricPixels)
		rect.origin.y = CGFloat(round(Double(rc.origin.y + rc.size.height / 2)))
		_metricTextLayer.frame = rect

		rect.size.width = CGFloat(britishPixels)
		rect.origin.y = CGFloat(round(Double(rc.origin.y)))
		_britishTextLayer.frame = rect

		_metricTextLayer.string = String(format: "%ld %@%@", Int(metricWide), metricUnit, metricWide > 1 ? metricSuffix : "")
		_britishTextLayer.string = String(format: "%ld %@%@", Int(britishWide), britishUnit, britishWide > 1 ? britishSuffix : "")

		rect.size.width = CGFloat(max(metricPixels, britishPixels))
		rect = rect.insetBy(dx: -2, dy: -2)
		let path2 = CGPath(rect: rect, transform: nil)
		layer.shadowPath = path2
	}
}
