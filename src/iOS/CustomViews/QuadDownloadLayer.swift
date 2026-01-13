//
//  QuadDownloadLayer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/29/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import QuartzCore
import UIKit

/// This class is used only for debugging.
/// It displays the quads that are downloading OSM data.
/// See: MapView.quadDownloadLayer and OsmMapData.downloadMissingData()
final class QuadDownloadLayer: CALayer {
	let mapView: MapView
	let viewPort: MapViewPort

	// MARK: Implementation

	override init(layer: Any) {
		let layer = layer as! QuadDownloadLayer
		mapView = layer.mapView
		viewPort = layer.viewPort
		super.init(layer: layer)
	}

	init(mapView: MapView, viewPort: MapViewPort) {
		self.mapView = mapView
		self.viewPort = viewPort
		super.init()

		needsDisplayOnBoundsChange = true

		mapView.viewPort.mapTransform.onChange.subscribe(self) { _ in
			self.setNeedsLayout()
		}
	}

	override func action(forKey event: String) -> (any CAAction)? {
		return NSNull()
	}

	override func layoutSublayers() {
		if isHidden {
			return
		}
		// update locations of tiles
		let tRotation = mapView.viewPort.mapTransform.rotation()
		sublayers = []
		mapView.editorLayer.mapData.region.enumerate({ quad in
			if !quad.isDownloaded, !quad.busy {
				return
			}
			let upperLeft = mapView.viewPort.mapTransform.screenPoint(
				forLatLon: LatLon(quad.rect.origin),
				birdsEye: true)
			let bottomRight = mapView.viewPort.mapTransform.screenPoint(
				forLatLon: LatLon(lon: quad.rect.origin.x + quad.rect.size.width,
				                  lat: quad.rect.origin.y + quad.rect.size.height),
				birdsEye: true)
			let screenRect = CGRect(
				x: upperLeft.x,
				y: upperLeft.y,
				width: bottomRight.x - upperLeft.x,
				height: bottomRight.y - upperLeft.y)
			/*
			 if !screenRect.intersects(self.bounds) {
			 	return
			 }
			 */
			let color: CGColor
			if quad.busy {
				color = UIColor.yellow.withAlphaComponent(0.3).cgColor
			} else {
				color = UIColor.green.withAlphaComponent(0.15).cgColor
			}
			let layer = CALayer()
			layer.frame = screenRect
			layer.backgroundColor = color
//			layer.anchorPoint = CGPoint(x: 0, y: 0)
			layer.borderColor = UIColor.black.cgColor
			layer.borderWidth = 1.0

			// we don't support screen rotation so this is broken
			let t = CGAffineTransform(rotationAngle: CGFloat(tRotation))
			layer.setAffineTransform(t)

			self.addSublayer(layer)
		})
	}

	override var transform: CATransform3D {
		get {
			return super.transform
		}
		set(transform) {
			super.transform = transform
			setNeedsLayout()
		}
	}

	override var isHidden: Bool {
		didSet(wasHidden) {
			if wasHidden, !isHidden {
				setNeedsLayout()
			}
		}
	}

	@available(*, unavailable)
	required init?(coder aDecoder: NSCoder) {
		fatalError()
	}
}
