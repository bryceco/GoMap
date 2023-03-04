//
//  NominatimViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/3/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import UIKit

private struct NominatimResult: Decodable {
	let boundingbox: [String]
	let display_name: String
}

class NominatimViewController: UIViewController, UISearchBarDelegate, UITableViewDelegate, UITableViewDataSource {
	@IBOutlet var searchBar: UISearchBar!
	private var resultsArray: [NominatimResult] = []
	@IBOutlet var activityIndicator: UIActivityIndicatorView!
	@IBOutlet var tableView: UITableView!
	private var historyArray = MostRecentlyUsed<String>(maxCount: 20, userDefaultsKey: "searchHistory")
	private var showingHistory = true

	override func viewDidLoad() {
		super.viewDidLoad()
		activityIndicator.color = UIColor.black
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		searchBar.becomeFirstResponder()
	}

	override func viewWillDisappear(_ animated: Bool) {
		view.endEditing(true)

		super.viewWillDisappear(animated)
	}

	// MARK: - Table view data source

	func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return showingHistory ? historyArray.count : resultsArray.count
	}

	func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
		return UIView()
	}

	func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
		return 44
	}

	func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		return UITableView.automaticDimension
	}

	static let tableViewCellIdentifier = "Cell"

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(
			withIdentifier: NominatimViewController.tableViewCellIdentifier,
			for: indexPath)

		if showingHistory {
			cell.textLabel?.text = historyArray.items[indexPath.row]
		} else {
			cell.textLabel?.text = resultsArray[indexPath.row].display_name
		}
		return cell
	}

	@IBAction func cancel(_ sender: Any) {
		dismiss(animated: true)
	}

	func jumpTo(lat: Double, lon: Double, zoom: Double?) {
		let appDelegate = AppDelegate.shared

		// disable GPS
		while appDelegate.mapView.gpsState != GPS_STATE.NONE {
			appDelegate.mapView.mainViewController.toggleLocationButton(self)
		}
		let latLon = LatLon(latitude: lat, longitude: lon)

		if let zoom = zoom,
		   zoom > 1,
		   zoom < 24
		{
			let scale = pow(2.0, zoom)
			appDelegate.mapView.setTransformFor(latLon: latLon, scale: scale)
		} else {
			let metersPerDegree = MetersPerDegreeAt(latitude: lat)
			let minMeters: Double = 50
			let widthDegrees = minMeters / metersPerDegree.y
			appDelegate.mapView.setTransformFor(latLon: latLon, width: widthDegrees)
		}

		dismiss(animated: true)
	}

	// MARK: - Table view delegate

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if showingHistory {
			// history item
			searchBar.text = historyArray.items[indexPath.row]
			searchBarSearchButtonClicked(searchBar)
			return
		}

		let box = resultsArray[indexPath.row].boundingbox.compactMap { Double($0) }
		if box.count == 4 {
			let lat1 = box[0]
			let lat2 = box[1]
			let lon1 = box[2]
			let lon2 = box[3]
			let lat = (lat1 + lat2) / 2
			let lon = (lon1 + lon2) / 2

			jumpTo(lat: lat, lon: lon, zoom: nil)
		}
	}

	/// try parsing as an OSM object reference
	/// https://www.openstreetmap.org/relation/12894314#map=
	func parsedAsOsmObjectRef(_ string: String) -> Bool {
		guard let (objType, objIdent) = LocationParser.osmObjectReference(string: string) else {
			return false
		}

		activityIndicator.startAnimating()
		var url = OSM_API_URL + "api/0.6/\(objType.string)/\(objIdent)"
		if objType != .NODE {
			url += "/full"
		}
		OsmDownloader.osmData(forUrl: url, completion: { result in
			DispatchQueue.main.async {
				self.activityIndicator.stopAnimating()
				switch result {
				case let .success(data):
					if let node = data.nodes.first {
						self.updateHistory(with: "\(objType.string) \(objIdent)")
						self.jumpTo(lat: node.latLon.lat, lon: node.latLon.lon, zoom: nil)
					} else {
						self.presentErrorMessage()
					}
				case let .failure(error):
					self.presentErrorMessage(error)
				}
			}
		})
		return true
	}

	/// try parsing as GOO.GL redirect
	/// https://goo.gl/maps/yGZxAN37wcmERVD6A
	func parsedAsGoogleDynamicLink(_ string: String) -> Bool {
		guard let url = URL(string: string),
		      LocationParser.isGoogleMapsRedirect(url: url, callback: { mapLocation in
		      	DispatchQueue.main.async {
		      		self.activityIndicator.stopAnimating()
		      		if let mapLocation = mapLocation {
		      			self.updateHistory(with: "\(mapLocation.latitude),\(mapLocation.longitude)")
		      			self.jumpTo(lat: mapLocation.latitude,
		      			            lon: mapLocation.longitude,
		      			            zoom: mapLocation.zoom)
		      		}
		      	}
		      })
		else {
			return false
		}
		activityIndicator.startAnimating()
		return true
	}

	/// Looks for a pair of non-integer numbers in the string, and jump to it if found
	func parsedAsLatLon(_ string: String) -> Bool {
		if let loc = LocationParser.mapLocationFrom(string: string) {
			updateHistory(with: "\(loc.latitude),\(loc.longitude)")
			jumpTo(lat: loc.latitude,
			       lon: loc.longitude,
			       zoom: loc.zoom > 0.0 ? loc.zoom : nil)
			return true
		}
		return false
	}

	func updateHistory(with string: String) {
		historyArray.updateWith(string)
	}

	// MARK: Search bar delegate

	func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
		dismiss(animated: true)
	}

	func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
		searchBar.resignFirstResponder()

		resultsArray = []
		guard let string = searchBar.text,
		      !string.isEmpty
		else {
			// no search
			searchBar.perform(#selector(UIResponder.resignFirstResponder), with: nil, afterDelay: 0.1)
			return
		}

		// try parsing it as a special case before doing Nominatim lookup
		if parsedAsOsmObjectRef(string) ||
			parsedAsGoogleDynamicLink(string) ||
			parsedAsLatLon(string)
		{
			return
		}

		let lang = PresetLanguages.preferredLanguageCode()
		if let text = string.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed),
		   let url = URL(string:
		   	"https://nominatim.openstreetmap.org/search?q=\(text)&format=json&limit=50&accept-language=\(lang)")
		{
			activityIndicator.startAnimating()

			URLSession.shared.data(with: url, completionHandler: { [self] result in
				DispatchQueue.main.async(execute: { [self] in

					activityIndicator.stopAnimating()

					switch result {
					case let .success(data):
						resultsArray = (try? JSONDecoder().decode([NominatimResult].self, from: data)) ?? []
						tableView.reloadData()

						if resultsArray.count > 0 {
							updateHistory(with: string)
						} else {
							presentErrorMessage()
						}
					case let .failure(error):
						presentErrorMessage(error)
					}
				})
			})
		}
		// flag that we're no longer showing history and remove all items
		showingHistory = false
		tableView.reloadData()
	}

	func presentErrorMessage(_ error: Error? = nil) {
		let alert = UIAlertController(title: NSLocalizedString("No results found", comment: ""),
		                              message: error?.localizedDescription ?? "",
		                              preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
		                              style: .cancel,
		                              handler: nil))
		present(alert, animated: true)
	}
}
