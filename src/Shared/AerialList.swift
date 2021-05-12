//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  CustomAerial.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/21/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//


import CommonCrypto
import Foundation

let BING_MAPS_KEY: String = "ApunJH62__wQs1qE32KVrf6Fmncn7OZj6gWg_wtr27DQLDCkwkxGl4RsItKW4Fkk"

private var CUSTOMAERIALLIST_KEY = "AerialList"
private var CUSTOMAERIALSELECTION_KEY = "AerialListSelection"
private var RECENTLY_USED_KEY = "AerialListRecentlyUsed"

let BING_IDENTIFIER = "BingIdentifier"
let MAPNIK_IDENTIFIER = "MapnikIdentifier"
let OSM_GPS_TRACE_IDENTIFIER = "OsmGpsTraceIdentifier"
let MAPBOX_LOCATOR_IDENTIFIER = "MapboxLocatorIdentifier"
let NO_NAME_IDENTIFIER = "No Name Identifier"
let MAXAR_PREMIUM_IDENTIFIER = "Maxar-Premium"
let MAXAR_STANDARD_IDENTIFIER = "Maxar-Standard"


class AerialService: NSObject {
    
    private(set) var name: String?
    private(set) var identifier: String?
    private(set) var url: String?
    private(set) var maxZoom: Int32 = 0
    
    
    private(set) var polygon: CGPath?
    private(set) var roundZoomUp = false
    private(set) var startDate: String?
    private(set) var endDate: String?
    private(set) var wmsProjection: String?
    private(set) var attributionString: String?
    private(set) var attributionIcon: UIImage?
    private(set) var attributionUrl: String?
    
    private static var supportedProjectionsList: [String]?
    static var supportedProjections: [String]? {
        if supportedProjectionsList == nil {
            supportedProjectionsList = [
                "EPSG:3857",
                "EPSG:4326",
                "EPSG:900913",
                "EPSG:3587",
                "EPSG:54004",
                "EPSG:41001",
                "EPSG:102113",
                "EPSG:102100",
                "EPSG:3785"
            ]
        }
        return supportedProjectionsList
    }
    
    init(
        name: String?,
        identifier: String,
        url: String?,
        maxZoom: Int?,
        roundUp: Bool,
        startDate: String?,
        endDate: String?,
        wmsProjection projection: String?,
        polygon: CGPath?,
        attribString: String?,
        attribIcon: UIImage?,
        attribUrl: String?
    ) {
        super.init()
        // normalize URLs
        var url = url
        url = url?.replacingOccurrences(of: "{ty}", with: "{-y}")
        url = url?.replacingOccurrences(of: "{zoom}", with: "{z}")
        
        self.name = name ?? ""
        self.identifier = identifier
        self.url = url ?? ""
        self.maxZoom = Int32(maxZoom ?? 21)
        roundZoomUp = roundUp
        self.startDate = startDate
        self.endDate = endDate
        wmsProjection = projection
        self.polygon = polygon?.copy()
        attributionString = (attribString?.count ?? 0) != 0 ? attribString : name
        attributionIcon = attribIcon
        attributionUrl = attribUrl
    }
    
    class func aerial(
        withName name: String?,
        identifier: String,
        url: String?,
        maxZoom: Int?,
        roundUp: Bool,
        startDate: String?,
        endDate: String?,
        wmsProjection projection: String?,
        polygon: CGPath?,
        attribString: String?,
        attribIcon: UIImage?,
        attribUrl: String?
    ) -> AerialService {
        return AerialService(name: name, identifier: identifier, url: url, maxZoom: maxZoom, roundUp: roundUp, startDate: startDate, endDate: endDate, wmsProjection: projection, polygon: polygon, attribString: attribString, attribIcon: attribIcon, attribUrl: attribUrl)
    }
    
    func isBingAerial() -> Bool {
        return identifier == BING_IDENTIFIER
    }
    
    func isMapnik() -> Bool {
        return identifier == MAPNIK_IDENTIFIER
    }
    
    func isOsmGpxOverlay() -> Bool {
        return identifier == OSM_GPS_TRACE_IDENTIFIER
    }
    
