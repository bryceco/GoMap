//
//  NearbyMappersViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/26/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import SafariServices
import UIKit

class NearbyMappersViewController: UITableViewController {
	private var mappers: [OsmUserStatistics] = []

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.estimatedRowHeight = 44
		tableView.rowHeight = UITableView.automaticDimension

		let appDelegate = AppDelegate.shared

		let rect = appDelegate.mapView.boundingLatLonForScreen()
		mappers = appDelegate.mapView.editorLayer.mapData.userStatistics(forRegion: rect)
		mappers.sort(by: { s1, s2 in s1.lastEdit.compare(s2.lastEdit) != .orderedAscending })
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if mappers.count == 0 {
			let alert = UIAlertController(
				title: NSLocalizedString("No Data", comment: "Alert title"),
				message: NSLocalizedString(
					"Ensure the editor view is visible and displays objects in the local area",
					comment: ""),
				preferredStyle: .alert)
			alert
				.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default,
				                         handler: { [self] _ in
				                         	navigationController?.popViewController(animated: true)
				                         }))
			present(alert, animated: true) {}
		}
	}

	// MARK: - Table view data source

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return mappers.count
	}

	// MARK: - Table view delegate

	static let tableViewCellIdentifier = "Cell"

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(
			withIdentifier: NearbyMappersViewController.tableViewCellIdentifier,
			for: indexPath)

		let stats = mappers[indexPath.row]
		cell.textLabel?.text = stats.user
		let date = DateFormatter.localizedString(
			from: stats.lastEdit,
			dateStyle: .medium,
			timeStyle: DateFormatter.Style.none)
		cell.detailTextLabel?.text = String.localizedStringWithFormat(
			NSLocalizedString("%ld edits, last active %@",
			                  comment: "Brief synopsis of a mapper's activity (count,last active date)"),
			Int(stats.editCount),
			date)

		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let stats = mappers[indexPath.row]
		let urlString = "\(OSM_SERVER.serverURL)user/\(stats.user)"
		let encodedUrlString = urlString.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)
		let url = URL(string: encodedUrlString ?? "")

		var safariViewController: SFSafariViewController?
		if let url = url {
			safariViewController = SFSafariViewController(url: url)
		}
		if let safariViewController = safariViewController {
			present(safariViewController, animated: true)
		}
	}
}
