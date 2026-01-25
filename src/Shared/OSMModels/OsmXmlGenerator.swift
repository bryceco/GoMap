//
//  OsmXmlGenerator.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/19/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

final class OsmXmlGenerator {
	// MARK: Changeset Metadata XML

	/// Creates the changeset XML (but not the changeset data XML)
	static func createXml(withType type: String, tags dictionary: [String: String]) -> DDXMLDocument? {
#if os(iOS)
		let doc = try! DDXMLDocument(xmlString: "<osm></osm>", options: 0)
		let root = doc.rootElement()!
#else
		let root = DDXMLNode.element(withName: "osm") as? DDXMLElement
		let doc = DDXMLDocument(rootElement: root)
		doc.characterEncoding = "UTF-8"
#endif
		guard let typeElement = DDXMLNode.element(withName: type) as? DDXMLElement else { return nil }
		root.addChild(typeElement)

		for (key, value) in dictionary {
			guard let tag = DDXMLNode.element(withName: "tag") as? DDXMLElement,
			      let attrKey = DDXMLNode.attribute(withName: "k", stringValue: key) as? DDXMLNode,
			      let attrValue = DDXMLNode.attribute(withName: "v", stringValue: value) as? DDXMLNode
			else { return nil }
			typeElement.addChild(tag)
			tag.addAttribute(attrKey)
			tag.addAttribute(attrValue)
		}
		return doc
	}

	// MARK: Changeset Payload XML

	class func element(for object: OsmBaseObject) -> DDXMLElement {
		let type = object.osmType.string
		let element = DDXMLNode.element(withName: type) as! DDXMLElement
		element
			.addAttribute(DDXMLNode
				.attribute(withName: "id", stringValue: NSNumber(value: object.ident).stringValue) as! DDXMLNode)
		element.addAttribute(DDXMLNode.attribute(withName: "timestamp", stringValue: object.timestamp) as! DDXMLNode)
		element
			.addAttribute(DDXMLNode
				.attribute(withName: "version", stringValue: NSNumber(value: object.version).stringValue) as! DDXMLNode)
		return element
	}

	class func addTags(for object: OsmBaseObject, element: DDXMLElement) {
		for (key, value) in object.tags {
			let tagElement = DDXMLElement.element(withName: "tag") as! DDXMLElement
			if let attribute = DDXMLNode.attribute(withName: "k", stringValue: key) as? DDXMLNode {
				tagElement.addAttribute(attribute)
			}
			if let attribute = DDXMLNode.attribute(withName: "v", stringValue: value) as? DDXMLNode {
				tagElement.addAttribute(attribute)
			}
			element.addChild(tagElement)
		}
	}