    func isMaxar() -> Bool {
        return (identifier == MAXAR_PREMIUM_IDENTIFIER) || (identifier == MAXAR_STANDARD_IDENTIFIER)
    }
    
    static var dateFormatterList: [DateFormatter]?
    class func date(from string: String?) -> Date? {
        
        let formatterYYYYMMDD = DateFormatter()
        formatterYYYYMMDD.dateFormat = "yyyy-MM-dd"
        formatterYYYYMMDD.timeZone = NSTimeZone(forSecondsFromGMT: 0) as TimeZone
        
        let formatterYYYYMM = DateFormatter()
        formatterYYYYMM.dateFormat = "yyyy-MM"
        formatterYYYYMM.timeZone = NSTimeZone(forSecondsFromGMT: 0) as TimeZone
        
        let formatterYYYY = DateFormatter()
        formatterYYYY.dateFormat = "yyyy"
        formatterYYYY.timeZone = NSTimeZone(forSecondsFromGMT: 0) as TimeZone
        
        dateFormatterList = [
            formatterYYYYMMDD,
            formatterYYYYMM,
            formatterYYYY
        ]
        
        if string == nil {
            return nil
        }
        
        for formatter in dateFormatterList ?? [] {
            let date = formatter.date(from: string ?? "")
            if let date = date {
                return date
            }
        }
        
        return nil
    }
    
    static var bing: AerialService? = nil
    class func defaultBingAerial() -> AerialService? {
        // `dispatch_once()` call was converted to a static variable initializer
        bing = AerialService.aerial(
            withName: "Bing Aerial",
            identifier: BING_IDENTIFIER,
            url: "https://ecn.{switch:t0,t1,t2,t3}.tiles.virtualearth.net/tiles/a{u}.jpeg?g=587&key=" + BING_MAPS_KEY,
            maxZoom: 21,
            roundUp: true,
            startDate: nil,
            endDate: nil,
            wmsProjection: nil,
            polygon: nil,
            attribString: "",
            attribIcon: UIImage(named: "bing-logo-white"),
            attribUrl: nil
        )
        return bing
    }
    
    static var service: AerialService? = nil
    class func maxarPremiumAerial() -> AerialService? {
        // `dispatch_once()` call was converted to a static variable initializer
        let url = "eZ5AGZGcRQyKahl/+UTyIm+vENuJECB4Hvu4ytCzjBoCBDeRMbsOkaQ7zD5rUAYfRDaQwnQRiqE4lj0KYTenPe1d1spljlcYgvYRsqjEtYp6AhCoBPO4Rz6d0Z9enlPqPj7KCvxyOcB8A/+3HkYjpMGMEcvA6oeSX9I0RH/PS9lQzmJACnINv3lFIonIZ1gY/yFVqi2FWnWCbTyFdy2+FlyrWqTfyeG8tstR+5wQsC+xmsaCmW8e41jROh1O0z+U"
        service = AerialService.aerial(
            withName: "Maxar Premium Aerial",
            identifier: MAXAR_PREMIUM_IDENTIFIER,
            url: aes.decryptString(url),
            maxZoom: 21,
            roundUp: true,
            startDate: nil,
            endDate: nil,
            wmsProjection: nil,
            polygon: nil,
            attribString: "Maxar Premium",
            attribIcon: nil,
            attribUrl: "https://wiki.openstreetmap.org/wiki/DigitalGlobe"
        )
        service?.loadIcon(fromWeb: "https://osmlab.github.io/editor-layer-index/sources/world/Maxar.png")
        return service
    }
    
