//
//  OsmDownloader.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/18/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Foundation

struct OsmDownloadData {
	var nodes: [OsmIdentifier:OsmNode] = [:]
	var ways: [OsmIdentifier:OsmWay] = [:]
	var relations: [OsmIdentifier:OsmRelation] = [:]
}

class OsmDownloadParser: NSObject, XMLParserDelegate {

	private var parserCurrentElementText: String = ""
	private var parserStack: [AnyHashable] = []
	private var parseError: Error?

	private (set) var result: OsmDownloadData = OsmDownloadData()

	func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String : String] = [:]) {
		parserCurrentElementText = ""

		if elementName == "node" {
			let lat = Double(attributeDict["lat"] ?? "") ?? 0.0
			let lon = Double(attributeDict["lon"] ?? "") ?? 0.0
			let node = OsmNode(fromXmlDict: attributeDict)!
			node.setLongitude(lon, latitude: lat, undo: nil)
			result.nodes[node.ident] = node
			parserStack.append(node)
		} else if elementName == "way" {
			let way = OsmWay(fromXmlDict: attributeDict)!
			result.ways[way.ident] = way
			parserStack.append(way)
		} else if elementName == "tag" {
			let key = attributeDict["k"]!
			let value = attributeDict["v"]!
			let object = parserStack.last as! OsmBaseObject
			object.constructTag(key, value: value)
			parserStack.append("tag")
		} else if elementName == "nd" {
			let way = parserStack.last as? OsmWay
			let ref = attributeDict["ref"]
			assert((ref != nil))
			way?.constructNode(NSNumber(value: Int64(ref ?? "") ?? 0))
			parserStack.append("nd")
		} else if elementName == "relation" {
			let relation = OsmRelation(fromXmlDict: attributeDict)!
			result.relations[relation.ident] = relation
			parserStack.append(relation)
		} else if elementName == "member" {
			let type = attributeDict["type"]
			let ref = NSNumber(value: Int64(attributeDict["ref"] ?? "") ?? 0)
			let role = attributeDict["role"]
			let member = OsmMember(type: type, ref: ref.int64Value, role: role)
			let relation = parserStack.last as! OsmRelation
			relation.constructMember(member)
			parserStack.append(member)
		} else if elementName == "osm" {

			// osm header
			let version = attributeDict["version"]
			if version != "0.6" {
				parseError = NSError(domain: "Parser", code: 102, userInfo: [
					NSLocalizedDescriptionKey: String.localizedStringWithFormat(NSLocalizedString("OSM data must be version 0.6 (fetched '%@')", comment: ""), version ?? "")
				])
				parser.abortParsing()
			}
			parserStack.append("osm")
		} else if elementName == "bounds" {
#if false
			let minLat = Double(attributeDict["minlat"] ?? "") ?? 0.0
			let minLon = Double(attributeDict["minlon"] ?? "") ?? 0.0
			let maxLat = Double(attributeDict["maxlat"] ?? "") ?? 0.0
			let maxLon = Double(attributeDict["maxlon"] ?? "") ?? 0.0
#endif
			parserStack.append("bounds")
		} else if elementName == "note" {

			// issued by Overpass API server
			parserStack.append(elementName)
		} else if elementName == "meta" {

			// issued by Overpass API server
			parserStack.append(elementName)
		} else {

			DLog("OSM parser: Unknown tag '%@'", elementName)
			parserStack.append(elementName)
#if false
			parseError = NSError(domain: "Parser", code: 102, userInfo: [
				NSLocalizedDescriptionKey: "OSM parser: Unknown tag '\(elementName)'"
			])
			parser.abortParsing()
#endif
		}
	}

	@objc func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
		parserStack.removeLast()
	}

	@objc func parser(_ parser: XMLParser, foundCharacters string: String) {
		parserCurrentElementText += string
	}

	@objc func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
		DLog("Parse error: \(parseError.localizedDescription), line \(parser.lineNumber), column \(parser.columnNumber)")
		self.parseError = parseError
	}

	@objc func parserDidEndDocument(_ parser: XMLParser) {
		assert(parserStack.count == 0 || parseError != nil)
	}

	private func reset() {
		parserCurrentElementText = ""
		parserStack = []
		result = OsmDownloadData()
	}

	func parseStream(_ stream: InputStream) -> Result<OsmDownloadData,Error> {
		defer {
			stream.close()
		}

		reset()
		let parser = XMLParser(stream: stream)
		parser.delegate = self
		parseError = nil

		let ok = parser.parse()
		if let error = parseError {
			return .failure(error)
		} else if !ok {
			return .failure(NSError())
		}
		return .success( result )
	}
}

class OsmDownloader {

	// http://wiki.openstreetmap.org/wiki/API_v0.6#Retrieving_map_data_by_bounding_box:_GET_.2Fapi.2F0.6.2Fmap
	static func osmData(forUrl url: String,
				 completion: @escaping (_ r: Result<OsmDownloadData,Error>) -> Void)
	{
		DownloadThreadPool.osmPool().stream(forUrl: url, callback: { stream, error2 in
			guard error2 == nil,
				  let stream = stream,
				  stream.streamError == nil
			else {
				DispatchQueue.main.async(execute: {
					completion(.failure(stream?.streamError ?? error2 ?? NSError()))
				})
				return
			}

			let parser = OsmDownloadParser()
			let result = parser.parseStream( stream )
			DispatchQueue.main.async(execute: {
				completion(result)
			})
		})
	}
}
