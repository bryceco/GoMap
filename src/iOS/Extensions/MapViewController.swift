//
//  MapViewController.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 2/28/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import UIKit
import SafariServices

extension MapViewController {
    @IBAction func openHelp() {
        let urlAsString = "https://wiki.openstreetmap.org/w/index.php?title=Go_Map!!&mobileaction=toggle_view_mobile"
        guard let url = URL(string: urlAsString) else { return }
        
        let safariViewController = SFSafariViewController(url: url)
		safariViewController.modalPresentationStyle = .popover
        present(safariViewController, animated: true)
    }
}