	static func createXmlFor<N: Sequence, W: Sequence, R: Sequence>
	(nodes: N, ways: W, relations: R, generator: String) -> DDXMLDocument?
		where N.Element == OsmNode, W.Element == OsmWay, R.Element == OsmRelation
	{
		let createNodeElement = DDXMLNode.element(withName: "create") as! DDXMLElement
		let modifyNodeElement = DDXMLNode.element(withName: "modify") as! DDXMLElement
		let deleteNodeElement = DDXMLNode.element(withName: "delete") as! DDXMLElement
		let createWayElement = DDXMLNode.element(withName: "create") as! DDXMLElement
		let modifyWayElement = DDXMLNode.element(withName: "modify") as! DDXMLElement
		let deleteWayElement = DDXMLNode.element(withName: "delete") as! DDXMLElement
		let createRelationElement = DDXMLNode.element(withName: "create") as! DDXMLElement
		let modifyRelationElement = DDXMLNode.element(withName: "modify") as! DDXMLElement
		let deleteRelationElement = DDXMLNode.element(withName: "delete") as! DDXMLElement

		if let attribute = DDXMLNode.attribute(withName: "if-unused", stringValue: "yes") as? DDXMLNode {
			deleteNodeElement.addAttribute(attribute)
		}
		if let attribute = DDXMLNode.attribute(withName: "if-unused", stringValue: "yes") as? DDXMLNode {
			deleteWayElement.addAttribute(attribute)
		}
		if let attribute = DDXMLNode.attribute(withName: "if-unused", stringValue: "yes") as? DDXMLNode {
			deleteRelationElement.addAttribute(attribute)
		}

		for node in nodes {
			if node.deleted, node.ident > 0 {
				// deleted
				let element = Self.element(for: node)
				deleteNodeElement.addChild(element)
			} else if node.isModified(), !node.deleted {
				// added/modified
				let element = Self.element(for: node)
				element
					.addAttribute(DDXMLNode
						.attribute(withName: "lat",
						           stringValue: NSNumber(value: node.latLon.lat).stringValue) as! DDXMLNode)
				element
					.addAttribute(DDXMLNode
						.attribute(withName: "lon",
						           stringValue: NSNumber(value: node.latLon.lon).stringValue) as! DDXMLNode)
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
			} else if way.isModified(), !way.deleted {
				// added/modified
				let element = Self.element(for: way)
				for node in way.nodes.removingDuplicatedItems() {
					let refElement = DDXMLElement.element(withName: "nd") as! DDXMLElement
					refElement
						.addAttribute(DDXMLNode
							.attribute(
								withName: "ref",
								stringValue: NSNumber(value: node.ident).stringValue) as! DDXMLNode)
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
			} else if relation.isModified(),
			          !relation.deleted
			{
				// added/modified
				let element = Self.element(for: relation)
				for member in relation.members {
					let memberElement = DDXMLElement.element(withName: "member") as! DDXMLElement
					memberElement
						.addAttribute(DDXMLNode
							.attribute(withName: "type", stringValue: member.type.string) as! DDXMLNode)
					memberElement
						.addAttribute(DDXMLNode
							.attribute(withName: "ref",
							           stringValue: NSNumber(value: member.ref).stringValue) as! DDXMLNode)
					memberElement
						.addAttribute(DDXMLNode
							.attribute(withName: "role", stringValue: member.role ?? "") as! DDXMLNode)
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

	private static func update(_ string: NSMutableAttributedString, withNode node: DDXMLElement) {
#if os(iOS)
		let font = UIFont.preferredFont(forTextStyle: .body)
#else
		let font = NSFont.labelFont(ofSize: 12)
#endif

		var foregroundColor = UIColor.black
		if #available(iOS 13.0, *) {
			foregroundColor = UIColor.label
		}

		let nodeName = node.attribute(forName: "id")?.stringValue
		string.append(NSAttributedString(string: "\tNode ", attributes: [
			NSAttributedString.Key.font: font,
			NSAttributedString.Key.foregroundColor: foregroundColor
		]))
		string.append(
			NSAttributedString(
				string: nodeName ?? "",
				attributes: [
					NSAttributedString.Key.font: font,
					NSAttributedString.Key.link: "n" + (nodeName ?? "")
				]))
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

	private static func update(_ string: NSMutableAttributedString, withWay way: DDXMLElement) {
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
#else
		let font = NSFont.labelFont(ofSize: 12)
#endif

		var foregroundColor = UIColor.black
		if #available(iOS 13.0, *) {
			foregroundColor = UIColor.label
		}

		let wayName = way.attribute(forName: "id")?.stringValue
		string.append(NSAttributedString(string: NSLocalizedString("\tWay ", comment: ""), attributes: [
			NSAttributedString.Key.font: font,
			NSAttributedString.Key.foregroundColor: foregroundColor
		]))
		string.append(
			NSAttributedString(
				string: wayName ?? "",
				attributes: [
					NSAttributedString.Key.font: font,
					NSAttributedString.Key.link: "w" + (wayName ?? "")
				]))
		string.append(
			NSAttributedString(
				string: String.localizedStringWithFormat(NSLocalizedString(" (%d nodes)\n", comment: ""), nodeCount),
				attributes: [
					NSAttributedString.Key.font: font,
					NSAttributedString.Key.foregroundColor: foregroundColor
				]))

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

	private static func update(_ string: NSMutableAttributedString, withRelation relation: DDXMLElement) {
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
#else
		let font = NSFont.labelFont(ofSize: 12)
#endif

		var foregroundColor = UIColor.black
		if #available(iOS 13.0, *) {
			foregroundColor = UIColor.label
		}

		let relationName = relation.attribute(forName: "id")?.stringValue
		string.append(NSAttributedString(string: NSLocalizedString("\tRelation ", comment: ""), attributes: [
			NSAttributedString.Key.font: font,
			NSAttributedString.Key.foregroundColor: foregroundColor
		]))
		string.append(
			NSAttributedString(
				string: relationName ?? "",
				attributes: [
					NSAttributedString.Key.font: font,
					NSAttributedString.Key.link: "r" + (relationName ?? "")
				]))
		string.append(
			NSAttributedString(
				string: String.localizedStringWithFormat(
					NSLocalizedString(" (%d members)\n", comment: ""),
					memberCount),
				attributes: [
					NSAttributedString.Key.font: font,
					NSAttributedString.Key.foregroundColor: foregroundColor
				]))

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

	private static func update(_ string: NSMutableAttributedString, withHeader header: String, objects: [Any]?) {
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
				update(string, withNode: object)
			} else if object.name == "way" {
				update(string, withWay: object)
			} else if object.name == "relation" {
				update(string, withRelation: object)
			} else {
				assertionFailure()
			}
		}
	}

	/// Converts an XML document to an AttributedString suitable for the Upload view
	static func attributedStringForXML(_ doc: DDXMLDocument) -> NSAttributedString? {
		let string = NSMutableAttributedString()
		guard let root = doc.rootElement() else { return nil }

		let deletes = root.elements(forName: "delete")
		let creates = root.elements(forName: "create")
		let modifys = root.elements(forName: "modify")
		for delete in deletes {
			update(string, withHeader: NSLocalizedString("Delete\n", comment: ""), objects: delete.children)
		}
		for create in creates {
			update(string, withHeader: NSLocalizedString("Create\n", comment: ""), objects: create.children)
		}
		for modify in modifys {
			update(string, withHeader: NSLocalizedString("Modify\n", comment: ""), objects: modify.children)
		}
		return string
	}
}
