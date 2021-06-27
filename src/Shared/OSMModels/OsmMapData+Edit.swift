//
//  OsmMapData+Edit.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/9/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import CoreLocation
import UIKit

// MARK: Rectangularize

private var rectoLowerThreshold = 0.0
private var rectoUpperThreshold = 0.0

extension OsmMapData {
	// basic stuff:

	// MARK: canDeleteNode

	// Only for solitary nodes. Otherwise use delete node in way.
	func canDelete(_ node: OsmNode, error: inout String?) -> EditAction? {
		if node.wayCount > 0 || node.parentRelations.count > 0 {
			error = NSLocalizedString("Can't delete node that is part of a relation", comment: "")
			return nil
		}
		return {
			self.deleteNodeUnsafe(node)
		}
	}

	// MARK: canDeleteWay

	func canDelete(_ way: OsmWay, error: inout String?) -> EditAction? {
		if way.parentRelations.count > 0 {
			var ok = false
			if way.parentRelations.count == 1 {
				if let relation = way.parentRelations.last {
					if relation.isMultipolygon() {
						ok = true
					} else if relation.isRestriction() {
						// allow deleting if we're both from and to (u-turn)
						let from = relation.member(byRole: "from")
						let to = relation.member(byRole: "to")
						if from?.obj == way, to?.obj == way {
							return {
								self.deleteRelationUnsafe(relation)
								self.deleteWayUnsafe(way)
							}
						}
					}
				}
			}
			if !ok {
				error = NSLocalizedString("Can't delete way that is part of a Route or similar relation", comment: "")
				return nil
			}
		}

		return {
			self.deleteWayUnsafe(way)
		}
	}

	// MARK: canDeleteRelation

	func canDelete(_ relation: OsmRelation, error: inout String?) -> EditAction? {
		if relation.isMultipolygon() {
			// okay
		} else if relation.isRestriction() {
			// okay
		} else {
			error = NSLocalizedString("Can't delete relation that is not a multipolygon", comment: "")
			return nil
		}

		return {
			self.deleteRelationUnsafe(relation)
		}
	}

	// relations

	// MARK: canAddWayToRelation

	func canAdd(_ obj: OsmBaseObject, to relation: OsmRelation, withRole role: String?,
	            error: inout String?) -> EditAction?
	{
		var role = role

		if !relation.isMultipolygon() {
			error = NSLocalizedString("Only multipolygon relations are supported", comment: "")
			return nil
		}
		guard let newWay = obj.isWay() else {
			error = NSLocalizedString("Can only add ways to multipolygons", comment: "")
			return nil
		}

		// place the member adjacent to a way its connected to, if any
		var index = 0
		for m in relation.members {
			index += 1
			guard let w = m.obj as? OsmWay,
			      m.role == "inner" || m.role == "outer"
			else {
				continue
			}
			if newWay.connectsTo(way: w) != nil {
				if role != nil, role! != m.role {
					error = NSLocalizedString("Cannot connect an inner way to an outer way", comment: "")
					return nil
				}
				role = m.role // copy the role of the way it's connected to
				break
			}
		}

		if role == nil {
			error = NSLocalizedString("Unknown role", comment: "relation role=* tag")
			return nil
		}

		return { [self] in
			let newMember = OsmMember(obj: newWay, role: role)
			self.addMemberUnsafe(newMember, to: relation, at: index)
		}
	}

	// ways

	// MARK: canAddNodeToWay

	func canAddNode(to way: OsmWay, at index: Int, error: inout String?) -> EditActionWithNode? {
		if way.nodes.count >= 2, index == 0 || index == way.nodes.count {
			// we don't want to extend a way that is a portion of a route relation, polygon, etc.
			for relation in way.parentRelations {
				if relation.isRestriction() {
					// only permissible if extending from/to on the end away from the via node/ways
					let viaList = relation.members(byRole: "via")
					let prevNode = index != 0 ? way.nodes.last : way.nodes[0]
					// disallow extending any via way, or any way touching via node
					for viaMember in viaList {
						let via = viaMember.obj
						if let via = via {
							if let prevNode = prevNode {
								if via.isWay() != nil, via == way || (via.isWay()?.nodes.contains(prevNode) ?? false) {
									error = NSLocalizedString(
										"Extending a 'via' in a Turn Restriction will break the relation",
										comment: "")
									return nil
								}
							}
						} else {
							error = NSLocalizedString(
								"The way belongs to a relation that is not fully downloaded",
								comment: "")
							return nil
						}
					}
				} else {
					error = NSLocalizedString(
						"Extending a way which belongs to a Route or similar relation may damage the relation",
						comment: "")
					return nil
				}
			}
		}
		if way.nodes.count == 2000 {
			error = NSLocalizedString("Maximum way length is 2000 nodes", comment: "")
			return nil
		}

		return { [self] node in
			addNodeUnsafe(node, to: way, at: index)
		}
	}

	// MARK: canRemoveObject:fromRelation

	func canRemove(_ obj: OsmBaseObject, from relation: OsmRelation, error: inout String?) -> EditAction? {
		if !relation.isMultipolygon() {
			error = NSLocalizedString("Only multipolygon relations are supported", comment: "")
			return nil
		}
		return { [self] in
			for index in relation.members.count..<0 {
				let member = relation.members[index]
				if member.obj == obj {
					deleteMember(inRelationUnsafe: relation, index: index)
				}
			}
		}
	}

