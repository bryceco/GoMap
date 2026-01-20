//
//  MapLayersView.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/18/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit

enum ZLAYER: CGFloat {
	case AERIAL = -100
	case BASEMAP = -98
	case LOCATOR = -50
	case DATA = -30
	case EDITOR = -20
	case QUADDOWNLOAD = -18
	case GPX = -15
	case ROTATEGRAPHIC = -3
	case BLINK = 4
	case CROSSHAIRS = 5
}

class MapLayersView: UIView {

	// List of all layers that are displayed and need to be resized, etc.
	// These can be either UIView or CALayer based.
	// Includes:
	// * MapLibre and MercatorTile basemap layers
	// * Editor layer
	// * Aerial imagery
	// * Gpx Layer
	// * DataOverlays like GeoJson
	@MainActor
	protocol LayerOrView: AnyObject {
		var hasTileServer: TileServer? { get }
		var isHidden: Bool { get set }
		func removeFromSuper()
	}

	var mainView: MainViewController { AppDelegate.shared.mainView }
	var viewPort: MapViewPort { mainView.viewPort }
	var mapView: MapView { mainView.mapView }

	// opaque background layers
	private(set) var aerialLayer: MercatorTileLayer!
	var basemapLayer: (MapLayersView.LayerOrView & DiskCacheSizeProtocol)!
	// transparent foreground layers
	private(set) var gpxLayer: GpxLayer!
	private(set) var locatorLayer: MercatorTileLayer!
	private(set) var dataOverlayLayer: DataOverlayLayer!
	private(set) var quadDownloadLayer: QuadDownloadLayer?
	// collect all of the above layers
	var allLayers: [LayerOrView] = []

	private var crossHairs: CrossHairsLayer!

	public var basemapServer: TileServer {
		get {
			let ident = UserPrefs.shared.currentBasemapSelection.value
			return BasemapServerList.first(where: { $0.identifier == ident }) ?? BasemapServerList.first!
		}
		set {
			basemapLayer?.removeFromSuper()
			allLayers.removeAll(where: { $0 === basemapLayer })

			if newValue.isVector {
				let view = MapLibreVectorTilesView(viewPort: viewPort,
				                                   tileServer: newValue)
				view.layer.zPosition = ZLAYER.BASEMAP.rawValue
				insertSubview(view, at: 0) // place at bottom so MapMarkers are above it
				basemapLayer = view
			} else {
				let layer = MercatorTileLayer(viewPort: viewPort,
				                              progress: mainView)
				layer.tileServer = newValue
				layer.supportDarkMode = true
				layer.zPosition = ZLAYER.BASEMAP.rawValue
				self.layer.addSublayer(layer)
				basemapLayer = layer
			}
			basemapLayer.isHidden = mainView.viewState.state != .BASEMAP

			allLayers.append(basemapLayer)
			UserPrefs.shared.currentBasemapSelection.value = newValue.identifier
		}
	}

	var displayDataOverlayLayers = false {
		didSet {
			UserPrefs.shared.mapViewEnableDataOverlay.value = displayDataOverlayLayers

			dataOverlayLayer.isHidden = !displayDataOverlayLayers

			if displayDataOverlayLayers {
				dataOverlayLayer.setNeedsLayout()
			}
			updateTileOverlayLayers(latLon: viewPort.screenCenterLatLon())
		}
	}

	func initDefaultChildViews(andAlso more: [LayerOrView]) {
		for layer in more {
			allLayers.append(layer)
		}

		// this option needs to be set before the editor is initialized
		locatorLayer = MercatorTileLayer(viewPort: viewPort, progress: mainView)
		locatorLayer.zPosition = ZLAYER.LOCATOR.rawValue
		locatorLayer.tileServer = TileServer.mapboxLocator
		locatorLayer.isHidden = true
		allLayers.append(locatorLayer)

		aerialLayer = MercatorTileLayer(viewPort: viewPort, progress: mainView)
		aerialLayer.zPosition = ZLAYER.AERIAL.rawValue
		aerialLayer.tileServer = AppState.shared.tileServerList.currentServer
		aerialLayer.isHidden = true
		allLayers.append(aerialLayer)

		gpxLayer = GpxLayer(viewPort: viewPort)
		gpxLayer.zPosition = ZLAYER.GPX.rawValue
		gpxLayer.isHidden = true
		allLayers.append(gpxLayer)

		dataOverlayLayer = DataOverlayLayer(viewPort: viewPort)
		dataOverlayLayer.zPosition = ZLAYER.DATA.rawValue
		dataOverlayLayer.isHidden = true
		allLayers.append(dataOverlayLayer)

#if DEBUG && false
		quadDownloadLayer = QuadDownloadLayer(mapData: AppDelegate.shared.mapView.editorLayer.mapData,
		                                      viewPort: viewPort)
		if let quadDownloadLayer {
			quadDownloadLayer.zPosition = ZLAYER.QUADDOWNLOAD.rawValue
			quadDownloadLayer.isHidden = false
			allLayers.append(quadDownloadLayer)
		}
#endif

		// implement crosshairs
		crossHairs = CrossHairsLayer(radius: 12.0)
		crossHairs.zPosition = ZLAYER.CROSSHAIRS.rawValue
		layer.addSublayer(crossHairs)
	}

