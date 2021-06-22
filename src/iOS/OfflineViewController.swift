//
//  OfflineViewController.swift
//  Go Map!!
//
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

class OfflineTableViewCell: UITableViewCell {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var detailLabel: UILabel!
	@IBOutlet var button: UIButton!
	@IBOutlet var activityView: UIActivityIndicatorView!
	var tileList: [String] = []
	var tileLayer: MercatorTileLayer?
}

class OfflineViewController: UITableViewController {
	@IBOutlet var _aerialCell: OfflineTableViewCell!
	@IBOutlet var _mapnikCell: OfflineTableViewCell!
	var activityCount = 0

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.estimatedRowHeight = 100
		tableView.rowHeight = UITableView.automaticDimension
		_aerialCell.tileLayer = AppDelegate.shared.mapView.aerialLayer
		_mapnikCell.tileLayer = AppDelegate.shared.mapView.mapnikLayer
		for cell in [_aerialCell!, _mapnikCell!] {
			cell.tileList = cell.tileLayer!.allTilesIntersectingVisibleRect()
			cell.detailLabel.text = String.localizedStringWithFormat(
				NSLocalizedString("%lu tiles needed", comment: ""),
				UInt(cell.tileList.count))
			cell.button.isEnabled = cell.tileList.count > 0
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		for cell in [_aerialCell, _mapnikCell] {
			cell?.activityView.stopAnimating()
		}
	}

	// MARK: - Table view delegate

	func downloadFile(for cell: OfflineTableViewCell) {
		if let cacheKey = cell.tileList.popLast() {
			cell.tileLayer?.downloadTile(forKey: cacheKey,
			                             completion: {
			                             	cell.detailLabel.text = String.localizedStringWithFormat(
			                             		NSLocalizedString("%lu tiles needed", comment: "Always plural"),
			                             		UInt(cell.tileList.count))
			                             	if cell.activityView.isAnimating {
			                             		// recurse
			                             		self.downloadFile(for: cell)
			                             	}
			                             })
		} else {
			// finished
			cell.button.setTitle(NSLocalizedString("Start", comment: "Begin downloading tiles"), for: .normal)
			cell.activityView.stopAnimating()
			activityCount -= 1
			if activityCount == 0 {
				navigationItem.setHidesBackButton(false, animated: true)
			}
		}
	}

	@IBAction func toggleDownload(_ sender: UIButton) {
		var cell = OfflineTableViewCell()
		if sender == _aerialCell.button {
			cell = _aerialCell
		} else {
			cell = _mapnikCell
		}

		if cell.activityView.isAnimating {
			// stop download
			cell.button.setTitle(NSLocalizedString("Start", comment: ""), for: .normal)
			cell.activityView.stopAnimating()
			activityCount -= 1
			if activityCount == 0 {
				navigationItem.setHidesBackButton(false, animated: true)
			}
		} else {
			// start download
			cell.button.setTitle(NSLocalizedString("Stop", comment: ""), for: .normal)
			cell.activityView.startAnimating()
			navigationItem.setHidesBackButton(true, animated: true)
			activityCount += 1
			downloadFile(for: cell)
		}
	}
}
