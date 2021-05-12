//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  RenderInfo.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/4/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import Foundation

private let RenderInfoMaxPriority = (33 + 1) * 3

var g_AddressRender: RenderInfo? = nil
var g_DefaultRender: RenderInfo? = nil

@objcMembers
class RenderInfo: NSObject {
    var renderPriority = 0

    var key: String?
    var value: String?
    var lineColor: UIColor?
    var lineWidth: CGFloat = 0.0
    var areaColor: UIColor?

    override var description: String {
        return "\(super.description) \(key ?? "")=\(value ?? "")"
    }

    func isAddressPoint() -> Bool {
        return self == g_AddressRender
    }

    class func color(forHexString text: String?) -> UIColor? {
        guard let text = text else {
            return nil
        }
        assert(text.count == 6)
        
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        let start = text.index(text.startIndex, offsetBy: 0)
        let hexColor = String(text[start...])
        if hexColor.count == 6 {
            let scanner = Scanner(string: hexColor)
            var hexNumber: UInt64 = 0
            if scanner.scanHexInt64(&hexNumber) {
                r = CGFloat((hexNumber & 0xff0000) >> 16) / 255.0
                g = CGFloat((hexNumber & 0x00ff00) >> 8) / 255.0
                b = CGFloat((hexNumber & 0x0000ff) >> 0) / 255.0
            }
        }
        
//        assert(sscanf(text?.utf8CString, "%2x%2x%2x", &r2, &g2, &b2) == 3)
//        let r: CGFloat = CGFloat(r2) / 255.0
//        let g: CGFloat = CGFloat(g2) / 255.0
//        let b: CGFloat = CGFloat(b2) / 255.0
#if os(iOS)
        if #available(iOS 13.0, *) {
            let color = UIColor(dynamicProvider: { traitCollection in
                if traitCollection.userInterfaceStyle == .dark {
                    // lighten colors for dark mode
                    let delta: CGFloat = 0.3
                    let r3 = r * (1 - delta) + delta
                    let g3 = g * (1 - delta) + delta
                    let b3 = b * (1 - delta) + delta
                    return UIColor(red: r3, green: g3, blue: b3, alpha: 1.0)
                }
                return UIColor(red: r, green: g, blue: b, alpha: 1.0)
            })
            return color
        } else {
            return UIColor(red: r, green: g, blue: b, alpha: 1.0)
        }
#else
        return UIColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
#endif
    }
    
    func renderPriority(for object: OsmBaseObject?) -> Int {
        var highwayDict: [String : NSNumber] = [:]
        highwayDict = [
            "motorway": NSNumber(value: 29),
            "trunk": NSNumber(value: 28),
            "motorway_link": NSNumber(value: 27),
            "primary": NSNumber(value: 26),
            "trunk_link": NSNumber(value: 25),
            "secondary": NSNumber(value: 24),
            "tertiary": NSNumber(value: 23),
            // railway
            "primary_link": NSNumber(value: 21),
            "residential": NSNumber(value: 20),
            "raceway": NSNumber(value: 19),
            "secondary_link": NSNumber(value: 10),
            "tertiary_link": NSNumber(value: 17),
            "living_street": NSNumber(value: 16),
            "road": NSNumber(value: 15),
            "unclassified": NSNumber(value: 14),
            "service": NSNumber(value: 13),
            "bus_guideway": NSNumber(value: 12),
            "track": NSNumber(value: 11),
            "pedestrian": NSNumber(value: 10),
            "cycleway": NSNumber(value: 9),
            "path": NSNumber(value: 8),
            "bridleway": NSNumber(value: 7),
            "footway": NSNumber(value: 6),
            "steps": NSNumber(value: 5),
            "construction": NSNumber(value: 4),
            "proposed": NSNumber(value: 3)
        ]
        var priority: Int
        if object?.modifyCount != 0 {
            priority = 33
        } else {
            if renderPriority == 0 {
                if (key == "natural") && (value == "coastline") {
                    renderPriority = 32
                } else if (key == "natural") && (value == "water") {
                    renderPriority = 31
                } else if (key == "waterway") && (value == "riverbank") {
                    renderPriority = 30
                } else if key == "landuse" {
                    renderPriority = 29
                } else if (key == "highway") && (value != nil) {
                    if let integerFromHighwayDict = highwayDict[value!]?.intValue {
                        if integerFromHighwayDict > 0 {
                            renderPriority = integerFromHighwayDict
                        }
                    }
                } else if key == "railway" {
                    renderPriority = 22
                } else if self == g_AddressRender {
                    renderPriority = 1
                } else {
                    renderPriority = 2
                }
            }
            priority = renderPriority
        }

        var bonus: Int
        if ((object?.isWay()) != nil) || ((object?.isRelation()?.isMultipolygon()) != nil) {
            bonus = 2
        } else if ((object?.isRelation()) != nil) {
            bonus = 1
        } else {
            bonus = 0
        }
        priority = 3 * priority + bonus
        assert(priority < RenderInfoMaxPriority)
        return priority
    }
}

