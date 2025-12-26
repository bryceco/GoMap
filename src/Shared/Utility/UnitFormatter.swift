//
//  UnitFormatter.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/25/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import Foundation

enum UnitType: String {
	case metric, imperial
}

class UnitFormatter {
	static let shared = UnitFormatter()

	private let measurementFormatter: MeasurementFormatter = {
		let formatter = MeasurementFormatter()
		formatter.unitOptions = [.providedUnit]
		formatter.numberFormatter = NumberFormatter()
		formatter.numberFormatter.minimumSignificantDigits = 3
		formatter.numberFormatter.maximumSignificantDigits = 3
		return formatter
	}()

	// format a distance to look nice
	func stringFor(meters: Double, unitType: UnitType) -> String {
		var width = Measurement(value: meters, unit: UnitLength.meters)
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

		return measurementFormatter.string(from: width)
	}

	func stringFor(meters: Double) -> String {
		let units: UnitType = Locale.current.usesMetricSystem ? .metric : .imperial
		return stringFor(meters: meters,
		                 unitType: units)
	}
}