    class func maxarStandardAerial() -> AerialService? {
        let url = "eZ5AGZGcRQyKahl/+UTyIm+vENuJECB4Hvu4ytCzjBoCBDeRMbsOkaQ7zD5rUAYfRDaQwnQRiqE4lj0KYTenPe1d1spljlcYgvYRsqjEtYp6AhCoBPO4Rz6d0Z9enlPqPj7KCvxyOcB8A/+3HkYjpMGMEcvA6oeSX9I0RH/PS9mdAZEC5TmU3odUJQ0hNzczrKtUDmNujrTNfFVHhZZWPLEVZUC9cE94VF/AJkoIigdmXooJ+5UcPtH/uzc6NbOb"
        service = AerialService.aerial(
            withName: "Maxar Standard Aerial",
            identifier: MAXAR_STANDARD_IDENTIFIER,
            url: aes.decryptString(url),
            maxZoom: 21,
            roundUp: true,
            startDate: nil,
            endDate: nil,
            wmsProjection: nil,
            polygon: nil,
            attribString: "Maxar Standard",
            attribIcon: nil,
            attribUrl: "https://wiki.openstreetmap.org/wiki/DigitalGlobe"
        )
        service?.loadIcon(fromWeb: "https://osmlab.github.io/editor-layer-index/sources/world/Maxar.png")
        return service
    }
    
    class func mapnik() -> AerialService? {
        service = AerialService.aerial(
            withName: "MapnikTiles",
            identifier: MAPNIK_IDENTIFIER,
            url: "https://{switch:a,b,c}.tile.openstreetmap.org/{z}/{x}/{y}.png",
            maxZoom: 19,
            roundUp: false,
            startDate: nil,
            endDate: nil,
            wmsProjection: nil,
            polygon: nil,
            attribString: nil,
            attribIcon: nil,
            attribUrl: nil
        )
        return service
    }
    
    class func gpsTrace() -> AerialService? {
        service = AerialService.aerial(
            withName: "OSM GPS Traces",
            identifier: OSM_GPS_TRACE_IDENTIFIER,
            url: "https://gps-{switch:a,b,c}.tile.openstreetmap.org/lines/{z}/{x}/{y}.png",
            maxZoom: 20,
            roundUp: false,
            startDate: nil,
            endDate: nil,
            wmsProjection: nil,
            polygon: nil,
            attribString: nil,
            attribIcon: nil,
            attribUrl: nil
        )
        return service
    }
    
    class func mapboxLocator() -> AerialService? {
        service = AerialService.aerial(
            withName: "Mapbox Locator",
            identifier: MAPBOX_LOCATOR_IDENTIFIER,
            url: "https://api.mapbox.com/styles/v1/openstreetmap/ckasmteyi1tda1ipfis6wqhuq/tiles/256/{zoom}/{x}/{y}{@2x}?access_token=pk.eyJ1Ijoib3BlbnN0cmVldG1hcCIsImEiOiJjaml5MjVyb3MwMWV0M3hxYmUzdGdwbzE4In0.q548FjhsSJzvXsGlPsFxAQ",
            maxZoom: 20,
            roundUp: false,
            startDate: nil,
            endDate: nil,
            wmsProjection: nil,
            polygon: nil,
            attribString: nil,
            attribIcon: nil,
            attribUrl: nil
        )
        return service
    }
    
    class func noName() -> AerialService? {
        service = AerialService.aerial(
            withName: "QA Poole No Name",
            identifier: NO_NAME_IDENTIFIER,
            url: "https://tile{switch:2,3}.poole.ch/noname/{zoom}/{x}/{y}.png",
            maxZoom: 25,
            roundUp: false,
            startDate: nil,
            endDate: nil,
            wmsProjection: nil,
            polygon: nil,
            attribString: nil,
            attribIcon: nil,
            attribUrl: nil
        )
        return service
    }
    
    func dictionary() -> [String : Any] {
        return [
            "name": name ?? "",
            "url": url ?? "",
            "zoom": NSNumber(value: maxZoom),
            "roundUp": NSNumber(value: roundZoomUp),
            "projection": wmsProjection ?? ""
        ]
    }
    
    convenience init(dictionary dict: [String : Any]) {
        var url = dict["url"] as? String
        
        // convert a saved aerial that uses a subdomain list to the new format
        if let subdomains = dict["subdomains"] as? [String] {
            if (subdomains.count) > 0 {
                var s = subdomains.joined(separator: ",")
                s = String(format: "{switch:\(s)}")
                url = url?.replacingOccurrences(of: "{t}", with: s)
            }
        }
        
        var projection = dict["projection"] as? String
        if (projection?.count ?? 0) == 0 {
            projection = nil
        }

        self.init(name: dict["name"] as? String, identifier: (url ?? ""), url: url, maxZoom: (dict["zoom"] as? NSNumber)?.intValue ?? 0, roundUp: (dict["roundUp"] as? NSNumber)?.boolValue ?? false, startDate: nil, endDate: nil, wmsProjection: projection, polygon: nil, attribString: nil, attribIcon: nil, attribUrl: nil)
    }
    