	// more complicated stuff:
	func canOrthogonalizeWay(_ way: OsmWay, error: inout String?) -> EditAction? {
		// needs a closed way to work properly.
		if !(way.isWay() != nil) || !way.isClosed() || way.nodes.count < 5 {
			error = NSLocalizedString("Requires a closed way with at least 4 nodes", comment: "")
			return nil
		}

#if false
		if squareness(points, count) == 0.0 {
			// already square
			return false
		}
#endif

		return { [self] in
			registerUndoCommentString(NSLocalizedString("Make Rectangular", comment: ""))

			let rectoThreshold = 12.0 // degrees within right or straight to alter
			rectoLowerThreshold = cos((90 - rectoThreshold) * .pi / 180)
			rectoUpperThreshold = cos(rectoThreshold * .pi / 180)

			var points = way.nodes.dropLast().map({
				OSMPoint(x: $0.latLon.lon, y: lat2latp($0.latLon.lat))
			})

			let epsilon = 1e-4

			if points.count == 3 {
				var score = 0.0
				var corner: Int = 0
				var dotp: Double = 1.0

				for _ in 0..<1000 {
					let motions = points.indices.map {
						calcMotion(points[$0], $0, points, &corner, &dotp)
					}
					points[corner] = Add(points[corner], motions[corner])
					score = dotp
					if score < epsilon {
						break
					}
				}

				// apply new position
				let node = way.nodes[corner]
				let latLon = LatLon(x: points[corner].x,
				                    y: latp2lat(points[corner].y))
				setLatLon(latLon, forNode: node)
			} else {
				let originalPoints = points
				var bestScore = 1e9
				var bestPoints: [OSMPoint] = []

				for step in 0..<1000 {
					var tempInt = 0
					var tempDouble = 0.0
					let motions = points.indices.map({
						calcMotion(points[$0], $0, points, &tempInt, &tempDouble)
					})
					for i in points.indices {
						if !motions[i].x.isNaN {
							points[i] = Add(points[i], motions[i])
						}
					}
					let newScore = squareness(points)
					if newScore < bestScore {
						bestPoints = points
						bestScore = newScore
					}
					if bestScore < epsilon {
						print("Straighten steps = \(step)")
						break
					}
				}

				points = bestPoints

				for i in way.nodes.indices {
					let modi = i < points.count ? i : 0
					let node = way.nodes[i]
					if !(points[modi] == originalPoints[modi]) {
						let latLon = LatLon(x: points[modi].x, y: latp2lat(points[modi].y))
						setLatLon(latLon, forNode: node)
					}
				}

				// remove empty nodes on straight sections
				// * deleting nodes that are referenced by non-downloaded ways could case data loss
				for i in points.indices.reversed() {
					let node = way.nodes[i]

					if node.wayCount > 1 || node.parentRelations.count > 0 || node.hasInterestingTags() {
						// skip
					} else {
						let dotp = normalizedDotProduct(i, points)
						if dotp < -1 + epsilon {
							var dummy: String?
							if let canDeleteNode = canDelete(node, from: way, error: &dummy) {
								canDeleteNode()
							} else {
								// oh well...
							}
						}
					}
				}
			}
		}
	}

	// MARK: canMergeNode:intoNode

	// used when dragging a node into another node
	func canMerge(_ node1: OsmNode, into node2: OsmNode, error: inout String?) -> EditActionReturnNode? {
		guard let mergedTags = OsmTags.Merge(
			ourTags: node1.tags,
			otherTags: node2.tags,
			allowConflicts: false)
		else {
			error = NSLocalizedString("The merged nodes contain conflicting tags", comment: "")
			return nil
		}

		let survivor: OsmNode
		if node1.ident < 0 {
			survivor = node2
		} else if node2.ident < 0 {
			survivor = node1
		} else if node1.wayCount > node2.wayCount {
			survivor = node1
		} else {
			survivor = node2
		}
		let deadNode = (survivor == node1) ? node2 : node1

		// if the nodes have different relation roles they can't merge

		// 1. disable if the nodes being connected have conflicting relation roles
		let nodes = [survivor, deadNode]
		var restrictions: [OsmRelation] = []
		var seen: [OsmIdentifier: String] = [:]
		for node in nodes {
			for relation in node.parentRelations {
				let member = relation.member(byRef: node)
				let role = member?.role

				// if this node is a via node in a restriction, remember for later
				if relation.isRestriction() {
					restrictions.append(relation)
				}

				if let prevRole = seen[relation.ident],
				   prevRole != role
				{
					error = NSLocalizedString("The nodes have conflicting roles in parent relations", comment: "")
					return nil
				} else {
					seen[relation.ident] = role
				}
			}
		}

		// gather restrictions for parent ways
		for node in nodes {
			let parents = waysContaining(node)
			for parent in parents {
				for relation in parent.parentRelations {
					if relation.isRestriction() {
						restrictions.append(relation)
					}
				}
			}
		}

		// test restrictions
		for relation in restrictions {
			var memberWays: [OsmWay] = []
			for member in relation.members {
				if member.isWay() {
					guard let memberObj = member.obj as? OsmWay else {
						error = NSLocalizedString("A relation the node belongs to is not fully downloaded", comment: "")
						return nil
					}
					memberWays.append(memberObj)
				}
			}

			let f = relation.member(byRole: "from")
			let t = relation.member(byRole: "to")
			let isUturn = f?.ref == t?.ref

			// 2a. disable if connection would damage a restriction (a key node is a node at the junction of ways)
			var collection: [String: Set<OsmNode>] = [:]
			var keyfrom: [OsmNode] = []
			var keyto: [OsmNode] = []
			for member in relation.members {
				let role = member.role ?? ""
				if member.isNode() {
					guard let node = member.obj as? OsmNode else {
						error = NSLocalizedString("A relation the node belongs to is not fully downloaded", comment: "")
						return nil
					}
					var c = collection[role] ?? Set<OsmNode>()
					c.insert(node)
					collection[role] = c
					if member.role == "via" {
						keyfrom.append(node)
						keyto.append(node)
					}
				} else if member.isWay() {
					guard let way = member.obj as? OsmWay,
					      way.nodes.count > 0
					else {
						error = NSLocalizedString("A relation the node belongs to is not fully downloaded", comment: "")
						return nil
					}
					var c = collection[role] ?? Set<OsmNode>()
					c.formUnion(way.nodes)
					collection[role] = c

					if (member.role == "from") || (member.role == "via") {
						keyfrom.append(way.nodes.first!)
						keyfrom.append(way.nodes.last!)
					}

					if (member.role == "to") || (member.role == "via") {
						keyto.append(way.nodes.first!)
						keyto.append(way.nodes.last!)
					}
				}
			}

			let filter = { node in
				!keyfrom.contains(node) && !keyto.contains(node)
			}
			let from = Array(collection["from"] ?? []).filter(filter)
			let to = Array(collection["to"] ?? []).filter(filter)
			let via = Array(collection["via"] ?? []).filter(filter)

			var connectFrom = false
			var connectVia = false
			var connectTo = false
			var connectKeyFrom = false
			var connectKeyTo = false

			for n in nodes {
				if from.contains(n) {
					connectFrom = true
				}
				if via.contains(n) {
					connectVia = true
				}
				if to.contains(n) {
					connectTo = true
				}
				if keyfrom.contains(n) {
					connectKeyFrom = true
				}
				if keyto.contains(n) {
					connectKeyTo = true
				}
			}
			if (connectFrom && connectTo && !isUturn) || (connectFrom && connectVia) || (connectTo && connectVia) {
				error = NSLocalizedString("Connecting the nodes would damage a relation", comment: "")
				return nil
			}

			// connecting to a key node -
			// if both nodes are on a member way (i.e. part of the turn restriction),
			// the connecting node must be adjacent to the key node.
			if connectKeyFrom || connectKeyTo {
				var n0: OsmNode?
				var n1: OsmNode?
				for way in memberWays {
					if way.nodes.contains(nodes[0]) {
						n0 = nodes[0]
					}
					if way.nodes.contains(nodes[1]) {
						n1 = nodes[1]
					}
				}

				if n0 != nil, n1 != nil {
					// both nodes are part of the restriction
					error = NSLocalizedString("Connecting the nodes would damage a relation", comment: "")
					return nil
				}
			}
		}

		return { [self] in
			if survivor == node1 {
				// update survivor to have location of other node
				setLatLon(node2.latLon, forNode: survivor)
			}

			setTags(mergedTags, for: survivor)

			// need to replace the node in all objects everywhere
			for (_, way) in ways {
				if way.nodes.contains(deadNode) {
					for index in 0..<way.nodes.count {
						if way.nodes[index] == deadNode {
							addNodeUnsafe(survivor, to: way, at: index)
							deleteNodeUnsafe(inWay: way, index: index + 1, preserveNode: false)
						}
					}
				}
			}

			for (_, relation) in relations {
				for index in 0..<relation.members.count {
					let member = relation.members[index]
					if member.obj == deadNode {
						let newMember = OsmMember(obj: survivor, role: member.role)
						addMemberUnsafe(newMember, to: relation, at: index + 1)
						deleteMember(inRelationUnsafe: relation, index: index)
					}
				}
			}
			deleteNodeUnsafe(deadNode)
			return survivor
		}
	}

