//
//  NominatimViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/3/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import UIKit

private struct NominatimResult: Decodable {
	let osm_type: String?
	let osm_id: Int?
	let boundingbox: [String]
	let display_name: String

	var latLon: LatLon? {
		let box = boundingbox.compactMap { Double($0) }
		guard box.count == 4 else { return nil }
		let lat1 = box[0]
		let lat2 = box[1]
		let lon1 = box[2]
		let lon2 = box[3]
		let lat = (lat1 + lat2) / 2
		let lon = (lon1 + lon2) / 2
		return LatLon(latitude: lat, longitude: lon)
	}
}

class NominatimViewController: UIViewController, UISearchBarDelegate, UITableViewDelegate, UITableViewDataSource {
	@IBOutlet var searchBar: UISearchBar!
	private var resultsArray: [NominatimResult] = []
	@IBOutlet var activityIndicator: UIActivityIndicatorView!
	@IBOutlet var tableView: UITableView!
	private var historyArray = MostRecentlyUsed<String>(maxCount: 20,
	                                                    userPrefsKey: UserPrefs.shared.searchHistory)
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

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		if showingHistory {
			let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryCell",
			                                         for: indexPath)
			cell.textLabel?.text = historyArray.items[indexPath.row]
			return cell
		} else {
			let cell = tableView.dequeueReusableCell(withIdentifier: "ResultCell",
			                                         for: indexPath)
			let result = resultsArray[indexPath.row]
			let subtitle: String
			if let latLon = result.latLon {
				// compute distance
				let dist = GreatCircleDistance(latLon,
				                               AppDelegate.shared.mainView.viewPort.screenCenterLatLon())
				subtitle = UnitFormatter.shared.stringFor(meters: dist)
			} else {
				subtitle = ""
			}
			cell.textLabel?.text = result.display_name
			cell.detailTextLabel?.text = subtitle
			return cell
		}
	}

	@IBAction func cancel(_ sender: Any) {
		dismiss(animated: true)
	}

	func jumpTo(lat: Double, lon: Double, zoom: Double?) {
		let mainView = AppDelegate.shared.mainView!

		// disable GPS
		while mainView.gpsState != GPS_STATE.NONE {
			mainView.toggleLocationButton(self)
		}
		let latLon = LatLon(latitude: lat, longitude: lon)

		if let zoom = zoom,
		   zoom > 1,
		   zoom < 24
		{
			mainView.viewPort.centerOn(latLon: latLon, zoom: zoom, rotation: 0.0)
		} else {
			mainView.viewPort.centerOn(latLon: latLon, metersWide: 50.0)
		}

		dismiss(animated: true)
	}

	// MARK: - Table view delegate

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		if showingHistory {
			// history item
			searchBar.text = historyArray.items[indexPath.row]
			searchBarSearchButtonClicked(searchBar)
			return
		}

		let result = resultsArray[indexPath.row]

		// if nominatim returned an OSM object directly then use it
		if let osmType = result.osm_type,
		   let osmId = result.osm_id,
		   parsedAsOsmObjectRef("\(osmType) \(osmId)")
		{
			return
		}

		if let latLon = result.latLon {
			jumpTo(lat: latLon.lat, lon: latLon.lon, zoom: nil)
		}
	}

	/// try parsing as an OSM object reference
	/// https://www.openstreetmap.org/relation/12894314#map=
	func parsedAsOsmObjectRef(_ string: String) -> Bool {
		guard let (objType, objIdent) = LocationParser.osmObjectReference(string: string) else {
			return false
		}

		activityIndicator.startAnimating()
		var url = OSM_SERVER.apiURL + "api/0.6/\(objType.string)/\(objIdent)"
		if objType != .NODE {
			url += "/full"
		}
		Task {
			do {
				let data = try await OsmDownloader.osmData(forUrl: url)
				await MainActor.run {
					self.activityIndicator.stopAnimating()
					if let node = data.nodes.first {
						self.updateHistory(with: "\(objType.string) \(objIdent)")
						self.jumpTo(lat: node.latLon.lat, lon: node.latLon.lon, zoom: nil)
					} else {
						self.presentErrorMessage()
					}
				}
			} catch {
				await MainActor.run {
					self.activityIndicator.stopAnimating()
					self.presentErrorMessage(error)
				}
			}
		}
		return true
	}

	/// try parsing as GOO.GL redirect
	/// https://goo.gl/maps/yGZxAN37wcmERVD6A
	func parsedAsGoogleDynamicLink(_ string: String) -> Bool {
		guard LocationParser.isGoogleMapsRedirect(urlString: string, callback: { mapLocation in
			DispatchQueue.main.async {
				self.activityIndicator.stopAnimating()
				if let mapLocation = mapLocation {
					self.updateHistory(with: "\(mapLocation.latitude),\(mapLocation.longitude)")
					self.jumpTo(lat: mapLocation.latitude,
					            lon: mapLocation.longitude,
					            zoom: mapLocation.zoom)
				} else {
					self.presentErrorMessage()
				}
			}
		}) else {
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

		guard
			let url = nominatimSearchURL(query: string,
			                             lang: PresetLanguages.preferredLanguageCode(),
			                             latLon: AppDelegate.shared.mainView.viewPort.screenCenterLatLon())
		else {
			return
		}
		activityIndicator.startAnimating()

		Task {
			defer {
				activityIndicator.stopAnimating()
			}
			do {
				let data = try await URLSession.shared.data(with: url)
				await MainActor.run {
					resultsArray = (try? JSONDecoder().decode([NominatimResult].self, from: data)) ?? []
					tableView.reloadData()

					if resultsArray.count > 0 {
						updateHistory(with: string)
						// flag that we're no longer showing history and remove all items
						showingHistory = false
						tableView.reloadData()
					} else {
						presentErrorMessage()
					}
				}
			} catch {
				await MainActor.run {
					presentErrorMessage(error)
				}
			}
		}
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

	func nominatimSearchURL(query string: String, lang: String, latLon: LatLon) -> URL? {
		var components = URLComponents(string: OSM_SERVER.nominatimUrl + "search")
		components?.queryItems = [
			URLQueryItem(name: "q", value: string),
			URLQueryItem(name: "format", value: "json"),
			URLQueryItem(name: "limit", value: "50"),
			URLQueryItem(name: "accept-language", value: lang),
			URLQueryItem(name: "lat", value: String(latLon.lat)),
			URLQueryItem(name: "lon", value: String(latLon.lon))
		]
		return components?.url
	}
}
