//
//  OsmXmlGenerator.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/19/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import KissXML
import UIKit

final class OsmXmlGenerator {
	// MARK: Changeset Metadata XML

	/// Creates the changeset XML (but not the changeset data XML)
	static func createXml(withType type: String, tags dictionary: [String: String]) -> DDXMLDocument? {
#if os(iOS)
		let doc = try! DDXMLDocument(xmlString: "<osm></osm>", options: 0)
		let root = doc.rootElement()!
#else
		let root = DDXMLElement(name: "osm")
		let doc = DDXMLDocument(rootElement: root)
		doc.characterEncoding = "UTF-8"
#endif
		let typeElement = DDXMLElement(name: type)
		root.addChild(typeElement)

		for (key, value) in dictionary {
			let tag = DDXMLElement(name: "tag")
			tag.addAttribute(DDXMLNode.attribute(withName: "k", stringValue: key) as! DDXMLNode)
			tag.addAttribute(DDXMLNode.attribute(withName: "v", stringValue: value) as! DDXMLNode)
			typeElement.addChild(tag)
		}
		return doc
	}

	// MARK: Changeset Payload XML

	class func element(for object: OsmBaseObject) -> DDXMLElement {
		let el = DDXMLElement(name: object.osmType.string)
		el.addAttribute(DDXMLNode.attribute(withName: "id", stringValue: String(object.ident)) as! DDXMLNode)
		el.addAttribute(DDXMLNode.attribute(withName: "timestamp", stringValue: object.timestamp) as! DDXMLNode)
		el.addAttribute(DDXMLNode.attribute(withName: "version", stringValue: String(object.version)) as! DDXMLNode)
		return el
	}

	class func addTags(for object: OsmBaseObject, element: DDXMLElement) {
		for (key, value) in object.tags {
			let tagElement = DDXMLElement(name: "tag")
			tagElement.addAttribute(DDXMLNode.attribute(withName: "k", stringValue: key) as! DDXMLNode)
			tagElement.addAttribute(DDXMLNode.attribute(withName: "v", stringValue: value) as! DDXMLNode)
			element.addChild(tagElement)
		}
	}

	/// Convenience overload that accepts a heterogeneous set of OSM objects,
	/// splitting them into nodes, ways, and relations before generating the XML.
	static func createXmlFor(objects: some Sequence<OsmBaseObject>, generator: String) -> DDXMLDocument? {
		createXmlFor(
			nodes: objects.compactMap { $0 as? OsmNode },
			ways: objects.compactMap { $0 as? OsmWay },
			relations: objects.compactMap { $0 as? OsmRelation },
			generator: generator)
	}