	func canStraightenWay(_ way: OsmWay, error: inout String?) -> EditAction? {
		let count = way.nodes.count
		var points: [OSMPoint?] = way.nodes.map({ OSMPoint(x: $0.latLon.lon, y: lat2latp($0.latLon.lat)) })
		if count > 2 {
			let startPoint = points[0]!
			let endPoint = points[count - 1]!
			let threshold = 0.2 * startPoint.distanceToPoint(endPoint)
			for i in 1..<(count - 1) {
				let node = way.nodes[i]
				let point = points[i]!
				let u = positionAlongWay(point, startPoint, endPoint)
				let newPoint = Add(startPoint, Mult(Sub(endPoint, startPoint), u))

				let dist = newPoint.distanceToPoint(point)
				if dist > threshold {
					error = NSLocalizedString("The way is not sufficiently straight", comment: "")
					return nil
				}

				// if node is interesting then move it, otherwise delete it.
				if node.wayCount > 1 || node.parentRelations.count > 0 || node.hasInterestingTags() {
					points[i] = newPoint
				} else {
					// safe to delete
					points[i] = nil
				}
			}
		}

		return { [self] in
			registerUndoCommentString(NSLocalizedString("Straighten", comment: ""))

			var i = count - 1
			while i >= 0 {
				if let point = points[i] {
					// update position
					let node = way.nodes[i]
					let latLon = LatLon(x: point.x,
					                    y: latp2lat(point.y))
					setLatLon(latLon, forNode: node)
				} else {
					// remove point
					let node = way.nodes[i]
					var dummy: String?
					if let canDelete = self.canDelete(node, from: way, error: &dummy) {
						canDelete()
					} else {
						// no big deal
					}
				}
				i -= 1
			}
		}
	}

	func canReverse(_ way: OsmWay, error: inout String?) -> EditAction? {
		let roleReversals = [
			"forward": "backward",
			"backward": "forward",
			"north": "south",
			"south": "north",
			"east": "west",
			"west": "east"
		]
		let nodeReversals = [
			"forward": "backward",
			"backward": "forward"
		]

		return { [self] in
			registerUndoCommentString(NSLocalizedString("Reverse", comment: ""))

			// reverse nodes
			let newNodes = Array(way.nodes.reversed())
			for i in 0..<newNodes.count {
				addNodeUnsafe(newNodes[i], to: way, at: i)
			}

			while way.nodes.count > newNodes.count {
				deleteNodeUnsafe(inWay: way, index: way.nodes.count - 1, preserveNode: false)
			}

			// reverse tags on way
			var newWayTags: [String: String] = [:]
			for (key, value) in way.tags {
				var k = key
				var v = value
				k = reverseKey(key)
				v = reverseValue(key, value)
				newWayTags[k] = v
			}
			setTags(newWayTags, for: way)

			// reverse direction tags on nodes in way
			for node in way.nodes {
				let value = node.tags["direction"]
				let replacement = nodeReversals[value ?? ""]
				if replacement != "" {
					var nodeTags = node.tags
					nodeTags["direction"] = replacement
					setTags(nodeTags, for: node)
				}
			}

			// reverse roles in relations the way belongs to
			for relation in way.parentRelations {
				for member in relation.members {
					if member.obj == way,
					   let role = member.role,
					   let newRole = roleReversals[role],
					   let index = relation.members.firstIndex(of: member)
					{
						let newMember = OsmMember(obj: way, role: newRole)
						deleteMember(inRelationUnsafe: relation, index: index)
						addMemberUnsafe(newMember, to: relation, at: index)
					}
				}
			}
		}
	}

	// MARK: deleteNodeFromWay

