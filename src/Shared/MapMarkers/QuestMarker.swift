//
//  QuestMarker.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/5/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

// An OSM object for a quest
final class QuestMarker: MapMarker {
	let ident: String
	let quest: QuestProtocol

	override var markerIdentifier: String {
		return ident
	}

	override var buttonLabel: String { quest.label }

	init?(object: OsmBaseObject, quest: QuestProtocol, ignorable: MapMarkerIgnoreListProtocol) {
		let ident = "quest-\(quest.ident)-\(object is OsmNode ? "n" : object is OsmWay ? "w" : "r")\(object.ident)"
		if ignorable.shouldIgnore(ident: ident) {
			return nil
		}
		let center = object.selectionPoint()
		self.quest = quest
		self.ident = ident
		super.init(latLon: center)
		self.object = object
		self.ignorable = ignorable
	}

	override func handleButtonPress(in mainView: MainViewController, markerView: MapMarkersView) {
		if mainView.mapView.isHidden {
			let alert = AlertPopup(title: "\(self.object!.friendlyDescription())",
			                       message: quest.title)
			alert.addAction(title: "OK", handler: nil)
			mainView.present(alert, animated: true)
		} else {
			let onClose = {
				// Need to update the QuestMarker icon
				markerView.updateRegion(withDelay: 0.0, including: [.quest])
			}
			let vc = QuestSolverController.instantiate(marker: self,
			                                           object: self.object!,
			                                           onClose: onClose)
			if #available(iOS 15.0, *),
			   let sheet = vc.sheetPresentationController
			{
				sheet.selectedDetentIdentifier = .large
				sheet.prefersScrollingExpandsWhenScrolledToEdge = false
				sheet.detents = [.medium(), .large()]
				sheet.delegate = mainView.mapView
			}
			mainView.present(vc, animated: true)
		}
	}
}