	static func createXmlFor<N: Sequence, W: Sequence, R: Sequence>
	(nodes: N, ways: W, relations: R, generator: String) -> DDXMLDocument?
		where N.Element == OsmNode, W.Element == OsmWay, R.Element == OsmRelation
	{
		let createNodeElement = DDXMLElement(name: "create")
		let modifyNodeElement = DDXMLElement(name: "modify")
		let deleteNodeElement = DDXMLElement(name: "delete")
		let createWayElement = DDXMLElement(name: "create")
		let modifyWayElement = DDXMLElement(name: "modify")
		let deleteWayElement = DDXMLElement(name: "delete")
		let createRelationElement = DDXMLElement(name: "create")
		let modifyRelationElement = DDXMLElement(name: "modify")
		let deleteRelationElement = DDXMLElement(name: "delete")

		for deleteElement in [deleteNodeElement, deleteWayElement, deleteRelationElement] {
			deleteElement.addAttribute(DDXMLNode.attribute(withName: "if-unused", stringValue: "yes") as! DDXMLNode)
		}

		for node in nodes {
			if node.deleted, node.ident > 0 {
				// deleted
				let element = Self.element(for: node)
				deleteNodeElement.addChild(element)
			} else if node.isModified, !node.deleted {
				// added/modified
				let element = Self.element(for: node)
				element.addAttribute(DDXMLNode.attribute(withName: "lat", stringValue: String(node.latLon.lat)) as! DDXMLNode)
				element.addAttribute(DDXMLNode.attribute(withName: "lon", stringValue: String(node.latLon.lon)) as! DDXMLNode)
				Self.addTags(for: node, element: element)
				if node.ident < 0 {
					createNodeElement.addChild(element)
				} else {
					modifyNodeElement.addChild(element)
				}
			}
		}

		for way in ways {
			if way.deleted, way.ident > 0 {
				let element = Self.element(for: way)
				deleteWayElement.addChild(element)
				for node in way.nodes {
					let nodeElement = Self.element(for: node)
					deleteWayElement.addChild(nodeElement)
				}
			} else if way.isModified, !way.deleted {
				// added/modified
				let element = Self.element(for: way)
				for node in way.nodes.removingDuplicatedItems() {
					let refElement = DDXMLElement(name: "nd")
					refElement.addAttribute(DDXMLNode.attribute(withName: "ref", stringValue: String(node.ident)) as! DDXMLNode)
					element.addChild(refElement)
				}
				Self.addTags(for: way, element: element)
				if way.ident < 0 {
					createWayElement.addChild(element)
				} else {
					modifyWayElement.addChild(element)
				}
			}
		}

		for relation in relations {
			if relation.deleted, relation.ident > 0 {
				let element = Self.element(for: relation)
				deleteRelationElement.addChild(element)
			} else if relation.isModified,
			          !relation.deleted
			{
				// added/modified
				let element = Self.element(for: relation)
				for member in relation.members {
					let memberElement = DDXMLElement(name: "member")
					memberElement.addAttribute(DDXMLNode.attribute(withName: "type", stringValue: member.type.string) as! DDXMLNode)
					memberElement.addAttribute(DDXMLNode.attribute(withName: "ref", stringValue: String(member.ref)) as! DDXMLNode)
					memberElement.addAttribute(DDXMLNode.attribute(withName: "role", stringValue: member.role ?? "") as! DDXMLNode)
					element.addChild(memberElement)
				}
				Self.addTags(for: relation, element: element)
				if relation.ident < 0 {
					createRelationElement.addChild(element)
				} else {
					modifyRelationElement.addChild(element)
				}
			}
		}

		let text = """
		<?xml version="1.0"?>\
		<osmChange generator="\(generator)" version="0.6"></osmChange>
		"""
		let doc = try! DDXMLDocument(xmlString: text, options: 0)
		let root = doc.rootElement()!

		if createNodeElement.childCount > 0 {
			root.addChild(createNodeElement)
		}
		if createWayElement.childCount > 0 {
			root.addChild(createWayElement)
		}
		if createRelationElement.childCount > 0 {
			root.addChild(createRelationElement)
		}

		if modifyNodeElement.childCount > 0 {
			root.addChild(modifyNodeElement)
		}
		if modifyWayElement.childCount > 0 {
			root.addChild(modifyWayElement)
		}
		if modifyRelationElement.childCount > 0 {
			root.addChild(modifyRelationElement)
		}

		if deleteRelationElement.childCount > 0 {
			root.addChild(deleteRelationElement)
		}
		if deleteWayElement.childCount > 0 {
			root.addChild(deleteWayElement)
		}
		if deleteNodeElement.childCount > 0 {
			root.addChild(deleteNodeElement)
		}

		if root.childCount == 0 {
			return nil // nothing to add
		}

		return doc
	}

	// MARK: Pretty print changeset

	private static func update(_ string: NSMutableAttributedString, withTag tag: DDXMLElement) {
#if os(iOS)
		let font = UIFont.preferredFont(forTextStyle: .callout)
#else
		let font = NSFont.labelFont(ofSize: 12)
#endif

		var foregroundColor = UIColor.black
		if #available(iOS 13.0, *) {
			foregroundColor = UIColor.label
		}

