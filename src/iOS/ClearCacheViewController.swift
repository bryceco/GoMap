//  Converted to Swift 5.2 by Swiftify v5.2.23024 - https://swiftify.com/
//
//  ClearCacheViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/15/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

enum Row : Int {
    case osmData = 0
    case mapnik = 1
    case aerial = 2
    case breadcrumb = 3
    case locator = 4
    case gps = 5
}

protocol GetDiskCacheSize {
	func getDiskCacheSize(_ pSize: inout Int, count pCount: inout Int)
}


class ClearCacheViewController: UITableViewController {
    @IBOutlet var _automaticCacheManagement: UISwitch!
    
    // MARK: - Table view data source
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
        
        let appDelegate = AppDelegate.shared
        
        _automaticCacheManagement.isOn = appDelegate?.mapView?.enableAutomaticCacheManagement ?? false
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        let appDelegate = AppDelegate.shared
        appDelegate?.mapView?.enableAutomaticCacheManagement = _automaticCacheManagement.isOn
    }
    
    // MARK: - Table view delegate
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let cell = cell as? ClearCacheCell else { return }
        if indexPath.section != 1 {
            return
        }
        
        let mapView = AppDelegate.shared?.mapView
        let mapData = mapView?.editorLayer.mapData
        
        var title: String? = nil
		var object: GetDiskCacheSize? = nil
        switch indexPath.row {
        case Row.osmData.rawValue:
            title = NSLocalizedString("Clear OSM Data", comment: "Delete cached data")
            object = nil
        case Row.mapnik.rawValue:
            title = NSLocalizedString("Clear Mapnik Tiles", comment: "Delete cached data")
			object = mapView?.mapnikLayer
        case Row.breadcrumb.rawValue:
            title = NSLocalizedString("Clear GPX Tracks", comment: "Delete cached data")
            object = mapView?.gpxLayer
        case Row.aerial.rawValue:
            title = NSLocalizedString("Clear Aerial Tiles", comment: "Delete cached data")
            object = mapView?.aerialLayer
        case Row.locator.rawValue:
            title = NSLocalizedString("Clear Locator Overlay Tiles", comment: "Delete cached data")
            object = mapView?.locatorLayer
        case Row.gps.rawValue:
            title = NSLocalizedString("Clear GPS Overlay Tiles", comment: "Delete cached data")
            object = mapView?.gpsTraceLayer
        default:
            break
        }
        cell.titleLabel.text = title
        cell.detailLabel.text = ""
        
        if indexPath.row == Row.osmData.rawValue {
            let objectCount = (mapData?.nodeCount() ?? 0) + (mapData?.wayCount() ?? 0) + (mapData?.relationCount() ?? 0)
            cell.detailLabel.text = String.localizedStringWithFormat(NSLocalizedString("%ld objects", comment: "Number of tiles/objects in cache"), objectCount)
        } else {
            cell.detailLabel.text = NSLocalizedString("computing size...", comment: "")
            DispatchQueue.global(qos: .default).async(execute: {
                var size = Int()
                var count = Int()
                object?.getDiskCacheSize(&size, count: &count)
                DispatchQueue.main.async(execute: {
                    cell.detailLabel.text = String.localizedStringWithFormat(NSLocalizedString("%.2f MB, %ld files", comment: "These values will always be large (plural)"), Double(size) / (1024 * 1024), count)
                })
            })
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let appDelegate = AppDelegate.shared
        
        if indexPath.section == 0 {
            return
        }
        
        switch indexPath.row {
        case Row.osmData.rawValue /* OSM */:
            if appDelegate?.mapView?.editorLayer.mapData.changesetAsXml() != nil {
                let alert = UIAlertController(
                    title: NSLocalizedString("Warning", comment: ""),
                    message: NSLocalizedString("You have made changes that have not yet been uploaded to the server. Clearing the cache will cause those changes to be lost.", comment: ""),
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: { action in
                    self.navigationController?.popViewController(animated: true)
                }))
                alert.addAction(UIAlertAction(title: NSLocalizedString("Purge", comment: "Discard editing changes when resetting OSM data cache"), style: .default, handler: { action in
                    appDelegate?.mapView?.editorLayer.purgeCachedDataHard(true)
                    appDelegate?.mapView?.placePushpinForSelection()
                    self.navigationController?.popViewController(animated: true)
                }))
                present(alert, animated: true)
                return
            }
            appDelegate?.mapView?.editorLayer.purgeCachedDataHard(true)
            appDelegate?.mapView?.removePin()
        case Row.mapnik.rawValue /* Mapnik */:
            appDelegate?.mapView?.mapnikLayer.purgeTileCache()
        case Row.breadcrumb.rawValue /* Breadcrumb */:
            appDelegate?.mapView?.gpxLayer.purgeTileCache()
        case Row.aerial.rawValue /* Bing */:
            appDelegate?.mapView?.aerialLayer.purgeTileCache()
        case Row.locator.rawValue /* Locator Overlay */:
            appDelegate?.mapView?.locatorLayer.purgeTileCache()
        case Row.gps.rawValue /* GPS Overlay */:
            appDelegate?.mapView?.gpsTraceLayer.purgeTileCache()
        default:
            break
        }
        dismiss(animated: true)
    }
}

class ClearCacheCell: UITableViewCell {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var detailLabel: UILabel!
}
