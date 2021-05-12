//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  NominatimViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/3/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import UIKit

class NominatimViewController: UIViewController, UISearchBarDelegate, UITableViewDelegate, UITableViewDataSource {
    @IBOutlet var _searchBar: UISearchBar!
    var _resultsArray: [AnyHashable]?
    @IBOutlet var _activityIndicator: UIActivityIndicatorView!
    @IBOutlet var _tableView: UITableView!
    var _historyArray: [AnyHashable]?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        _activityIndicator.color = UIColor.black
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        _searchBar.becomeFirstResponder()
        
        _historyArray = UserDefaults.standard.object(forKey: "searchHistory") as? [AnyHashable]
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        view.endEditing(true)
        
        super.viewWillDisappear(animated)
        UserDefaults.standard.set(_historyArray, forKey: "searchHistory")
    }
    
    // MARK: - Table view data source
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return (_searchBar.text?.count ?? 0) != 0 ? (_resultsArray?.count ?? 0) : (_historyArray?.count ?? 0)
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
        let cell = tableView.dequeueReusableCell(withIdentifier: NominatimViewController.tableViewCellIdentifier, for: indexPath)
        
        if (_searchBar.text?.count ?? 0) != 0 {
            let dict = _resultsArray?[indexPath.row] as? [AnyHashable : Any]
            cell.textLabel?.text = dict?["display_name"] as? String
        } else {
            cell.textLabel?.text = _historyArray?[indexPath.row] as? String
        }
        return cell
    }
    
    @IBAction func cancel(_ sender: Any) {
        dismiss(animated: true)
    }
    
    func jump(toLat lat: Double, lon: Double) {
        let appDelegate = AppDelegate.shared
        let metersPerDegree = MetersPerDegree(lat)
        let minMeters: Double = 50
        let widthDegrees = minMeters / metersPerDegree
        
        // disable GPS
        while appDelegate?.mapView?.gpsState != GPS_STATE_NONE {
            appDelegate?.mapView?.mainViewController.toggleLocation(self)
        }
        
        appDelegate?.mapView?.setTransformForLatitude(lat, longitude: lon, width: widthDegrees)
        
        dismiss(animated: true)
    }
    
    // MARK: - Table view delegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if (_searchBar.text?.count ?? 0) == 0 {
            // history item
            _searchBar.text = _historyArray?[indexPath.row] as? String
            searchBarSearchButtonClicked(_searchBar)
            return
        }
        
        let dict = _resultsArray?[indexPath.row] as? [AnyHashable : Any]
        if let box = dict?["boundingbox"] as? [String] {
            var lat1 = Double(box[0]) ?? 0.0
            let lat2 = Double(box[1]) ?? 0.0
            var lon1 = Double(box[2]) ?? 0.0
            let lon2 = Double(box[3]) ?? 0.0
            
            lat1 = (lat1 + lat2) / 2
            lon1 = (lon1 + lon2) / 2
            
            jump(toLat: lat1, lon: lon1)
        }
    }
    
    // look for a pair of non-integer numbers in the string, and jump to it if found
    func containsLatLon(_ text: String?) -> Bool {
        let scanner = Scanner(string: text ?? "")
        let digits = CharacterSet(charactersIn: "-0123456789")
        let comma = CharacterSet(charactersIn: ",/")
        scanner.charactersToBeSkipped = CharacterSet.whitespaces
        var lat: Double = 0.0
        var lon: Double = 0.0
        
        while !scanner.isAtEnd {
            scanner.scanUpToCharacters(from: digits, into: nil)
            let pos = scanner.scanLocation
            if scanner.scanDouble(UnsafeMutablePointer<Double>(mutating: &lat)) && lat != Double(Int(lat)) && lat > -90 && lat < 90 && scanner.scanCharacters(from: comma, into: nil) && scanner.scanDouble(UnsafeMutablePointer<Double>(mutating: &lon)) && lon != Double(Int(lon)) && lon >= -180 && lon <= 180 {
                updateHistory(with: "\(lat),\(lon)")
                jump(toLat: lat, lon: lon)
                return true
            }
            if scanner.scanLocation == pos && !scanner.isAtEnd {
                scanner.scanLocation = pos + 1
            }
        }
        return false
    }
    
    func updateHistory(with string: String?) {
        var a = _historyArray ?? []
        a.removeAll {$0 as? String == string}
        a.insert(string ?? "", at: 0)
        while (a.count) > 20 {
            a.removeLast()
        }
        _historyArray = a
    }
    
    // MARK: Search bar delegate
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        dismiss(animated: true)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        
        _resultsArray = nil
        let string = searchBar.text
        if (string?.count ?? 0) == 0 {
            // no search
            self._searchBar.perform(#selector(UIResponder.resignFirstResponder), with: nil, afterDelay: 0.1)
        } else if containsLatLon(string) {
            return
        } else {
            // searching
            _activityIndicator.startAnimating()
            
            let text = string?.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)
            let url = "https://nominatim.openstreetmap.org/search?q=\(text ?? "")&format=json&limit=50"
            var task: URLSessionDataTask? = nil
            if let url1 = URL(string: url) {
                task = URLSession.shared.dataTask(with: url1, completionHandler: { [self] data, response, error in
                    DispatchQueue.main.async(execute: { [self] in
                        
                        _activityIndicator.stopAnimating()
                        
                        if data != nil && error == nil {
                            
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
                            
                            var json: Any? = nil
                            do {
                                if let data = data {
                                    json = try JSONSerialization.jsonObject(with: data, options: [])
                                }
                            } catch {
                            }
                            _resultsArray = json as? [AnyHashable]
                            _tableView.reloadData()
                            
                            if (_resultsArray?.count ?? 0) > 0 {
                                updateHistory(with: string)
                            }
                        } else {
                            // error fetching results
                        }
                        
                        if (_resultsArray?.count ?? 0) == 0 {
                            let alert = UIAlertController(title: NSLocalizedString("No results found", comment: ""), message: nil, preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
                            present(alert, animated: true)
                        }
                    })
                })
            }
            task?.resume()
        }
        _tableView.reloadData()
    }
}