	func canDisconnectOrDelete(_ node: OsmNode, in way: OsmWay, isDelete: Bool, error: inout String?) -> Bool {
		// only care if node is an endpoiont
		if node == way.nodes.first || node == way.nodes.last {
			// we don't want to truncate a way that is a portion of a route relation, polygon, etc.
			for relation in way.parentRelations {
				if relation.isRestriction() {
					for member in relation.members {
						if member.obj == nil {
							error = NSLocalizedString(
								"The way belongs to a relation that is not fully downloaded",
								comment: "")
							return false
						}
					}

					// only permissible if deleting interior node of via, or non-via node in from/to
					let viaList = relation.members(byRole: "via")
					let from = relation.member(byRole: "from")
					let to = relation.member(byRole: "to")
					if from?.obj == way || to?.obj == way {
						if isDelete, way.nodes.count <= 2 {
							error = NSLocalizedString("Can't remove Turn Restriction to/from way", comment: "")
							return false // deleting node will cause degenerate way
						}
						for viaMember in viaList {
							if viaMember.obj == node {
								error = NSLocalizedString("Can't remove Turn Restriction 'via' node", comment: "")
								return false
							} else {
								if let viaObject = viaMember.obj,
								   let common = viaObject.isWay()?.connectsTo(way: way)
								{
									if common.isNode() == node {
										// deleting the node that connects from/to and via
										error = NSLocalizedString(
											"Can't remove Turn Restriction node connecting 'to'/'from' to 'via'",
											comment: "")
										return false
									}
								}
							}
						}
					}

					// disallow deleting an endpoint of any via way, or a via node itself
					for viaMember in viaList {
						if viaMember.obj == way {
							// can't delete an endpoint of a via way
							error = NSLocalizedString("Can't remove node in Turn Restriction 'via' way", comment: "")
							return false
						}
					}
				} else if relation.isMultipolygon() {
					// okay
				} else {
					// don't allow deleting an endpoint node of routes, etc.
					error = NSLocalizedString("Can't remove component of a Route or similar relation", comment: "")
					return false
				}
			}
		}
		return true
	}

	func canDelete(_ node: OsmNode, from way: OsmWay, error: inout String?) -> EditAction? {
		if !canDisconnectOrDelete(node, in: way, isDelete: true, error: &error) {
			return nil
		}

		return { [self] in
			let needAreaFixup = way.nodes.last == node && way.nodes.first == node
			while let index = way.nodes.firstIndex(of: node) {
				deleteNodeUnsafe(inWay: way, index: index, preserveNode: false)
			}
			if way.nodes.count < 2 {
				var dummy: String?
				if let delete = canDelete(way, error: &dummy) {
					delete() // this will also delete any relations the way belongs to
				} else {
					deleteWayUnsafe(way)
				}
			} else if needAreaFixup {
				// special case where deleted node is first & last node of an area
				addNodeUnsafe(way.nodes.first!, to: way, at: way.nodes.count)
			}
			updateParentMultipolygonRelationRoles(for: way)
		}
	}

	// MARK: disconnectWayAtNode

	// disconnect all other ways from the selected way joined to it at node
	// if the node doesn't belong to any other ways then it's a self-intersection
	func canDisconnectWay(_ way: OsmWay, at node: OsmNode, error: inout String?) -> EditActionReturnNode? {
		if !way.nodes.contains(node) {
			error = NSLocalizedString("Node is not an element of way", comment: "")
			return nil
		}
		if node.wayCount < 2 {
			error = NSLocalizedString("The way must have at least 2 nodes", comment: "")
			return nil
		}

		if !canDisconnectOrDelete(node, in: way, isDelete: false, error: &error) {
			return nil
		}

		return { [self] in
			registerUndoCommentString(NSLocalizedString("Disconnect", comment: ""))

			let loc = node.latLon
			let newNode = createNode(atLocation: loc)
			setTags(node.tags, for: newNode)

			if waysContaining(node).count > 1 {
				// detach node from other ways containing it
				while let index = way.nodes.firstIndex(of: node) {
					addNodeUnsafe(newNode, to: way, at: index + 1)
					deleteNodeUnsafe(inWay: way, index: index, preserveNode: false)
				}
			} else {
				// detach node from self-intersection
				if let index = way.nodes.firstIndex(of: node) {
					addNodeUnsafe(newNode, to: way, at: index + 1)
					deleteNodeUnsafe(inWay: way, index: index, preserveNode: false)
				}
			}
			return newNode
		}
	}

