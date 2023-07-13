//
//  AccountInfoTableViewController.swift
//  Go Map!!
//
//  Created by Patrick Steiner on 13.07.23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import UIKit

final class AccountInfoTableViewController: UITableViewController {
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var refreshAccountButton: UIButton!
    @IBOutlet weak var usernameLabel: UILabel!
    @IBOutlet weak var changesetsLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        fetchAccountInfos()
    }

    private func fetchAccountInfos() {
        if activityIndicator.isAnimating {
            return
        }

        activityIndicator.color = .darkGray
        activityIndicator.startAnimating()
        refreshAccountButton.isHidden = true

        AppDelegate.shared.oAuth2.getUserDetails { [weak self] dict in
            guard let strongSelf = self else { return }

            strongSelf.activityIndicator.stopAnimating()
            strongSelf.refreshAccountButton.isHidden = false

            if let dict {
                if let name = dict["display_name"] as? String {
                    AppDelegate.shared.userName = name
                    strongSelf.usernameLabel.text = name
                }

                if let changesets = dict["changesets"] as? [String: Any], let count = changesets["count"] as? Int64 {
                    strongSelf.changesetsLabel.text = "\(count)"
                }

            } else {
                strongSelf.presentBadLoginDialog()
            }
        }
    }

    private func setupUI() {
        usernameLabel.text = AppDelegate.shared.userName
    }

    private func presentBadLoginDialog() {
        let alert = UIAlertController(
            title: NSLocalizedString("Bad login", comment: ""),
            message: NSLocalizedString("Not found", comment: "User credentials not found"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
                                      style: .cancel,
                                      handler: nil))
        self.present(alert, animated: true)
    }

    @IBAction func didTapRefreshButton(_ sender: UIButton) {
        fetchAccountInfos()
    }
    
    @IBAction func didTapSignOutButton(_ sender: UIButton) {
        AppDelegate.shared.oAuth2.removeAuthorization()
        AppDelegate.shared.userName = nil

        self.navigationController?.popToRootViewController(animated: true)
    }
}