		let text =
			"\t\t\(tag.attribute(forName: "k")?.stringValue ?? "") = \(tag.attribute(forName: "v")?.stringValue ?? "")\n"
		string.append(NSAttributedString(string: text, attributes: [
			NSAttributedString.Key.font: font,
			NSAttributedString.Key.foregroundColor: foregroundColor
		]))
	}

	private static func update(_ string: NSMutableAttributedString, withMember tag: DDXMLElement) {
#if os(iOS)
		let font = UIFont.preferredFont(forTextStyle: .callout)
#else
		let font = NSFont.labelFont(ofSize: 12)
#endif
		var foregroundColor = UIColor.black
		if #available(iOS 13.0, *) {
			foregroundColor = UIColor.label
		}

		let text =
			"\t\t\(tag.attribute(forName: "type")?.stringValue ?? "") \(tag.attribute(forName: "ref")?.stringValue ?? ""): \"\(tag.attribute(forName: "role")?.stringValue ?? "")\"\n"
		string.append(NSAttributedString(string: text, attributes: [
			NSAttributedString.Key.font: font,
			NSAttributedString.Key.foregroundColor: foregroundColor
		]))
	}

	private static func update(_ string: NSMutableAttributedString, withNode node: DDXMLElement,
	                           primaryDescriptions: [Int64: String], parentWayNames: [Int64: String])
	{
#if os(iOS)
		let font = UIFont.preferredFont(forTextStyle: .body)
		let boldDescriptor = font.fontDescriptor.withSymbolicTraits(.traitBold)
		let boldFont = boldDescriptor.map { UIFont(descriptor: $0, size: 0) } ?? font
#else
		let font = NSFont.labelFont(ofSize: 12)
		let boldFont = NSFont.boldSystemFont(ofSize: 12)
#endif

		var foregroundColor = UIColor.black
		if #available(iOS 13.0, *) {
			foregroundColor = UIColor.label
		}

		let nodeName = node.attribute(forName: "id")?.stringValue
		let ident = nodeName.flatMap { Int64($0) }

		if let desc = ident.flatMap({ primaryDescriptions[$0] }) {
			// Bold description first, then "— Node {linked-ID}"
			string.append(NSAttributedString(string: "\t\(desc) ", attributes: [
				NSAttributedString.Key.font: boldFont,
				NSAttributedString.Key.foregroundColor: foregroundColor
			]))
			string.append(NSAttributedString(string: "— Node ", attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.foregroundColor: foregroundColor
			]))
			string.append(NSAttributedString(string: nodeName ?? "", attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.link: "n" + (nodeName ?? "")
			]))
		} else {
			// "Node {linked-ID}", optionally with parent way context
			string.append(NSAttributedString(string: "\tNode ", attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.foregroundColor: foregroundColor
			]))
			string.append(NSAttributedString(string: nodeName ?? "", attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.link: "n" + (nodeName ?? "")
			]))
			if let parentWay = ident.flatMap({ parentWayNames[$0] }) {
				string.append(NSAttributedString(string: " (in \(parentWay))", attributes: [
					NSAttributedString.Key.font: font,
					NSAttributedString.Key.foregroundColor: foregroundColor
				]))
			}
		}
		string.append(NSAttributedString(string: "\n", attributes: [
			NSAttributedString.Key.font: font
		]))
		for tag in node.children ?? [] {
			guard let tag = tag as? DDXMLElement else {
				continue
			}
			if tag.name == "tag" {
				update(string, withTag: tag)
			} else {
				assertionFailure()
			}
		}
	}

	private static func update(_ string: NSMutableAttributedString, withWay way: DDXMLElement,
	                           primaryDescriptions: [Int64: String], parentWayNames: [Int64: String])
	{
		var nodeCount = 0
		for tag in way.children ?? [] {
			guard let tag = tag as? DDXMLElement else {
				continue
			}
			if tag.name == "nd" {
				nodeCount += 1
			}
		}

#if os(iOS)
		let font = UIFont.preferredFont(forTextStyle: .body)
		let boldDescriptor = font.fontDescriptor.withSymbolicTraits(.traitBold)
		let boldFont = boldDescriptor.map { UIFont(descriptor: $0, size: 0) } ?? font
#else
		let font = NSFont.labelFont(ofSize: 12)
		let boldFont = NSFont.boldSystemFont(ofSize: 12)
#endif

		var foregroundColor = UIColor.black
		if #available(iOS 13.0, *) {
			foregroundColor = UIColor.label
		}

		let wayName = way.attribute(forName: "id")?.stringValue
		let ident = wayName.flatMap { Int64($0) }
		let nodeCountStr = String.localizedStringWithFormat(NSLocalizedString(" (%d nodes)\n", comment: ""), nodeCount)

		if let desc = ident.flatMap({ primaryDescriptions[$0] }) {
			// Bold description first, then "— Way {linked-ID} (N nodes)"
			string.append(NSAttributedString(string: "\t\(desc) ", attributes: [
				NSAttributedString.Key.font: boldFont,
				NSAttributedString.Key.foregroundColor: foregroundColor
			]))
			string.append(NSAttributedString(string: "— Way ", attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.foregroundColor: foregroundColor
			]))
			string.append(NSAttributedString(string: wayName ?? "", attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.link: "w" + (wayName ?? "")
			]))
			string.append(NSAttributedString(string: nodeCountStr, attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.foregroundColor: foregroundColor
			]))
		} else {
			string.append(NSAttributedString(string: NSLocalizedString("\tWay ", comment: ""), attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.foregroundColor: foregroundColor
			]))
			string.append(NSAttributedString(string: wayName ?? "", attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.link: "w" + (wayName ?? "")
			]))
			string.append(NSAttributedString(string: nodeCountStr, attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.foregroundColor: foregroundColor
			]))
		}

		for tag in way.children ?? [] {
			guard let tag = tag as? DDXMLElement else {
				continue
			}
			if tag.name == "tag" {
				update(string, withTag: tag)
			} else if tag.name == "nd" {
				// skip
			} else {
				assertionFailure()
			}
		}
	}

	private static func update(_ string: NSMutableAttributedString, withRelation relation: DDXMLElement,
	                           primaryDescriptions: [Int64: String], parentWayNames: [Int64: String])
	{
		var memberCount = 0
		for tag in relation.children ?? [] {
			guard let tag = tag as? DDXMLElement else {
				continue
			}
			if tag.name == "member" {
				memberCount += 1
			}
		}

#if os(iOS)
		let font = UIFont.preferredFont(forTextStyle: .body)
		let boldDescriptor = font.fontDescriptor.withSymbolicTraits(.traitBold)
		let boldFont = boldDescriptor.map { UIFont(descriptor: $0, size: 0) } ?? font
#else
		let font = NSFont.labelFont(ofSize: 12)
		let boldFont = NSFont.boldSystemFont(ofSize: 12)
#endif

		var foregroundColor = UIColor.black
		if #available(iOS 13.0, *) {
			foregroundColor = UIColor.label
		}

		let relationName = relation.attribute(forName: "id")?.stringValue
		let ident = relationName.flatMap { Int64($0) }
		let memberCountStr = String.localizedStringWithFormat(NSLocalizedString(" (%d members)\n", comment: ""), memberCount)

		if let desc = ident.flatMap({ primaryDescriptions[$0] }) {
			// Bold description first, then "— Relation {linked-ID} (N members)"
			string.append(NSAttributedString(string: "\t\(desc) ", attributes: [
				NSAttributedString.Key.font: boldFont,
				NSAttributedString.Key.foregroundColor: foregroundColor
			]))
			string.append(NSAttributedString(string: "— Relation ", attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.foregroundColor: foregroundColor
			]))
			string.append(NSAttributedString(string: relationName ?? "", attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.link: "r" + (relationName ?? "")
			]))
			string.append(NSAttributedString(string: memberCountStr, attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.foregroundColor: foregroundColor
			]))
		} else {
			string.append(NSAttributedString(string: NSLocalizedString("\tRelation ", comment: ""), attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.foregroundColor: foregroundColor
			]))
			string.append(NSAttributedString(string: relationName ?? "", attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.link: "r" + (relationName ?? "")
			]))
			string.append(NSAttributedString(string: memberCountStr, attributes: [
				NSAttributedString.Key.font: font,
				NSAttributedString.Key.foregroundColor: foregroundColor
			]))
		}

		for tag in relation.children ?? [] {
			guard let tag = tag as? DDXMLElement else {
				continue
			}
			if tag.name == "tag" {
				update(string, withTag: tag)
			} else if tag.name == "member" {
				update(string, withMember: tag)
			} else {
				assertionFailure()
			}
		}
	}

	private static func update(_ string: NSMutableAttributedString, withHeader header: String, objects: [Any]?,
	                           primaryDescriptions: [Int64: String], parentWayNames: [Int64: String])
	{
		guard let objects = objects,
		      objects.count > 0
		else {
			return
		}

		var foregroundColor = UIColor.black
		if #available(iOS 13.0, *) {
			foregroundColor = UIColor.label
		}