	// returns the new other half
	func canSplitWay(_ selectedWay: OsmWay, at node: OsmNode, error: inout String?) -> EditActionReturnWay? {
		return { [self] in
			registerUndoCommentString(NSLocalizedString("Split", comment: ""))
			let wayA = selectedWay
			let wayB = createWay()
			setTags(wayA.tags, for: wayB)

			let wayIsOuter = (wayA.isSimpleMultipolygonOuterMember() ? wayA.parentRelations
				.last : nil) // only 1 parent relation if it is simple

			if wayA.isClosed() {
				// remove duplicated node
				deleteNodeUnsafe(inWay: wayA, index: wayA.nodes.count - 1, preserveNode: false)

				// get segment indices
				let idxA = wayA.nodes.firstIndex(of: node)!
				let idxB = splitArea(wayA.nodes, idxA)

				// build new way
				var i = idxB
				while i != idxA {
					addNodeUnsafe(wayA.nodes[i], to: wayB, at: wayB.nodes.count)
					i = (i + 1) % wayA.nodes.count
				}

				// delete moved nodes from original way
				for n in wayB.nodes {
					let i = wayA.nodes.firstIndex(of: n)!
					deleteNodeUnsafe(inWay: wayA, index: i, preserveNode: false)
				}

				// rebase A so it starts with selected node
				while wayA.nodes.first != node {
					addNodeUnsafe(wayA.nodes.first!, to: wayA, at: wayA.nodes.count)
					deleteNodeUnsafe(inWay: wayA, index: 0, preserveNode: false)
				}

				// add shared endpoints
				addNodeUnsafe(wayB.nodes.first!, to: wayA, at: wayA.nodes.count)
				addNodeUnsafe(wayA.nodes.first!, to: wayB, at: wayB.nodes.count)
			} else {
				// place common node in new way
				addNodeUnsafe(node, to: wayB, at: 0)

				// move remaining nodes to 2nd way
				let idx = wayA.nodes.firstIndex(of: node)! + 1
				while idx < wayA.nodes.count {
					addNodeUnsafe(wayA.nodes[idx], to: wayB, at: wayB.nodes.count)
					deleteNodeUnsafe(inWay: wayA, index: idx, preserveNode: false)
				}
			}

			// get a unique set of parent relations (de-duplicate)
			let relations = Set<OsmRelation>(wayA.parentRelations)

			// fix parent relations
			for relation in relations {
				if relation.isRestriction() {
					let f = relation.member(byRole: "from")
					let v = relation.members(byRole: "via")
					let t = relation.member(byRole: "to")

					if f?.obj == wayA || t?.obj == wayA {
						// 1. split a FROM/TO
						var keepB = false
						for member in v {
							guard let via = member.obj else {
								continue
							}
							if let isNode = via.isNode() {
								if wayB.nodes.contains(isNode) {
									keepB = true
									break
								} else if via.isWay() != nil, (via.isWay()?.connectsTo(way: wayB)) != nil {
									keepB = true
									break
								}
							}
						}

						if keepB {
							// replace member(s) referencing A with B
							for index in 0..<relation.members.count {
								let memberA = relation.members[index]
								if memberA.obj == wayA {
									let memberB = OsmMember(obj: wayB, role: memberA.role)
									addMemberUnsafe(memberB, to: relation, at: index + 1)
									deleteMember(inRelationUnsafe: relation, index: index)
								}
							}
						}
					} else {
						// 2. split a VIA
						var prevWay = f?.obj
						for index in 0..<relation.members.count {
							let memberA = relation.members[index]
							if memberA.role == "via" {
								if memberA.obj == wayA {
									let memberB = OsmMember(obj: wayB, role: memberA.role)
									if let prevWay = prevWay as? OsmWay {
										let insertBefore = (wayB.connectsTo(way: prevWay) != nil) && true
										addMemberUnsafe(memberB, to: relation, at: insertBefore ? index : index + 1)
										break
									}
								}
								prevWay = memberA.obj
							}
						}
					}
				} else {
					// All other relations (Routes, Multipolygons, etc):
					// 1. Both `wayA` and `wayB` remain in the relation
					// 2. But must be inserted as a pair

					if relation == wayIsOuter {
						if let merged = OsmTags.Merge(
							ourTags: relation.tags,
							otherTags: wayA.tags,
							allowConflicts: true)
						{
							setTags(merged, for: relation)
							setTags([:], for: wayA)
							setTags([:], for: wayB)
						}
					}

					// if this is a route relation we want to add the new member in such a way that the route maintains a consecutive sequence of ways
					var prevWay: OsmWay?
					var index = 0
					for member in relation.members {
						if member.obj == wayA {
							let insertBefore = (prevWay != nil) && ((prevWay?.isWay()?.connectsTo(way: wayB)) != nil)
							let newMember = OsmMember(obj: wayB, role: member.role)
							addMemberUnsafe(newMember, to: relation, at: insertBefore ? index : index + 1)
							break
						}
						prevWay = member.obj as? OsmWay
						index += 1
					}
				}
			}

			return wayB
		}
	}

	// MARK: Turn-restriction relations

	func updateTurnRestrictionRelation(_ restriction: OsmRelation?, via viaNode: OsmNode,
	                                   from fromWay: OsmWay, fromWayNode: OsmNode,
	                                   to toWay: OsmWay, toWayNode: OsmNode,
	                                   turn strTurn: String,
	                                   newWays resultWays: inout [OsmWay],
	                                   willSplit requiresSplitting: ((_ splitWays: [OsmWay]) -> Bool)?) -> OsmRelation?
	{
		if !fromWay.nodes.contains(viaNode) ||
			!fromWay.nodes.contains(fromWayNode) ||
			!toWay.nodes.contains(viaNode) ||
			!toWay.nodes.contains(toWayNode) ||
			viaNode == fromWayNode ||
			viaNode == toWayNode
		{
			// error
			return nil
		}

		// find ways that need to be split
		var splits: [OsmWay] = []
		let list = (fromWay == toWay) ? [fromWay] : [fromWay, toWay]
		for way in list {
			var split = false
			if way.isClosed() {
				split = true
			} else if way.nodes.first != viaNode, way.nodes.last != viaNode {
				split = true
			}
			if split {
				splits.append(way)
			}
		}
		if let requiresSplitting = requiresSplitting,
		   splits.count > 0,
		   !requiresSplitting(splits)
		{
			return nil
		}

		// get all necessary splits
		var splitFuncs: [EditActionReturnWay] = []
		for way in splits {
			var error: String?
			guard let split = canSplitWay(way, at: viaNode, error: &error) else {
				return nil
			}
			splitFuncs.append(split)
		}

		registerUndoCommentString(NSLocalizedString("create turn restriction", comment: ""))

		var fromWay = fromWay
		var toWay = toWay

		var newWays: [OsmWay] = []
		for i in splitFuncs.indices {
			let way = splits[i]
			let newWay = splitFuncs[i]()
			if way == fromWay, newWay.nodes.contains(fromWayNode) {
				fromWay = newWay
			}
			if way == toWay, newWay.nodes.contains(toWayNode) {
				toWay = newWay
			}
			newWays[i] = newWay
		}

		var restriction = restriction
		if restriction == nil {
			restriction = createRelation()
		} else {
			while restriction!.members.count > 0 {
				deleteMember(inRelationUnsafe: restriction!, index: 0)
			}
		}

		var tags: [String: String] = [:]
		tags["type"] = "restriction"
		tags["restriction"] = strTurn
		setTags(tags, for: restriction!)

		let fromM = OsmMember(obj: fromWay, role: "from")
		let viaM = OsmMember(obj: viaNode, role: "via")
		let toM = OsmMember(obj: toWay, role: "to")

		addMemberUnsafe(fromM, to: restriction!, at: 0)
		addMemberUnsafe(viaM, to: restriction!, at: 1)
		addMemberUnsafe(toM, to: restriction!, at: 2)

		resultWays = newWays

		return restriction
	}

