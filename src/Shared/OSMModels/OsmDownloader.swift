//
//  OsmDownloader.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/18/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Foundation

struct OsmDownloadData {
	var nodes: [OsmNode] = []
	var ways: [OsmWay] = []
	var relations: [OsmRelation] = []
}

class OsmDownloadParser: NSObject, XMLParserDelegate {
	private var parserCurrentElementText: String = "" // not currently used, it's mostly whitespace
	private var parserStack: [Any] = []
	private var parseError: Error?

	private(set) var result = OsmDownloadData()

	func parser(
		_ parser: XMLParser,
		didStartElement elementName: String,
		namespaceURI: String?,
		qualifiedName: String?,
		attributes attributeDict: [String: String] = [:])
	{
		parserCurrentElementText = ""

		if elementName == "node" {
			guard let latText = attributeDict["lat"],
			      let lonText = attributeDict["lon"],
			      let lat = Double(latText),
			      let lon = Double(lonText)
			else {
				parseError = NSError(domain: "Parser", code: 102, userInfo: [
					NSLocalizedDescriptionKey: "OSM parser: missing lat/lon"
				])
				parser.abortParsing()
				return
			}
			let node = OsmNode(fromXmlDict: attributeDict)!
			node.setLongitude(lon, latitude: lat, undo: nil)
			result.nodes.append(node)
			parserStack.append(node)
		} else if elementName == "way" {
			let way = OsmWay(fromXmlDict: attributeDict)!
			result.ways.append(way)
			parserStack.append(way)
		} else if elementName == "tag" {
			let key = attributeDict["k"]!
			let value = attributeDict["v"]!
			guard let object = parserStack.last as? OsmBaseObject else {
				parser.abortParsing()
				return
			}
			object.constructTag(key, value: value)
			parserStack.append("tag")
		} else if elementName == "nd" {
			guard let way = parserStack.last as? OsmWay,
			      let ref = attributeDict["ref"],
			      let ref = Int64(ref)
			else {
				parser.abortParsing()
				return
			}
			way.constructNode(ref)
			parserStack.append("nd")
		} else if elementName == "relation" {
			let relation = OsmRelation(fromXmlDict: attributeDict)!
			result.relations.append(relation)
			parserStack.append(relation)
		} else if elementName == "member" {
			guard let relation = parserStack.last as? OsmRelation,
			      let ref = attributeDict["ref"],
			      let ref = Int64(ref)
			else {
				parser.abortParsing()
				return
			}
			let type = attributeDict["type"]
			let role = attributeDict["role"]
			let member = OsmMember(type: type, ref: ref, role: role)
			relation.constructMember(member)
			parserStack.append(member)
		} else if elementName == "osm" {
			// osm header
			let version = attributeDict["version"]
			if version != "0.6" {
				parseError = NSError(domain: "Parser", code: 102, userInfo: [
					NSLocalizedDescriptionKey: String.localizedStringWithFormat(
						NSLocalizedString("OSM data must be version 0.6 (fetched '%@')", comment: ""),
						version ?? "")
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

	@objc func parser(
		_ parser: XMLParser,
		didEndElement elementName: String,
		namespaceURI: String?,
		qualifiedName qName: String?)
	{
		parserStack.removeLast()
	}

	@objc func parser(_ parser: XMLParser, foundCharacters string: String) {
		parserCurrentElementText += string
	}

	@objc func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
		DLog(
			"Parse error: \(parseError.localizedDescription), line \(parser.lineNumber), column \(parser.columnNumber)")
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

	func parseStream(_ stream: InputStream) -> Result<OsmDownloadData, Error> {
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
		return .success(result)
	}
}

enum OsmDownloader {
	// http://wiki.openstreetmap.org/wiki/API_v0.6#Retrieving_map_data_by_bounding_box:_GET_.2Fapi.2F0.6.2Fmap
	static func osmData(forUrl url: String,
	                    completion: @escaping (_ r: Result<OsmDownloadData, Error>) -> Void)
	{
		DownloadThreadPool.osmPool.stream(forUrl: url, callback: { result in
			switch result {
			case let .success(stream):
				if let error = stream.streamError {
					DispatchQueue.main.async(execute: {
						completion(.failure(error))
					})
					return
				}
				let parser = OsmDownloadParser()
				let result = parser.parseStream(stream)
				DispatchQueue.main.async(execute: {
					completion(result)
				})
			case let .failure(error):
				DispatchQueue.main.async(execute: {
					completion(.failure(error))
				})
				return
			}
		})
	}
}
