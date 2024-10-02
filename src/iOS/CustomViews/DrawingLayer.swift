//
//  DrawingLayer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/27/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import UIKit


private class PathShapeLayer: CAShapeLayer {
	fileprivate struct Properties {
		var position: OSMPoint?
		var lineWidth: CGFloat
	}

	let firstPoint: LatLon?

	fileprivate var props = Properties(position: nil, lineWidth: 0.0)

	// An array of paths, each simplified according to zoom level
	// so we have good performance when zoomed out:
	fileprivate var shapePaths = [CGPath?](repeating: nil, count: 32)

	var color: UIColor = .red {
		didSet {
			strokeColor = color.cgColor
			setNeedsLayout()
		}
	}
    
    var polygonFillColor: UIColor = .cyan {
        didSet {
            strokeColor = color.cgColor
            setNeedsLayout()
        }
    }
    
    private func isPolygon(points: [CGPoint]) -> Bool {
        if points.count < 3 {
            return false
        }
        
        if points.first == points.last {
            return true
        }
        return false
    }

	override init(layer: Any) {
		let layer = layer as! PathShapeLayer
		props = layer.props
		shapePaths = layer.shapePaths
		color = layer.color
		firstPoint = layer.firstPoint
		super.init(layer: layer)
	}

	init(withLatLonPath latLonPath: CGPath) {
        let points = latLonPath.getPoints()
		if let first = points.first {
			firstPoint = LatLon(lon: first.x, lat: first.y)
		} else {
			firstPoint = nil
		}
		super.init()
		var refPoint = OSMPoint.zero
		shapePaths = [CGPath?](repeating: nil, count: 32)
		shapePaths[0] = Self.mapPath(for: latLonPath, refPoint: &refPoint)
		path = shapePaths[0]
		anchorPoint = CGPoint.zero
		position = CGPoint(refPoint)
		strokeColor = color.cgColor
        fillColor = nil
        if isPolygon(points: points) {
            fillColor = polygonFillColor.cgColor
        }
		lineWidth = 2.0
		lineCap = .square
		lineJoin = .miter
		zPosition = 0.0
		actions = actions
		props.position = refPoint
		props.lineWidth = lineWidth

		actions = [
			"onOrderIn": NSNull(),
			"onOrderOut": NSNull(),
			"hidden": NSNull(),
			"sublayers": NSNull(),
			"contents": NSNull(),
			"bounds": NSNull(),
			"position": NSNull(),
			"transform": NSNull(),
			"lineWidth": NSNull()
		]
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// Convert the points to a CGPath in Map coordinates so we can draw it
	fileprivate static func mapPath(for latLonPath: CGPath, refPoint: inout OSMPoint) -> CGPath {
		var newPath = CGMutablePath()
		var haveFirst = false

		latLonPath.apply(action: { element in
			let elementPt = element.points[0]
			var mappedPoint = MapTransform.mapPoint(forLatLon: LatLon(lon: elementPt.x, lat: elementPt.y))
			if !haveFirst {
				haveFirst = true
				refPoint = mappedPoint
			}
			mappedPoint.x -= refPoint.x
			mappedPoint.y -= refPoint.y
			mappedPoint.x *= PATH_SCALING
			mappedPoint.y *= PATH_SCALING
			switch element.type {
			case .moveToPoint:
				newPath.move(to: CGPoint(mappedPoint))
			case .addLineToPoint:
				newPath.addLine(to: CGPoint(mappedPoint))
			case .closeSubpath:
				newPath.closeSubpath()
			default:
				// not implemented
				fatalError()
			}
		})

		// place refPoint at upper-left corner of bounding box so it can be the origin for the frame/anchorPoint
		let bbox = newPath.boundingBoxOfPath
		var tran = CGAffineTransform(translationX: -bbox.origin.x, y: -bbox.origin.y)
		if let path2 = newPath.mutableCopy(using: &tran) {
			newPath = path2
		}
		refPoint = OSMPoint(x: refPoint.x + Double(bbox.origin.x) / PATH_SCALING,
		                    y: refPoint.y + Double(bbox.origin.y) / PATH_SCALING)
		return newPath
	}
}

protocol DrawingLayerDelegate {
	func geojsonData() -> [(GeoJSONGeometry, UIColor)]
}

// A layer that draws things stored in GeoJSON formats.
class DrawingLayer: CALayer {
	let mapView: MapView