	// MARK: joinWay

	func canJoin(_ selectedWay: OsmWay, at selectedNode: OsmNode, error: inout String?) -> EditAction? {
		if selectedWay.nodes.first != selectedNode, selectedWay.nodes.last != selectedNode {
			error = NSLocalizedString("Node must be the first or last node of the way", comment: "")
			return nil // must be endpoint node
		}

		let ways = waysContaining(selectedNode)
		var otherWays: [OsmWay] = []
		var otherMatchingTags: [OsmWay] = []
		for way in ways {
			if way == selectedWay {
				continue
			}
			if way.nodes.first == selectedNode || way.nodes.last == selectedNode {
				if way.tags == selectedWay.tags {
					otherMatchingTags.append(way)
				} else {
					otherWays.append(way)
				}
			}
		}
		if otherMatchingTags.count != 0 {
			otherWays = otherMatchingTags
		}
		if otherWays.count > 1 {
			// ambigious connection
			error = NSLocalizedString("The target way is ambiguous", comment: "")
			return nil
		} else if otherWays.count == 0 {
			error = NSLocalizedString("Missing way to connect to", comment: "")
			return nil
		}

		guard let otherWay = otherWays.first else { return nil }
		if (otherWay.nodes.count + selectedWay.nodes.count) > 2000 {
			error = NSLocalizedString("Max nodes after joining is 2000", comment: "")
			return nil
		}

		var relations = Set<OsmRelation>(selectedWay.parentRelations)
		relations = relations.intersection(Set<OsmRelation>(otherWay.parentRelations))
		for relation in relations {
			// both belong to relation
			if relation.isRestriction() {
				// joining is only okay if both belong to via
				let viaList = relation.members(byRole: "via")
				var foundSet = 0
				for member in viaList {
					if member.obj == selectedWay {
						foundSet |= 1
					}
					if member.obj == otherWay {
						foundSet |= 2
					}
				}
				if foundSet != 3 {
					error = NSLocalizedString(
						"Joining would invalidate a Turn Restriction the way belongs to",
						comment: "")
					return nil
				}
			}
			// route or polygon, so should be okay
		}

		// check if extending the way would break something
		var loc = selectedWay.nodes.firstIndex(of: selectedNode) ?? 0
		if canAddNode(to: selectedWay, at: loc > 0 ? loc : loc + 1, error: &error) == nil {
			return nil
		}
		loc = otherWay.nodes.firstIndex(of: selectedNode) ?? 0
		if canAddNode(to: otherWay, at: loc > 0 ? loc : loc + 1, error: &error) == nil {
			return nil
		}

		let newTags = OsmTags.Merge(ourTags: selectedWay.tags, otherTags: otherWay.tags, allowConflicts: false)
		if newTags == nil {
			// tag conflict
			error = NSLocalizedString("The ways contain incompatible tags", comment: "")
			return nil
		}

		return { [self] in

			// join nodes, preserving selected way
			var index = 0
			var dummy: String?
			if selectedWay.nodes.last == otherWay.nodes[0] {
				registerUndoCommentString(NSLocalizedString("Join", comment: ""))
				for n in otherWay.nodes {
					if index == 0 {
						continue
					}
					index += 1
					addNodeUnsafe(n, to: selectedWay, at: selectedWay.nodes.count)
				}
			} else if selectedWay.nodes.last == otherWay.nodes.last {
				registerUndoCommentString(NSLocalizedString("Join", comment: ""))
				if let reverse = canReverse(otherWay, error: &dummy) { // reverse the tags on other way
					reverse()
				}
				for n in otherWay.nodes {
					if index == 0 {
						continue
					}
					index += 1
					addNodeUnsafe(n, to: selectedWay, at: selectedWay.nodes.count)
				}
			} else if selectedWay.nodes[0] == otherWay.nodes[0] {
				registerUndoCommentString(NSLocalizedString("Join", comment: ""))
				if let reverse = canReverse(otherWay, error: &dummy) { // reverse the tags on other way
					reverse()
				}
				for n in otherWay.nodes.reversed() {
					if index == 0 {
						continue
					}
					index += 1
					addNodeUnsafe(n, to: selectedWay, at: 0)
				}
			} else if selectedWay.nodes[0] == otherWay.nodes.last {
				registerUndoCommentString(NSLocalizedString("Join", comment: ""))
				for n in otherWay.nodes.reversed() {
					if index == 0 {
						continue
					}
					index += 1
					addNodeUnsafe(n, to: selectedWay, at: 0)
				}
			} else {
				DbgAssert(false)
				return // never happens
			}

			// join tags
			setTags(newTags!, for: selectedWay)

			deleteWayUnsafe(otherWay)
			updateParentMultipolygonRelationRoles(for: selectedWay)
		}
	}

