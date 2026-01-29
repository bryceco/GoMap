//
//  MapMarkersView.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/23/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit

class MapMarkersView: UIView {
	let viewPort: MapViewPort
	private lazy var mapMarkerDatabase = MapMarkerDatabase()

	init(viewPort: MapViewPort, mapData: OsmMapData) {
		self.viewPort = viewPort
		super.init(frame: .zero)

		self.mapMarkerDatabase.mapData = mapData

		viewPort.mapTransform.onChange.subscribe(self) { [weak self] in
			self?.updateMapMarkerButtonPositions()
		}

		AppState.shared.gpxTracks.onChangeTracks.subscribe(self) { [weak self] in
			// if we import a new track it might contain waypoints
			self?.updateRegion(withDelay: 0.0, including: .gpx)
		}

		/*
		 LocationProvider.shared.onChangeLocation.subscribe(self) { [weak self] _ in
		 	self?.updateMapMarkerButtonPositions()
		 }
		  */
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// override hittest so we don't block touches on the UIViews below us.
	override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
		let hitView = super.hitTest(point, with: event)
		return hitView == self ? nil : hitView
	}

	func reset() {
		mapMarkerDatabase.removeAll()
	}

	// This is rarely called, maybe we should instead just reset everything.
	func removeMarkers(where predicate: (MapMarker) -> Bool) {
		mapMarkerDatabase.removeMarkers(where: predicate)
	}

	func didSelectObject(_ object: OsmBaseObject?) {
		mapMarkerDatabase.didSelectObject(object)
	}

	// This performs an inexpensive update using only data we've already collected and have cached
	func updateMapMarkerButtonPositions() {
		// need this to disable implicit animation
		UIView.performWithoutAnimation({
			let MaxMarkers = 50
			var count = 0
			// update new and existing buttons
			for marker in self.mapMarkerDatabase.allMapMarkers {
				// Update the location of the button
				let onScreen = updateButtonPositionForMapMarker(marker: marker,
				                                                hidden: count > MaxMarkers)
				if onScreen {
					count += 1
				}
			}
		})
	}

	// Update the location of the button. Return true if it is on-screen.
	private func updateButtonPositionForMapMarker(marker: MapMarker,
	                                              hidden: Bool) -> Bool
	{
		// create buttons that haven't been created
		guard !hidden else {
			marker.button?.isHidden = true
			return false
		}
		if marker.button == nil {
			let button = marker.makeButton()
			button.addTarget(self,
			                 action: #selector(mapMarkerButtonPress(_:)),
			                 for: .touchUpInside)
			button.tag = marker.buttonId
			addSubview(button)
			if let object = marker.object {
				// If marker is associated with an object then the marker needs to be
				// updated when the object changes:
				object.observer = { obj in
					let markers = self.mapMarkerDatabase.refreshMarkersFor(object: obj)
					for marker in markers {
						_ = self.updateButtonPositionForMapMarker(marker: marker, hidden: false)
					}
				}
			}
		}

		// Set position of button
		let button = marker.button!
		button.isHidden = false
		// We don't want a fixme marker to obscure a POI node, so give it a small offset:
		let offsetX = (marker is KeepRightMarker) || (marker is FixmeMarker)
			? 1.0 / MetersPerDegreeAt(latitude: marker.latLon.lat).x
			: 0.0
		let latLon = LatLon(latitude: marker.latLon.lat,
		                    longitude: marker.latLon.lon + offsetX)
		let pos = viewPort.mapTransform.screenPoint(forLatLon: latLon,
		                                            birdsEye: true)
		if let button = button as? MapPinButton {
			button.arrowPoint = pos
		} else {
			button.center = pos
		}
		return bounds.contains(pos)
	}

	func updateRegion(withDelay delay: TimeInterval,
	                  including: MapMarkerDatabase.MapMarkerSet)
	{
		mapMarkerDatabase.updateRegion(withDelay: delay,
		                               including: including,
		                               completion: {
		                               	self.updateMapMarkerButtonPositions()
		                               })
	}

	@objc func mapMarkerButtonPress(_ sender: Any?) {
		guard
			let button = sender as? UIButton,
			let marker = mapMarkerDatabase.mapMarker(forButtonId: button.tag),
			let mainView = AppDelegate.shared.mainView,
			let mapView = mainView.mapView
		else { return }

		if let object = marker.object,
		   !mapView.isHidden
		{
			let pt = object.latLonOnObject(forLatLon: marker.latLon)
			let point = viewPort.mapTransform.screenPoint(forLatLon: pt, birdsEye: true)
			mapView.selectObject(object, pinAt: point)
		}

		marker.handleButtonPress(in: mainView, markerView: self)
	}

	// FIXME: Move this somewhere else since it is specific to Notes, but mapMarkerDatabase is private so ??
	func upload(note: OsmNoteMarker,
	            close: Bool,
	            comment: String) async throws -> OsmNoteMarker
	{
		return try await mapMarkerDatabase.upload(note: note,
		                                          close: close,
		                                          comment: comment)
	}
}

extension MapMarkersView: MapLayersView.LayerOrView {
	var hasTileServer: TileServer? {
		return nil
	}

	func removeFromSuper() {
		removeFromSuperview()
	}
}
