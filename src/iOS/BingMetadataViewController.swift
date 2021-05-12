//  Converted to Swift 5.2 by Swiftify v5.2.23024 - https://swiftify.com/
//
//  BingMetadataViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/6/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

// http://www.microsoft.com/maps/attribution.aspx

class BingMetadataViewController: UIViewController {
    @IBOutlet var activityIndicator: UIActivityIndicatorView!
    @IBOutlet var textView: UITextView!

    // Might be an error with parsing under neath
    override func viewDidLoad() {
        super.viewDidLoad()

        activityIndicator.startAnimating()

        let appDelegate = AppDelegate.shared
        guard let viewRect = appDelegate?.mapView?.screenLongitudeLatitude() else { return }
        var zoomLevel = appDelegate?.mapView?.aerialLayer.zoomLevel() ?? 0
        let aerialService = appDelegate?.mapView?.aerialLayer.aerialService
        if zoomLevel > (aerialService?.maxZoom ?? 0) {
            zoomLevel = aerialService?.maxZoom ?? 0
        }

        appDelegate?.mapView?.aerialLayer.metadata({ data, error in
            self.activityIndicator.stopAnimating()

            if data != nil && error == nil {
                var json: Any? = nil
                do {
                    if let data = data {
                        json = try JSONSerialization.jsonObject(with: data, options: [])
                    }
                } catch {
                }

                var attrList: [String] = []

                let resourceSets = (json as? [AnyHashable : Any])?["resourceSets"] as? [AnyHashable]
                for resourceSet in resourceSets ?? [] {
                    let resources = (resourceSet as? [AnyHashable : Any])?["resources"]
                    if let resources: [Any] = resources as? [Any] {
                        for resource in resources {
                            let vintageStart = ((resource as? [AnyHashable : Any])?["vintageStart"] as? String) ?? ""
                            let vintageEnd = ((resource as? [AnyHashable : Any])?["vintageEnd"] as? String) ?? ""
                            let providers = (resource as? [AnyHashable : Any])?["imageryProviders"]
                            if (providers != nil) {
                                if let providers: [Any] = providers as? [Any] {
                                    for provider in providers {
                                        var attribution = ((provider as? [AnyHashable : Any])?["attribution"] as? String) ?? ""
                                        let areas = (provider as? [AnyHashable : Any])?["coverageAreas"] as? [AnyHashable]
                                        for area in areas ?? [] {
                                            guard let area = area as? [AnyHashable : Any] else {
                                                continue
                                            }
                                            let zoomMin = (area["zoomMin"] as? NSNumber)?.intValue ?? 0
                                            let zoomMax = (area["zoomMax"] as? NSNumber)?.intValue ?? 0
                                            let bbox = area["bbox"] as? [AnyHashable] ?? []
                                            var rect = OSMRect.init(origin: _OSMPoint.init(x: (bbox[1] as? NSNumber)?.doubleValue ?? 0.0, y: (bbox[0] as? NSNumber)?.doubleValue ?? 0.0), size: OSMSize.init(width: (bbox[3] as? NSNumber)?.doubleValue ?? 0.0, height: (bbox[2] as? NSNumber)?.doubleValue ?? 0.0))
                                            rect.size.width -= rect.origin.x
                                            rect.size.height -= rect.origin.y
                                            if zoomLevel >= zoomMin && zoomLevel <= zoomMax && OSMRectIntersectsRect(viewRect, rect) {
                                                if vintageStart != "" && vintageEnd != "" {
                                                    attribution = "\(attribution)\n   \(vintageStart) - \(vintageEnd)"
                                                }
                                                attrList.append(attribution)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                attrList = (attrList as NSArray).sortedArray(comparator: { obj1, obj2 in
                    if ((obj1 as? NSString) ?? "").range(of: "Microsoft").location != NSNotFound {
                        return ComparisonResult(rawValue: -1)!
                    }
                    if ((obj2 as? NSString) ?? "").range(of: "Microsoft").location != NSNotFound {
                        return ComparisonResult(rawValue: 1)!
                    }
                    return (obj1 as? NSString ?? NSString()).compare(obj2 as? String ?? "")
                }) as? [String] ?? []

                
                let text = attrList.joined(separator: "\n\n• ")
                self.textView.text = String.localizedStringWithFormat(NSLocalizedString("Background imagery %@", comment: "identifies current aerial imagery"), text)
            } else if let error = error {
                self.textView.text = String.localizedStringWithFormat(NSLocalizedString("Error fetching metadata: %@", comment: ""), error.localizedDescription)
            } else {
                self.textView.text = NSLocalizedString("An unknown error occurred fetching metadata", comment: "")
            }
        })
    }
    
    @IBAction func cancel(_ sender: Any) {
        dismiss(animated: true)
    }
}
