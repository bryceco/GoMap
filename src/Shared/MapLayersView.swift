//
//  MapLayersView.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/18/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit

/// The main map display: Editor, Aerial, Basemap etc.
enum MapViewState: Int {
	case EDITOR
	case EDITORAERIAL
	case AERIAL
	case BASEMAP
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
	protocol LayerOrView {
		var hasTileServer: TileServer? { get }
		var isHidden: Bool { get set }
		func removeFromSuper()
	}

	var allLayers: [LayerOrView] = []
	var mainView: MainViewController { AppDelegate.shared.mainView as! MainViewController }
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

	public var basemapServer: TileServer {
		get {
			let ident = UserPrefs.shared.currentBasemapSelection.value
			return BasemapServerList.first(where: { $0.identifier == ident }) ?? BasemapServerList.first!
		}
		set {
			let oldServerId = basemapServer.identifier
			allLayers.removeAll(where: {
				if $0.hasTileServer?.identifier == oldServerId {
					$0.removeFromSuper()
					return true
				}
				return false
			})

			if newValue.isVector {
				let view = MapLibreVectorTilesView(viewPort: viewPort, tileServer: newValue)
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
			allLayers.append(basemapLayer)

			UserPrefs.shared.currentBasemapSelection.value = newValue.identifier

			basemapLayer.isHidden = mapView.viewState != .BASEMAP
		}
	}

	var displayDataOverlayLayers = false {
		didSet {
			dataOverlayLayer.isHidden = !displayDataOverlayLayers

			if displayDataOverlayLayers {
				dataOverlayLayer.setNeedsLayout()
			}
			updateTileOverlayLayers(latLon: viewPort.screenCenterLatLon())
		}
	}

	func addDefaultChildViews(andAlso more: [LayerOrView]) {
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
		quadDownloadLayer = QuadDownloadLayer(mapData: mapView.editorLayer.mapData, viewPort: viewPort)
		if let quadDownloadLayer = quadDownloadLayer {
			quadDownloadLayer.zPosition = ZLAYER.QUADDOWNLOAD.rawValue
			quadDownloadLayer.isHidden = false
			allLayers.append(quadDownloadLayer)
		}
#endif

		for layer in more {
			allLayers.append(layer)
		}
	}

	func setUpChildViews(with main: MainViewController) {
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

		mainView.settings.$displayGpxTracks.subscribe(self) { [weak self] displayGpxTracks in
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

		bounds.origin = CGPoint(x: -frame.size.width/2,
								y: -frame.size.height/2)

		// update bounds of layers
		for bg in allLayers {
			switch bg {
			case let layer as CALayer:
				layer.frame = bounds
				layer.bounds = bounds
			case let view as UIView:
				view.frame = bounds
				view.bounds = bounds.offsetBy(dx: bounds.width / 2, dy: bounds.height / 2)
			default:
				fatalError()
			}
		}
	}

	func updateTileOverlayLayers(latLon: LatLon) {
		let overlaysIdList = UserPrefs.shared.tileOverlaySelections.value ?? []

		// if they toggled display of the noname layer we need to refresh the editor layer
		if overlaysIdList.contains(TileServer.noName.identifier) != mapView.useUnnamedRoadHalo() {
			mapView.editorLayer.clearCachedProperties()
		}

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

}
