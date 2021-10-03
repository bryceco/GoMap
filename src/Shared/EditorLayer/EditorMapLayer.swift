//
//  OsmMapLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/5/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import CoreGraphics
import CoreLocation
import UIKit

// compile options:
public let SHOW_3D = false
private let FADE_INOUT = false
private let SINGLE_SIDED_WALLS = true

// drawing options
private let DEFAULT_LINECAP = CAShapeLayerLineCap.square
private let DEFAULT_LINEJOIN = CAShapeLayerLineJoin.miter
private let MinIconSizeInPixels: CGFloat = 24.0
private let Pixels_Per_Character: CGFloat = 8.0
private let NodeHighlightRadius: CGFloat = 6.0

// MARK: MenuLocation enum

// Specifies where the owner should places UIAlert messages and menus
enum MenuLocation {
	case none
	case editBar
	case rect(CGRect)
}

// MARK: EditorMapLayerOwner protocol

// The UIView that hosts us.
protocol EditorMapLayerOwner: UIView, MapViewProgress {
	var mapTransform: MapTransform { get }

	func crosshairs() -> CGPoint

	func pushpinView() -> PushPinView? // fetch the pushpin from owner
	func removePin()
	func placePushpin(at: CGPoint, object: OsmBaseObject?)
	func placePushpinForSelection(at point: CGPoint?)

	func flashMessage(_ message: String)
	func showAlert(_ title: String, message: String?)
	func presentAlert(alert: UIAlertController, location: MenuLocation)
	func presentError(_ error: Error, flash: Bool)

	func setScreenFromMap(transform: OSMTransform) // used when undo/redo change the location
	func boundingLatLonRectForScreen() -> OSMRect
	func metersPerPixel() -> Double

	// boolean options chosen by owner
	func useTurnRestrictions() -> Bool
	func useAutomaticCacheManagement() -> Bool
	func useUnnamedRoadHalo() -> Bool

	// editing actions handled by owner
	func presentTagEditor(_ sender: Any?)
	func presentEditActionSheet(_ sender: Any?)
	func presentTurnRestrictionEditor()

	// FIXME: We should move this functionality into EditorMapLayer
	func blink(_ object: OsmBaseObject?, segment: Int)
	func unblinkObject()
	func startObjectRotation()

	// FIXME: this shouldn't be in the editor layer. Move to MapView.
	func addNote()

	// notify owner that tags changed so it can refresh e.g. fixme= buttons
	func didUpdateObject()
	func selectionDidChange()
}

// MARK: EditorMapLayer

final class EditorMapLayer: CALayer {
	let highwayScale: CGFloat = 2.0
	var shownObjects: ContiguousArray<OsmBaseObject> = []
	var fadingOutSet: [OsmBaseObject] = []
	var highlightLayers: [CALayer] = []
	var isPerformingLayout = false
	var baseLayer: CATransformLayer

	struct DragState {
		var startPoint: LatLon // to track total movement
		var didMove: Bool // to maintain undo stack
		var confirmDrag: Bool // should we confirm that the user wanted to drag the selected object? Only if they haven't modified it since selecting it
	}

	var dragState = DragState(startPoint: .zero, didMove: false, confirmDrag: false)

	let objectFilters = EditorFilters()

	var whiteText = false {
		didSet {
			if oldValue != whiteText {
				CurvedGlyphLayer.whiteOnBlack = whiteText
				resetDisplayLayers()
			}
		}
	}

	let mapData: OsmMapData
	let owner: EditorMapLayerOwner

	var silentUndo = false // don't flash message about undo

	private(set) var atVisibleObjectLimit = false
	private let geekbenchScoreProvider = Geekbench()

