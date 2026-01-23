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
		let offsetX = (marker is KeepRightMarker) || (marker is FixmeMarker) ? 0.00001 : 0.0
		let pos = viewPort.mapTransform.screenPoint(forLatLon: LatLon(latitude: marker.latLon.lat,
		                                                              longitude: marker.latLon.lon + offsetX),
		                                            birdsEye: true)
		if pos.x.isInfinite || pos.y.isInfinite {
			return false
		}
		if let button = button as? MapPinButton {
			button.arrowPoint = pos
		} else {
			var rc = button.bounds
			rc = rc.offsetBy(dx: pos.x - rc.size.width / 2,
			                 dy: pos.y - rc.size.height / 2)
			button.frame = rc
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

		var object: OsmBaseObject?
		if let marker = marker as? KeepRightMarker {
			object = marker.object(from: mapMarkerDatabase.mapData)
		} else {
			object = marker.object
		}

		if !mapView.isHidden,
		   let object = object
		{
			let pt = object.latLonOnObject(forLatLon: marker.latLon)
			let point = viewPort.mapTransform.screenPoint(forLatLon: pt, birdsEye: true)
			mapView.selectObject(object, pinAt: point)
		}

		if (marker is WayPointMarker) || (marker is KeepRightMarker) || (marker is GeoJsonMarker) {
			let comment: NSAttributedString
			let title: String
			switch marker {
			case let marker as WayPointMarker:
				title = "Waypoint"
				comment = marker.description
			case let marker as GeoJsonMarker:
				title = "GeoJSON"
				comment = NSAttributedString(string: marker.description)
			case let marker as KeepRightMarker:
				title = "Keep Right"
				comment = NSAttributedString(string: marker.description)
			default:
				title = ""
				comment = NSAttributedString(string: "")
			}

			let alert = AlertPopup(title: title, message: comment)
			if let marker = marker as? KeepRightMarker {
				alert.addAction(
					title: NSLocalizedString("Ignore", comment: ""),
					handler: {
						// they want to hide this button from now on
						marker.ignore()
						mapView.unselectAll()
					})
			}
			mainView.present(alert, animated: true)
		} else if let object = object {
			// Fixme marker or Quest marker
			if !mapView.isHidden {
				if let marker = marker as? QuestMarker {
					let onClose = {
						// Need to update the QuestMarker icon
						self.updateRegion(withDelay: 0.0, including: [.quest])
					}
					let vc = QuestSolverController.instantiate(marker: marker,
					                                           object: object,
					                                           onClose: onClose)
					if #available(iOS 15.0, *),
					   let sheet = vc.sheetPresentationController
					{
						sheet.selectedDetentIdentifier = .large
						sheet.prefersScrollingExpandsWhenScrolledToEdge = false
						sheet.detents = [.medium(), .large()]
						sheet.delegate = mapView
					}
					mainView.present(vc, animated: true)
				} else {
					mapView.presentTagEditor(nil)
				}
			} else {
				let text: String
				if let fixme = marker as? FixmeMarker,
				   let object = fixme.object
				{
					text = FixmeMarker.fixmeTag(object) ?? ""
				} else if let quest = marker as? QuestMarker {
					text = quest.quest.title
				} else {
					text = ""
				}
				let alert = UIAlertController(title: "\(object.friendlyDescription())",
				                              message: text,
				                              preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
				mainView.present(alert, animated: true)
			}
		} else if let note = marker as? OsmNoteMarker {
			mainView.performSegue(withIdentifier: "NotesSegue", sender: note)
		}
	}

	// FIXME: Move this into NoteMarker
	func update(
		note: OsmNoteMarker,
		close: Bool,
		comment: String,
		completion: @escaping (Result<OsmNoteMarker, Error>) -> Void)
	{
		mapMarkerDatabase.update(note: note, close: close, comment: comment, completion: completion)
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
