//
//  BingMetadataViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/6/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

// http://www.microsoft.com/maps/attribution.aspx

import UIKit

class BingMetadataViewController: UIViewController {
	@IBOutlet var activityIndicator: UIActivityIndicatorView!
	@IBOutlet var textView: UITextView!

	// Might be an error with parsing under neath
	override func viewDidLoad() {
		super.viewDidLoad()

		activityIndicator.startAnimating()

		let appDelegate = AppDelegate.shared
		let viewRect = appDelegate.mapView.boundingLatLonRectForScreen()
		var zoomLevel = appDelegate.mapView.aerialLayer.zoomLevel()
		let aerialService = appDelegate.mapView.aerialLayer.tileServer
		if zoomLevel > aerialService.maxZoom {
			zoomLevel = aerialService.maxZoom
		}

		appDelegate.mapView.aerialLayer.metadata({ result in
			self.activityIndicator.stopAnimating()

			guard let result = result else {
				self.textView.text = NSLocalizedString("An unknown error occurred fetching metadata", comment: "")
				return
			}
			switch result {
			case let .success(data):
				let json = try? JSONSerialization.jsonObject(with: data, options: [])

				var attrList: [String] = []

				let resourceSets = (json as? [String: Any])?["resourceSets"] as? [Any]
				for resourceSet in resourceSets ?? [] {
					let resources = (resourceSet as? [String: Any])?["resources"]
					guard let resources = resources as? [Any] else { continue }
					for resource in resources {
						let vintageStart = ((resource as? [String: Any])?["vintageStart"] as? String) ?? ""
						let vintageEnd = ((resource as? [String: Any])?["vintageEnd"] as? String) ?? ""
						guard let providers = (resource as? [String: Any])?["imageryProviders"] else { continue }
						guard let providers = providers as? [Any] else { continue }
						for provider in providers {
							var attribution = ((provider as? [String: Any])?["attribution"] as? String) ?? ""
							let areas = (provider as? [String: Any])?["coverageAreas"] as? [Any]
							for area in areas ?? [] {
								guard let area = area as? [String: Any] else { continue }
								let zoomMin = (area["zoomMin"] as? NSNumber)?.intValue ?? 0
								let zoomMax = (area["zoomMax"] as? NSNumber)?.intValue ?? 0
								guard let bbox = area["bbox"] as? [NSNumber],
								      bbox.count == 4
								else { continue }
								var rect = OSMRect(origin: OSMPoint(x: bbox[1].doubleValue,
								                                    y: bbox[0].doubleValue),
								                   size: OSMSize(width: bbox[3].doubleValue,
								                                 height: bbox[2].doubleValue))
								rect.size.width -= rect.origin.x
								rect.size.height -= rect.origin.y
								if zoomLevel >= zoomMin,
								   zoomLevel <= zoomMax,
								   viewRect.intersectsRect(rect)
								{
									if vintageStart != "", vintageEnd != "" {
										attribution = "\(attribution)\n   \(vintageStart) - \(vintageEnd)"
									}
									attrList.append(attribution)
								}
							}
						}
					}
				}

				attrList.sort(by: { obj1, obj2 in
					let isMS1 = obj1.contains("Microsoft") ? 0 : 1
					let isMS2 = obj2.contains("Microsoft") ? 0 : 1
					if isMS1 != isMS2 { return isMS1 < isMS2 }
					return obj1 < obj2
				})

				let text = attrList.joined(separator: "\n\n• ")
				self.textView.text = String.localizedStringWithFormat(
					NSLocalizedString("Background imagery %@", comment: "identifies current aerial imagery"),
					text)
			case let .failure(error):
				self.textView.text = String.localizedStringWithFormat(
					NSLocalizedString("Error fetching metadata: %@", comment: ""),
					"\(error.localizedDescription)")
			}
		})
	}

	@IBAction func cancel(_ sender: Any) {
		dismiss(animated: true)
	}
}