@objcMembers
class RenderInfoDatabase: NSObject {
    var allFeatures: [RenderInfo] = []
    var keyDict: [String : [String? : RenderInfo?]] = [:]

    static var _database = RenderInfoDatabase()

    class func shared() -> RenderInfoDatabase? {
        return _database
    }

    class func readConfiguration() -> [RenderInfo] {
        var text = NSData(contentsOfFile: "RenderInfo.json") as Data?
        if text == nil {
            if let path = Bundle.main.path(forResource: "RenderInfo", ofType: "json") {
                text = NSData(contentsOfFile: path) as Data?
            }
        }
        var features: [String : [String : Any]] = [:]
        do {
            if let text = text {
                features = try JSONSerialization.jsonObject(with: text, options: []) as? [String:[String: Any]] ?? [:]
            }
        } catch { }

        var renderList: [RenderInfo] = []
        
        for (feature, dict) in features {
            let keyValue = feature.components(separatedBy: "/")
            let render = RenderInfo()
            render.key = keyValue[0]
            render.value = keyValue.count > 1 ? keyValue[1] : ""
            render.lineColor = RenderInfo.color(forHexString: dict["lineColor"] as? String)
            render.areaColor = RenderInfo.color(forHexString: dict["areaColor"] as? String)
            render.lineWidth = CGFloat((dict["lineWidth"] as? NSNumber)?.doubleValue ?? 0.0)
            renderList.append(render)
        }
        return renderList
    }

    override required init() {
        super.init()
        allFeatures = RenderInfoDatabase.readConfiguration()
        keyDict = [:]
        for tag in allFeatures {
            var valDict = keyDict[tag.key ?? ""]
            if valDict == nil {
                valDict = [tag.value : tag]
                keyDict[tag.key ?? ""] = valDict
            } else {
                valDict?[tag.value] = tag
            }
        }
    }

    func renderInfo(for object: OsmBaseObject) -> RenderInfo? {
        var tags = object.tags
        // if the object is part of a rendered relation than inherit that relation's tags
        if (object.parentRelations?.count != 0) && (object.isWay() != nil) && !object.hasInterestingTags() {
            if let parentRelations = object.parentRelations {
                for parent in parentRelations {
                    guard let parent = parent as? OsmRelation else {
                        continue
                    }
                    if parent.isBoundary() {
                        tags = parent.tags
                        break
                    }
                }
            }
        }

        // try exact match
        var bestRender: RenderInfo? = nil
        var bestIsDefault = false
        var bestCount = 0
        for (key, value) in tags ?? [:] {
            let valDict = keyDict[key]
            if valDict == nil {
                return nil
            }
            var render = valDict?[value] as? RenderInfo
            var isDefault = false
            if render == nil {
                render = valDict?[""] as? RenderInfo
                if render != nil {
                    isDefault = true
                }
            }
            if render == nil {
                return nil
            }
            let count: Int = ((render?.lineColor != nil) ? 1 : 0) + ((render?.areaColor != nil) ? 1 : 0)
            if bestRender == nil || (bestIsDefault && !isDefault) || (count > bestCount) {
                bestRender = render
                bestCount = count
                bestIsDefault = isDefault
                return nil
            }
        }
        if let bestRender = bestRender {
            return bestRender
        }

        // check if it is an address point
        var isAddress: Bool = (object.isNode() != nil) && ((object.tags?.count ?? 0) > 0)
        if isAddress {
            if let tags1 = object.tags {
                for (key, _) in tags1 {
                    if IsInterestingKey(key) && !key.hasPrefix("addr:") {
                        isAddress = false
                        break
                    }
                }
            }
            if isAddress {
                if g_AddressRender == nil {
                    g_AddressRender = RenderInfo()
                    g_AddressRender?.key = "ADDRESS"
                    g_AddressRender?.lineWidth = 0.0
                }
                return g_AddressRender
            }
        }

        if g_DefaultRender == nil {
            g_DefaultRender = RenderInfo()
            g_DefaultRender?.key = "DEFAULT"
#if os(iOS)
            g_DefaultRender?.lineColor = UIColor.black
#else
            g_DefaultRender?.lineColor = NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 1)
#endif
            g_DefaultRender?.lineWidth = 0.0
        }
        return g_DefaultRender
    }
}