	func setUpChildViews() {
		// set the background color visible when in editor-only mode
		backgroundColor = UIColor(white: 0.1, alpha: 1.0)

		// insert them
		for bg in allLayers {
			switch bg {
			case let view as UIView:
				addSubview(view)
			case let layer as CALayer:
				self.layer.addSublayer(layer)
			default:
				fatalError()
			}
		}

		// self-assigning will do everything to set up the appropriate layer
		basemapServer = basemapServer
		basemapLayer.isHidden = true

		// these need to be loaded late because assigning to them changes the view
		displayDataOverlayLayers = UserPrefs.shared.mapViewEnableDataOverlay.value ?? false

		mainView.settings.$displayGpxTracks.callAndSubscribe(self) { [weak self] displayGpxTracks in
			self?.gpxLayer.isHidden = !displayGpxTracks
			LocationProvider.shared.allowsBackgroundLocationUpdates
				= AppState.shared.gpxTracks.recordTracksInBackground && displayGpxTracks
		}

		UserPrefs.shared.tileOverlaySelections.onChange.subscribe(self) { [weak self] _ in
			guard let self = self else { return }
			self.updateTileOverlayLayers(latLon: viewPort.screenCenterLatLon())
		}
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		bounds.origin = CGPoint(x: -bounds.size.width / 2,
		                        y: -bounds.size.height / 2)

		crossHairs.position = viewPort.screenCenterPoint()

		// update bounds of layers
		for bg in allLayers {
			switch bg {
			case let layer as CALayer:
				layer.frame = bounds
				layer.bounds.origin = bounds.origin
			case let view as MapLibreVectorTilesView:
				view.frame = bounds
				view.bounds.origin = CGPoint(x: bounds.origin.x + bounds.width / 2,
				                             y: bounds.origin.y + bounds.height / 2)
			case let view as UIView:
				view.frame = bounds
				view.bounds.origin = bounds.origin
			default:
				fatalError()
			}
		}
	}

	func updateTileOverlayLayers(latLon: LatLon) {
		let overlaysIdList = UserPrefs.shared.tileOverlaySelections.value ?? []

		// remove any overlay layers no longer displayed
		allLayers = allLayers.filter { layer in
			// make sure it's a tile server and an overlay
			guard let tileServer = layer.hasTileServer,
			      tileServer.overlay
			else {
				return true // keep layer
			}
			// check it isn't a valid overlay for the user selection and is in current region
			if displayDataOverlayLayers,
			   overlaysIdList.contains(tileServer.identifier),
			   tileServer.coversLocation(latLon)
			{
				return true // keep layer
			}
			// remove layer
			layer.removeFromSuper()
			return false
		}

		if displayDataOverlayLayers {
			// create any overlay layers the user had enabled
			for ident in overlaysIdList {
				if allLayers.contains(where: {
					$0.hasTileServer?.identifier == ident
				}) {
					// already have it
					continue
				}
				guard let tileServer = AppState.shared.tileServerList.serviceWithIdentifier(ident) else {
					// server doesn't exist anymore
					var list = overlaysIdList
					list.removeAll(where: { $0 == ident })
					UserPrefs.shared.tileOverlaySelections.value = list
					continue
				}
				guard tileServer.coversLocation(latLon) else {
					continue
				}

				let layer = MercatorTileLayer(viewPort: viewPort, progress: mainView)
				layer.zPosition = ZLAYER.GPX.rawValue
				layer.tileServer = tileServer
				layer.isHidden = false
				allLayers.append(layer)
				self.layer.addSublayer(layer)
			}
		}
		setNeedsLayout()
	}

	func noNameLayer() -> MapLayersView.LayerOrView? {
		return allLayers.first(where: { $0.hasTileServer === TileServer.noName })
	}
}
