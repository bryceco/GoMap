//
//  NominatimViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/3/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import UIKit

class NominatimViewController: UIViewController, UISearchBarDelegate, UITableViewDelegate, UITableViewDataSource {
	@IBOutlet var searchBar: UISearchBar!
	private var resultsArray: [[String: Any]] = []
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
			let dict = resultsArray[indexPath.row]
			cell.textLabel?.text = dict["display_name"] as? String
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
		   zoom > 1 && zoom < 24
		{
			let scale = pow( 2.0, zoom)
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

		let dict = resultsArray[indexPath.row]
		if let box = dict["boundingbox"] as? [String] {
			let lat1 = Double(box[0]) ?? 0.0
			let lat2 = Double(box[1]) ?? 0.0
			let lon1 = Double(box[2]) ?? 0.0
			let lon2 = Double(box[3]) ?? 0.0

			let lat = (lat1 + lat2) / 2
			let lon = (lon1 + lon2) / 2

			jumpTo(lat: lat, lon: lon, zoom: nil)
		}
	}

	/// Looks for a pair of non-integer numbers in the string, and jump to it if found
	func containsLatLon(_ text: String) -> Bool {
		if let loc = LocationParser.mapLocationFrom(text: text) {
			updateHistory(with: "\(loc.latitude),\(loc.longitude)")
			jumpTo(lat: loc.latitude,
				 lon: loc.longitude,
				 zoom: loc.zoom > 0.0 ? loc.zoom : nil)
			return true
		}
		return false
	}

	/// try parsing as an OSM URL
	/// https://www.openstreetmap.org/relation/12894314#map=
	func containsOsmObjectID(string: String) -> Bool {
		var string = string.lowercased()
		if let hash = string.firstIndex(of: "#") {
			string = String(string[..<hash])
		}
		var objIdent: NSString?
		var objType: NSString?
		let delim = CharacterSet(charactersIn: "/,. -")
		let scanner = Scanner(string: String(string.reversed()))
		scanner.charactersToBeSkipped = nil
		if scanner.scanCharacters(from: CharacterSet.alphanumerics, into: &objIdent),
		   let objIdent = objIdent,
		   let objIdent2 = Int64(String((objIdent as String).reversed())),
		   scanner.scanCharacters(from: delim, into: nil),
		   scanner.scanCharacters(from: CharacterSet.alphanumerics, into: &objType),
		   let objType = objType,
		   let objType2 = try? OSM_TYPE(string: String((objType as String).reversed()))
		{
			activityIndicator.startAnimating()
			var url = OSM_API_URL + "api/0.6/\(objType2.string)/\(objIdent2)"
			if objType2 != .NODE {
				url += "/full"
			}
			OsmDownloader.osmData(forUrl: url, completion: { result in
				DispatchQueue.main.async {
					self.activityIndicator.stopAnimating()
					switch result {
					case let .success(data):
						if let node = data.nodes.first {
							self.updateHistory(with: "\(objType2.string) \(objIdent2)")
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

		// try parsing as an OSM URL
		// https://www.openstreetmap.org/relation/12894314#map=
		if containsOsmObjectID(string: string) {
			return
		}

		// Do this after checking for an OSM object URL since those can contain lat/lon as well
		if containsLatLon(string) {
			return
		}

		if let text = string.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed),
		   let url = URL(string: "https://nominatim.openstreetmap.org/search?q=\(text)&format=json&limit=50")
		{
			activityIndicator.startAnimating()

			URLSession.shared.data(with: url, completionHandler: { [self] result in
				DispatchQueue.main.async(execute: { [self] in

					activityIndicator.stopAnimating()

					switch result {
					case let .success(data):
						if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
							resultsArray = json as? [[String: Any]] ?? []
							tableView.reloadData()
						}

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