	init(owner: EditorMapLayerOwner) {
		self.owner = owner

		var t = CACurrentMediaTime()
		var alert: UIAlertController?
		do {
			let mapData = try OsmMapData.withArchivedData()
			t = CACurrentMediaTime() - t
			if owner.useAutomaticCacheManagement() {
				_ = mapData.discardStaleData()
			} else if t > 5.0 {
				// need to pause before posting the alert because the view controller isn't ready here yet
				let text = NSLocalizedString(
					"Your OSM data cache is getting large, which may lead to slow startup and shutdown times.\n\nYou may want to clear the cache (under Display settings) to improve performance.",
					comment: "")
				alert = UIAlertController(
					title: NSLocalizedString("Cache size warning", comment: ""),
					message: text,
					preferredStyle: .alert)
				alert!
					.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
			}
			self.mapData = mapData
		} catch {
			mapData = OsmMapData()
			mapData.purgeHard() // force database to get reset

			if let error = error as? MapDataError,
			   error == MapDataError.archiveDoesNotExist
			{
				// a clean install
			} else {
				print("Database error: \(error.localizedDescription)")
				alert = UIAlertController(title: NSLocalizedString("Database error", comment: ""),
				                          message: NSLocalizedString(
				                          	"Something went wrong while attempting to restore your data. Any pending changes have been lost. Sorry.",
				                          	comment: ""),
				                          preferredStyle: .alert)
				alert!
					.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
			}
		}

		baseLayer = CATransformLayer()

		super.init()

		if let alert = alert {
			// this has to occur after super.init()
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
				self.owner.presentAlert(alert: alert, location: .none)
			})
		}

		objectFilters.onChange = { self.mapData.clearCachedProperties() }
		whiteText = true

		// observe changes to screen
		owner.mapTransform.observe(by: self, callback: { self.updateMapLocation() })

		OsmMapData.g_EditorMapLayerForArchive = self

		mapData.undoContextForComment = { comment in
			let location = Data.fromStruct(self.owner.mapTransform.transform)
			var dict: [String: Any] = [:]
			dict["comment"] = comment
			dict["location"] = location
			if let pushpin = self.owner.pushpinView()?.arrowPoint {
				dict["pushpin"] = NSCoder.string(for: pushpin)
			}
			if let selectedRelation = self.selectedRelation {
				dict["selectedRelation"] = selectedRelation
			}
			if let selectedWay = self.selectedWay {
				dict["selectedWay"] = selectedWay
			}
			if let selectedNode = self.selectedNode {
				dict["selectedNode"] = selectedNode
			}
			return dict
		}
		mapData.undoCommentCallback = { undo, context in
			if self.silentUndo {
				return
			}

			guard let action = context["comment"] as? String,
			      let location = context["location"] as? Data,
			      let transform: OSMTransform = location.asStruct()
			else { return }
			// FIXME: Use Coder for OSMTransform (warning: doing this will break backwards compatibility)
			owner.setScreenFromMap(transform: transform)
			let title = undo ? NSLocalizedString("Undo", comment: "") : NSLocalizedString("Redo", comment: "")

			self.selectedRelation = context["selectedRelation"] as? OsmRelation
			self.selectedWay = context["selectedWay"] as? OsmWay
			self.selectedNode = context["selectedNode"] as? OsmNode
			if self.selectedNode?.deleted ?? false {
				self.selectedNode = nil
			}

			if let pushpin = context["pushpin"] as? String,
			   let primary = self.selectedPrimary
			{
				// since we don't record the pushpin location until after a drag has begun we need to re-center on the object:
				var pt = NSCoder.cgPoint(for: pushpin)
				let loc = self.owner.mapTransform.latLon(forScreenPoint: pt)
				let pos = primary.latLonOnObject(forLatLon: loc)
				pt = self.owner.mapTransform.screenPoint(forLatLon: pos, birdsEye: true)
				// place pushpin
				self.owner.placePushpin(at: pt, object: primary)
			} else {
				self.owner.removePin()
			}
			let message = "\(title) \(action)"
			self.owner.flashMessage(message)
		}
		addSublayer(baseLayer)

		NotificationCenter.default.addObserver(
			forName: UIContentSizeCategory.didChangeNotification,
			object: nil,
			queue: nil,
			using: { _ in
				self.resetDisplayLayers()
			})
	}

	override init(layer: Any) {
		let layer = layer as! EditorMapLayer
		owner = layer.owner
		mapData = layer.mapData
		baseLayer = CATransformLayer() // not sure if we should provide the original or not?
		super.init(layer: layer)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	override var bounds: CGRect {
		get { super.bounds }
		set {
			super.bounds = newValue
			baseLayer.frame = bounds
			baseLayer.bounds = bounds // need to set both of these so bounds stays in sync with superlayer bounds
			updateMapLocation()
		}
	}

	func save() {
		mapData.archiveModifiedData()
	}

	// MARK: Map data

	func clearCachedProperties() {
		mapData.clearCachedProperties() // reset layers associated with objects
		setNeedsLayout()
	}

	func purgeCachedDataHard(_ hard: Bool) {
		owner.removePin()
		selectedNode = nil
		selectedWay = nil
		selectedRelation = nil
		if hard {
			mapData.purgeHard()
		} else {
			mapData.purgeSoft()
		}

		setNeedsLayout()
		updateMapLocation()
	}

	func updateMapLocation() {
		if isHidden {
			mapData.cancelCurrentDownloads()
			return
		}

		if owner.mapTransform.transform.a == 1.0 {
			return // identity, we haven't been initialized yet
		}

		let box = owner.boundingLatLonRectForScreen()
		if box.size.height <= 0 || box.size.width <= 0 {
			return
		}

		let view: ViewRegion
		switch MapTransform.projection {
		case .mercator:
			view = ViewRegion(encloses: { return box.containsRect($0)},
							  intersects: { return box.intersectsRect($0)})
		case .polarSouth:
			let mapTransform = owner.mapTransform
			let sc = self.bounds
			view = ViewRegion(encloses: {
				let corners = $0.corners().map { mapTransform.screenPoint(forLatLon: LatLon($0), birdsEye: true) }
				return corners.first(where: { !sc.contains($0) }) == nil
			}, intersects: {
				let corners = $0.corners().map { mapTransform.screenPoint(forLatLon: LatLon($0), birdsEye: true) }
				return corners.first(where: { sc.contains($0) }) != nil
			})
		}

		let center = owner.mapTransform.latLon(forScreenPoint: owner.crosshairs())
		print("box contains center = \(box.containsPoint(OSMPoint(center)))")

		mapData.downloadMissingData(inRect: view, withProgress: owner, didChange: { [self] error in
			if let error = error {
				// present error asynchrounously so we don't interrupt the current UI action
				DispatchQueue.main.async(execute: { [self] in
					// if we've been hidden don't bother displaying errors
					if !isHidden {
						owner.presentError(error, flash: true)
					}
				})
				return
			}
			setNeedsLayout()
		})
		setNeedsLayout()
	}

	func didReceiveMemoryWarning() {
		purgeCachedDataHard(false)
		save()
	}

	// MARK: Common Drawing

	static func ImageScaledToSize(_ image: UIImage, _ iconSize: CGFloat) -> UIImage {
		var size = CGSize(width: Int(iconSize * UIScreen.main.scale), height: Int(iconSize * UIScreen.main.scale))
		let ratio = image.size.height / image.size.width
		if ratio < 1.0 {
			size.height *= ratio
		} else if ratio > 1.0 {
			size.width /= ratio
		}
		UIGraphicsBeginImageContext(size)
		image.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
		let newIcon = UIGraphicsGetImageFromCurrentImageContext()!
		UIGraphicsEndImageContext()
		return newIcon
	}

	static func IconScaledForDisplay(_ icon: UIImage) -> UIImage {
		return EditorMapLayer.ImageScaledToSize(icon, MinIconSizeInPixels)
	}

	func path(for way: OsmWay) -> CGPath {
		let path = CGMutablePath()
		var first = true
		for node in way.nodes {
			let pt = owner.mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: false)
			if pt.x.isInfinite {
				break
			}
			if first {
				path.move(to: CGPoint(x: pt.x, y: pt.y))
				first = false
			} else {
				path.addLine(to: CGPoint(x: pt.x, y: pt.y))
			}
		}
		return path
	}

	static let shopColor = UIColor(red: 0xAC / 255.0, green: 0x39 / 255.0, blue: 0xAC / 255.0, alpha: 1.0)
	static let treeColor = UIColor(red: 18 / 255.0, green: 122 / 255.0, blue: 56 / 255.0, alpha: 1.0)
	static let amenityColor = UIColor(red: 0x73 / 255.0, green: 0x4A / 255.0, blue: 0x08 / 255.0, alpha: 1.0)
	static let tourismColor = UIColor(red: 0x00 / 255.0, green: 0x92 / 255.0, blue: 0xDA / 255.0, alpha: 1.0)
	static let medicalColor = UIColor(red: 0xDA / 255.0, green: 0x00 / 255.0, blue: 0x92 / 255.0, alpha: 1.0)
	static let poiColor = UIColor.blue
	static let stopColor = UIColor(red: 196 / 255.0, green: 4 / 255.0, blue: 4 / 255.0, alpha: 1.0)

	func defaultColor(for object: OsmBaseObject) -> UIColor? {
		if object.tags["shop"] != nil {
			return EditorMapLayer.shopColor
		} else if object.tags["amenity"] != nil || object.tags["building"] != nil || object.tags["leisure"] != nil {
			return EditorMapLayer.amenityColor
		} else if object.tags["tourism"] != nil || object.tags["transport"] != nil {
			return EditorMapLayer.tourismColor
		} else if object.tags["medical"] != nil {
			return EditorMapLayer.medicalColor
		} else if object.tags["name"] != nil {
			return EditorMapLayer.poiColor
		} else if object.tags["natural"] == "tree" {
			return EditorMapLayer.treeColor
		} else if object.isNode() != nil, object.tags["highway"] == "stop" {
			return EditorMapLayer.stopColor
		}
		return nil
	}

	private func HouseNumberForObjectTags(_ tags: [String: String]) -> String? {
		guard let houseNumber = tags["addr:housenumber"] else {
			return nil
		}
		if let unitNumber = tags["addr:unit"] {
			return "\(houseNumber)/\(unitNumber)"
		}
		return houseNumber
	}

	func invoke(
		alongScreenClippedWay way: OsmWay,
		block: @escaping (_ p1: OSMPoint, _ p2: OSMPoint, _ isEntry: Bool, _ isExit: Bool) -> Bool)
	{
		let viewRect = OSMRect(bounds)
		var prevInside: Bool = false
		var prev = OSMPoint.zero
		var first = true

		for node in way.nodes {
			let pt = OSMPoint(owner.mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: false))
			let inside = viewRect.containsPoint(pt)
			defer {
				prev = pt
				prevInside = inside
			}
			if first {
				first = false
				continue
			}

			var cross: [OSMPoint] = []
			if !(prevInside && inside) {
				// at least one point was outside, so determine where line intersects the screen
				cross = EditorMapLayer.ClipLineToRect(p1: prev, p2: pt, rect: viewRect)
				if cross.isEmpty {
					// both are outside and didn't cross
					continue
				}
			}

			let p1 = prevInside ? prev : cross[0]
			let p2 = inside ? pt : cross.last!

			let proceed = block(p1, p2, !prevInside, !inside)
			if !proceed {
				break
			}
			prevInside = inside
		}
	}

	func invoke(
		alongScreenClippedWay way: OsmWay,
		offset initialOffset: Double,
		interval: Double,
		block: @escaping (_ pt: OSMPoint, _ direction: OSMPoint) -> Void)
	{
		var offset = initialOffset
		invoke(alongScreenClippedWay: way, block: { p1, p2, isEntry, _ in
			if isEntry {
				offset = initialOffset
			}
			var dx: Double = p2.x - p1.x
			var dy: Double = p2.y - p1.y
			let len = hypot(dx, dy)
			dx /= len
			dy /= len
			while offset < len {
				// found it
				let pos = OSMPoint(x: p1.x + offset * dx, y: p1.y + offset * dy)
				let dir = OSMPoint(x: dx, y: dy)
				block(pos, dir)
				offset += interval
			}
			offset -= len
			return true
		})
	}

	// clip a way to the path inside the viewable rect so we can draw a name on it
	func pathClipped(toViewRect way: OsmWay, length pLength: UnsafeMutablePointer<CGFloat>?) -> CGPath? {
		var path: CGMutablePath?
		var length = 0.0
		var firstPoint = OSMPoint.zero
		var lastPoint = OSMPoint.zero

		invoke(alongScreenClippedWay: way, block: { p1, p2, _, isExit in
			if path == nil {
				path = CGMutablePath()
				path!.move(to: CGPoint(x: p1.x, y: p1.y))
				firstPoint = p1
			}
			path!.addLine(to: CGPoint(x: p2.x, y: p2.y))
			lastPoint = p2
			length += hypot(p1.x - p2.x, p1.y - p2.y)
			if isExit {
				return false
			}
			return true
		})
		if path != nil {
			// orient path so text draws right-side up
			if lastPoint.x - firstPoint.x < 0 {
				// reverse path
				path = path!.reversed()
			}
		}
		if pLength != nil {
			pLength!.pointee = CGFloat(length)
		}

		return path
	}

	// MARK: CAShapeLayer drawing

	private static let ZSCALE: CGFloat = 0.001
	private static let Z_BASE: CGFloat = -1.0
	private let Z_OCEAN = Z_BASE + 1 * ZSCALE
	private let Z_AREA = Z_BASE + 2 * ZSCALE
	private let Z_HALO = Z_BASE + 3 * ZSCALE
	private let Z_CASING = Z_BASE + 4 * ZSCALE
	private let Z_LINE = Z_BASE + 5 * ZSCALE
	private let Z_TEXT = Z_BASE + 6 * ZSCALE
	private let Z_ARROW = Z_BASE + 7 * ZSCALE
	private let Z_NODE = Z_BASE + 8 * ZSCALE
	private let Z_TURN = Z_BASE + 9 * ZSCALE // higher than street signals, etc
	private let Z_BUILDING_WALL = Z_BASE + 10 * ZSCALE
	private let Z_BUILDING_ROOF = Z_BASE + 11 * ZSCALE
	private let Z_HIGHLIGHT_WAY = Z_BASE + 12 * ZSCALE
	private let Z_HIGHLIGHT_NODE = Z_BASE + 13 * ZSCALE
	private let Z_HIGHLIGHT_ARROW = Z_BASE + 14 * ZSCALE

	func buildingWallLayer(for p1: OSMPoint, point p2: OSMPoint, height: Double,
	                       hue: CGFloat) -> CALayerWithProperties?
	{
		var dir = Sub(p2, p1)
		let length = Mag(dir)
		let angle = atan2(dir.y, dir.x)

		dir.x /= length
		dir.y /= length

		var intensity = angle / .pi
		if intensity < 0 {
			intensity += 1
		}
		let color = UIColor(
			hue: (37 + hue) / 360.0,
			saturation: 0.61,
			brightness: CGFloat(0.5 + intensity / 2),
			alpha: 1.0)

		let wall = CALayerWithProperties()
		wall.anchorPoint = CGPoint(x: 0, y: 0)
		wall.zPosition = Z_BUILDING_WALL
#if SINGLE_SIDED_WALLS
		wall.doubleSided = false
#else
		wall.isDoubleSided = true
#endif
		wall.isOpaque = true
		wall.frame = CGRect(x: 0, y: 0, width: CGFloat(length * PATH_SCALING), height: CGFloat(height))
		wall.backgroundColor = color.cgColor
		wall.position = CGPoint(p1)
		wall.borderWidth = 1.0
		wall.borderColor = UIColor.black.cgColor

		let t1 = CATransform3DMakeRotation(.pi / 2, CGFloat(dir.x), CGFloat(dir.y), 0)
		let t2 = CATransform3DMakeRotation(CGFloat(angle), 0, 0, 1)
		let t = CATransform3DConcat(t2, t1)
		wall.transform = t

		let props = wall.properties
		props.transform = t
		props.position = p1
		props.lineWidth = 1.0
		props.is3D = true

		return wall
	}

	func getShapeLayers(for object: OsmBaseObject) -> [CALayer & LayerPropertiesProviding] {
		if object.shapeLayers != nil {
			return object.shapeLayers!
		}

		let renderInfo = object.renderInfo!
		var layers: [CALayer & LayerPropertiesProviding] = []

		if let node = object as? OsmNode {
			layers.append(contentsOf: shapeLayers(for: node))
		}

		// casing
		if object.isWay() != nil || (object.isRelation()?.isMultipolygon() ?? false) {
			if renderInfo.lineWidth != 0.0, !(object.isWay()?.isArea() ?? false) {
				var refPoint = OSMPoint.zero
				let path = object.linePathForObject(withRefPoint: &refPoint)
				if let path = path {
					do {
						let layer = CAShapeLayerWithProperties()
						layer.anchorPoint = CGPoint(x: 0, y: 0)
						layer.position = CGPoint(refPoint)
						layer.path = path
						layer.strokeColor = UIColor.black.cgColor
						layer.fillColor = nil
						layer.lineWidth = (1 + renderInfo.lineWidth) * highwayScale
						layer.lineCap = DEFAULT_LINECAP
						layer.lineJoin = DEFAULT_LINEJOIN
						layer.zPosition = Z_CASING
						let props = layer.properties
						props.position = refPoint
						props.lineWidth = layer.lineWidth
						if let bridge = object.tags["bridge"],
						   !OsmTags.isOsmBooleanFalse(bridge)
						{
							props.lineWidth += 4
						}
						if let tunnel = object.tags["tunnel"],
						   !OsmTags.isOsmBooleanFalse(tunnel)
						{
							props.lineWidth += 2
							layer.strokeColor = UIColor.brown.cgColor
						}

						layers.append(layer)
					}

					// provide a halo for streets that don't have a name
					if owner.useUnnamedRoadHalo(), object.isWay()?.needsNoNameHighlight() ?? false {
						// it lacks a name
						let haloLayer = CAShapeLayerWithProperties()
						haloLayer.anchorPoint = CGPoint(x: 0, y: 0)
						haloLayer.position = CGPoint(refPoint)
						haloLayer.path = path
						haloLayer.strokeColor = UIColor.red.cgColor
						haloLayer.fillColor = nil
						haloLayer.lineWidth = (2 + renderInfo.lineWidth) * highwayScale
						haloLayer.lineCap = DEFAULT_LINECAP
						haloLayer.lineJoin = DEFAULT_LINEJOIN
						haloLayer.zPosition = Z_HALO
						let haloProps = haloLayer.properties
						haloProps.position = refPoint
						haloProps.lineWidth = haloLayer.lineWidth

						layers.append(haloLayer)
					}
				}
			}
		}
		// way (also provides an outline for areas)
		if object.isWay() != nil || (object.isRelation()?.isMultipolygon() ?? false) {
			var refPoint = OSMPoint(x: 0, y: 0)
			let path = object.linePathForObject(withRefPoint: &refPoint)

			if let path = path {
				var lineWidth = renderInfo.lineWidth * highwayScale
				if lineWidth == 0 {
					lineWidth = 1
				}

				let layer = CAShapeLayerWithProperties()
				layer.anchorPoint = CGPoint(x: 0, y: 0)
				let bbox = path.boundingBoxOfPath
				layer.bounds = CGRect(x: 0, y: 0, width: bbox.size.width, height: bbox.size.height)
				layer.position = CGPoint(refPoint)
				layer.path = path
				layer.strokeColor = (renderInfo.lineColor ?? UIColor.black).cgColor
				layer.fillColor = nil
				layer.lineWidth = lineWidth
				layer.lineCap = DEFAULT_LINECAP
				layer.lineJoin = DEFAULT_LINEJOIN
				layer.zPosition = Z_LINE

				let props = layer.properties
				props.position = refPoint
				props.lineWidth = layer.lineWidth
				layers.append(layer)
			}
		}

		// Area
		if (object.isWay()?.isArea() ?? false) || (object.isRelation()?.isMultipolygon() ?? false) {
			if let areaColor = renderInfo.areaColor,
			   !object.isCoastline()
			{
				var refPoint = OSMPoint.zero
				let path = object.shapePathForObject(withRefPoint: &refPoint)
				if let path = path {
					// draw
					let alpha: CGFloat = object.tags["landuse"] != nil ? 0.15 : 0.25
					let layer = CAShapeLayerWithProperties()
					layer.anchorPoint = CGPoint(x: 0, y: 0)
					layer.path = path
					layer.position = CGPoint(refPoint)
					layer.fillColor = areaColor.withAlphaComponent(alpha).cgColor
					layer.lineCap = DEFAULT_LINECAP
					layer.lineJoin = DEFAULT_LINEJOIN
					layer.zPosition = Z_AREA
					let props = layer.properties
					props.position = refPoint

					layers.append(layer)
					if SHOW_3D {
						// if its a building then add walls for 3D
						if object.tags["building"] != nil {
							// calculate height in meters
							var height: Double = 0.0
							if let value = object.tags["height"] {
								// height in meters?
								var v1: Double = 0
								var v2: Double = 0
								let scanner = Scanner(string: value)
								if scanner.scanDouble(&v1) {
									scanner.scanCharacters(from: CharacterSet.whitespacesAndNewlines, into: nil)
									if scanner.scanString("'", into: nil) {
										// feet
										if scanner.scanDouble(&v2) {
											if scanner.scanString("\"", into: nil) {
												// inches
											} else {
												// malformed
											}
										}
										height = (v1 * 12 + v2) * 0.0254 // meters/inch
									} else if scanner.scanString("ft", into: nil) {
										height = v1 * 0.3048 // meters/foot
									} else if scanner.scanString("yd", into: nil) {
										height = v1 * 0.9144 // meters/yard
									}
								}
							} else {
								var levels = Double(object.tags["building:levels"] ?? "0") ?? 0.0
								if levels == 0 {
									levels = 1
								}
								height = 3 * levels // 3 meters per level
							}
							let hue = CGFloat(object.ident % 20 - 10)
							var hasPrev = false
							var prevPoint = OSMPoint.zero
							path.apply(action: { [self] element in
								if element.type == .moveToPoint {
									prevPoint = Add(refPoint, Mult(OSMPoint(element.points[0]), 1 / PATH_SCALING))
									hasPrev = true
								} else if element.type == .addLineToPoint, hasPrev {
									let pt = Add(refPoint, Mult(OSMPoint(element.points[0]), 1 / PATH_SCALING))
									let wall = buildingWallLayer(for: pt, point: prevPoint, height: height, hue: hue)
									if let wall = wall {
										layers.append(wall)
									}
									prevPoint = pt
								} else {
									hasPrev = false
								}
							})
							if true {
								// get roof
								let color = UIColor(hue: 0, saturation: 0.05, brightness: 0.75 + hue / 100, alpha: 1.0)
								let roof = CAShapeLayerWithProperties()
								roof.anchorPoint = CGPoint(x: 0, y: 0)
								let bbox = path.boundingBoxOfPath
								roof.bounds = CGRect(x: 0, y: 0, width: bbox.size.width, height: bbox.size.height)
								roof.position = CGPoint(refPoint)
								roof.path = path
								roof.fillColor = color.cgColor
								roof.strokeColor = UIColor.black.cgColor
								roof.lineWidth = 1.0
								roof.lineCap = DEFAULT_LINECAP
								roof.lineJoin = DEFAULT_LINEJOIN
								roof.zPosition = Z_BUILDING_ROOF
								roof.isDoubleSided = true

								let t = CATransform3DMakeTranslation(0, 0, CGFloat(height))
								roof.properties.position = refPoint
								roof.properties.transform = t
								roof.properties.is3D = true
								roof.properties.lineWidth = 1.0
								roof.transform = t
								layers.append(roof)
							}
						}
					} // SHOW_3D
				}
			}
		}

		// Names
		if object.isWay() != nil || (object.isRelation()?.isMultipolygon() ?? false) {
			// get object name, or address if no name
			var name = object.givenName()
			if name == nil {
				name = HouseNumberForObjectTags(object.tags)
			}

			if let name = name {
				let isHighway = object.isWay() != nil && !(object.isWay()?.isArea() ?? false)
				if isHighway {
					// These are drawn dynamically
				} else {
					let point = object.isWay() != nil ? object.isWay()!.centerPoint() : object.isRelation()!
						.centerPoint()
					let pt = MapTransform.mapPoint(forLatLon: point)

					let layer = CurvedGlyphLayer.layerWithString(name)
					layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
					layer.position = CGPoint(x: pt.x, y: pt.y)
					layer.zPosition = Z_TEXT

					let props = layer.properties
					props.position = pt

					layers.append(layer)
				}
			}
		}

		// Turn Restrictions
		if owner.useTurnRestrictions() {
			if object.isRelation()?.isRestriction() ?? false {
				let viaMembers = object.isRelation()?.members(byRole: "via") ?? []
				for viaMember in viaMembers {
					if let viaMemberObject = viaMember.obj,
					   viaMemberObject.isNode() != nil || viaMemberObject.isWay() != nil
					{
						let latLon = viaMemberObject.selectionPoint()
						let pt = MapTransform.mapPoint(forLatLon: latLon)

						let restrictionLayerIcon = CALayerWithProperties()
						restrictionLayerIcon.bounds = CGRect(
							x: 0,
							y: 0,
							width: CGFloat(MinIconSizeInPixels),
							height: CGFloat(MinIconSizeInPixels))
						restrictionLayerIcon.anchorPoint = CGPoint(x: 0.5, y: 0.5)
						restrictionLayerIcon.position = CGPoint(x: pt.x, y: pt.y)
						if viaMember.isWay(), object.tags["restriction"] == "no_u_turn" {
							restrictionLayerIcon.contents = UIImage(named: "no_u_turn")?.cgImage
						} else {
							restrictionLayerIcon.contents = UIImage(named: "restriction_sign")?.cgImage
						}
						restrictionLayerIcon.zPosition = Z_TURN
						let restrictionIconProps = restrictionLayerIcon.properties
						restrictionIconProps.position = pt

						layers.append(restrictionLayerIcon)
					}
				}
			}
		}
		object.shapeLayers = layers
		return layers
	}

	// use the "marker" icon
	static let genericMarkerIcon: UIImage = {
		var markerIcon = UIImage(named: "maki-marker-stroked")!
		markerIcon = EditorMapLayer.IconScaledForDisplay(markerIcon)
		return markerIcon
	}()

	/// Determines the `CALayer` instances required to present the given `node` on the map.
	/// - Parameter node: The `OsmNode` instance to get the layers for.
	/// - Returns: A list of `CALayer` instances that are used to represent the given `node` on the map.
	func shapeLayers(for node: OsmNode) -> [CALayer & LayerPropertiesProviding] {
		var layers: [CALayer & LayerPropertiesProviding] = []

		let directionLayers = directionShapeLayers(with: node)
		layers.append(contentsOf: directionLayers)

		let pt = MapTransform.mapPoint(forLatLon: node.latLon)
		var drawRef = true

		// fetch icon
		let feature = PresetsDatabase.shared.matchObjectTagsToFeature(node.tags,
		                                                              geometry: node.geometry(),
		                                                              includeNSI: false)
		var icon = feature?.iconScaled24()
		if icon == nil {
			if node.tags["amenity"] != nil || node.tags["name"] != nil {
				icon = Self.genericMarkerIcon
			}
		}
		if let icon = icon {
			/// White circle as the background
			let backgroundLayer = CALayer()
			backgroundLayer.bounds = CGRect(
				x: 0,
				y: 0,
				width: CGFloat(MinIconSizeInPixels),
				height: CGFloat(MinIconSizeInPixels))
			backgroundLayer.backgroundColor = UIColor.white.cgColor
			backgroundLayer.cornerRadius = MinIconSizeInPixels / 2.0
			backgroundLayer.masksToBounds = true
			backgroundLayer.anchorPoint = CGPoint.zero
			backgroundLayer.borderColor = UIColor.darkGray.cgColor
			backgroundLayer.borderWidth = 1.0
			backgroundLayer.isOpaque = true

			/// The actual icon image serves as a `mask` for the icon's color layer, allowing for "tinting" of the icons.
			let iconMaskLayer = CALayer()
			let padding: CGFloat = 4
			iconMaskLayer.frame = CGRect(
				x: padding,
				y: padding,
				width: CGFloat(MinIconSizeInPixels) - padding * 2,
				height: CGFloat(MinIconSizeInPixels) - padding * 2)
			iconMaskLayer.contents = icon.cgImage

			let iconLayer = CALayer()
			iconLayer.bounds = CGRect(
				x: 0,
				y: 0,
				width: CGFloat(MinIconSizeInPixels),
				height: CGFloat(MinIconSizeInPixels))
			let iconColor = defaultColor(for: node)
			iconLayer.backgroundColor = (iconColor ?? UIColor.black).cgColor
			iconLayer.mask = iconMaskLayer
			iconLayer.anchorPoint = CGPoint.zero
			iconLayer.isOpaque = true

			let layer = CALayerWithProperties()
			layer.addSublayer(backgroundLayer)
			layer.addSublayer(iconLayer)
			layer.bounds = CGRect(x: 0, y: 0, width: CGFloat(MinIconSizeInPixels), height: CGFloat(MinIconSizeInPixels))
			layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
			layer.position = CGPoint(x: pt.x, y: pt.y)
			layer.zPosition = Z_NODE
			layer.isOpaque = true

			let props = layer.properties
			props.position = pt
			layers.append(layer)
		} else {
			// draw generic box
			let color = defaultColor(for: node)
			if let houseNumber = color != nil ? nil : HouseNumberForObjectTags(node.tags) {
				let layer = CurvedGlyphLayer.layerWithString(houseNumber)
				layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
				layer.position = CGPoint(x: pt.x, y: pt.y)
				layer.zPosition = Z_TEXT
				let props = layer.properties
				props.position = pt

				drawRef = false

				layers.append(layer)
			} else {
				// generic box
				let layer = CAShapeLayerWithProperties()
				let rect = CGRect(
					x: CGFloat(round(MinIconSizeInPixels / 4)),
					y: CGFloat(round(MinIconSizeInPixels / 4)),
					width: CGFloat(round(MinIconSizeInPixels / 2)),
					height: CGFloat(round(MinIconSizeInPixels / 2)))
				let path = CGPath(rect: rect, transform: nil)
				layer.path = path
				layer.frame = CGRect(
					x: -MinIconSizeInPixels / 2,
					y: -MinIconSizeInPixels / 2,
					width: MinIconSizeInPixels,
					height: MinIconSizeInPixels)
				layer.position = CGPoint(x: pt.x, y: pt.y)
				layer.strokeColor = (color ?? UIColor.black).cgColor
				layer.fillColor = nil
				layer.lineWidth = 2.0
				layer.backgroundColor = UIColor.white.cgColor
				layer.borderColor = UIColor.darkGray.cgColor
				layer.borderWidth = 1.0
				layer.cornerRadius = MinIconSizeInPixels / 2
				layer.zPosition = Z_NODE

				let props = layer.properties
				props.position = pt

				layers.append(layer)
			}
		}

		if drawRef {
			if let ref = node.tags["ref"] {
				let label = CurvedGlyphLayer.layerWithString(ref)
				label.anchorPoint = CGPoint(x: 0.0, y: 0.5)
				label.position = CGPoint(x: pt.x, y: pt.y)
				label.zPosition = Z_TEXT
				label.properties.position = pt
				label.properties.offset = CGPoint(x: 12, y: 0)
				layers.append(label)
			}
		}

		return layers
	}

	func directionShapeLayer(for node: OsmNode,
	                         withDirection direction: NSRange) -> (CALayer & LayerPropertiesProviding)
	{
		let heading = Double(direction.location - 90 + direction.length / 2)

		let layer = CAShapeLayerWithProperties()

		layer.fillColor = UIColor(white: 0.2, alpha: 0.5).cgColor
		layer.strokeColor = UIColor(white: 1.0, alpha: 0.5).cgColor
		layer.lineWidth = 1.0

		layer.zPosition = Z_NODE

		let pt = MapTransform.mapPoint(forLatLon: node.latLon)

		let screenAngle = owner.mapTransform.transform.rotation()
		layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(screenAngle)))

		let radius: CGFloat = 30.0
		let fieldOfViewRadius = Double(direction.length != 0 ? direction.length : 55)
		let path = CGMutablePath()
		path.addArc(
			center: CGPoint.zero,
			radius: radius,
			startAngle: CGFloat(radiansFromDegrees(heading - fieldOfViewRadius / 2)),
			endAngle: CGFloat(radiansFromDegrees(heading + fieldOfViewRadius / 2)),
			clockwise: false)
		path.addLine(to: CGPoint(x: 0, y: 0))
		path.closeSubpath()
		layer.path = path

		let layerProperties = layer.properties
		layerProperties.position = pt
		layerProperties.isDirectional = true

		return layer
	}

	func directionLayerForNode(in way: OsmWay, node: OsmNode,
	                           facing second: Int) -> (CALayer & LayerPropertiesProviding)?
	{
		if second < 0 || second >= way.nodes.count {
			return nil
		}
		let nextNode = way.nodes[second]
		// compute angle to next node
		let p1 = MapTransform.mapPoint(forLatLon: node.latLon)
		let p2 = MapTransform.mapPoint(forLatLon: nextNode.latLon)
		let angle = atan2(p2.y - p1.y, p2.x - p1.x)
		var direction = 90 + Int(round(angle * 180 / .pi)) // convert to north-facing clockwise direction
		if direction < 0 {
			direction += 360
		}
		return directionShapeLayer(for: node, withDirection: NSRange(location: direction, length: 0))
	}

	/// Determines the `CALayer` instance required to draw the direction of the given `node`.
	/// - Parameter node: The node to get the layer for.
	/// - Returns: A `CALayer` instance for rendering the given node's direction.
	func directionShapeLayers(with node: OsmNode) -> [CALayer & LayerPropertiesProviding] {
		if let direction = node.direction {
			return [directionShapeLayer(for: node, withDirection: direction)]
		}

		guard let highway = node.tags["highway"] else { return [] }

		var directionValue: String?
		if highway == "traffic_signals" {
			directionValue = node.tags["traffic_signals:direction"]
		} else if highway == "stop" {
			directionValue = node.tags["direction"]
		}
		if let directionValue = directionValue {
			enum DIR { case IS_NONE, IS_FORWARD, IS_BACKWARD, IS_BOTH, IS_ALL }
			let isDirection: DIR = directionValue == "forward" ? .IS_FORWARD :
				directionValue == "backward" ? .IS_BACKWARD :
				directionValue == "both" ? .IS_BOTH :
				directionValue == "all" ? .IS_ALL :
				.IS_NONE

			if isDirection != .IS_NONE {
				var wayList = mapData.waysContaining(node) // this is expensive, only do if necessary
				wayList = wayList.filter({ $0.tags["highway"] != nil })
				if wayList.count > 0 {
					if wayList.count > 1, isDirection != .IS_ALL {
						return [] // the direction isn't well defined
					}
					var list: [CALayer & LayerPropertiesProviding] = []
					list.reserveCapacity(2 * wayList.count) // sized for worst case
					for way in wayList {
						let pos = way.nodes.firstIndex(of: node)
						if isDirection != .IS_FORWARD {
							if let layer = directionLayerForNode(in: way, node: node, facing: (pos ?? 0) + 1) {
								list.append(layer)
							}
						}
						if isDirection != .IS_BACKWARD {
							if let layer = directionLayerForNode(in: way, node: node, facing: (pos ?? 0) - 1) {
								list.append(layer)
							}
						}
					}
					return list
				}
			}
		}
		return []
	}

	func getShapeLayersForHighlights() -> [CALayer] {
		let geekScore = Geekbench.score
		var nameLimit = Int(5 + (geekScore - 500) / 200) // 500 -> 5, 2500 -> 10
		var nameSet: Set<String> = []
		var layers: [CALayer & LayerPropertiesProviding] = []
		let regularColor = UIColor.cyan
		let relationColor = UIColor(red: 66 / 255.0, green: 188 / 255.0, blue: 244 / 255.0, alpha: 1.0)

		// highlighting
		var highlights: Set<OsmBaseObject> = []
		if let obj = selectedNode {
			highlights.insert(obj)
		}
		if let obj = selectedWay {
			highlights.insert(obj)
		}
		if let obj = selectedRelation {
			let members = obj.allMemberObjects()
			highlights = highlights.union(members)
		}

		for object in highlights {
			// selected is false if its highlighted because it's a member of a selected relation
			let selected = object == selectedNode || object == selectedWay

			if let way = object as? OsmWay {
				let path = self.path(for: way)
				var lineWidth: CGFloat = selected ? 1.0 : 2.0
				let wayColor = selected ? regularColor : relationColor

				if lineWidth == 0 {
					lineWidth = 1
				}
				lineWidth += 2 // since we're drawing highlight 2-wide we don't want it to intrude inward on way

				let layer = CAShapeLayerWithProperties()
				layer.strokeColor = wayColor.cgColor
				layer.lineWidth = lineWidth
				layer.path = path
				layer.fillColor = UIColor.clear.cgColor
				layer.zPosition = Z_HIGHLIGHT_WAY

				let props = layer.properties
				props.lineWidth = layer.lineWidth

				layers.append(layer)

				// Turn Restrictions
				if owner.useTurnRestrictions() {
					for relation in object.parentRelations {
						if relation.isRestriction(),
						   relation.member(byRole: "from")?.obj == object
						{
							// the From member of the turn restriction is the selected way
							if selectedNode == nil || relation.member(byRole: "via")?.obj == selectedNode {
								// highlight if no node is selected, or the selected node is the via node
								for member in relation.members {
									if let way = member.obj as? OsmWay {
										let turnPath = self.path(for: way)
										let haloLayer = CAShapeLayerWithProperties()
										haloLayer.anchorPoint = CGPoint(x: 0, y: 0)
										haloLayer.path = turnPath
										if member.obj == object && (member.role != "to") {
											haloLayer.strokeColor = UIColor.black.withAlphaComponent(0.75).cgColor
										} else if relation.tags["restriction"]?.hasPrefix("only_") ?? false {
											haloLayer.strokeColor = UIColor.blue.withAlphaComponent(0.75).cgColor
										} else if relation.tags["restriction"]?.hasPrefix("no_") ?? false {
											haloLayer.strokeColor = UIColor.red.withAlphaComponent(0.75).cgColor
										} else {
											// some other kind of restriction
											haloLayer.strokeColor = UIColor.orange.withAlphaComponent(0.75).cgColor
										}
										haloLayer.fillColor = nil
										haloLayer.lineWidth = ((way.renderInfo?.lineWidth ?? 0) + 6) * highwayScale
										haloLayer.lineCap = CAShapeLayerLineCap.round
										haloLayer.lineJoin = CAShapeLayerLineJoin.round
										haloLayer.zPosition = Z_HALO
										let haloProps = haloLayer.properties
										haloProps.lineWidth = haloLayer.lineWidth

										if ((member.role == "to") && member.obj == object) ||
											((member.role == "via") && member.isWay())
										{
											haloLayer.lineDashPattern = [NSNumber(value: Double(10.0 * highwayScale)),
											                             NSNumber(value: Double(10.0 * highwayScale))]
										}

										layers.append(haloLayer)
									}
								}
							}
						}
					}
				}

				// draw nodes of way
				let nodes = object == selectedWay ? object.nodeSet() : []
				for node in nodes {
					let layer2 = CAShapeLayerWithProperties()
					layer2.position = owner.mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: false)
					layer2.strokeColor = node == selectedNode ? UIColor.yellow.cgColor : UIColor.green.cgColor
					layer2.fillColor = UIColor.clear.cgColor
					layer2.lineWidth = 3.0
					layer2.shadowColor = UIColor.black.cgColor
					layer2.shadowRadius = 2.0
					layer2.shadowOpacity = 0.5
					layer2.shadowOffset = CGSize(width: 0, height: 0)
					layer2.masksToBounds = false

					let rect = CGRect(x: -NodeHighlightRadius,
					                  y: -NodeHighlightRadius,
					                  width: 2 * NodeHighlightRadius,
					                  height: 2 * NodeHighlightRadius)

					let rc1 = rect.insetBy(dx: layer2.lineWidth / 2, dy: layer2.lineWidth / 2)
					let rc2 = rc1.insetBy(dx: -layer2.lineWidth, dy: -layer2.lineWidth)

					if node.hasInterestingTags() {
						layer2.path = CGPath(rect: rect, transform: nil)
						let shadow = UIBezierPath(rect: rc1)
						shadow.append(UIBezierPath(rect: rc2).reversing())
						layer2.shadowPath = shadow.cgPath
					} else {
						layer2.path = CGPath(ellipseIn: rect, transform: nil)
						let shadow = UIBezierPath(ovalIn: rc1)
						shadow.append(UIBezierPath(ovalIn: rc2).reversing())
						layer2.shadowPath = shadow.cgPath
					}
					layer2.zPosition = Z_HIGHLIGHT_NODE + (node == selectedNode ? 0.1 * EditorMapLayer.ZSCALE : 0)
					layers.append(layer2)
				}
			} else if let node = object as? OsmNode {
				// draw square around selected node
				let pt = owner.mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: false)

				let layer = CAShapeLayerWithProperties()
				var rect = CGRect(x: -MinIconSizeInPixels / 2,
				                  y: -MinIconSizeInPixels / 2,
				                  width: MinIconSizeInPixels,
				                  height: MinIconSizeInPixels)
				rect = rect.insetBy(dx: -3, dy: -3)
				let path = CGPath(rect: rect, transform: nil)
				layer.path = path

				layer.anchorPoint = CGPoint(x: 0, y: 0)
				layer.position = CGPoint(x: pt.x, y: pt.y)
				layer.strokeColor = selected ? UIColor.green.cgColor : UIColor.white.cgColor
				layer.fillColor = UIColor.clear.cgColor
				layer.lineWidth = 2.0

				layer.zPosition = Z_HIGHLIGHT_NODE
				layers.append(layer)
			}
		}

		// Arrow heads and street names
		for object in shownObjects {
			guard let way = object as? OsmWay else {
				continue
			}
			let isHighlight = highlights.contains(way)
			if way.isOneWay != .NONE || isHighlight {
				// arrow heads
				invoke(alongScreenClippedWay: way, offset: 50, interval: 100, block: { loc, dir in
					// draw direction arrow at loc/dir
					let reversed = way.isOneWay == ONEWAY.BACKWARD
					let len: Double = reversed ? -15 : 15
					let width: Double = 5

					let p1 = OSMPoint(x: loc.x - dir.x * len + dir.y * width,
					                  y: loc.y - dir.y * len - dir.x * width)
					let p2 = OSMPoint(x: loc.x - dir.x * len - dir.y * width,
					                  y: loc.y - dir.y * len + dir.x * width)

					let arrowPath = CGMutablePath()
					arrowPath.move(to: CGPoint(x: p1.x, y: p1.y))
					arrowPath.addLine(to: CGPoint(x: loc.x, y: loc.y))
					arrowPath.addLine(to: CGPoint(x: p2.x, y: p2.y))
					arrowPath
						.addLine(to: CGPoint(x: CGFloat(loc.x - dir.x * len * 0.5),
						                     y: CGFloat(loc.y - dir.y * len * 0.5)))
					arrowPath.closeSubpath()

					let arrow = CAShapeLayerWithProperties()
					arrow.path = arrowPath
					arrow.lineWidth = 1
					arrow.fillColor = UIColor.black.cgColor
					arrow.strokeColor = UIColor.white.cgColor
					arrow.lineWidth = 0.5
					arrow.zPosition = isHighlight ? self.Z_HIGHLIGHT_ARROW : self.Z_ARROW

					layers.append(arrow)
				})
			}

			// street names
			if nameLimit > 0 {
				var parentRelation: OsmRelation?
				for parent in way.isWay()?.parentRelations ?? [] {
					if parent.isBoundary() || parent.isWaterway() {
						parentRelation = parent
						break
					}
				}

				if !way.isArea() || parentRelation != nil,
				   let name = way.givenName() ?? parentRelation?.givenName(),
				   !nameSet.contains(name),
				   way.nodes.count >= 2
				{
					var length: CGFloat = 0.0
					if let path = pathClipped(toViewRect: way.isWay()!, length: &length),
					   length >= CGFloat(name.count) * Pixels_Per_Character
					{
						if let layer = CurvedGlyphLayer.layer(WithString: name as NSString, alongPath: path),
						   let a = layer.glyphLayers(),
						   a.count > 0
						{
							layers.append(contentsOf: a)
							nameLimit -= 1
							nameSet.insert(name)
						}
					}
				}
			}
		}

		return layers
	}

	/// Determines whether text layers that display street names should be rasterized.
	/// - Returns: The value to use for the text layer's `shouldRasterize` property.
	func shouldRasterizeStreetNames() -> Bool {
		return Geekbench.score < 2500
	}

	func resetDisplayLayers() {
		// need to refresh all text objects
		mapData.enumerateObjects(usingBlock: { obj in
			obj.shapeLayers = nil
		})
		baseLayer.sublayers = nil
		setNeedsLayout()
	}

	// MARK: Select objects and draw

	func getVisibleObjects() -> ContiguousArray<OsmBaseObject> {
		let box = owner.boundingLatLonRectForScreen()
		var a: ContiguousArray<OsmBaseObject> = []
		a.reserveCapacity(4000)
		mapData.enumerateObjects(inRegion: box, block: { obj in
			var show = obj.isShown
			if show == TRISTATE.UNKNOWN {
				if !obj.deleted {
					if let node = obj as? OsmNode {
						if node.wayCount == 0 || node.hasInterestingTags() {
							show = TRISTATE.YES
						}
					} else if obj.isWay() != nil {
						show = TRISTATE.YES
					} else if obj.isRelation() != nil {
						show = TRISTATE.YES
					}
				}
				obj.isShown = show == TRISTATE.YES ? TRISTATE.YES : TRISTATE.NO
			}
			if show == TRISTATE.YES {
				a.append(obj)
			}
		})
		return a
	}

	func filterObjects(_ objects: inout ContiguousArray<OsmBaseObject>) {
		// filter everything
		let predicate = objectFilters.predicateForFilters()
		objects = objects.filter({ predicate($0) })

		var add: [OsmBaseObject] = []
		var remove: [OsmBaseObject] = []
		for obj in objects {
			// if we are showing relations we need to ensure the members are visible too
			if let relation = obj as? OsmRelation,
			   relation.isMultipolygon()
			{
				let set = relation.allMemberObjects()
				for o in set {
					if o.isWay() != nil {
						add.append(o)
					}
				}
			}
			// if a way belongs to relations which are hidden, and it has no other tags itself, then hide it as well
			if obj is OsmWay,
			   obj.parentRelations.count > 0, !obj.hasInterestingTags()
			{
				var hidden = true
				for parent in obj.parentRelations {
					if !(parent.isMultipolygon() || parent.isBoundary()) || objects.contains(parent) {
						hidden = false
						break
					}
				}
				if hidden {
					remove.append(obj)
				}
			}
		}
		for o in remove {
			objects.removeAll { $0 === o }
		}
		for o in add {
			objects.append(o)
		}
	}

	func getObjectsToDisplay() -> ContiguousArray<OsmBaseObject> {
		let geekScore = Int(Geekbench.score)
		var objectLimit = 3 * (50 + (geekScore - 500) / 40) // 500 -> 50, 2500 -> 10

		// get objects in visible rect
		var objects = getVisibleObjects()

		let a = mapData.nodes.values.map({ owner.mapTransform.screenPoint(forLatLon: $0.latLon, birdsEye: true) })
		print("getObjectsToDisplay = \(a)")

		atVisibleObjectLimit = objects.count >= objectLimit // we want this to reflect the unfiltered count

		if objectFilters.enableObjectFilters {
			filterObjects(&objects)
		}

		// get renderInfo for objects
		for object in objects {
			if object.renderInfo == nil {
				object.renderInfo = RenderInfoDatabase.shared.renderInfoForObject(object)
			}
			if object.renderPriorityCached == 0 {
				object.renderPriorityCached = object.renderInfo!.renderPriorityForObject(object)
			}
		}

		// sort from big to small objects, and remove excess objects
		objects = RenderInfo.sortByPriority(list: objects, keepingFirst: objectLimit)

		// sometimes there are way too many address nodes that clog up the view, so limit those items specifically
		objectLimit = objects.count
		var addressCount = 0
		while addressCount < objectLimit {
			let obj = objects[objectLimit - addressCount - 1]
			if !obj.renderInfo!.isAddressPoint() {
				break
			}
			addressCount += 1
		}
		if addressCount > 50 {
			let range = NSIndexSet(indexesIn: NSRange(location: objectLimit - addressCount, length: addressCount))
			for deletionIndex in range.reversed() { objects.remove(at: deletionIndex) }
		}

		return objects
	}

	func layoutSublayersSafe() {
		if let birdsEye = owner.mapTransform.birdsEye() {
			var t = CATransform3DIdentity
			t.m34 = CGFloat(-1.0 / birdsEye.distance)
			t = CATransform3DRotate(t, CGFloat(birdsEye.rotation), 1.0, 0, 0)
			baseLayer.sublayerTransform = t
		} else {
			baseLayer.sublayerTransform = CATransform3DIdentity
		}

		let previousObjects = shownObjects

		shownObjects = getObjectsToDisplay()
		shownObjects.append(contentsOf: Array(fadingOutSet))

		// remove layers no longer visible
		var removals = Set<OsmBaseObject>(previousObjects)
		for object in shownObjects {
			removals.remove(object)
		}
		// use fade when removing objects
		if removals.count != 0 {
#if FADE_INOUT
			CATransaction.begin()
			CATransaction.setAnimationDuration(1.0)
			CATransaction.setCompletionBlock({
				for object in removals {
					fadingOutSet.removeAll { $0 as AnyObject === object as AnyObject }
					shownObjects.removeAll { $0 as AnyObject === object as AnyObject }
					for layer in object.shapeLayers {
						if layer.opacity < 0.1 {
							layer.removeFromSuperlayer()
						}
					}
				}
			})
			for object in removals {
				fadingOutSet.union(removals)
				for layer in object.shapeLayers {
					layer.opacity = 0.01
				}
			}
			CATransaction.commit()
#else
			for object in removals {
				for layer in object.shapeLayers ?? [] {
					layer.removeFromSuperlayer()
				}
			}
#endif
		}

#if FADE_INOUT
		CATransaction.begin()
		CATransaction.setAnimationDuration(1.0)
#endif

		let tRotation = owner.mapTransform.rotation()
		let tScale = owner.mapTransform.scale()
		let pScale = CGFloat(tScale / PATH_SCALING)
		let pixelsPerMeter = 0.8 * 1.0 / owner.mapTransform.metersPerPixel(atScreenPoint: bounds.center())

		for object in shownObjects {
			let layers = getShapeLayers(for: object)

			for layer in layers {
				// configure the layer for presentation
				let isShapeLayer = layer is CAShapeLayer
				let props = layer.properties
				let pt = props.position
				var pt2 = OSMPoint(owner.mapTransform.screenPoint(forMapPoint: pt, birdsEye: false))

				if props.is3D || (isShapeLayer && object.isNode() == nil) {
					// way or area -- need to rotate and scale
					if props.is3D {
						if owner.mapTransform.birdsEye() == nil {
							layer.removeFromSuperlayer()
							continue
						}
						var t = CATransform3DMakeTranslation(CGFloat(pt2.x - pt.x), CGFloat(pt2.y - pt.y), 0)
						t = CATransform3DScale(t, CGFloat(pScale), CGFloat(pScale), CGFloat(pixelsPerMeter))
						t = CATransform3DRotate(t, CGFloat(tRotation), 0, 0, 1)
						t = CATransform3DConcat(props.transform, t)
						layer.transform = t
						if !isShapeLayer {
							layer.borderWidth = props.lineWidth / pScale // wall
						}
					} else {
						var t = CGAffineTransform(translationX: CGFloat(pt2.x - pt.x), y: CGFloat(pt2.y - pt.y))
						t = t.scaledBy(x: CGFloat(pScale), y: CGFloat(pScale))
						t = t.rotated(by: CGFloat(tRotation))
						layer.setAffineTransform(t)
					}

					if isShapeLayer {
					} else {
						// its a wall, so bounds are already height/length of wall
					}

					if isShapeLayer {
						let shape = layer as! CAShapeLayer
						shape.lineWidth = CGFloat(props.lineWidth / pScale)
					}
				} else {
					// node or text -- no scale transform applied
					if layer is CATextLayer {
						// get size of building (or whatever) into which we need to fit the text
						if object.isNode() != nil {
							// its a node with text, such as an address node
						} else {
							// its a label on a building or polygon
							let rcMap = MapTransform.mapRect(forLatLonRect: object.boundingBox)
							let rcScreen = owner.mapTransform.boundingScreenRect(forMapRect: rcMap)
							if layer.bounds.size.width >= 1.1 * rcScreen.size.width {
								// text label is too big so hide it
								layer.removeFromSuperlayer()
								continue
							}
						}
					} else if layer.properties.isDirectional {
						// a direction layer (direction=*), so it needs to rotate with the map
						layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(tRotation)))
					} else {
						// its an icon or a generic box
					}

					let scale = Double(UIScreen.main.scale)
					pt2.x = round(pt2.x * scale) / scale
					pt2.y = round(pt2.y * scale) / scale
					DbgAssert(pt2.y.isFinite)
					layer.position = CGPoint(x: CGFloat(pt2.x) + props.offset.x,
					                         y: CGFloat(pt2.y) + props.offset.y)
				}

				// add the layer if not already present
				if layer.superlayer == nil {
#if FADE_INOUT
					layer.removeAllAnimations()
					layer.opacity = 1.0
#endif
					baseLayer.addSublayer(layer)
				}
			}
		}

