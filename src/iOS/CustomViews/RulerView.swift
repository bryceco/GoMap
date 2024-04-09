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
	private var shapeLayer: CAShapeLayer
	private var textLayer: CATextLayer
	private var unitType: UnitType {
		didSet {
			updateText()
		}
	}

	var mapView: MapView? {
		didSet {
			mapView?.mapTransform.observe(by: self, callback: { self.updateText() })
		}
	}

	enum UnitType: String {
		case metric, imperial
	}

	required init?(coder: NSCoder) {
		shapeLayer = CAShapeLayer()
		textLayer = CATextLayer()
		unitType = Locale.current.usesMetricSystem ? .metric : .imperial

		super.init(coder: coder)
		self.isUserInteractionEnabled = true

		backgroundColor = nil

		shapeLayer.lineWidth = 2
		shapeLayer.strokeColor = UIColor.black.cgColor
		shapeLayer.fillColor = nil

		let font = UIFont.preferredFont(forTextStyle: .caption2)
		let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .caption2)
		let monospacedFontDescriptor = fontDescriptor.addingAttributes([
			.featureSettings: [[
				UIFontDescriptor.FeatureKey.featureIdentifier: kNumberSpacingType,
				UIFontDescriptor.FeatureKey.typeIdentifier: kMonospacedNumbersSelector
			]]
		])
		let monospacedFont = UIFont(descriptor: monospacedFontDescriptor, size: font.pointSize)
		textLayer.font = monospacedFont
		textLayer.fontSize = 12 // font.pointSize;
		textLayer.foregroundColor = UIColor.black.cgColor
		textLayer.alignmentMode = .center
		textLayer.contentsScale = UIScreen.main.scale

		layer.shadowColor = UIColor.white.cgColor
		layer.shadowRadius = 0.0
		layer.shadowOpacity = 0.4
		layer.shadowOffset = CGSize(width: 0, height: 0)
		layer.shadowPath = CGPath(rect: bounds.insetBy(dx: -2, dy: -2), transform: nil)

		shapeLayer.shadowOpacity = 0.0
		textLayer.shadowOpacity = 0.0

		layer.addSublayer(shapeLayer)
		layer.addSublayer(textLayer)

		let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(toggleUnitType))
		addGestureRecognizer(tapGestureRecognizer)

		NotificationCenter.default.addObserver(self, selector: #selector(localeDidChange), name: NSLocale.currentLocaleDidChangeNotification, object: nil)
	}

	override var frame: CGRect {
		get {
			return super.frame
		}
		set(frame) {
			super.frame = frame
			shapeLayer.frame = bounds
			setNeedsLayout()
		}
	}

	override func layoutSubviews() {
		let rc = bounds
		if rc.size.width <= 1 || rc.size.height <= 1 {
			return
		}

		let path = CGMutablePath()
		path.move(to: CGPoint(x: rc.minX, y: rc.minY))
		path.addLine(to: CGPoint(x: rc.minX, y: rc.maxY))
		path.addLine(to: CGPoint(x: rc.maxX, y: rc.maxY))
		path.addLine(to: CGPoint(x: rc.maxX, y: rc.minY))
		shapeLayer.path = path

		textLayer.frame = rc
	}

	private func updateText() {
		guard let mapView = mapView else {
			return
		}
		let left = convert(CGPoint(x: bounds.minX, y: bounds.minY), to: mapView)
		let right = convert(CGPoint(x: bounds.maxX, y: bounds.minY), to: mapView)
		let rulerLength = mapView.distance(from: left, to: right)

		var width = Measurement(value: rulerLength, unit: UnitLength.meters)
		switch unitType {
		case .metric:
			if width.value >= 1000 {
				width = width.converted(to: .kilometers)
			} else if width.value < 1.0 {
				width = width.converted(to: .centimeters)
			}
		case .imperial:
			width = width.converted(to: .feet)
			if width.value >= 5280 {
				width = width.converted(to: .miles)
			} else if width.value < 1.0 {
				width = width.converted(to: .inches)
			}
		}

		let formatter = MeasurementFormatter()
		formatter.unitOptions = [.providedUnit]
		formatter.numberFormatter = NumberFormatter()
		formatter.numberFormatter.minimumSignificantDigits = 3
		formatter.numberFormatter.maximumSignificantDigits = 3
		textLayer.string = formatter.string(from: width)
	}

	@objc private func toggleUnitType() {
		unitType = (unitType == .metric) ? .imperial : .metric
	}

	@objc private func localeDidChange() {
		unitType = Locale.current.usesMetricSystem ? .metric : .imperial
	}

	override func setNeedsLayout() {
		super.setNeedsLayout()
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}
}
