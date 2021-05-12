//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
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
    var _mappers: NSArray = []

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.estimatedRowHeight = 44
        tableView.rowHeight = UITableView.automaticDimension

        let appDelegate = AppDelegate.shared

        if let rect = appDelegate?.mapView?.screenLongitudeLatitude() {
            _mappers = appDelegate?.mapView?.editorLayer.mapData.userStatistics(forRegion: rect) as NSArray? ?? []
        }
        _mappers = _mappers.sortedArray(comparator: { s1, s2 in
            return ((s1 as AnyObject).lastEdit).compare((s1 as AnyObject).lastEdit)
        }) as NSArray
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if _mappers.count == 0 {
            let alert = UIAlertController(
                title: NSLocalizedString("No Data", comment: "Alert title"),
                message: NSLocalizedString("Ensure the editor view is visible and displays objects in the local area", comment: ""),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: { [self] action in
                navigationController?.popViewController(animated: true)
            }))
            present(alert, animated: true) {
            }
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return _mappers.count
    }

    // MARK: - Table view delegate

    static let tableViewCellIdentifier = "Cell"

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: NearbyMappersViewController.tableViewCellIdentifier, for: indexPath)

        let stats = _mappers[indexPath.row] as? OsmUserStatistics
        cell.textLabel?.text = stats?.user
        var date: String? = nil
        if let lastEdit = stats?.lastEdit {
            date = DateFormatter.localizedString(from: lastEdit, dateStyle: .medium, timeStyle: DateFormatter.Style.none)
        }
        cell.detailTextLabel?.text = String.localizedStringWithFormat(NSLocalizedString("%ld edits, last active %@", comment: "Brief synopsis of a mapper's activity (count,last active date)"), Int(stats?.editCount ?? 0), date ?? "")

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let stats = _mappers[indexPath.row] as? OsmUserStatistics
        let user = stats?.user
        let urlString = "https://www.openstreetmap.org/user/\(user ?? "")"
        let encodedUrlString = urlString.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)
        let url = URL(string: encodedUrlString ?? "")

        var safariViewController: SFSafariViewController? = nil
        if let url = url {
            safariViewController = SFSafariViewController(url: url)
        }
        if let safariViewController = safariViewController {
            present(safariViewController, animated: true)
        }
    }
}
