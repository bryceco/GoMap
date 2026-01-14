//
//  MapViewPort.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/10/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import CoreLocation
import UIKit

// Allows other layers of the map to view changes to the map view
protocol MapViewPort: AnyObject {
	var mapTransform: MapTransform { get }
}

final class MapViewPortObject: MapViewPort {
	var mapTransform = MapTransform()
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
		DisplayLink.shared.addName(DisplayLinkHeading, block: { [weak self] in
			guard let self else { return }

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
			self.rotate(by: CGFloat(miniHeading - prevHeading), aroundScreenPoint: center)
			prevHeading = miniHeading
			if elapsedTime >= duration {
				DisplayLink.shared.removeName(DisplayLinkHeading)
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
	}

	func headingAdjustedForInterfaceOrientation(_ clHeading: CLHeading) -> Double {
		var heading = clHeading.trueHeading * .pi / 180
		if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
			switch scene.interfaceOrientation {
			case .portraitUpsideDown:
				heading += .pi
			case .landscapeLeft:
				heading -= .pi / 2
			case .landscapeRight:
				heading += .pi / 2
			case .portrait:
				fallthrough
			default:
				break
			}
		}
		return heading
	}

	func rotateToHeading(_ heading: Double) {
		// Rotate to face current compass heading
		let center = screenCenterPoint()
		let screenAngle = mapTransform.rotation()
		animateRotation(by: -(screenAngle + heading), aroundPoint: center)
	}

	func rotateToNorth() {
		rotateToHeading(0.0)
	}
}

// Add functions for changing the location of the viewport
extension MapViewPort {
	// MARK: Set location

	// Try not to call this directly, since scale isn't something exposed.
	// Use one of the centerOn() functions instead.
	func setTransformFor(
		latLon: LatLon,
		scale newScale: Double? = nil,
		rotation: Double? = nil)
	{
		// Current matrix
		let old = mapTransform.transform

		// Extract current scale from matrix magnitude
		let currentScale = mapTransform.scale()
		let scale = newScale ?? currentScale

		// Compute uniform scale factor
		let factor = scale / currentScale

		// Scale the matrix without touching rotation
		let a = old.a * factor
		let b = old.b * factor
		let c = old.c * factor
		let d = old.d * factor

		// Compute translation to center on the new lat/lon
		let pt = MapTransform.mapPoint(forLatLon: latLon)
		let tx = -(pt.x * a + pt.y * c)
		let ty = -(pt.x * b + pt.y * d)

		mapTransform.transform = OSMTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
	}

	// center without changing zoom or rotation, such as when pressing the Center button
	func centerOn(latLon: LatLon, zoom: Double?, rotation: Double?) {
		let scale: Double?
		if let zoom {
			scale = pow(2.0, zoom)
		} else {
			scale = nil
		}
		setTransformFor(latLon: latLon,
		                scale: scale,
		                rotation: rotation)
	}

	func centerOn(latLon: LatLon, metersWide: Double?) {
		let metersWide = metersWide ?? 20.0
		let degrees = metersToDegrees(meters: metersWide, latitude: latLon.lat)
		let scale = 360 / (degrees / 2)
		setTransformFor(latLon: latLon,
		                scale: scale,
		                rotation: 0.0)
	}

	func updateHeading(_ heading: Double, accuracy: Double) {
		let screenAngle = mapTransform.rotation()

		if AppDelegate.shared.mainView.gpsState == .HEADING {
			// rotate to new heading
			let center = screenCenterPoint()
			let delta = -(heading + screenAngle)
			rotate(by: CGFloat(delta), aroundScreenPoint: center)
		} else if let locationBall = AppDelegate.shared.mainView?.locationBallView {
			// rotate location ball
			locationBall.headingAccuracy = CGFloat(accuracy * (.pi / 180))
			locationBall.showHeading = true
			locationBall.heading = CGFloat(heading + screenAngle - .pi / 2)
		}
	}
}
