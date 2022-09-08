//
//  QuadDownloadLayer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/29/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import QuartzCore
import UIKit

/// This class is used only for debugging.
/// It displays the quads that are downloading OSM data.
/// See: MapView.quadDownloadLayer and OsmMapData.downloadMissingData()
final class QuadDownloadLayer: CALayer {
	let mapView: MapView

	// MARK: Implementation

	override init(layer: Any) {
		let layer = layer as! QuadDownloadLayer
		mapView = layer.mapView
		super.init(layer: layer)
	}

	init(mapView: MapView) {
		self.mapView = mapView
		super.init()

		needsDisplayOnBoundsChange = true

		// disable animations
		actions = [
			"onOrderIn": NSNull(),
			"onOrderOut": NSNull(),
			"sublayers": NSNull(),
			"contents": NSNull(),
			"bounds": NSNull(),
			"position": NSNull(),
			"anchorPoint": NSNull(),
			"transform": NSNull(),
			"isHidden": NSNull()
		]

		mapView.mapTransform.observe(by: self, callback: {
			self.setNeedsLayout()
		})
	}

	override func layoutSublayers() {
		if isHidden {
			return
		}
		// update locations of tiles
		let tRotation = mapView.screenFromMapTransform.rotation()
		sublayers = []
		mapView.editorLayer.mapData.region.enumerate({ quad in
			if !quad.isDownloaded, !quad.busy {
				return
			}
			let upperLeft = mapView.mapTransform.screenPoint(forLatLon: LatLon(quad.rect.origin), birdsEye: true)
			let bottomRight = mapView.mapTransform.screenPoint(
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
