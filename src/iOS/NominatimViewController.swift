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
	private var historyArray: [String] = []

	override func viewDidLoad() {
		super.viewDidLoad()
		activityIndicator.color = UIColor.black
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		searchBar.becomeFirstResponder()

		historyArray = UserDefaults.standard.object(forKey: "searchHistory") as? [String] ?? []
	}

	override func viewWillDisappear(_ animated: Bool) {
		view.endEditing(true)

		super.viewWillDisappear(animated)
		UserDefaults.standard.set(historyArray, forKey: "searchHistory")
	}

	// MARK: - Table view data source

	func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return (searchBar.text?.count ?? 0) != 0 ? resultsArray.count : historyArray.count
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

		if searchBar.text?.isEmpty ?? true {
			cell.textLabel?.text = historyArray[indexPath.row]
		} else {
			let dict = resultsArray[indexPath.row]
			cell.textLabel?.text = dict["display_name"] as? String
		}
		return cell
	}

	@IBAction func cancel(_ sender: Any) {
		dismiss(animated: true)
	}

	func jump(toLat lat: Double, lon: Double) {
		let appDelegate = AppDelegate.shared
		let metersPerDegree = MetersPerDegreeAt(latitude: lat)
		let minMeters: Double = 50
		let widthDegrees = minMeters / metersPerDegree.y

		// disable GPS
		while appDelegate.mapView.gpsState != GPS_STATE.NONE {
			appDelegate.mapView.mainViewController.toggleLocation(self)
		}

		appDelegate.mapView.setTransformFor(latLon: LatLon(latitude: lat, longitude: lon),
		                                    width: widthDegrees)

		dismiss(animated: true)
	}

	// MARK: - Table view delegate

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		if (searchBar.text?.count ?? 0) == 0 {
			// history item
			searchBar.text = historyArray[indexPath.row]
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

			jump(toLat: lat, lon: lon)
		}
	}

	/// Looks for a pair of non-integer numbers in the string, and jump to it if found
	func containsLatLon(_ text: String) -> Bool {
		let text = text.trimmingCharacters(in: .whitespacesAndNewlines)

		// try parsing as a URL containing lat=,lon=
		if let comps = URLComponents(string: text) {
			if let lat = comps.queryItems?.first(where: { $0.name == "lat" })?.value,
			   let lon = comps.queryItems?.first(where: { $0.name == "lon" })?.value,
			   let lat = Double(lat),
			   let lon = Double(lon)
			{
				updateHistory(with: "\(lat),\(lon)")
				jump(toLat: lat, lon: lon)
				return true
			}
		}

		let scanner = Scanner(string: text)
		let digits = CharacterSet(charactersIn: "-0123456789")
		let comma = CharacterSet(charactersIn: ",°/")
		scanner.charactersToBeSkipped = CharacterSet.whitespaces

		while !scanner.isAtEnd {
			scanner.scanUpToCharacters(from: digits, into: nil)
			let pos = scanner.scanLocation
			var lat: Double = 0.0
			var lon: Double = 0.0
			if scanner.scanDouble(&lat), lat != Double(Int(lat)), lat > -90, lat < 90,
			   scanner.scanCharacters(from: comma, into: nil),
			   scanner.scanDouble(&lon), lon != Double(Int(lon)), lon >= -180, lon <= 180
			{
				updateHistory(with: "\(lat),\(lon)")
				jump(toLat: lat, lon: lon)
				return true
			}
			if scanner.scanLocation == pos, !scanner.isAtEnd {
				scanner.scanLocation = pos + 1
			}
		}
		return false
	}

	func updateHistory(with string: String) {
		historyArray.removeAll { $0 == string }
		historyArray.insert(string, at: 0)
		while historyArray.count > 20 {
			historyArray.removeLast()
		}
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
		if containsLatLon(string) {
			return
		}

		// searching
		activityIndicator.startAnimating()

		let text = string.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)
		let url = "https://nominatim.openstreetmap.org/search?q=\(text ?? "")&format=json&limit=50"
		if let url1 = URL(string: url) {
			let task = URLSession.shared.dataTask(with: url1, completionHandler: { [self] data, _, error in
				DispatchQueue.main.async(execute: { [self] in

					activityIndicator.stopAnimating()

					if let data = data,
					   error == nil
					{
						/*
						 {
						 "place_id":"5639098",
						 "licence":"Data \u00a9 OpenStreetMap contributors, ODbL 1.0. https:\/\/www.openstreetmap.org\/copyright",
						 "osm_type":"node",
						 "osm_id":"585214834",
						 "boundingbox":["55.9587516784668","55.9587554931641","-3.20986247062683","-3.20986223220825"],
						 "lat":"55.9587537","lon":"-3.2098624",
						 "display_name":"Hectors, Deanhaugh Street, Stockbridge, Dean, Edinburgh, City of Edinburgh, Scotland, EH4 1NE, United Kingdom",
						 "class":"amenity",
						 "type":"pub",
						 "icon":"https:\/\/nominatim.openstreetmap.org\/images\/mapicons\/food_pub.p.20.png"
						 },
						 */

						let json = try? JSONSerialization.jsonObject(with: data, options: [])
						resultsArray = json as? [[String: Any]] ?? []
						tableView.reloadData()

						if resultsArray.count > 0 {
							updateHistory(with: string)
						}
					} else {
						// error fetching results
					}

					if resultsArray.count == 0 {
						let alert = UIAlertController(
							title: NSLocalizedString("No results found", comment: ""),
							message: nil,
							preferredStyle: .alert)
						alert
							.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
													 style: .cancel,
							                         handler: nil))
						present(alert, animated: true)
					}
				})
			})
			task.resume()
		}
		tableView.reloadData()
	}
}
