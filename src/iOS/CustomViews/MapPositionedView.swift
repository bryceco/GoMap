//
//  MapPositionedView.swift
//  OpenStreetMap
//
//  Protocol for views that track a geographic location on the map
//

import CoreLocation
import UIKit

protocol MapPositionedView: UIView {
	var location: LatLon { get set }
	var viewPort: MapViewPort? { get set }

	/// Called when the view's screen position needs to be updated
	func updateScreenPosition()
}

extension MapPositionedView {

	/// Default implementation of screen position update
	func screenPoint() -> CGPoint? {
		guard
			let viewPort,
			let mapView = AppDelegate.shared.mapView
		else {
			return nil
		}
		let point = viewPort.mapTransform.screenPoint(forLatLon: location, birdsEye: false)
		return viewPort.mapTransform.wrappedScreenPoint(point, screenBounds: mapView.bounds)
	}

	func updateScreenPosition() {
		if let point = screenPoint() {
			center = point
		}
	}

	/// Default implementation of location update
	func updateLocationDefault(_ location: LatLon) {
		// set new position
		self.location = location
		updateScreenPosition()
	}

	func updateLocation(_ location: LatLon) {
		updateLocationDefault(location)
	}

	/// Call this in the viewPort didSet to handle subscription management
	func viewPortChange(oldValue: MapViewPort?) {
		oldValue?.mapTransform.onChange.unsubscribe(self as AnyObject)
		viewPort?.mapTransform.onChange.subscribe(self as AnyObject) { [weak self] in
			self?.updateScreenPosition()
		}
	}
}