#if FADE_INOUT
		CATransaction.commit()
#endif

		// draw highlights: these layers are computed in screen coordinates and don't need to be transformed
		for layer in highlightLayers {
			// remove old highlights
			layer.removeFromSuperlayer()
		}

		// get highlights
		highlightLayers = getShapeLayersForHighlights()

		// get ocean
		let ocean = getOceanLayer(shownObjects)
		if let ocean = ocean {
			highlightLayers.append(ocean)
		}
		for layer in highlightLayers {
			// add new highlights
			baseLayer.addSublayer(layer)
		}

		// NSLog(@"%ld layers", (long)self.sublayers.count);
	}

	override func layoutSublayers() {
		if isHidden {
			return
		}

		isPerformingLayout = true
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		layoutSublayersSafe()
		CATransaction.commit()
		isPerformingLayout = false
	}

	override func setNeedsLayout() {
		if isPerformingLayout {
			return
		}
		super.setNeedsLayout()
	}

	// MARK: Highlighting and Selection

	var selectedPrimary: OsmBaseObject? { selectedNode ?? selectedWay ?? selectedRelation }

	var selectedNode: OsmNode? {
		didSet {
			if oldValue != selectedNode {
				setNeedsDisplay()
				owner.selectionDidChange()
			}
		}
	}

	var selectedWay: OsmWay? {
		didSet {
			if oldValue != selectedWay {
				setNeedsDisplay()
				owner.selectionDidChange()
			}
		}
	}

	var selectedRelation: OsmRelation? {
		didSet {
			if oldValue != selectedRelation {
				self.setNeedsDisplay()
				owner.selectionDidChange()
			}
		}
	}

	// MARK: Properties

	override var isHidden: Bool {
		didSet(wasHidden) {
			if wasHidden, !isHidden {
				updateMapLocation()
			}
			if !wasHidden, isHidden {
				self.selectedNode = nil
				self.selectedWay = nil
				self.selectedRelation = nil
				owner.removePin()
			}
		}
	}

	// MARK: Coding

	override func encode(with coder: NSCoder) {
		fatalError()
	}
}