	var geojsonDelegate: DrawingLayerDelegate?

	private var layerDict: [UUID: PathShapeLayer]

	@available(*, unavailable)
	required init?(coder aDecoder: NSCoder) {
		fatalError()
	}

	init(mapView: MapView) {
		self.mapView = mapView
		layerDict = [:]
		super.init()

		actions = [
			"onOrderIn": NSNull(),
			"onOrderOut": NSNull(),
			"hidden": NSNull(),
			"sublayers": NSNull(),
			"contents": NSNull(),
			"bounds": NSNull(),
			"position": NSNull(),
			"transform": NSNull(),
			"lineWidth": NSNull()
		]

		// observe changes to geometry
		mapView.mapTransform.observe(by: self, callback: { self.setNeedsLayout() })

		setNeedsLayout()
	}

	// MARK: Drawing

	override var bounds: CGRect {
		get {
			return super.bounds
		}
		set(bounds) {
			super.bounds = bounds
			setNeedsLayout()
		}
	}

	private func layoutSublayersSafe() {
		let tRotation = mapView.screenFromMapTransform.rotation()
		let tScale = mapView.screenFromMapTransform.scale() / PATH_SCALING
		var scale = Int(floor(-log(tScale)))
		if scale < 0 {
			scale = 0
		}

		// get list of GeoJSON structs
		let geomList = geojsonDelegate?.geojsonData() ?? []

		// compute what's new and what's old
		var newDict: [UUID: PathShapeLayer] = [:]
		for (geom, color) in geomList {
			if let layer = layerDict.removeValue(forKey: geom.uuid) {
				// Layer already exists
				layer.color = color
				newDict[geom.uuid] = layer
			} else {
				// It's a new layer
				if let path = geom.latLonBezierPath {
					let layer = PathShapeLayer(withLatLonPath: path.cgPath)
					layer.color = color
					newDict[geom.uuid] = layer
				}
			}
		}
		for layer in layerDict.values {
			layer.removeFromSuperlayer()
		}
		layerDict = newDict

		// move the layers to the correct location on screen
		for layer in layerDict.values {
			// adjust point density according to zoom level
			if layer.shapePaths[scale] == nil {
				let epsilon = pow(Double(10.0), Double(scale)) / 256.0
				layer.shapePaths[scale] = layer.shapePaths[0]?.pathWithReducedPoints(epsilon)
			}
			layer.path = layer.shapePaths[scale]

			// configure the layer for presentation
			guard let pt = layer.props.position else { return }
			let pt2 = OSMPoint(mapView.mapTransform.screenPoint(forMapPoint: pt, birdsEye: false))

			// rotate and scale
			var t = CGAffineTransform(translationX: CGFloat(pt2.x - pt.x), y: CGFloat(pt2.y - pt.y))
			t = t.scaledBy(x: CGFloat(tScale), y: CGFloat(tScale))
			t = t.rotated(by: CGFloat(tRotation))

			layer.setAffineTransform(t)

			layer.lineWidth = layer.props.lineWidth / CGFloat(tScale)

			// add the layer if not already present
			if layer.superlayer == nil {
				insertSublayer(layer, at: UInt32(sublayers?.count ?? 0)) // place at bottom
			}
		}

		if mapView.mapTransform.birdsEyeRotation != 0 {
			var t = CATransform3DIdentity
			t.m34 = -1.0 / CGFloat(mapView.mapTransform.birdsEyeDistance)
			t = CATransform3DRotate(t, CGFloat(mapView.mapTransform.birdsEyeRotation), 1.0, 0, 0)
			sublayerTransform = t
		} else {
			sublayerTransform = CATransform3DIdentity
		}
	}

	override func layoutSublayers() {
		if !isHidden {
			layoutSublayersSafe()
		}
	}
}
