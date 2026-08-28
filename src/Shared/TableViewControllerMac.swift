//
//  TableViewControllerMac.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/6/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit

/// This class adds default behaviors to UITableViewController that make header and footer
/// text present correctly when running in the "Designed for iPad (Mac)" runtime context.
class TableViewControllerMac: UITableViewController {

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 44

		tableView.sectionHeaderHeight = UITableView.automaticDimension
		tableView.estimatedSectionHeaderHeight = 28
		tableView.sectionFooterHeight = UITableView.automaticDimension
		tableView.estimatedSectionFooterHeight = 28
	}

	override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		if self.tableView(tableView, titleForHeaderInSection: section) == nil {
			return 0
		}
		return UITableView.automaticDimension
	}

	override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
		if self.tableView(tableView, titleForFooterInSection: section) == nil {
			return 0
		}
		return UITableView.automaticDimension
	}
}
