//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  VoiceAnnouncement.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/26/15.
//  Copyright © 2015 Bryce Cogswell. All rights reserved.
//

import AVFoundation
import Foundation

class VoiceAnnouncement: NSObject, AVSpeechSynthesizerDelegate {
    var synthesizer: AVSpeechSynthesizer?
    var previousObjects: [AnyHashable : Any]?
    var previousCoord: CLLocationCoordinate2D?
    var currentHighway: OsmWay?
    var previousClosestHighway: OsmWay?
    var utteranceMap: NSMapTable<AnyObject, AnyObject>?
    var isNewUpdate = false

    var mapView: MapView?
    var radius = 0.0
    var buildings = false
    var streets = false
    var addresses = false
    var shopsAndAmenities = false

    private var _enabled = false
    var enabled: Bool {
        get {
            _enabled
        }
        set(enabled) {
            if enabled != _enabled {
                _enabled = enabled
                if !enabled {
                    removeAll()
                }
            }
        }
    }

    override init() {
        super.init()
        utteranceMap = NSMapTable(keyOptions: .opaquePersonality, valueOptions: .opaquePersonality)

        buildings = false
        addresses = false
        streets = true
        shopsAndAmenities = true

        enabled = true
    }

    func say(_ text: String, for object: OsmBaseObject?) {
        if synthesizer == nil {
            synthesizer = AVSpeechSynthesizer()
            synthesizer?.delegate = self
        }

        if object != nil && isNewUpdate {
            isNewUpdate = false
            say("update", for: nil)
        }

        let utterance = AVSpeechUtterance(string: text)
        synthesizer?.speak(utterance)

        utteranceMap?.setObject(object, forKey: utterance)
    }

    func removeAll() {
        synthesizer?.stopSpeaking(at: .word)
        utteranceMap?.removeAllObjects()
    }

    func announce(forLocation coord: CLLocationCoordinate2D) {
        if !enabled {
            return
        }

        isNewUpdate = true

        var a: [[OsmBaseObject]]

        let metersPerDegree = CGPoint(x: MetersPerDegreeLongitude(coord.latitude), y: MetersPerDegreeLatitude(coord.latitude))
        if previousCoord?.latitude == nil && previousCoord?.longitude == nil {
            previousCoord = coord
        }
        
//        OSMRect.init(origin: OSMPoint(x: min(previousCoord?.longitude, coord.longitude), y: min(previousCoord?.latitude, coord.latitude)), size: OSMSize(width: abs(), height: ))
        let box = OSMRect(min(previousCoord?.longitude, coord.longitude), min(previousCoord?.latitude, coord.latitude), abs(Float((previousCoord?.longitude ?? 0) - coord.longitude)), abs(Float((previousCoord?.latitude ?? 0) - coord.latitude)))
        box.origin.x -= radius / Double(metersPerDegree.x)
        box.origin.y -= radius / Double(metersPerDegree.y)
        box.size.width += 2 * radius / Double(metersPerDegree.x)
        box.size.height += 2 * radius / Double(metersPerDegree.y)

        mapView?.editorLayer.mapData.enumerateObjects(inRegion: box, block: { [self] obj in
            if obj?.deleted {
                return
            }
            if !obj?.hasInterestingTags {
                return
            }
            // make sure it is within distance
            var dist: Double? = nil
            if let previousCoord = previousCoord {
                dist = obj?.distance(toLineSegment: OSMPointFromCoordinate(previousCoord), point: OSMPointFromCoordinate(coord)) ?? 0.0
            }
            if (dist ?? 0.0) < radius {
                if currentHighway != nil && obj?.isWay && obj?.tags["highway"] != nil && !currentHighway?.sharesNodes(withWay: obj?.isWay) {
                    return // only announce ways connected to current way
                }
                a.append([NSNumber(value: dist ?? 0.0), obj])
            }
        })

        // sort by distance
        (a as NSArray).sortedArray(comparator: { obj1, obj2 in
            let d1 = (obj1?[0] as? NSNumber)?.doubleValue ?? 0.0
            let d2 = (obj2?[0] as? NSNumber)?.doubleValue ?? 0.0
            return d1 < d2 ? .orderedAscending : d1 > d2 ? .orderedDescending : .orderedSame
        })

        let now = Date()
        var currentObjects: [AnyHashable : Any] = [:]
        var closestHighwayWay: OsmWay? = nil
        var closestHighwayDist = 1000000.0
        var newCurrentHighway: OsmWay? = nil
        for item in a {
            guard let item = item as? [AnyHashable] else {
                continue
            }
            let object = item[1] as? OsmBaseObject

            // track highway we're closest to
            if object?.isWay && object?.tags["highway"] != nil {
                let distance = (item[0] as? NSNumber).doubleValue
                if distance < closestHighwayDist {
                    closestHighwayDist = distance
                    closestHighwayWay = object?.isWay
                }
            }
        }
        if closestHighwayWay != nil && closestHighwayWay == previousClosestHighway {
            if closestHighwayWay != currentHighway {
                currentHighway = closestHighwayWay
                newCurrentHighway = currentHighway
            }
        }
        previousClosestHighway = closestHighwayWay

        for item in a {
            guard let item = item as? [AnyHashable] else {
                continue
            }
            let object = item[1] as? OsmBaseObject

            // if we've recently announced object then don't announce again
            let ident = NSNumber(value: object?.extendedIdentifier ?? 0)
            currentObjects[ident] = now
            if previousObjects?[ident] != nil && object != newCurrentHighway {
                continue
            }

            if buildings && object?.tags["building"] != nil {
                var building = object?.tags["building"] as? String
                if building == "yes" {
                    building = ""
                }
                var text = "building \(building ?? "")"
                say(text, for: object)
            }

            if addresses && object?.tags["addr:housenumber"] != nil {
                let number = object?.tags["addr:housenumber"] as? String
                let street = object?.tags["addr:street"] as? String
                var text = "\(street ?? "") number \(number ?? "")"
                say(text, for: object)
            }

            if streets && object?.isWay && object?.tags["highway"] != nil {
                let type = object?.tags["highway"] as? String
                var name = object?.tags["name"] as? String
                if name == nil {
                    name = object?.tags["ref"] as? String
                }
                if (type == "service") && name == nil && object != newCurrentHighway {
                    // skip
                } else {
                    var text = name ?? type
                    if object == newCurrentHighway {
                        text = "Now following \(text ?? "")"
                    }
                    say(text, for: object)
                }
            }

            if shopsAndAmenities {
                if object?.tags["shop"] != nil || object?.tags["amenity"] != nil {
                    var text = object?.friendlyDescription
                    say(text, for: object)
                }
            }
        }

        previousObjects = currentObjects
        previousCoord = coord
    }

    // MARK: delegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let object = utteranceMap?.object(forKey: utterance) as? OsmBaseObject
        mapView?.editorLayer.selectedNode = object?.isNode()
        mapView?.editorLayer.selectedWay = object?.isWay()
        mapView?.editorLayer.selectedRelation = object?.isRelation()
        utteranceMap?.removeObject(forKey: utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        mapView?.editorLayer.selectedNode = nil
        mapView?.editorLayer.selectedWay = nil
        mapView?.editorLayer.selectedRelation = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        speechSynthesizer(synthesizer, didFinish: utterance)
    }
}

@inline(__always) private func OSMPointFromCoordinate(_ coord: CLLocationCoordinate2D) -> OSMPoint {
    let point = OSMPoint(x: coord.longitude, y: coord.latitude)
    return point
}