    var metadataUrl: String? {
        if isBingAerial() {
            return "https://dev.virtualearth.net/REST/V1/Imagery/Metadata/Aerial/%f,%f?zl=%d&include=ImageryProviders&key=" + BING_MAPS_KEY
        }
        return nil
    }
    
    private var _placeholderImage: Data?
    var placeholderImage: Data? {
        if let _placeholderImage = _placeholderImage {
            return _placeholderImage.count != 0 ? _placeholderImage : nil
        }
        var name: String? = nil
        if isBingAerial() {
            name = "BingPlaceholderImage"
        } else if identifier == "EsriWorldImagery" {
            name = "EsriPlaceholderImage"
        }
        if let name = name {
            var path = Bundle.main.path(forResource: name, ofType: "png")
            if path == nil {
                path = Bundle.main.path(forResource: name, ofType: "jpg")
            }
            let data = NSData(contentsOfFile: path ?? "") as Data?
            if (data?.count ?? 0) != 0 {
                DispatchQueue.main.sync(execute: {
                    _placeholderImage = data
                })
            }
            return _placeholderImage
        }
        _placeholderImage = Data()
        return nil
    }
    
    func scaleAttributionIcon(toHeight height: CGFloat) {
        if attributionIcon != nil && abs(Float((attributionIcon?.size.height ?? 0.0) - height)) > 0.1 {
            let scale = (attributionIcon?.size.height ?? 0.0) / height
#if os(iOS)
            var size = attributionIcon?.size
            size?.height /= scale
            size?.width /= scale
            UIGraphicsBeginImageContext(size ?? CGSize.zero)
            attributionIcon?.draw(in: CGRect(x: 0.0, y: 0.0, width: size?.width ?? 0.0, height: size?.height ?? 0.0))
            let imageCopy = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            attributionIcon = imageCopy
#else
            var size = NSSize((attributionIcon?.size.width ?? 0.0) * scale, (attributionIcon?.size.height ?? 0.0) * scale)
            let result = NSImage(size: size)
            result.lockFocus()
            var transform = AffineTransform()
            transform.scale(scale)
            (transform as NSAffineTransform).concat()
            attributionIcon?.draw(at: NSPoint.zero, from: NSRect.zero, operation: .copy, fraction: 1.0)
            result.unlockFocus()
            attributionIcon = result
#endif
        }
    }
    
    func loadIcon(fromWeb url: String) {
        var request: URLRequest? = nil
        if let url1 = URL(string: url) {
            request = URLRequest(
                url: url1,
                cachePolicy: .returnCacheDataElseLoad,
                timeoutInterval: 60)
        }
        var task: URLSessionDataTask? = nil
        if let request = request {
            task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
                if let data = data {
                    let image = UIImage(data: data)
                    DispatchQueue.main.async(execute: { [self] in
                        attributionIcon = image
                    })
                }
            })
        }
        task?.resume()
    }
    
    override var description: String {
        return name ?? ""
    }
}

class AerialList: NSObject {
    
    var userDefinedList: [AerialService] = [] // user-defined tile servers
    var downloadedList: [AerialService] = [] // downloaded on each launch
    var _recentlyUsed: [AerialService] = []
    private(set) var lastDownloadDate: Date?
    
    override init() {
        super.init()
        fetchOsmLabAerials({ [self] in
            // if a non-builtin aerial service is current then we need to select it once the list is loaded
            load()
        })
    }
    
    func builtinServices() -> [AnyHashable]? {
        return [
            AerialService.defaultBingAerial()
        ].compactMap { $0 }
    }
    
    func userDefinedServices() -> [AerialService] {
        return userDefinedList
    }
    
