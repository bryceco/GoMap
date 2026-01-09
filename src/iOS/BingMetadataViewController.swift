//
//  BingMetadataViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/6/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

// http://www.microsoft.com/maps/attribution.aspx

import UIKit

private struct Welcome: Decodable {
	let authenticationResultCode: String
	let brandLogoURI: String?
	let copyright: String
	let resourceSets: [ResourceSet]
	let statusCode: Int
	let statusDescription, traceId: String
}

private struct ResourceSet: Decodable {
	let estimatedTotal: Int
	let resources: [Resource]
}

private struct Resource: Decodable {
	let __type: String
	let imageHeight: Int
	let imageUrl: String
	let imageWidth: Int
	let imageryProviders: [ImageryProvider]?
	let vintageEnd, vintageStart: String?
	let zoomMax, zoomMin: Int
}

private struct ImageryProvider: Decodable {
	let attribution: String
	let coverageAreas: [CoverageArea]
}

private struct CoverageArea: Decodable {
	let bbox: [Double]
	let zoomMax, zoomMin: Int
}

class BingMetadataViewController: UIViewController {
	@IBOutlet var activityIndicator: UIActivityIndicatorView!
	@IBOutlet var textView: UITextView!

	// Might be an error with parsing under neath
	override func viewDidLoad() {
		super.viewDidLoad()

		activityIndicator.startAnimating()

		let appDelegate = AppDelegate.shared
		let viewRect = appDelegate.mapView.boundingLatLonForScreen()
		var zoomLevel = appDelegate.mapView.aerialLayer.zoomLevel()
		let aerialService = appDelegate.mapView.aerialLayer.tileServer
		if zoomLevel > aerialService.maxZoom {
			zoomLevel = aerialService.maxZoom
		}

		Task {
			do {
				let data = try await appDelegate.mapView.aerialLayer.metadata()
				await MainActor.run {
					self.activityIndicator.stopAnimating()

					var attrList: [String] = []

					let welcome: Welcome?
					do {
						welcome = try JSONDecoder().decode(Welcome.self, from: data)
					} catch {
						print("error = \(error)")
						welcome = nil
					}

					for resourceSet in welcome?.resourceSets ?? [] {
						for resource in resourceSet.resources {
							for provider in resource.imageryProviders ?? [] {
								var attribution = provider.attribution
								for area in provider.coverageAreas {
									guard area.bbox.count == 4 else { continue }
									var rect = OSMRect(origin: OSMPoint(x: area.bbox[1],
									                                    y: area.bbox[0]),
									                   size: OSMSize(width: area.bbox[3],
									                                 height: area.bbox[2]))
									rect.size.width -= rect.origin.x
									rect.size.height -= rect.origin.y
									if zoomLevel >= area.zoomMin,
									   zoomLevel <= area.zoomMax,
									   viewRect.intersectsRect(rect)
									{
										if let vintageStart = resource.vintageStart,
										   let vintageEnd = resource.vintageEnd
										{
											attribution = "\(attribution)\n\(vintageStart) - \(vintageEnd)"
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

					let text = attrList.joined(separator: "\n\n")
					self.textView.text = String.localizedStringWithFormat(
						NSLocalizedString("Background imagery %@", comment: "identifies current aerial imagery"),
						"") + "\n\n" + text
				}
			} catch {
				await MainActor.run {
					self.activityIndicator.stopAnimating()
					self.textView.text = String.localizedStringWithFormat(
						NSLocalizedString("Error fetching metadata: %@", comment: ""),
						"\(error.localizedDescription)")
				}
			}
		}
	}

	@IBAction func cancel(_ sender: Any) {
		dismiss(animated: true)
	}
}