	func canCircularizeWay(_ way: OsmWay, error: inout String?) -> EditAction? {
		if !(way.isWay() != nil) || !way.isClosed() || way.nodes.count < 4 {
			error = NSLocalizedString("Requires a closed way with at least 3 nodes", comment: "")
			return nil
		}

		func insertNode(in way: OsmWay, withCenter center: LatLon, angle: Double, radius: Double, atIndex index: Int) {
			let point = LatLon(latitude: latp2lat(center.lat + cos(angle * .pi / 180) * radius),
			                   longitude: center.lon + sin(angle * .pi / 180) * radius)
			let node = createNode(atLocation: point)
			addNodeUnsafe(node, to: way, at: index)
		}

		return { [self] in
			var center = way.centerPoint()
			center.lat = lat2latp(center.lat)
			let radius = AverageDistanceToCenter(way, center)

			for n in way.nodes.dropLast() {
				let c = hypot(n.latLon.lon - center.lon,
				              lat2latp(n.latLon.lat) - center.lat)
				let lat = latp2lat(center.lat + (lat2latp(n.latLon.lat) - center.lat) / c * radius)
				let lon = center.lon + (n.latLon.lon - center.lon) / c * radius
				let latLon = LatLon(x: lon, y: lat)
				setLatLon(latLon, forNode: n)
			}

			// Insert extra nodes to make circle
			// clockwise: angles decrease, wrapping round from -170 to 170
			let clockwise = way.isClockwise()
			var i = 0
			while i < way.nodes.count { // number of nodes is mutated inside the loop
				var j = (i + 1) % way.nodes.count

				let n1 = way.nodes[i]
				let n2 = way.nodes[j]

				var a1 = atan2(n1.latLon.lon - center.lon, lat2latp(n1.latLon.lat) - center.lat) * (180 / .pi)
				var a2 = atan2(n2.latLon.lon - center.lon, lat2latp(n2.latLon.lat) - center.lat) * (180 / .pi)
				if clockwise {
					if a2 > a1 {
						a2 -= 360
					}
					let diff = a1 - a2
					if diff > 20 {
						var ang = a1 - 20
						while ang > a2 + 10 {
							insertNode(in: way, withCenter: center, angle: ang, radius: radius, atIndex: i + 1)
							j += 1
							i += 1
							ang -= 20
						}
					}
				} else {
					if a1 > a2 {
						a1 -= 360
					}
					let diff = a2 - a1
					if diff > 20 {
						var ang = a1 + 20
						while ang < a2 - 10 {
							insertNode(in: way, withCenter: center, angle: ang, radius: radius, atIndex: i + 1)
							j += 1
							i += 1
							ang += 20
						}
					}
				}
				i += 1
			}
		}
	}

	// MARK: Duplicate

	func duplicateNode(_ node: OsmNode, withOffset offset: OSMPoint) -> OsmNode {
		let loc = LatLon(latitude: node.latLon.lat + offset.y,
		                 longitude: node.latLon.lon + offset.x)
		let newNode = createNode(atLocation: loc)
		setTags(node.tags, for: newNode)
		return newNode
	}

	func duplicateWay(_ way: OsmWay, withOffset offset: OSMPoint) -> OsmWay {
		let newWay = createWay()
		for index in way.nodes.indices {
			let node = way.nodes[index]
			// check if node is a duplicate of previous node
			let prev = way.nodes.firstIndex(where: { $0 == node }) ?? index
			let newNode = prev < index ? newWay.nodes[prev] : duplicateNode(node, withOffset: offset)
			addNodeUnsafe(newNode, to: newWay, at: index)
		}
		setTags(way.tags, for: newWay)
		return newWay
	}

	func duplicate(_ object: OsmBaseObject, withOffset offset: OSMPoint) -> OsmBaseObject? {
		let comment = NSLocalizedString("duplicate", comment: "create a duplicate")
		if object.isNode() != nil {
			registerUndoCommentString(comment)
			return duplicateNode(object.isNode()!, withOffset: offset)
		} else if object.isWay() != nil {
			registerUndoCommentString(comment)
			return duplicateWay(object.isWay()!, withOffset: offset)
		} else if object.isRelation()?.isMultipolygon() ?? false {
			registerUndoCommentString(comment)
			let newRelation = createRelation()
			if let members = object.isRelation()?.members {
				for member in members {
					if let way = member.obj as? OsmWay {
						var newWay: OsmWay?
						for prev in 0..<newRelation.members.count {
							let m = object.isRelation()?.members[prev]
							if m?.obj == way {
								// way is duplicated
								newWay = newRelation.members[prev].obj as? OsmWay
								break
							}
						}
						if newWay == nil {
							newWay = duplicateWay(way, withOffset: offset)
						}
						let newMember = OsmMember(obj: newWay!, role: member.role)
						newRelation.addMember(newMember, atIndex: newRelation.members.count, undo: undoManager)
					}
				}
			}
			setTags(object.tags, for: newRelation)
			return newRelation
		}
		return nil
	}

	// MARK: straightenWay

	private func positionAlongWay(_ node: OSMPoint, _ start: OSMPoint, _ end: OSMPoint) -> Double {
		return ((node.x - start.x) * (end.x - start.x) + (node.y - start.y) * (end.y - start.y)) /
			MagSquared(Sub(end, start))
	}

	// MARK: reverseWay

	func reverseKey(_ key: String) -> String {
		let replacements = [
			":right": ":left",
			":left": ":right",
			":forward": ":backward",
			":backward": ":forward"
		]
		var newKey = key
		for (k, v) in replacements {
			if key.hasSuffix(k) {
				newKey = newKey.replacingOccurrences(of: k, with: v, options: .backwards, range: nil)
			}
		}
		return newKey
	}

	static var isNumericRegex: NSRegularExpression?

	private func isNumeric(_ s: String) -> Bool {
		if OsmMapData.isNumericRegex == nil {
			let numeric = "^[+\\-]?[\\d.]"
			do {
				OsmMapData.isNumericRegex = try NSRegularExpression(pattern: numeric, options: .caseInsensitive)
			} catch {}
		}
		let r = OsmMapData.isNumericRegex?.rangeOfFirstMatch(
			in: s,
			options: [],
			range: NSRange(location: 0, length: s.count))
		return (r?.length ?? 0) > 0
	}

	func reverseValue(_ key: String, _ value: String) -> String {
		if (key == "incline") && isNumeric(value) {
			let ch = value[value.startIndex]
			if ch == "-" {
				return String(value.dropFirst())
			} else if ch == "+" {
				return "-\(value.dropFirst())"
			} else {
				return "-\(value)"
			}
		} else if (key == "incline") || (key == "direction") {
			if value == "up" {
				return "down"
			}
			if value == "down" {
				return "up"
			}
			return value
		} else {
			if value == "left" {
				return "right"
			}
			if value == "right" {
				return "left"
			}
			return value
		}
	}

	// MARK: updateMultipolygonRelationRoles

