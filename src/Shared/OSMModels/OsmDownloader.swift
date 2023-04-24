//
//  OsmDownloader.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/18/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation

struct OsmDownloadData {
	var nodes: [OsmNode] = []
	var ways: [OsmWay] = []
	var relations: [OsmRelation] = []
}

enum OsmParserError: LocalizedError {
	case missingLatLon
	case unexpectedStackElement
	case badNodeRef
	case badRelationRefID
	case missingKeyValInTag
	case badXmlDict(String, [String: String])
	case unsupportedOsmApiVersion(String?)

	public var errorDescription: String? {
		switch self {
		case .missingLatLon: return "missing lat/lon"
		case .unexpectedStackElement: return "unexpectedStackElement"
		case .badNodeRef: return "bad node ref ID"
		case .badRelationRefID: return "badRelationRefID"
		case .missingKeyValInTag: return ""
		case let .badXmlDict(ele, dict):
			return "badXmlDict(\(ele)):\n \(dict.map({ k, v in "\(k)=\(v)" }).joined(separator: ",\n"))"
		case let .unsupportedOsmApiVersion(str): return "unsupportedOsmApiVersion(\(str ?? "nil")"
		}
	}
}

class OsmDownloadParser: NSObject, XMLParserDelegate {
	private var parserCurrentElementText = "" // not currently used, it's mostly whitespace
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

		switch elementName {
		case "node":
			guard let node = OsmNode(fromXmlDict: attributeDict) else {
				parseError = OsmParserError.badXmlDict(elementName, attributeDict)
				parser.abortParsing()
				return
			}
			result.nodes.append(node)
			parserStack.append(node)
		case "way":
			guard let way = OsmWay(fromXmlDict: attributeDict) else {
				parseError = OsmParserError.badXmlDict(elementName, attributeDict)
				parser.abortParsing()
				return
			}
			result.ways.append(way)
			parserStack.append(way)
		case "tag":
			guard let key = attributeDict["k"],
			      let value = attributeDict["v"]
			else {
				parseError = OsmParserError.badXmlDict(elementName, attributeDict)
				parser.abortParsing()
				return
			}
			guard let object = parserStack.last as? OsmBaseObject else {
				parseError = OsmParserError.unexpectedStackElement
				parser.abortParsing()
				return
			}
			object.constructTag(key, value: value)
			parserStack.append("tag")
		case "nd":
			guard let way = parserStack.last as? OsmWay,
			      let ref2 = attributeDict["ref"],
			      let ref = Int64(ref2)
			else {
				parseError = OsmParserError.badNodeRef
				parser.abortParsing()
				return
			}
			way.constructNode(ref)
			parserStack.append("nd")
		case "relation":
			guard let relation = OsmRelation(fromXmlDict: attributeDict) else {
				parseError = OsmParserError.badXmlDict(elementName, attributeDict)
				parser.abortParsing()
				return
			}
			result.relations.append(relation)
			parserStack.append(relation)
		case "member":
			guard let relation = parserStack.last as? OsmRelation,
			      let ref2 = attributeDict["ref"],
			      let ref = Int64(ref2)
			else {
				parseError = OsmParserError.badRelationRefID
				parser.abortParsing()
				return
			}
			guard let type2 = attributeDict["type"],
			      let type = try? OSM_TYPE(string: type2)
			else {
				parseError = OsmParserError.badXmlDict(elementName, attributeDict)
				parser.abortParsing()
				return
			}
			let role = attributeDict["role"]
			let member = OsmMember(type: type, ref: ref, role: role)
			relation.constructMember(member)
			parserStack.append(member)
		case "osm":
			// osm header
			let version = attributeDict["version"]
			if version != "0.6" {
				parseError = OsmParserError.unsupportedOsmApiVersion(version)
				parser.abortParsing()
			}
			parserStack.append("osm")
		case "bounds":
#if false
			let minLat = Double(attributeDict["minlat"] ?? "") ?? 0.0
			let minLon = Double(attributeDict["minlon"] ?? "") ?? 0.0
			let maxLat = Double(attributeDict["maxlat"] ?? "") ?? 0.0
			let maxLon = Double(attributeDict["maxlon"] ?? "") ?? 0.0
#endif
			parserStack.append("bounds")
		case "note":
			// issued by Overpass API server
			parserStack.append(elementName)
		case "meta":
			// issued by Overpass API server
			parserStack.append(elementName)
		default:
			DLog("OSM parser: Unknown tag '%@'", elementName)
			parserStack.append(elementName)
#if false
			parseError = NSError(domain: "Parser", code: 102, userInfo: [
				NSLocalizedDescriptionKey: "OSM parser: Unknown tag '\(elementName)'"
			])
			parseError = OsmParserError.unknown

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
		result.nodes.reserveCapacity(5000)
		result.ways.reserveCapacity(100)
		result.relations.reserveCapacity(100)
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
			}
		})
	}
}
