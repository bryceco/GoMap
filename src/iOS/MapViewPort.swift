//
//  MapViewPort.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/10/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit

// Allows other layers of the map to view changes to the map view
protocol MapViewPort: AnyObject, MapViewProgress {
	var mapTransform: MapTransform { get }
}

// Add functions for retrieving metrics about the viewport (read-only)
extension MapViewPort {
	func screenCenterPoint() -> CGPoint {
		return AppDelegate.shared.mapView.bounds.center()
	}

	func metersPerPixel() -> Double {
		return mapTransform.metersPerPixel(atScreenPoint: screenCenterPoint())
	}

	func pixelsPerDegree() -> OSMSize {
		let metersPerPixel = metersPerPixel()
		let metersPerDegree = MetersPerDegreeAt(latitude: screenCenterLatLon().lat)
		return OSMSize(width: metersPerDegree.x / metersPerPixel,
		               height: metersPerDegree.y / metersPerPixel)
	}

	func boundingMapRectForScreen() -> OSMRect {
		let rc = OSMRect(AppDelegate.shared.mapView.layer.bounds)
		return mapTransform.boundingMapRect(forScreenRect: rc)
	}

	func boundingLatLonForScreen() -> OSMRect {
		let rc = boundingMapRectForScreen()
		let rect = MapTransform.latLon(forMapRect: rc)
		return rect
	}

	func screenCenterLatLon() -> LatLon {
		return mapTransform.latLon(forScreenPoint: screenCenterPoint())
	}
}

// MARK: Resize & movement
let DisplayLinkHeading = "Heading"
let DisplayLinkPanning = "Panning" // disable gestures inside toolbar buttons

extension MapViewPort {

	var mapFromScreenTransform: OSMTransform {
		return mapTransform.transform.inverse()
	}

	func isLocationSpecified() -> Bool {
		return !(mapTransform.transform == .identity)
	}

	func adjustOrigin(by delta: CGPoint) {
		if delta.x == 0.0, delta.y == 0.0 {
			return
		}

		let o = OSMTransform.translation(Double(delta.x), Double(delta.y))
		let t = mapTransform.transform.concat(o)
		mapTransform.transform = t
	}

	func adjustZoom(by ratio: CGFloat, aroundScreenPoint zoomCenter: CGPoint) {
		guard ratio != 1.0,
		      AppDelegate.shared.mapView.isRotateObjectMode == nil
		else {
			return
		}

		let maxZoomIn = Double(Int(1) << 30)

		let scale = mapTransform.scale()
		var ratio = Double(ratio)
		if ratio * scale < 1.0 {
			ratio = 1.0 / scale
		}
		if ratio * scale > maxZoomIn {
			ratio = maxZoomIn / scale
		}

		let offset = mapTransform.mapPoint(forScreenPoint: OSMPoint(zoomCenter), birdsEye: false)
		var t = mapTransform.transform
		t = t.translatedBy(dx: offset.x, dy: offset.y)
		t = t.scaledBy(ratio)
		t = t.translatedBy(dx: -offset.x, dy: -offset.y)
		mapTransform.transform = t
	}

	func rotate(by angle: CGFloat, aroundScreenPoint zoomCenter: CGPoint) {
		if angle == 0.0 {
			return
		}

		let offset = mapTransform.mapPoint(forScreenPoint: OSMPoint(zoomCenter), birdsEye: false)
		var t = mapTransform.transform
		t = t.translatedBy(dx: offset.x, dy: offset.y)
		t = t.rotatedBy(Double(angle))
		t = t.translatedBy(dx: -offset.x, dy: -offset.y)
		mapTransform.transform = t

		// FIXME: remove this
		let mapView = AppDelegate.shared.mapView!
		let mainView = AppDelegate.shared.mainView!

		let screenAngle = mapTransform.rotation()
		mainView.compassButton.rotate(angle: CGFloat(screenAngle))
		if !mapView.locationBallLayer.isHidden {
			if mapView.gpsState == .HEADING,
			   abs(mapView.locationBallLayer.heading - -.pi / 2) < 0.0001
			{
				// don't pin location ball to North until we've animated our rotation to north
				mapView.locationBallLayer.heading = -.pi / 2
			} else {
				if let heading = mapView.locationManager.heading {
					let heading = mapView.heading(for: heading)
					mapView.locationBallLayer.heading = CGFloat(screenAngle + heading - .pi / 2)
				}
			}
		}
	}