	func updateMultipolygonRelationRoles(_ relation: OsmRelation) {
		if !relation.isMultipolygon() {
			return
		}

		var isComplete: ObjCBool = false
		var members = relation.members

		let loopList = OsmRelation.buildMultipolygonFromMembers(members, repairing: false, isComplete: &isComplete)

		if !isComplete.boolValue {
			return
		}

		var innerSet: [OsmMember] = []
		for loop in loopList {
			var refPoint = OSMPoint.zero
			guard let path = OsmWay.shapePath(forNodes: loop, forward: true, withRefPoint: &refPoint)
			else {
				continue
			}
			for m in 0..<members.count {
				let member = members[m]
				guard let way = member.obj as? OsmWay else { continue }
				if way.nodes.count == 0 {
					continue
				}
				let node = way.nodes.last
				if let node = node {
					if loop.contains(node) {
						// This way is part of the loop being checked against
						continue
					}
				}
				let PATH_SCALING: Double = 0.0
				var pt = MapTransform.mapPoint(forLatLon: node!.latLon)
				pt = Sub(pt, refPoint)
				pt = Mult(pt, PATH_SCALING)
				let isInner = path.contains(CGPoint(pt), using: .winding)
				if isInner {
					innerSet.append(member)
				}
			}
		}
		// update roles if necessary
		var changed = false
		for m in 0..<members.count {
			let member = members[m]
			if let obj = member.obj {
				if innerSet.contains(member) {
					if member.role != "inner" {
						members[m] = OsmMember(obj: obj, role: "inner")
						changed = true
					}
				} else {
					if member.role != "outer" {
						members[m] = OsmMember(obj: obj, role: "outer")
						changed = true
					}
				}
			}
		}
		if changed {
			updateMembersUnsafe(members, in: relation)
		}
	}

	func updateParentMultipolygonRelationRoles(for way: OsmWay) {
		for relation in way.parentRelations {
			// might have moved an inner outside a multipolygon
			updateMultipolygonRelationRoles(relation)
		}
	}

	// MARK: splitWayAtNode

	// if the way is closed, we need to search for a partner node
	// to split the way at.
	//
	// The following looks for a node that is both far away from
	// the initial node in terms of way segment length and nearby
	// in terms of beeline-distance. This assures that areas get
	// split on the most "natural" points (independent of the number
	// of nodes).
	// For example: bone-shaped areas get split across their waist
	// line, circles across the diameter.
	private func splitArea(_ nodes: [OsmNode], _ idxA: Int) -> Int {
		let count = nodes.count
		var lengths = [Double](repeating: 0.0, count: count)
		var best: Double = 0
		var idxB = 0

		assert(idxA >= 0 && idxA < count)

		// calculate lengths
		var length: Double = 0
		var i = (idxA + 1) % count
		while i != idxA {
			let n1 = nodes[i]
			let n2 = nodes[(i - 1 + count) % count]
			length += n1.location().distanceToPoint(n2.location())
			lengths[i] = length
			i = (i + 1) % count
		}
		lengths[idxA] = 0.0 // never used, but need it to convince static analyzer that it isn't an unitialized variable
		length = 0
		i = (idxA - 1 + count) % count
		while i != idxA {
			let n1 = nodes[i]
			let n2 = nodes[(i + 1) % count]
			length += n1.location().distanceToPoint(n2.location())
			if length < lengths[i] {
				lengths[i] = length
			}
			i = (i - 1 + count) % count
		}

		// determine best opposite node to split
		for i in 0..<count {
			if i == idxA {
				continue
			}
			let n1 = nodes[idxA]
			let n2 = nodes[i]
			let cost = lengths[i] / n1.location().distanceToPoint(n2.location())
			if cost > best {
				idxB = i
				best = cost
			}
		}

		return idxB
	}

	// MARK: Circularize

	private func AverageDistanceToCenter(_ way: OsmWay, _ center: LatLon) -> Double {
		var d: Double = 0
		for i in 0..<(way.nodes.count - 1) {
			let n = way.nodes[i]
			d += hypot(n.latLon.lon - center.lon,
			           lat2latp(n.latLon.lat) - center.lat)
		}
		d /= Double(way.nodes.count - 1)
		return d
	}

	private func filterDotProduct(_ dotp: Double) -> Double {
		if rectoLowerThreshold > abs(dotp) || abs(dotp) > rectoUpperThreshold {
			return dotp
		}
		return 0.0
	}

	private func normalizedDotProduct(_ i: Int, _ points: [OSMPoint]) -> Double {
		let a = points[(i - 1 + points.count) % points.count]
		let b = points[i]
		let c = points[(i + 1) % points.count]
		var p = Sub(a, b)
		var q = Sub(c, b)

		p = p.unitVector()
		q = q.unitVector()

		return Dot(p, q)
	}

	private func squareness(_ points: [OSMPoint]) -> Double {
		var sum = 0.0
		for i in points.indices {
			var dotp = normalizedDotProduct(i, points)
			dotp = filterDotProduct(dotp)
			sum += 2.0 * min(abs(dotp - 1.0), min(abs(dotp), abs(dotp + 1.0)))
		}
		return sum
	}

	private func calcMotion(_ b: OSMPoint, _ i: Int, _ array: [OSMPoint], _ pCorner: inout Int,
	                        _ pDotp: inout Double) -> OSMPoint
	{
		let a = array[(i - 1 + array.count) % array.count]
		let c = array[(i + 1) % array.count]
		var p = Sub(a, b)
		var q = Sub(c, b)

		let origin = OSMPoint.zero
		let scale: Double = 2 * min(p.distanceToPoint(origin), q.distanceToPoint(origin))
		p = p.unitVector()
		q = q.unitVector()

		if p.x.isNaN || q.x.isNaN {
			if pDotp != 0 {
				pDotp = 1.0
			}
			return OSMPoint(x: 0, y: 0)
		}

		var dotp = filterDotProduct(Dot(p, q))

		// nasty hack to deal with almost-straight segments (angle is closer to 180 than to 90/270).
		if array.count > 3 {
			if dotp < -0.707106781186547 {
				// -sin(PI/4)
				dotp += 1.0
			}
		} else {
			// for triangles save the best corner
			if dotp != 0.0, pDotp != 0, abs(Float(dotp)) < Float(pDotp) {
				pCorner = i
				pDotp = Double(abs(Float(dotp)))
			}
		}

		var r = Add(p, q).unitVector()
		r = Mult(r, 0.1 * dotp * scale)
		return r
	}
}