#if os(iOS)
		let font = UIFont.preferredFont(forTextStyle: .headline)
#else
		let font = NSFont.labelFont(ofSize: 12)
#endif
		string.append(NSAttributedString(string: header, attributes: [
			NSAttributedString.Key.font: font,
			NSAttributedString.Key.foregroundColor: foregroundColor
		]))
		for object in objects {
			guard let object = object as? DDXMLElement else {
				continue
			}
			if object.name == "node" {
				update(string, withNode: object, primaryDescriptions: primaryDescriptions, parentWayNames: parentWayNames)
			} else if object.name == "way" {
				update(string, withWay: object, primaryDescriptions: primaryDescriptions, parentWayNames: parentWayNames)
			} else if object.name == "relation" {
				update(string, withRelation: object, primaryDescriptions: primaryDescriptions, parentWayNames: parentWayNames)
			} else {
				assertionFailure()
			}
		}
	}

	/// Counts the nodes, ways, and relations present in an osmChange document.
	/// Mirrors the same element enumeration used by attributedStringForXML, so the
	/// counts always match what is actually displayed and uploaded.
	static func objectCounts(in doc: DDXMLDocument) -> (nodes: Int, ways: Int, relations: Int) {
		var nodes = 0, ways = 0, relations = 0
		guard let root = doc.rootElement() else { return (0, 0, 0) }
		let sections = root.elements(forName: "create")
			+ root.elements(forName: "modify")
			+ root.elements(forName: "delete")
		for section in sections {
			for child in (section.children ?? []).compactMap({ $0 as? DDXMLElement }) {
				switch child.name {
				case "node": nodes += 1
				case "way": ways += 1
				case "relation": relations += 1
				default: break
				}
			}
		}
		return (nodes, ways, relations)
	}

	/// Converts an XML document to an AttributedString suitable for the Upload view.
	/// - `primaryDescriptions`: maps object ID → bold label shown before the type+ID (for objects with tags)
	/// - `parentWayNames`: maps node ID → parent way label shown after the ID (for topology nodes)
	static func attributedStringForXML(_ doc: DDXMLDocument,
	                                   primaryDescriptions: [Int64: String] = [:],
	                                   parentWayNames: [Int64: String] = [:]) -> NSAttributedString?
	{
		let string = NSMutableAttributedString()
		guard let root = doc.rootElement() else { return nil }

		let deletes = root.elements(forName: "delete")
		let creates = root.elements(forName: "create")
		let modifys = root.elements(forName: "modify")
		for delete in deletes {
			update(string, withHeader: NSLocalizedString("Delete\n", comment: ""), objects: delete.children,
			       primaryDescriptions: primaryDescriptions, parentWayNames: parentWayNames)
		}
		for create in creates {
			update(string, withHeader: NSLocalizedString("Create\n", comment: ""), objects: create.children,
			       primaryDescriptions: primaryDescriptions, parentWayNames: parentWayNames)
		}
		for modify in modifys {
			update(string, withHeader: NSLocalizedString("Modify\n", comment: ""), objects: modify.children,
			       primaryDescriptions: primaryDescriptions, parentWayNames: parentWayNames)
		}
		return string
	}
}
