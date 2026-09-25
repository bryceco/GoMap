//
//  OsmDownloader.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/18/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation

class OsmDownloadParser: NSObject, XMLParserDelegate {

	enum Error: LocalizedError {
		case missingLatLon
		case unexpectedStackElement
		case badNodeRef
		case badRelationRefID
		case missingKeyValInTag
		case badXmlDict(String, [String: String])
		case unsupportedOsmApiVersion(String?)
		case unknownParseFailure

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
			case .unknownParseFailure: return "XML parse failed"
			}
		}
	}

	private var parserStack: [String] = []
	private var parseError: Swift.Error?

	// Buffering state for the element currently being built
	private var buildingType: String? // "node", "way", or "relation"
	private var currentAttributeDict: [String: String] = [:]
	private var currentTags: [String: String] = [:]
	private var currentNodeRefs: [OsmIdentifier] = []
	private var currentMembers: [OsmMember] = []

	private(set) var result = OsmServerData()

	func parser(
		_ parser: XMLParser,
		didStartElement elementName: String,
		namespaceURI: String?,
		qualifiedName: String?,
		attributes attributeDict: [String: String] = [:])
	{
		parserStack.append(elementName)

		switch elementName {
		case "node", "way", "relation":
			buildingType = elementName
			currentAttributeDict = attributeDict
			currentTags = [:]
			currentNodeRefs = []
			currentMembers = []

		case "tag":
			guard let key = attributeDict["k"],
			      let value = attributeDict["v"]
			else {
				parseError = Error.missingKeyValInTag
				parser.abortParsing()
				return
			}
			if !PresetsDatabase.shared.discarded.shouldDiscard(key: key, value: value) {
				currentTags[key] = value
			}

		case "nd":
			guard buildingType == "way",
			      let ref2 = attributeDict["ref"],
			      let ref = Int64(ref2)
			else {
				parseError = Error.badNodeRef
				parser.abortParsing()
				return
			}
			currentNodeRefs.append(ref)

		case "member":
			guard buildingType == "relation",
			      let ref2 = attributeDict["ref"],
			      let ref = Int64(ref2),
			      let type2 = attributeDict["type"],
			      let type = try? OSM_TYPE(string: type2)
			else {
				parseError = Error.badRelationRefID
				parser.abortParsing()
				return
			}
			let role = attributeDict["role"]
			currentMembers.append(OsmMember(type: type, ref: ref, role: role))

		case "osm":
			let version = attributeDict["version"]
			if version != "0.6" {
				parseError = Error.unsupportedOsmApiVersion(version)
				parser.abortParsing()
			}

		default:
			break
		}
	}

	@objc func parser(
		_ parser: XMLParser,
		didEndElement elementName: String,
		namespaceURI: String?,
		qualifiedName qName: String?)
	{
		parserStack.removeLast()

		switch elementName {
		case "node":
			guard let latText = currentAttributeDict["lat"],
			      let lonText = currentAttributeDict["lon"],
			      let lat = Double(latText),
			      let lon = Double(lonText),
			      let versionStr = currentAttributeDict["version"],
			      let version = Int(versionStr),
			      let changesetStr = currentAttributeDict["changeset"],
			      let changeset = Int64(changesetStr),
			      let identStr = currentAttributeDict["id"],
			      let ident = Int64(identStr),
			      let timestamp = currentAttributeDict["timestamp"]
			else {
				parseError = Error.badXmlDict(elementName, currentAttributeDict)
				parser.abortParsing()
				return
			}
			let node = OsmServerNode(
				ident: ident,
				version: version,
				changeset: changeset,
				user: currentAttributeDict["user"] ?? "",
				uid: Int(currentAttributeDict["uid"] ?? "") ?? 0,
				timestamp: timestamp,
				tags: currentTags,
				body: LatLon(latitude: lat, longitude: lon))
			result.nodes.append(node)
			buildingType = nil

		case "way":
			guard let versionStr = currentAttributeDict["version"],
			      let version = Int(versionStr),
			      let changesetStr = currentAttributeDict["changeset"],
			      let changeset = Int64(changesetStr),
			      let identStr = currentAttributeDict["id"],
			      let ident = Int64(identStr),
			      let timestamp = currentAttributeDict["timestamp"]
			else {
				parseError = Error.badXmlDict(elementName, currentAttributeDict)
				parser.abortParsing()
				return
			}
			let way = OsmServerWay(
				ident: ident,
				version: version,
				changeset: changeset,
				user: currentAttributeDict["user"] ?? "",
				uid: Int(currentAttributeDict["uid"] ?? "") ?? 0,
				timestamp: timestamp,
				tags: currentTags,
				body: currentNodeRefs)
			result.ways.append(way)
			buildingType = nil

		case "relation":
			guard let versionStr = currentAttributeDict["version"],
			      let version = Int(versionStr),
			      let changesetStr = currentAttributeDict["changeset"],
			      let changeset = Int64(changesetStr),
			      let identStr = currentAttributeDict["id"],
			      let ident = Int64(identStr),
			      let timestamp = currentAttributeDict["timestamp"]
			else {
				parseError = Error.badXmlDict(elementName, currentAttributeDict)
				parser.abortParsing()
				return
			}
			let relation = OsmServerRelation(
				ident: ident,
				version: version,
				changeset: changeset,
				user: currentAttributeDict["user"] ?? "",
				uid: Int(currentAttributeDict["uid"] ?? "") ?? 0,
				timestamp: timestamp,
				tags: currentTags,
				body: currentMembers)
			result.relations.append(relation)
			buildingType = nil

		default:
			break
		}
	}

	@objc func parser(_ parser: XMLParser, foundCharacters string: String) {}

	@objc func parser(_ parser: XMLParser, parseErrorOccurred parseError: Swift.Error) {
		DLog(
			"Parse error: \(parseError.localizedDescription), line \(parser.lineNumber), column \(parser.columnNumber)")
		self.parseError = parseError
	}

	@objc func parserDidEndDocument(_ parser: XMLParser) {
		assert(parserStack.count == 0 || parseError != nil)
	}

	private func reset() {
		parserStack = []
		buildingType = nil
		currentAttributeDict = [:]
		currentTags = [:]
		currentNodeRefs = []
		currentMembers = []
		result = OsmServerData()
	}

	func parseStream(_ stream: InputStream) throws -> OsmServerData {
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
		if !ok || parseError != nil {
			throw parseError ?? parser.parserError ?? Error.unknownParseFailure
		}
		return result
	}
}

enum OsmDownloader {
	// http://wiki.openstreetmap.org/wiki/API_v0.6#Retrieving_map_data_by_bounding_box:_GET_.2Fapi.2F0.6.2Fmap
	static func osmData(forUrl url: URL) async throws -> OsmServerData {
		let stream = try await DownloadThreadPool.osmPool.stream(forUrl: url)
		if let error = stream.streamError {
			throw error
		}
		let parser = OsmDownloadParser()
		let result = try parser.parseStream(stream)
		return result
	}
}