    func pathToExternalAerialsCache() -> String? {
        // get tile cache folder
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).map(\.path)
        if paths.count != 0 {
            let bundleName = Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String
            let path = URL(fileURLWithPath: URL(fileURLWithPath: paths[0]).appendingPathComponent(bundleName ?? "").path).appendingPathComponent("OSM Aerial Providers.json").path
            do {
                try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path, withIntermediateDirectories: true, attributes: nil)
            } catch {
            }
            return path
        }
        return nil
    }
    
     func addPoints(_ points: [AnyHashable]?, to path: CGMutablePath?) {
         var first = true
         for pt in points ?? [] {
             guard let pt = pt as? [AnyHashable] else {
                 continue
             }
            let lon = (pt[0] as? NSNumber)?.doubleValue ?? 0.0
            let lat = (pt[1] as? NSNumber)?.doubleValue ?? 0.0
             if first {
                 path?.move(to: CGPoint(x: CGFloat(lon), y: CGFloat(lat)), transform: .identity)
                 first = false
             } else {
                 path?.addLine(to: CGPoint(x: CGFloat(lon), y: CGFloat(lat)), transform: .identity)
             }
         }
         path?.closeSubpath()
     }
    
     func processOsmLabAerialsList(_ featureArray: [AnyHashable]?, isGeoJSON: Bool) -> [AnyHashable]? {
         let categories = [
             "photo": NSNumber(value: true),
             "elevation": NSNumber(value: true)
         ]
         
         let supportedTypes = [
             "tms": NSNumber(value: true),
             "wms": NSNumber(value: true),
             "scanex": NSNumber(value: false),
             "wms_endpoint": NSNumber(value: false),
             "wmts": NSNumber(value: false),
             "bing": NSNumber(value: false)
         ]

        
         let supportedProjections = Set<AnyHashable>(AerialService.supportedProjections ?? [])
         
         var externalAerials: [AnyHashable] = []
         for entry in featureArray ?? [] {
             guard let entry = entry as? [AnyHashable : Any] else {
                 continue
             }
             
             // TODO: import SwiftTryCatch from https://github.com/ypopovych/SwiftTryCatch
             SwiftTryCatch.try({
                 
                 if isGeoJSON && (entry["type"] != "Feature") {
                     print("Aerial: skipping type \(entry["type"])")
                     continue
                 }
                 var properties: [AnyHashable : Any]? = nil
                 if let anEntry = entry["properties"] as? [AnyHashable : Any] {
                     properties = isGeoJSON ? anEntry : entry
                 }
                 let name = properties?["name"] as? String
                 if name?.hasPrefix("Maxar ") ?? false {
                     // we special case their imagery because they require a special key
                     continue
                 }
                 let identifier = properties?["id"] as? String
                 let category = properties?["category"] as? String
                 if categories[category ?? ""] == nil {
                     if identifier == "OpenTopoMap" {
                         // okay
                     } else {
                         // NSLog(@"category %@ - %@",category,identifier);
                         continue
                     }
                 }
                 let startDateString = properties?["start_date"] as? String
                 let endDateString = properties?["end_date"] as? String
                 let endDate = AerialService.date(from: endDateString)
                 if endDate != nil && (endDate?.timeIntervalSinceNow ?? 0.0) < -20 * 365.0 * 24 * 60 * 60 {
                     continue
                 }
                 let type = properties?["type"] as? String
                 let projections = properties?["available_projections"] as? [AnyHashable]
                 var url = properties?["url"] as? String
                 let maxZoom = isGeoJSON ? (properties?["max_zoom"] as? NSNumber)?.intValue ?? 0 : (properties?["extent"]["max_zoom"] as? NSNumber)?.intValue ?? 0
                 var attribIconString = properties?["icon"] as? String
                 let attribString = properties?["attribution"]["text"] as? String
                 let attribUrl = properties?["attribution"]["url"] as? String
                 let overlay = (properties?["overlay"] as? NSNumber)?.intValue ?? 0
                 let supported = supportedTypes[type ?? ""]
                 if supported == nil {
                     print("Aerial: unsupported type \(type ?? ""): \(name ?? "")\n")
                     continue
                 } else if supported.boolValue == false {
                     continue
                 }
                 if overlay != 0 {
                     // we don@"t support overlays yet
                     continue
                 }
                 if !(url?.hasPrefix("http:") ?? false || url?.hasPrefix("https:") ?? false) {
                     // invalid url
                     print("Aerial: bad url \(url ?? ""): \(name ?? "")\n")
                     continue
                 }
                 
                 // we only support some types of WMS projections
                 var projection: String? = nil
                 if type == "wms" {
                     for proj in projections ?? [] {
                         guard let proj = proj as? String else {
                             continue
                         }
                         if supportedProjections.contains(proj) {
                             projection = proj
                             break
                         }
                     }
                     if projection == nil {
                         continue
                     }
                 }
                 
                 var polygonPoints: [AnyHashable]? = nil
                 var isMultiPolygon = false // a GeoJSON multipolygon, which has an extra layer of nesting
                 if isGeoJSON {
                     let geometry = entry["geometry"] as? [AnyHashable : Any]
                     if geometry is [AnyHashable : Any] {
                         polygonPoints = geometry?["coordinates"] as? [AnyHashable]
                         isMultiPolygon = geometry?["type"] == "MultiPolygon"
                     }
                 } else {
                     polygonPoints = properties?["extent"]["polygon"] as? [AnyHashable]
                 }
                 
                 var polygon: CGPath? = nil
                 if let polygonPoints = polygonPoints {
                     let path = CGMutablePath()
                     if isMultiPolygon {
                         for outer in polygonPoints {
                             guard let outer = outer as? [AnyHashable] else {
                                 continue
                             }
                             for loop in outer {
                                 guard let loop = loop as? [AnyHashable] else {
                                     continue
                                 }
                                 addPoints(loop, to: path)
                             }
                         }
                     } else {
                         for loop in polygonPoints {
                             guard let loop = loop as? [AnyHashable] else {
                                 continue
                             }
                             addPoints(loop, to: path)
                         }
                     }
                     polygon = path.copy()
                 }
                 
                 var attribIcon: UIImage? = nil
                 var httpIcon = false
                 if (attribIconString?.count ?? 0) > 0 {
                     let prefixList = ["data:image/png;base64,", "data:image/png:base64,", "png:base64,"]
                     for prefix in prefixList {
                         if attribIconString?.hasPrefix(prefix) ?? false {
                             attribIconString = (attribIconString as NSString?)?.substring(from: prefix.count)
                             let decodedData = Data(base64Encoded: attribIconString ?? "", options: [])
                             if let decodedData = decodedData {
                                 attribIcon = UIImage(data: decodedData)
                             }
                             if attribIcon == nil {
                                 print("bad icon decode: \(attribIconString ?? "")\n")
                             }
                             break
                         }
                     }
                     if attribIcon == nil {
                         if attribIconString?.hasPrefix("http") ?? false {
                             httpIcon = true
                         } else {
                             print("Aerial: unsupported icon format in \(name ?? ""): \(attribIconString ?? "")\n")
                         }
                     }
                 }
                 
                 // support for {apikey}
                 if url?.contains("{apikey}") ?? false {
                     var apikey: String? = nil
                     if url?.contains(".thunderforest.com/") ?? false {
                         apikey = "be3dc024e3924c22beb5f841d098a8a3" // Please don't use in other apps. Sign up for a free account at Thunderforest.com insead.
                     } else {
                         continue
                     }
                     url = url?.replacingOccurrences(of: "{apikey}", with: apikey ?? "")
                 }
                 
                 let service = AerialService.aerial(withName: name, identifier: identifier, url: url, maxZoom: maxZoom, roundUp: true, startDate: startDateString, endDate: endDateString, wmsProjection: projection, polygon: polygon, attribString: attribString, attribIcon: attribIcon, attribUrl: attribUrl)
                 externalAerials.append(service)
                 
                 if httpIcon {
                     service.loadIcon(fromWeb: attribIconString)
                 }
             }, catch: { exception in
                 print("*** Aerial skipped\n")
             }, finallyBlock: {
             })
         }
         externalAerials = (externalAerials as NSArray).sortedArray(comparator: { obj1, obj2 in
             return obj1?.name?.caseInsensitiveCompare(obj2?.name ?? "") ?? ComparisonResult.orderedSame
         }) as? [AnyHashable] ?? externalAerials
         return externalAerials // return immutable copy
     }
    
    func processOsmLabAerialsData(_ data: Data?) -> [AnyHashable]? {
        if data == nil || (data?.count ?? 0) == 0 {
            return nil
        }
        
        // TODO: import SwiftTryCatch from https://github.com/ypopovych/SwiftTryCatch
        SwiftTryCatch.try({
            var json: Any? = nil
            do {
                if let data = data {
                    json = try JSONSerialization.jsonObject(with: data, options: [])
                }
            } catch {
                return nil
            }
            if json is [AnyHashable] {
                // unversioned (old ELI) variety
                return processOsmLabAerialsList(json as? [AnyHashable], isGeoJSON: false)
            } else {
                let meta = json?["meta"] as? [AnyHashable : Any]
                if meta == nil {
                    // josm variety
                } else {
                    // new ELI variety
                    let formatVersion = meta?["format_version"] as? String
                    if formatVersion != "1.0" {
                        return nil
                    }
                    let metaType = json?["type"] as? String
                    if metaType != "FeatureCollection" {
                        return nil
                    }
                }
                let features = json?["features"] as? [AnyHashable]
                return processOsmLabAerialsList(features, isGeoJSON: true)
            }
        }, catch: { exception in
            return nil
        }, finallyBlock: {
        })
    }
    
    func fetchOsmLabAerials(_ completion: @escaping () -> Void) {
        // get cached data
        let cachedData = NSData(contentsOfFile: pathToExternalAerialsCache() ?? "") as Data?
        let now = Date()
        lastDownloadDate = UserDefaults.standard.object(forKey: "lastImageryDownloadDate") as? Date
        if let lastDownloadDate = lastDownloadDate {
            if cachedData == nil || (lastDownloadDate != nil && now.timeIntervalSince(lastDownloadDate) >= 60 * 60 * 24 * 7) {
                // download newer version periodically
                let urlString = "https://josm.openstreetmap.de/maps?format=geojson"
                //NSString * urlString = @"https://osmlab.github.io/editor-layer-index/imagery.geojson";
                let downloadUrl = URL(string: urlString)
                var downloadTask: URLSessionDataTask? = nil
                if let downloadUrl = downloadUrl {
                    downloadTask = URLSession.shared.dataTask(with: downloadUrl, completionHandler: { [self] data, response, error in
                        UserDefaults.standard.set(now, forKey: "lastImageryDownloadDate")
                        let externalAerials = processOsmLabAerialsData(data)
                        if (externalAerials?.count ?? 0) > 100 {
                            // cache download for next time
                            do {
                                try data?.write(to: pathToExternalAerialsCache(), options: .atomic)
                            } catch {
                            }
                            // notify caller of update
                            DispatchQueue.main.async(execute: { [self] in
                                downloadedList = externalAerials
                                completion()
                            })
                        }
                    })
                }
                downloadTask?.resume()
                lastDownloadDate = now
            }
        }
        
        // read cached version
        let externalAerials = processOsmLabAerialsData(cachedData)
        downloadedList = externalAerials
        completion()
    }
    
    func load() {
        let defaults = UserDefaults.standard
        userDefinedList = defaults.object(forKey: CUSTOMAERIALLIST_KEY) as? NSMutableArray ?? []
        if userDefinedList.count == 0 {
            userDefinedList = []
        } else {
            for i in 0 ..< userDefinedList.count {
                userDefinedList[i] = AerialService(dictionary: userDefinedList[i] as? [String : Any] ?? [:])
            }
        }
        
        // fetch and decode recently used list
        var dict: [String : Any] = [:]
        for service in downloadedList {
            dict[service.identifier ?? ""] = service
        }
        for service in userDefinedList {
            dict[service.identifier ?? ""] = service
        }
        for service in [
            AerialService.maxarPremiumAerial(),
            AerialService.maxarStandardAerial()
        ] {
            dict[service?.identifier ?? ""] = service
        }
        
        let recentIdentiers: [AnyHashable]? = (defaults.object(forKey: RECENTLY_USED_KEY) ?? []) as? [AnyHashable]
        _recentlyUsed = [AnyHashable](repeating: 0, count: recentIdentiers?.count ?? 0) as? [AerialService]
        for identifier in recentIdentiers ?? [] {
            guard let identifier = identifier as? String else {
                continue
            }
            let service = dict[identifier] as? AerialService
            if let service = service {
                _recentlyUsed?.append(service)
            }
        }
        
        var currentIdentifier = defaults.object(forKey: CUSTOMAERIALSELECTION_KEY) as? String
        if currentIdentifier == nil || (currentIdentifier is NSNumber) {
            currentIdentifier = BING_IDENTIFIER
        }
        var a: [AnyHashable]? = nil
        if let builtinServices = builtinServices(), let userDefinedServices = userDefinedServices(), let array = builtinServices + userDefinedServices, let downloadedList = downloadedList {
            a = array + downloadedList
        }
        for service in a ?? [] {
            guard let service = service as? AerialService else {
                continue
            }
            if currentIdentifier == service.identifier {
                currentAerial = service
                break
            }
        }
        if currentAerial == nil {
            currentAerial = builtinServices()?[0] as? AerialService
        }
    }
    
    func save() {
        let defaults = UserDefaults.standard
        var a = userDefinedList
        for i in 0 ..< a.count {
            a[i] = a[i].dictionary()
        }
        defaults.set(a, forKey: CUSTOMAERIALLIST_KEY)
        defaults.set(currentAerial?.identifier, forKey: CUSTOMAERIALSELECTION_KEY)
        
        var recents: [AnyHashable] = []
        for service in _recentlyUsed {
            recents.append(service.identifier ?? "")
        }
        defaults.set(recents, forKey: RECENTLY_USED_KEY)
    }
    
    func services(forRegion rect: OSMRect) -> [AerialService] {
        // find imagery relavent to the viewport
        let center = CGPoint(x: rect.origin.x + rect.size.width / 2, y: rect.origin.y + rect.size.height / 2)
        var result: [AerialService] = []
        for service in downloadedList {
            if service.polygon == nil || (service.polygon?.contains(center, using: .winding, transform: .identity) ?? false) {
                result.append(service)
            }
        }
        if let maxar = AerialService.maxarPremiumAerial() {
            result.append(maxar)
        }
        if let maxar = AerialService.maxarStandardAerial() {
            result.append(maxar)
        }
        
        result = (result as NSArray).sortedArray(comparator: { obj1, obj2 in
            return (obj1 as? AerialService)?.name?.compare((obj2 as? AerialService)?.name ?? "") ?? .orderedSame
        }) as? [AerialService] ?? result
        return result
    }
    
    private var _currentAerial: AerialService?
    var currentAerial: AerialService? {
        get {
            return _currentAerial
        }
        set(currentAerial) {
            _currentAerial = currentAerial
            
            // update recently used
            let MAX_ITEMS = 6
            _recentlyUsed.removeAll { $0 as AnyObject === currentAerial as AnyObject }
            if let currentAerial = currentAerial {
                _recentlyUsed.insert(currentAerial, at: 0)
            }
            while _recentlyUsed.count > MAX_ITEMS {
                _recentlyUsed.removeLast()
            }
        }
    }
    
    func recentlyUsed() -> [AerialService]? {
        return _recentlyUsed
    }
    
    func count() -> Int {
        return userDefinedList.count
    }
    
    func service(at index: Int) -> AerialService? {
        return userDefinedList[index]
    }
    
    func addUserDefinedService(_ service: AerialService, at index: Int) {
        userDefinedList.insert(service, at: index)
    }
    
    func removeUserDefinedService(at index: Int) {
        if index >= userDefinedList.count {
            return
        }
        let s = userDefinedList[index]
        userDefinedList.remove(at: index)
        if s == currentAerial {
            currentAerial = builtinServices()?[0] as? AerialService
        }
        _recentlyUsed.removeAll { $0 as AnyObject === s as AnyObject }
    }
}
