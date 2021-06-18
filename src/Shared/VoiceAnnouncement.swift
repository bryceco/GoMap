//
//  VoiceAnnouncement.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/26/15.
//  Copyright © 2015 Bryce Cogswell. All rights reserved.
//

import AVFoundation
import Foundation
import CoreLocation

class VoiceAnnouncement: NSObject, AVSpeechSynthesizerDelegate {
    var synthesizer: AVSpeechSynthesizer?
    var previousObjects = [OsmExtendedIdentifier : Date]()
	var previousCoord = LatLon.zero
	var currentHighway: OsmWay? = nil
    var previousClosestHighway: OsmWay? = nil
    var utteranceMap = NSMapTable<AVSpeechUtterance, OsmBaseObject>(keyOptions: .opaquePersonality, valueOptions: .opaquePersonality)

    var isNewUpdate = false

    var mapView: MapView!
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

        utteranceMap.setObject(object, forKey: utterance)
    }

    func removeAll() {
        synthesizer?.stopSpeaking(at: .word)
        utteranceMap.removeAllObjects()
    }

    func announce(forLocation coord: LatLon) {
		guard let mapView = mapView else { return }
        if !enabled {
            return
        }

        isNewUpdate = true

		let metersPerDegree = MetersPerDegreeAt(latitude:coord.latitude)
		if previousCoord.latitude == 0.0 && previousCoord.longitude == 0.0 {
            previousCoord = coord
        }
        
//        OSMRect.init(origin: OSMPoint(x: min(previousCoord?.longitude, coord.longitude), y: min(previousCoord?.latitude, coord.latitude)), size: OSMSize(width: abs(), height: ))
		var box = OSMRect(origin:OSMPoint(x:min(previousCoord.longitude, coord.longitude),
										  y:min(previousCoord.latitude, coord.latitude)),
						  size:OSMSize(width: abs(previousCoord.longitude - coord.longitude),
									   height: abs(previousCoord.latitude - coord.latitude)))
        box.origin.x -= radius / Double(metersPerDegree.x)
        box.origin.y -= radius / Double(metersPerDegree.y)
        box.size.width += 2 * radius / Double(metersPerDegree.x)
        box.size.height += 2 * radius / Double(metersPerDegree.y)

		var a = [(Double,OsmBaseObject)]()

		mapView.editorLayer.mapData.enumerateObjects(inRegion: box, block: { obj in
            if obj.deleted {
                return
            }
            if !obj.hasInterestingTags() {
                return
            }
            // make sure it is within distance
			let dist = obj.distance(toLineSegment: OSMPointFromCoordinate(self.previousCoord),
									point: OSMPointFromCoordinate(coord))

			if dist < self.radius {
				if let currentHighway = self.currentHighway,
				   let way = obj.isWay(),
				   obj.tags["highway"] != nil,
				   !currentHighway.sharesNodes(with: way)
				{
					return // only announce ways connected to current way
                }
                a.append((dist, obj))
            }
        })

        // sort by distance
		a.sort { obj1,obj2 in return obj1.0 < obj2.0 }

        let now = Date()
        var currentObjects: [OsmExtendedIdentifier : Date] = [:]
        var closestHighwayWay: OsmWay? = nil
        var closestHighwayDist = 1000000.0
        var newCurrentHighway: OsmWay? = nil
        for (distance,object) in a {

            // track highway we're closest to
            if object.isWay() != nil && object.tags["highway"] != nil {
				if distance < closestHighwayDist {
                    closestHighwayDist = distance
                    closestHighwayWay = object.isWay()
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

        for (_,object) in a {

            // if we've recently announced object then don't announce again
            let ident = object.extendedIdentifier
            currentObjects[ident] = now
			if previousObjects[ident] != nil && object != newCurrentHighway {
                continue
            }

            if buildings && object.tags["building"] != nil {
				var building = object.tags["building"] ?? ""
                if building == "yes" {
                    building = ""
                }
                let text = "building \(building)"
                say(text, for: object)
            }

            if addresses,
			   let number = object.tags["addr:housenumber"]
			{
                let street = object.tags["addr:street"]
                let text = "\(street ?? "") number \(number)"
                say(text, for: object)
            }

            if streets,
			   object.isWay() != nil,
			   let type = object.tags["highway"]
			{
                let name = object.tags["name"] ?? object.tags["ref"]
                if type == "service" && name == nil && object != newCurrentHighway {
                    // skip
                } else {
                    var text = name ?? type
                    if object == newCurrentHighway {
						text = "Now following \(text)"
                    }
                    say(text, for: object)
                }
            }

            if shopsAndAmenities {
                if object.tags["shop"] != nil || object.tags["amenity"] != nil {
                    let text = object.friendlyDescription()
                    say(text, for: object)
                }
            }
        }

        previousObjects = currentObjects
        previousCoord = coord
    }

    // MARK: delegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
		let object = utteranceMap.object(forKey: utterance)
        mapView.editorLayer.selectedNode = object?.isNode()
        mapView.editorLayer.selectedWay = object?.isWay()
        mapView.editorLayer.selectedRelation = object?.isRelation()
        utteranceMap.removeObject(forKey: utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        mapView.editorLayer.selectedNode = nil
        mapView.editorLayer.selectedWay = nil
        mapView.editorLayer.selectedRelation = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        speechSynthesizer(synthesizer, didFinish: utterance)
    }
}

@inline(__always) private func OSMPointFromCoordinate(_ coord: LatLon) -> OSMPoint {
    let point = OSMPoint(x: coord.longitude, y: coord.latitude)
    return point
}