	func animateRotation(by deltaHeading: Double, aroundPoint center: CGPoint) {
		var deltaHeading = deltaHeading
		// don't rotate the long way around
		while deltaHeading < -.pi {
			deltaHeading += 2 * .pi
		}
		while deltaHeading > .pi {
			deltaHeading -= 2 * .pi
		}

		if abs(deltaHeading) < 0.00001 {
			return
		}

		let startTime = CACurrentMediaTime()

		let duration = 0.4
		var prevHeading: Double = 0
		weak let weakSelf = self
		DisplayLink.shared.addName(DisplayLinkHeading, block: {
			if let myself = weakSelf {
				var elapsedTime = CACurrentMediaTime() - startTime
				if elapsedTime > duration {
					elapsedTime = CFTimeInterval(duration) // don't want to over-rotate
				}
				// Rotate using an ease-in/out curve. This ensures that small changes in direction don't cause jerkiness.
				// result = interpolated value, t = current time, b = initial value, c = delta value, d = duration
				func easeInOutQuad(_ t: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
					var t = t
					t /= d / 2
					if t < 1 {
						return c / 2 * t * t + b
					}
					t -= 1
					return -c / 2 * (t * (t - 2) - 1) + b
				}
				let miniHeading = easeInOutQuad(elapsedTime, 0, deltaHeading, duration)
				myself.rotate(by: CGFloat(miniHeading - prevHeading), aroundScreenPoint: center)
				prevHeading = miniHeading
				if elapsedTime >= duration {
					DisplayLink.shared.removeName(DisplayLinkHeading)
				}
			}
		})
	}

	func rotateBirdsEye(by angle: Double) {
		var angle = angle
		// limit maximum rotation
		var t = mapTransform.transform
		let maxRotation = Double(65 * (Double.pi / 180))
#if TRANSFORM_3D
		let currentRotation = atan2(t.m23, t.m22)
#else
		let currentRotation = Double(mapTransform.birdsEyeRotation)
#endif
		if currentRotation + angle > maxRotation {
			angle = maxRotation - currentRotation
		}
		if currentRotation + Double(angle) < 0 {
			angle = -currentRotation
		}

		let offset = mapTransform.mapPoint(forScreenPoint: OSMPoint(screenCenterPoint()),
		                                   birdsEye: false)

		t = t.translatedBy(dx: offset.x, dy: offset.y)
#if TRANSFORM_3D
		t = CATransform3DRotate(t, delta, 1.0, 0.0, 0.0)
#else
		mapTransform.birdsEyeRotation += angle
#endif
		t = t.translatedBy(dx: -offset.x, dy: -offset.y)
		mapTransform.transform = t

		let mapView = AppDelegate.shared.mapView!
		if !mapView.locationBallLayer.isHidden {
			mapView.updateUserLocationIndicator(nil)
		}
	}

	func rotateToNorth() {
		// Rotate to face North
		let center = screenCenterPoint()
		let rotation = mapTransform.rotation()
		animateRotation(by: -rotation, aroundPoint: center)
	}

	func rotateToHeading() {
		// Rotate to face current compass heading
		let mapView = AppDelegate.shared.mapView!

		if let heading = mapView.locationManager.heading {
			let center = mapView.viewPort.screenCenterPoint()
			let screenAngle = mapView.viewPort.mapTransform.rotation()
			let heading = mapView.heading(for: heading)
			animateRotation(by: -(screenAngle + heading), aroundPoint: center)
		}
	}
}

// Add functions for changing the location of the viewport
extension MapViewPort {
	// MARK: Set location

	// Try not to call this directly, since scale isn't something exposed.
	// Use one of the centerOn() functions instead.
	func setTransformFor(latLon: LatLon, scale: Double? = nil) {
		var lat = latLon.lat
		lat = min(lat, MapTransform.latitudeLimit)
		lat = max(lat, -MapTransform.latitudeLimit)
		let latLon2 = LatLon(latitude: lat, longitude: latLon.lon)
		let point = mapTransform.screenPoint(forLatLon: latLon2, birdsEye: false)
		let center = screenCenterPoint()
		let delta = CGPoint(x: center.x - point.x, y: center.y - point.y)
		adjustOrigin(by: delta)

		if let scale = scale {
			let ratio = scale / mapTransform.scale()
			adjustZoom(by: CGFloat(ratio), aroundScreenPoint: screenCenterPoint())
		}
	}

	// center without changing zoom
	func centerOn(latLon: LatLon) {
		setTransformFor(latLon: latLon, scale: nil)
	}

	func centerOn(latLon: LatLon, zoom: Double) {
		let scale = pow(2.0, zoom)
		setTransformFor(latLon: latLon,
		                scale: scale)
	}

	func centerOn(latLon: LatLon, metersWide: Double) {
		let degrees = metersToDegrees(meters: metersWide, latitude: latLon.lat)
		let scale = 360 / (degrees / 2)
		setTransformFor(latLon: latLon,
		                scale: scale)
	}

	func centerOn(_ location: MapLocation) {
		let zoom = location.zoom > 0 ? location.zoom : 21.0
		let latLon = LatLon(latitude: location.latitude, longitude: location.longitude)
		centerOn(latLon: latLon,
		         zoom: zoom)
		let rotation = location.direction * .pi / 180.0 + mapTransform.rotation()
		rotate(by: CGFloat(-rotation), aroundScreenPoint: screenCenterPoint())
		if let state = location.viewState {
			AppDelegate.shared.mapView.viewState = state
		}
	}
}
