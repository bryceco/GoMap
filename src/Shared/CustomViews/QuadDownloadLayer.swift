//
//  QuadDownloadLayer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/29/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

/// This class is used only for debugging.
/// It displays the quads that are downloading OSM data.
/// See: MapView.quadDownloadLayer and OsmMapData.downloadMissingData()
final class QuadDownloadLayer: CALayer {
	private let mapData: OsmMapData
	private let viewPort: MapViewPort

	// MARK: Implementation

	override init(layer: Any) {
		let layer = layer as! QuadDownloadLayer
		mapData = layer.mapData
		viewPort = layer.viewPort
		super.init(layer: layer)
	}

	init(mapData: OsmMapData, viewPort: MapViewPort) {
		self.mapData = mapData
		self.viewPort = viewPort
		super.init()

		needsDisplayOnBoundsChange = true

		viewPort.mapTransform.onChange.subscribe(self) { _ in
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
		sublayers = []
		mapData.region.enumerate({ quad in
			if !quad.isDownloaded, !quad.busy {
				return
			}
			let rect = quad.rect
			let p1 = viewPort.mapTransform.screenPoint(
				forLatLon: LatLon(lon: rect.origin.x, lat: rect.origin.y),
				birdsEye: true)
			let p2 = viewPort.mapTransform.screenPoint(
				forLatLon: LatLon(lon: rect.origin.x + rect.size.width, lat: rect.origin.y),
				birdsEye: true)
			let p3 = viewPort.mapTransform.screenPoint(
				forLatLon: LatLon(lon: rect.origin.x + rect.size.width, lat: rect.origin.y + rect.size.height),
				birdsEye: true)
			let p4 = viewPort.mapTransform.screenPoint(
				forLatLon: LatLon(lon: rect.origin.x, lat: rect.origin.y + rect.size.height),
				birdsEye: true)

			let color: CGColor
			if quad.busy {
				color = UIColor.yellow.withAlphaComponent(0.3).cgColor
			} else {
				color = UIColor.green.withAlphaComponent(0.15).cgColor
			}

			let path = CGMutablePath()
			path.move(to: p1)
			path.addLine(to: p2)
			path.addLine(to: p3)
			path.addLine(to: p4)
			path.closeSubpath()

			let shapeLayer = CAShapeLayer()
			shapeLayer.path = path
			shapeLayer.fillColor = color
			shapeLayer.strokeColor = UIColor.black.cgColor
			shapeLayer.lineWidth = 1.0

			self.addSublayer(shapeLayer)
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

extension QuadDownloadLayer: MapLayersView.LayerOrView {
	var hasTileServer: TileServer? {
		return nil
	}

	func removeFromSuper() {
		removeFromSuperlayer()
	}
}
