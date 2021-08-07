//
//  EditorMapLayer+Edit.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/3/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

extension EditorMapLayer {
	func undo() {
		mapData.undo()
		setNeedsLayout()
	}

	func redo() {
		mapData.redo()
		setNeedsLayout()
	}

	// MARK: Copy/Paste

	private var copyPasteTags: [String: String] {
		get { return UserDefaults.standard.object(forKey: "copyPasteTags") as? [String: String] ?? [:] }
		set { UserDefaults.standard.set(newValue, forKey: "copyPasteTags") }
	}

	func copyTags(_ object: OsmBaseObject) -> Bool {
		guard object.tags.count > 0 else { return false }
		copyPasteTags = object.tags
		return true
	}

	func canPasteTags() -> Bool {
		return copyPasteTags.count > 0
	}

	private func pasteTagsMerge(_ object: OsmBaseObject) {
		// Merge tags
		let newTags = OsmTags.Merge(ourTags: object.tags, otherTags: copyPasteTags, allowConflicts: true)!
		mapData.setTags(newTags, for: object)
		setNeedsLayout()
		owner.didUpdateObject()
	}

	private func pasteTagsReplace(_ object: OsmBaseObject) {
		// Replace all tags
		mapData.setTags(copyPasteTags, for: object)
		setNeedsLayout()
		owner.didUpdateObject()
	}

	/// Offers the option to either merge tags or replace them with the copied tags.
	func pasteTags() {
		let copyPasteTags = self.copyPasteTags
		guard let selectedPrimary = self.selectedPrimary else { return }
		guard copyPasteTags.count > 0 else {
			owner.showAlert(NSLocalizedString("No tags to paste", comment: ""), message: nil)
			return
		}

		if selectedPrimary.tags.count > 0 {
			let question = String.localizedStringWithFormat(
				NSLocalizedString("Pasting %ld tag(s)", comment: ""),
				copyPasteTags.count)
			let alertPaste = UIAlertController(
				title: NSLocalizedString("Paste", comment: ""),
				message: question,
				preferredStyle: .alert)
			alertPaste
				.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
			alertPaste
				.addAction(UIAlertAction(title: NSLocalizedString("Merge Tags", comment: ""),
				                         style: .default, handler: { [self] _ in
				                         	self.pasteTagsMerge(selectedPrimary)
				                         }))
			alertPaste
				.addAction(UIAlertAction(title: NSLocalizedString("Replace Tags", comment: ""), style: .default,
				                         handler: { [self] _ in
				                         	self.pasteTagsReplace(selectedPrimary)
				                         }))
			owner.presentAlert(alert: alertPaste, location: .none)
		} else {
			pasteTagsReplace(selectedPrimary)
		}
	}

	/// Called by the tag editor when user finally commits changes.
	/// This method creates a node at the pushpin if there is nothing selected.
	func setTagsForCurrentObject(_ tags: [String: String]) {
		if let selectedPrimary = self.selectedPrimary {
			// update current object
			mapData.setTags(tags, for: selectedPrimary)
			owner.didUpdateObject()
		} else {
			// create new object
			guard let pushpin = owner.pushpinView() else {
				// shouldn't ever happen but there have been a few crashes so it does
				return
			}
			let point = pushpin.arrowPoint
			let node = createNode(atScreenPoint: point)
			mapData.setTags(tags, for: node)
			selectedNode = node
			// create new pushpin for new object
			owner.placePushpinForSelection(at: nil)
		}
		setNeedsLayout()
		dragState.confirmDrag = false
		owner.didUpdateObject()
	}

	// MARK: Selection

	func selectObjectAtPoint(_ point: CGPoint) {
		owner.unblinkObject() // used by Mac Catalyst, harmless otherwise

		if selectedWay != nil,
		   // check for selecting node inside previously selected way
		   let hit = osmHitTestNode(inSelectedWay: point, radius: DefaultHitTestRadius)
		{
			selectedNode = hit

		} else {
			// hit test anything
			var segment = -1
			if let hit = osmHitTest(
				point,
				radius: DefaultHitTestRadius,
				isDragConnect: false,
				ignoreList: [],
				segment: &segment)
			{
				if let hit = hit as? OsmNode {
					selectedNode = hit
					selectedWay = nil
					selectedRelation = nil
				} else if let hit = hit as? OsmWay {
					if let selectedRelation = self.selectedRelation,
					   hit.parentRelations.contains(selectedRelation)
					{
						// selecting way inside previously selected relation
						selectedNode = nil
						selectedWay = hit
					} else if hit.parentRelations.count > 0 {
						// select relation the way belongs to
						var relations = hit.parentRelations.filter { relation in
							relation.isMultipolygon() || relation.isBoundary() || relation.isWaterway()
						}
						if relations.count == 0, !hit.hasInterestingTags() {
							relations = hit
								.parentRelations // if the way doesn't have tags then always promote to containing relation
						}
						if let relation = relations.first {
							selectedNode = nil
							selectedWay = nil
							selectedRelation = relation
						} else {
							selectedNode = nil
							selectedWay = hit
							selectedRelation = nil
						}
					} else {
						selectedNode = nil
						selectedWay = hit
						selectedRelation = nil
					}
				} else if let hit = hit as? OsmRelation {
					selectedNode = nil
					selectedWay = nil
					selectedRelation = hit
				} else {
					fatalError()
				}
			} else {
				selectedNode = nil
				selectedWay = nil
				selectedRelation = nil
			}
		}

		owner.removePin()

		if let selectedPrimary = self.selectedPrimary {
			// adjust tap point to touch object
			var latLon = owner.mapTransform.latLon(forScreenPoint: point)
			latLon = selectedPrimary.latLonOnObject(forLatLon: latLon)
			let point = owner.mapTransform.screenPoint(forLatLon: latLon, birdsEye: true)

			owner.placePushpin(at: point, object: selectedPrimary)

			if selectedPrimary is OsmWay || selectedPrimary is OsmRelation {
				// if they later try to drag this way ask them if they really wanted to
				dragState.confirmDrag = selectedPrimary.modifyCount == 0
			}
		}
	}

	// MARK: Dragging

	func dragBegin() {
		mapData.beginUndoGrouping()
		dragState.totalMovement = .zero
		dragState.didMove = false
	}

	func dragContinue(object: OsmBaseObject,
	                  dragx: CGFloat, dragy: CGFloat,
	                  isRotateObjectMode: (rotateObjectOverlay: CAShapeLayer, rotateObjectCenter: LatLon)?)
	{
		// don't accumulate undo moves
		dragState.totalMovement.x += dragx
		dragState.totalMovement.y += dragy
		if dragState.didMove {
			mapData.endUndoGrouping()
			silentUndo = true
			let dict = mapData.undo()
			silentUndo = false
			mapData.beginUndoGrouping()
			if let dict = dict as? [String: String] {
				// maintain the original pin location:
				mapData.registerUndoCommentContext(dict)
			}
		}
		dragState.didMove = true

		// move all dragged nodes
		if let rotate = isRotateObjectMode {
			// rotate object
			let delta = Double(-(dragState.totalMovement.x + dragState.totalMovement.y) / 100)
			let axis = owner.mapTransform.screenPoint(forLatLon: rotate.rotateObjectCenter,
			                                          birdsEye: true)
			let nodeSet = (object.isNode() != nil) ? selectedWay?.nodeSet() : object.nodeSet()
			for node in nodeSet ?? [] {
				let pt = owner.mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: true)
				let diff = OSMPoint(x: Double(pt.x - axis.x), y: Double(pt.y - axis.y))
				let radius = hypot(diff.x, diff.y)
				var angle = atan2(diff.y, diff.x)
				angle += delta
				let new = OSMPoint(
					x: Double(axis.x) + radius * Double(cos(angle)),
					y: Double(axis.y) + Double(radius * sin(angle)))
				let dist = CGPoint(x: new.x - Double(pt.x), y: -(new.y - Double(pt.y)))
				adjust(node, byScreenDistance: dist)
			}
		} else {
			// drag object
			let delta = CGPoint(x: dragState.totalMovement.x,
			                    y: -dragState.totalMovement.y)

			for node in object.nodeSet() {
				adjust(node, byScreenDistance: delta)
			}
		}

		// do hit testing for connecting to other objects
		if selectedWay != nil, object.isNode() != nil {
			var segment = -1
			if let hit = hitTestDragConnection(for: object as! OsmNode, segment: &segment),
			   hit.isWay() != nil || hit.isNode() != nil
			{
				owner.blink(hit, segment: segment)
			} else {
				owner.unblinkObject()
			}
		}
	}

	func dragFinish(object: OsmBaseObject, isRotate: Bool) {
		mapData.endUndoGrouping()

		if let way = object.isWay() {
			// update things if we dragged a multipolygon inner member to become outer
			mapData.updateParentMultipolygonRelationRoles(for: way)
		} else if let selectedWay = self.selectedWay,
		          object.isNode() != nil
		{
			// you can also move an inner to an outer by dragging nodes one at a time
			mapData.updateParentMultipolygonRelationRoles(for: selectedWay)
		}

		if let selectedWay = self.selectedWay,
		   let dragNode = object.isNode()
		{
			// dragging a node that is part of a way
			let dragWay = selectedWay
			var segment = -1
			let hit = hitTestDragConnection(for: dragNode, segment: &segment)
			if var hit = hit as? OsmNode {
				// replace dragged node with hit node
				do {
					let merge = try mapData.canMerge(dragNode, into: hit)
					hit = merge()
					if dragWay.isArea() {
						selectedNode = nil
						let pt = owner.mapTransform.screenPoint(forLatLon: hit.latLon, birdsEye: true)
						owner.placePushpin(at: pt, object: dragWay)
					} else {
						selectedNode = hit
						owner.placePushpinForSelection(at: nil)
					}
				} catch {
					owner.showAlert(error.localizedDescription, message: nil)
					return
				}
			} else if let hit = hit as? OsmWay {
				// add new node to hit way
				let pt = hit.latLonOnObject(forLatLon: dragNode.latLon)
				mapData.setLatLon(pt, forNode: dragNode)
				do {
					let add = try canAddNode(toWay: hit, atIndex: segment + 1)
					add(dragNode)
				} catch {
					owner.showAlert(
						NSLocalizedString("Error connecting to way", comment: ""),
						message: error.localizedDescription)
				}
			}
			return
		}
		if isRotate {
			return
		}
		if let selectedWay = self.selectedWay,
		   selectedWay.tags.count == 0,
		   selectedWay.parentRelations.count == 0
		{
			return
		}
		if selectedWay != nil, selectedNode != nil {
			return
		}
		if dragState.confirmDrag {
			dragState.confirmDrag = false

			let alertMove = UIAlertController(
				title: NSLocalizedString("Confirm move", comment: ""),
				message: NSLocalizedString("Move selected object?", comment: ""),
				preferredStyle: .alert)
			alertMove
				.addAction(UIAlertAction(title: NSLocalizedString("Undo", comment: ""), style: .cancel, handler: { _ in
					// cancel move
					self.mapData.undo()
					self.mapData.removeMostRecentRedo()
					self.selectedNode = nil
					self.selectedWay = nil
					self.selectedRelation = nil
					self.owner.removePin()
					self.setNeedsLayout()
				}))
			alertMove
				.addAction(UIAlertAction(title: NSLocalizedString("Move", comment: ""), style: .default, handler: { _ in
					// okay
				}))
			owner.presentAlert(alert: alertMove, location: .none)
		}
	}

	func hitTestDragConnection(for node: OsmNode, segment: inout Int) -> OsmBaseObject? {
		guard let way = selectedWay,
		      let index = way.nodes.firstIndex(of: node),
		      let point = owner.pushpinView()?.arrowPoint
		else { return nil }

		var ignoreList: [OsmBaseObject] = []
		let parentWays = node.wayCount == 1 ? [way] : mapData.waysContaining(node)
		if way.nodes.count < 3 {
			ignoreList = parentWays + way.nodes
		} else if index == 0 {
			// if end-node then okay to connect to self-nodes except for adjacent
			let nodes = [way.nodes[0],
			             way.nodes[1],
			             way.nodes[2]]
			ignoreList = parentWays + nodes
		} else if index == way.nodes.count - 1 {
			// if end-node then okay to connect to self-nodes except for adjacent
			let nodes = [way.nodes[index],
			             way.nodes[index - 1],
			             way.nodes[index - 2]]
			ignoreList = parentWays + nodes
		} else {
			// if middle node then never connect to self
			if !parentWays.isEmpty {
				ignoreList = parentWays + way.nodes
			}
		}
		let hit = osmHitTest(point,
		                     radius: DragConnectHitTestRadius,
		                     isDragConnect: true,
		                     ignoreList: ignoreList,
		                     segment: &segment)
		return hit
	}

	// MARK: Rotate

	func rotateBegin() {
		mapData.beginUndoGrouping()
		dragState.didMove = false
	}

	func rotateContinue(delta: CGFloat,
	                    rotate: (rotateObjectOverlay: CAShapeLayer, rotateObjectCenter: LatLon))
	{
		if dragState.didMove {
			// don't allows undo list to accumulate
			mapData.endUndoGrouping()
			silentUndo = true
			mapData.undo()
			silentUndo = false
			mapData.beginUndoGrouping()
		}

		dragState.didMove = true

		let axis = owner.mapTransform.screenPoint(forLatLon: rotate.rotateObjectCenter, birdsEye: true)
		let rotatedObject = selectedRelation ?? selectedWay
		if let nodeSet = rotatedObject?.nodeSet() {
			for node in nodeSet {
				let pt = owner.mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: true)
				let diff = OSMPoint(x: Double(pt.x - axis.x), y: Double(pt.y - axis.y))
				let radius = hypot(diff.x, diff.y)
				var angle = atan2(diff.y, diff.x)

				angle += Double(delta)
				let new = OSMPoint(x: Double(axis.x) + radius * cos(angle), y: Double(axis.y) + radius * sin(angle))
				let dist = CGPoint(x: CGFloat(new.x) - pt.x, y: -(CGFloat(new.y) - pt.y))
				adjust(node, byScreenDistance: dist)
			}
		}
	}

	func rotateFinish() {
		mapData.endUndoGrouping()
	}

	// MARK: Editing

	func adjust(_ node: OsmNode, byScreenDistance delta: CGPoint) {
		var pt = owner.mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: true)
		pt.x += delta.x
		pt.y -= delta.y
		let loc = owner.mapTransform.latLon(forScreenPoint: pt)
		mapData.setLatLon(loc, forNode: node)

		setNeedsLayout()
	}

	func duplicateObject(_ object: OsmBaseObject, withOffset offset: OSMPoint) -> OsmBaseObject? {
		let newObject = mapData.duplicate(object, withOffset: offset)!
		setNeedsLayout()
		return newObject
	}

	func createNode(atScreenPoint point: CGPoint) -> OsmNode {
		let loc = owner.mapTransform.latLon(forScreenPoint: point)
		let node = mapData.createNode(atLocation: loc)
		setNeedsLayout()
		return node
	}

	func createWay(with node: OsmNode) -> OsmWay {
		let way = mapData.createWay()
		let add = try! mapData.canAddNode(to: way, at: 0)
		add(node)
		setNeedsLayout()
		return way
	}

	func canAddNode(toWay way: OsmWay, atIndex index: Int) throws -> EditActionWithNode {
		let action = try mapData.canAddNode(to: way, at: index)
		return { [self] node in
			action(node)
			setNeedsLayout()
		}
	}

	func canDeleteSelectedObject() throws -> EditAction {
		if let selectedNode = selectedNode {
			// delete node from selected way
			let action: EditAction
			if let selectedWay = selectedWay {
				action = try mapData.canDelete(selectedNode, from: selectedWay)
			} else {
				action = try mapData.canDelete(selectedNode)
			}
			let way = selectedWay
			return { [self] in
				// deselect node after we've removed it from ways
				action()
				self.selectedNode = nil
				if way?.deleted ?? false {
					self.selectedWay = nil
				}
				setNeedsLayout()
			}
		} else if let selectedWay = selectedWay {
			// delete way
			if let action = try? mapData.canDelete(selectedWay) {
				return { [self] in
					action()
					self.selectedNode = nil
					self.selectedWay = nil
					setNeedsLayout()
				}
			}
		} else if let selectedRelation = selectedRelation {
			if let action = try? mapData.canDelete(selectedRelation) {
				return { [self] in
					action()
					self.selectedNode = nil
					self.selectedWay = nil
					self.selectedRelation = nil
					setNeedsLayout()
				}
			}
		}
		throw EditError.text("")
	}

	func deleteCurrentSelection() {
		guard let selectedPrimary = self.selectedPrimary,
		      let pushpinView = owner.pushpinView()
		else { return }

		let deleteHandler: ((_ action: UIAlertAction?) -> Void) = { [self] _ in
			do {
				let canDelete = try self.canDeleteSelectedObject()
				canDelete()
				var pos = pushpinView.arrowPoint
				owner.removePin()
				if self.selectedPrimary != nil {
					pos = owner.mapTransform.screenPoint(on: selectedPrimary, forScreenPoint: pos)
					if let primary = self.selectedPrimary {
						owner.placePushpin(at: pos, object: primary)
					}
				}
			} catch {
				owner.showAlert(NSLocalizedString("Delete failed", comment: ""), message: error.localizedDescription)
			}
		}

		if selectedRelation?.isMultipolygon() ?? false, selectedPrimary.isWay() != nil {
			// delete way from relation
			let alertDelete = UIAlertController(
				title: NSLocalizedString("Delete", comment: ""),
				message: NSLocalizedString("Member of multipolygon relation", comment: ""),
				preferredStyle: .actionSheet)
			alertDelete
				.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
				                         style: .cancel,
				                         handler: { _ in
				                         }))
			alertDelete
				.addAction(UIAlertAction(title: NSLocalizedString("Delete completely", comment: ""),
				                         style: .default,
				                         handler: deleteHandler))
			alertDelete
				.addAction(UIAlertAction(title: NSLocalizedString("Detach from relation", comment: ""),
				                         style: .default,
				                         handler: { [self] _ in
				                         	do {
				                         		let canRemove = try self.mapData.canRemove(selectedPrimary,
				                         		                                           from: self
				                         		                                           	.selectedRelation!)
				                         		canRemove()
				                         		self.selectedRelation = nil
				                         		owner.didUpdateObject()
				                         	} catch {
				                         		owner.showAlert(
				                         			NSLocalizedString("Delete failed", comment: ""),
				                         			message: error.localizedDescription)
				                         	}
				                         }))
			owner.presentAlert(alert: alertDelete, location: .editBar)

		} else {
			// regular delete
			let name = selectedPrimary.friendlyDescription()
			let question = String.localizedStringWithFormat(NSLocalizedString("Delete %@?",
																			  comment: "Confirm deleting a node/way"),
															name)
			let alertDelete = UIAlertController(
				title: NSLocalizedString("Delete", comment: ""),
				message: question,
				preferredStyle: .alert)
			alertDelete
				.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
			alertDelete
				.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: ""),
				                         style: .destructive, handler: deleteHandler))
			owner.presentAlert(alert: alertDelete, location: .none)
		}
	}

	func editActionsAvailable() -> [EDIT_ACTION] {
		var actionList: [EDIT_ACTION] = []
		if let selectedWay = self.selectedWay {
			if let selectedNode = self.selectedNode {
				// node in way
				let parentWays: [OsmWay] = mapData.waysContaining(selectedNode)
				let disconnect = parentWays.count > 1 ||
					selectedNode.hasInterestingTags() ||
					selectedWay.isSelfIntersection(selectedNode)
				let split = selectedWay.isClosed() ||
					(selectedNode != selectedWay.nodes[0] && selectedNode != selectedWay.nodes.last)
				let join = parentWays.count > 1
				let restriction = owner.useTurnRestrictions() && self.selectedWay?.tags["highway"] != nil && parentWays
					.count > 1

				actionList = [.COPYTAGS]

				if disconnect {
					actionList.append(.DISCONNECT)
				}
				if split {
					actionList.append(.SPLIT)
				}
				if join {
					actionList.append(.JOIN)
				}
				actionList.append(.ROTATE)
				if restriction {
					actionList.append(.RESTRICT)
				}
			} else {
				if selectedWay.isClosed() {
					// polygon
					actionList = [
						.COPYTAGS,
						.RECTANGULARIZE,
						.CIRCULARIZE,
						.ROTATE,
						.DUPLICATE,
						.REVERSE,
						.CREATE_RELATION
					]
				} else {
					// line
					actionList = [.COPYTAGS, .STRAIGHTEN, .REVERSE, .DUPLICATE, .CREATE_RELATION]
				}
			}
		} else if selectedNode != nil {
			// node
			actionList = [.COPYTAGS, .DUPLICATE]
		} else if let selectedRelation = self.selectedRelation {
			// relation
			if selectedRelation.isMultipolygon() {
				actionList = [.COPYTAGS, .ROTATE, .DUPLICATE]
			} else {
				actionList = [.COPYTAGS, .PASTETAGS]
			}
		} else {
			// nothing selected
			return []
		}
		return actionList
	}

	/// Performs the selected action on the currently selected editor objects
	func performEdit(_ action: EDIT_ACTION) {
		// if trying to edit a node in a way that has no tags assume user wants to edit the way instead
		switch action {
		case .RECTANGULARIZE, .STRAIGHTEN, .REVERSE, .DUPLICATE, .ROTATE, .CIRCULARIZE, .COPYTAGS, .PASTETAGS,
		     .EDITTAGS, .CREATE_RELATION:
			if selectedWay != nil, selectedNode != nil, (selectedNode?.tags.count ?? 0) == 0,
			   (selectedWay?.tags.count ?? 0) == 0, !(selectedWay?.isMultipolygonMember() ?? false)
			{
				// promote the selection to the way
				selectedNode = nil
				owner.didUpdateObject()
			}
		case .SPLIT, .JOIN, .DISCONNECT, .RESTRICT, .ADDNOTE, .DELETE, .MORE:
			break
		}

		do {
			switch action {
			case .COPYTAGS:
				if let selectedPrimary = self.selectedPrimary {
					if !copyTags(selectedPrimary) {
						throw EditError.text(NSLocalizedString("The object does not contain any tags", comment: ""))
					}
				}
			case .PASTETAGS:
				if selectedPrimary == nil {
					// pasting to brand new object, so we need to create it first
					setTagsForCurrentObject([:])
				}

				if selectedWay != nil, selectedNode != nil, selectedWay?.tags.count ?? 0 == 0 {
					// if trying to edit a node in a way that has no tags assume user wants to edit the way instead
					selectedNode = nil
					owner.didUpdateObject()
				}
				pasteTags()
			case .DUPLICATE:
				guard let primary = selectedPrimary,
				      let pushpinView = owner.pushpinView()
				else { return }
				let delta = CGPoint(x: owner.crosshairs().x - pushpinView.arrowPoint.x,
				                    y: owner.crosshairs().y - pushpinView.arrowPoint.y)
				var offset: OSMPoint
				if hypot(delta.x, delta.y) > 20 {
					// move to position of crosshairs
					let p1 = owner.mapTransform.latLon(forScreenPoint: pushpinView.arrowPoint)
					let p2 = owner.mapTransform.latLon(forScreenPoint: owner.crosshairs())
					offset = OSMPoint(x: p2.lon - p1.lon, y: p2.lat - p1.lat)
				} else {
					offset = OSMPoint(x: 0.00005, y: -0.00005)
				}
				guard let newObject = duplicateObject(primary, withOffset: offset)
				else {
					throw EditError.text(NSLocalizedString("Could not duplicate object", comment: ""))
				}
				selectedNode = newObject.isNode()
				selectedWay = newObject.isWay()
				selectedRelation = newObject.isRelation()
				owner.placePushpinForSelection(at: nil)
			case .ROTATE:
				if selectedWay == nil, !(selectedRelation?.isMultipolygon() ?? false) {
					throw EditError.text(NSLocalizedString("Only ways/multipolygons can be rotated", comment: ""))
				} else {
					owner.startObjectRotation()
				}
			case .RECTANGULARIZE:
				guard let selectedWay = self.selectedWay else { return }
				if selectedWay.ident >= 0, !owner.screenLatLonRect().containsRect(selectedWay.boundingBox) {
					throw EditError.text(NSLocalizedString("The selected way must be completely visible",
					                                       comment: "")) // avoid bugs where nodes are deleted from other objects
				}
				let rect = try mapData.canOrthogonalizeWay(self.selectedWay!)
				rect()
			case .REVERSE:
				let reverse = try mapData.canReverse(selectedWay!)
				reverse()
			case .JOIN:
				let join = try mapData.canJoin(selectedWay!, at: selectedNode!)
				selectedWay = join()
			case .DISCONNECT:
				let disconnect = try mapData.canDisconnectWay(selectedWay!, at: selectedNode!)
				selectedNode = disconnect()
				owner.placePushpinForSelection(at: nil)
			case .SPLIT:
				let split = try mapData.canSplitWay(selectedWay!, at: selectedNode!)
				_ = split()
			case .STRAIGHTEN:
				if let selectedWay = self.selectedWay {
					let boundingBox = selectedWay.boundingBox
					if selectedWay.ident >= 0, !owner.screenLatLonRect().containsRect(boundingBox) {
						throw EditError.text(NSLocalizedString("The selected way must be completely visible",
						                                       comment: "")) // avoid bugs where nodes are deleted from other objects
					} else {
						let straighten = try mapData.canStraightenWay(selectedWay)
						straighten()
					}
				}
			case .CIRCULARIZE:
				let circle = try mapData.canCircularizeWay(selectedWay!)
				circle()
			case .EDITTAGS:
				owner.presentTagEditor(nil)
			case .ADDNOTE:
				owner.addNote()
			case .DELETE:
				deleteCurrentSelection()
			case .MORE:
				owner.presentEditActionSheet(nil)
			case .RESTRICT:
				owner.presentTurnRestrictionEditor()
			case .CREATE_RELATION:
				guard let selectedPrimary = self.selectedPrimary else { return }
				let create: ((_ type: String) -> Void) = { [self] type in
					do {
						let relation = self.mapData.createRelation()
						var tags = selectedPrimary.tags
						tags["type"] = type
						self.mapData.setTags(tags, for: relation)
						// need the relation type to be set before adding
						let add = try self.mapData.canAdd(selectedPrimary,
						                                  to: relation,
						                                  withRole: "outer")
						add()
						self.mapData.setTags([:], for: selectedPrimary)
						self.selectedNode = nil
						self.selectedWay = nil
						self.selectedRelation = relation
						self.setNeedsLayout()
						owner.didUpdateObject()
						owner.showAlert(
							NSLocalizedString("Adding members:", comment: ""),
							message: NSLocalizedString(
								"To add another member to the relation 'long press' on the way to be added",
								comment: ""))
					} catch {
						owner.showAlert(error.localizedDescription, message: nil)
					}
				}
				let actionSheet = UIAlertController(
					title: NSLocalizedString("Create Relation Type", comment: ""),
					message: nil,
					preferredStyle: .actionSheet)
				actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Multipolygon", comment: ""),
				                                    style: .default,
				                                    handler: { _ in
				                                    	create("multipolygon")
				                                    }))
				actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
				                                    style: .cancel,
				                                    handler: nil))
				let rc = CGRect(origin: owner.pushpinView()?.arrowPoint ?? .zero, size: .zero)
				owner.presentAlert(alert: actionSheet, location: .rect(rc))
				return
			}
		} catch {
			owner.showAlert(error.localizedDescription, message: nil)
		}
		setNeedsLayout()
		owner.didUpdateObject()
	}

	// MARK: Create node/ways

	func longPressAtPoint(_ point: CGPoint) {
		let objects = osmHitTestMultiple(point, radius: DefaultHitTestRadius)
		if objects.count == 0 {
			return
		}

		// special case for adding members to relations:
		if selectedPrimary?.isRelation()?.isMultipolygon() ?? false {
			let ways = objects.compactMap({ $0 as? OsmWay })
			if ways.count == 1 {
				let confirm = UIAlertController(
					title: NSLocalizedString("Add way to multipolygon?", comment: ""),
					message: nil,
					preferredStyle: .alert)
				let addMmember: ((String?) -> Void) = { [self] role in
					do {
						let add = try self.mapData.canAdd(ways[0],
						                                  to: self.selectedRelation!,
						                                  withRole: role)
						add()
						owner.flashMessage(NSLocalizedString("added to multipolygon relation", comment: ""))
						self.setNeedsLayout()
					} catch {
						owner.showAlert(NSLocalizedString("Error", comment: ""), message: error.localizedDescription)
					}
				}
				confirm.addAction(UIAlertAction(
					title: NSLocalizedString("Add outer member", comment: "Add to relation"),
					style: .default,
					handler: { _ in
						addMmember("outer")
					}))
				confirm.addAction(UIAlertAction(
					title: NSLocalizedString("Add inner member", comment: "Add to relation"),
					style: .default,
					handler: { _ in
						addMmember("inner")
					}))
				confirm
					.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel,
					                         handler: nil))
				owner.presentAlert(alert: confirm, location: .none)
			}
			return
		}

		let multiSelectSheet = UIAlertController(
			title: NSLocalizedString("Select Object", comment: ""),
			message: nil,
			preferredStyle: .actionSheet)
		for object in objects {
			var title = object.friendlyDescription()
			if !title.hasPrefix("(") {
				// indicate what type of object it is
				if object.isNode() != nil {
					title = title + NSLocalizedString(" (node)", comment: "")
				} else if object.isWay() != nil {
					title = title + NSLocalizedString(" (way)", comment: "")
				} else if object.isRelation() != nil {
					let type = object.tags["type"] ?? NSLocalizedString("relation", comment: "")
					title = title + " (\(type))"
				}
			}
			multiSelectSheet.addAction(UIAlertAction(title: title, style: .default, handler: { [self] _ in
				// processing for selecting one of multipe objects
				self.selectedNode = nil
				self.selectedWay = nil
				self.selectedRelation = nil
				if let node = object.isNode() {
					// select the way containing the node, then select the node in the way
					self.selectedWay = objects
						.first(where: { ($0 as? OsmWay)?.nodes.contains(node) ?? false }) as? OsmWay
					self.selectedNode = node
				} else if object.isWay() != nil {
					self.selectedWay = object.isWay()
				} else if object.isRelation() != nil {
					self.selectedRelation = object.isRelation()
				}
				let pos = owner.mapTransform.screenPoint(on: object, forScreenPoint: point)
				owner.placePushpin(at: pos, object: object)
			}))
		}
		multiSelectSheet
			.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
		let rc = CGRect(x: point.x, y: point.y, width: 0.0, height: 0.0)
		owner.presentAlert(alert: multiSelectSheet, location: .rect(rc))
	}

	func extendSelectedWay(to newPoint: CGPoint, from pinPoint: CGPoint) -> Result<CGPoint, EditError> {
		if let way = selectedWay,
		   self.selectedNode == nil
		{
			// insert a new node into way at arrowPoint
			let pt = owner.mapTransform.latLon(forScreenPoint: pinPoint)
			let segment = way.segmentClosestToPoint(pt)
			do {
				let add = try canAddNode(toWay: way, atIndex: segment + 1)
				let newNode = createNode(atScreenPoint: pinPoint)
				add(newNode)
				selectedNode = newNode
				return .success(newPoint)
			} catch {
				return .failure(error as! EditError)
			}
		}

		let prevNode: OsmNode
		let way: OsmWay
		if let selectedNode = self.selectedNode,
		   let selectedWay = self.selectedWay,
		   selectedWay.nodes.count > 0,
		   selectedWay.isClosed() || (selectedNode != selectedWay.nodes.first && selectedNode != selectedWay.nodes.last)
		{
			// both a node and way are selected but selected node is not an endpoint (or way is closed),
			// so we will create a new way "T" from that node
			prevNode = selectedNode // use the existing node selected by user
			way = createWay(with: selectedNode) // create a new way extending off of it
		} else {
			// we're either extending a way from it's end, or creating a new way with
			// the pushpin as one end of it and crosshairs (or mouse click) as the other
			prevNode = selectedNode ?? createNode(atScreenPoint: pinPoint)
			way = selectedWay ?? createWay(with: prevNode)
		}

		let prevIndex = way.nodes.firstIndex(of: prevNode)!
		var nextIndex = prevIndex
		if nextIndex == way.nodes.count - 1 {
			nextIndex += 1
		}
		// add new node at point
		var newPoint = newPoint
		let prevPrevNode = way.nodes.count >= 2 ? way.nodes[way.nodes.count - 2] : nil
		let prevPrevPoint = prevPrevNode != nil ? owner.mapTransform.screenPoint(
			forLatLon: prevPrevNode!.latLon,
			birdsEye: true) : CGPoint.zero

		if hypot(pinPoint.x - newPoint.x, pinPoint.y - newPoint.y) > 10.0,
		   prevPrevNode == nil || hypot(prevPrevPoint.x - newPoint.x, prevPrevPoint.y - newPoint.y) > 10.0
		{
			// it's far enough from previous point to use
		} else {
			// compute a good place for next point
			if way.nodes.count < 2 {
				// create 2nd point in the direction of the center of the screen
				let vert = abs(Float(pinPoint.x - newPoint.x)) < abs(Float(pinPoint.y - newPoint.y))
				if vert {
					newPoint.x = pinPoint.x
					newPoint.y = abs(newPoint.y - pinPoint.y) < 30 ? pinPoint.y + 60 : 2 * newPoint.y - pinPoint.y
				} else {
					newPoint.x = abs(newPoint.x - pinPoint.x) < 30 ? pinPoint.x + 60 : 2 * newPoint.x - pinPoint.x
					newPoint.y = pinPoint.y
				}
			} else if way.nodes.count == 2 {
				// create 3rd point 90 degrees from first 2
				let n1 = way.nodes[1 - prevIndex]
				let p1 = owner.mapTransform.screenPoint(forLatLon: n1.latLon, birdsEye: true)
				var delta = CGPoint(x: p1.x - pinPoint.x, y: p1.y - pinPoint.y)
				let len = hypot(delta.x, delta.y)
				if len > 100 {
					delta.x *= CGFloat(100 / len)
					delta.y *= CGFloat(100 / len)
				}
				let np1 = CGPoint(x: pinPoint.x - delta.y, y: pinPoint.y + delta.x)
				let np2 = CGPoint(x: pinPoint.x + delta.y, y: pinPoint.y - delta.x)
				if OSMPoint(np1).distanceToPoint(OSMPoint(newPoint)) < OSMPoint(np2)
					.distanceToPoint(OSMPoint(newPoint))
				{
					newPoint = np1
				} else {
					newPoint = np2
				}
			} else {
				// create 4th point and beyond following angle of previous 3
				let n1 = prevIndex == 0 ? way.nodes[1] : way.nodes[prevIndex - 1]
				let n2 = prevIndex == 0 ? way.nodes[2] : way.nodes[prevIndex - 2]
				let p1 = owner.mapTransform.screenPoint(forLatLon: n1.latLon, birdsEye: true)
				let p2 = owner.mapTransform.screenPoint(forLatLon: n2.latLon, birdsEye: true)
				let d1 = OSMPoint(x: Double(pinPoint.x - p1.x), y: Double(pinPoint.y - p1.y))
				let d2 = OSMPoint(x: Double(p1.x - p2.x), y: Double(p1.y - p2.y))
				var a1 = atan2(d1.y, d1.x)
				let a2 = atan2(d2.y, d2.x)
				var dist = hypot(d1.x, d1.y)
				// if previous angle was 90 degrees then match length of first leg to make a rectangle
				if way.nodes.count == 3 || way.nodes.count == 4, abs(fmod(abs(Float(a1 - a2)), .pi) - .pi / 2) < 0.1 {
					dist = hypot(d2.x, d2.y)
				} else if dist > 100 {
					dist = 100
				}
				a1 += a1 - a2
				newPoint = CGPoint(x: Double(pinPoint.x) + dist * cos(a1),
				                   y: Double(Double(pinPoint.y) + dist * sin(a1)))
			}
			// make sure selected point is on-screen
			var rc = bounds.insetBy(dx: 20.0, dy: 20.0)
			rc.size.height -= 190
			newPoint.x = CGFloat(max(newPoint.x, rc.origin.x))
			newPoint.x = CGFloat(min(newPoint.x, rc.origin.x + rc.size.width))
			newPoint.y = CGFloat(max(newPoint.y, rc.origin.y))
			newPoint.y = CGFloat(min(newPoint.y, rc.origin.y + rc.size.height))
		}

		if way.nodes.count >= 2 {
			let start = prevIndex == 0 ? way.nodes.last! : way.nodes[0]
			let s = owner.mapTransform.screenPoint(forLatLon: start.latLon, birdsEye: true)
			let d = hypot(s.x - newPoint.x, s.y - newPoint.y)
			if d < 3.0 {
				// join first to last
				if let action = try? canAddNode(toWay: way, atIndex: nextIndex) {
					action(start)
					selectedWay = way
					selectedNode = nil
					return .success(s)
				} else {
					// fall through to non-joining case
				}
			}
		}

		let addNodeToWay: EditActionWithNode
		do {
			addNodeToWay = try canAddNode(toWay: way, atIndex: nextIndex)
		} catch {
			return .failure(error as! EditError)
		}
		let node2 = createNode(atScreenPoint: newPoint)
		selectedWay = way // set selection before perfoming add-node action so selection is recorded in undo stack
		selectedNode = node2
		addNodeToWay(node2)
		return .success(newPoint)
	}

	func addNode(at dropPoint: CGPoint) {
		if isHidden {
			owner.flashMessage(NSLocalizedString("Editing layer not visible", comment: ""))
			return
		}

		// we are either creating a brand new node unconnected to an existing way,
		// converting a dropped pin to a way by adding a new node
		// or adding a node to a selected way/node combination
		guard let pushpinView = owner.pushpinView(),
		      self.selectedNode == nil || selectedWay != nil
		else {
			// drop a new pin
			selectedNode = nil
			selectedWay = nil
			selectedRelation = nil
			owner.placePushpin(at: dropPoint, object: nil)
			return
		}

		let prevPointIsOffScreen = !bounds.contains(pushpinView.arrowPoint)
		let offscreenWarning: (() -> Void) = {
			self.owner.flashMessage(NSLocalizedString("Selected object is off screen", comment: ""))
		}

		if let selectedWay = self.selectedWay,
		   let selectedNode = self.selectedNode
		{
			// already editing a way so try to extend it
			if selectedWay
				.isClosed() || !(selectedNode == selectedWay.nodes.first || selectedNode == selectedWay.nodes.last)
			{
				if prevPointIsOffScreen {
					offscreenWarning()
					return
				}
			}
		} else if selectedPrimary == nil {
			// just dropped a pin, so convert it into a way
		} else if selectedWay != nil, selectedNode == nil {
			// add a new node to a way at location of pushpin
			if prevPointIsOffScreen {
				offscreenWarning()
				return
			}
		} else {
			// not supported
			return
		}

		switch extendSelectedWay(to: dropPoint, from: pushpinView.arrowPoint) {
		case let .success(pt):
			owner.placePushpinForSelection(at: pt)
		case let .failure(error):
			if case let .text(text) = error {
				owner.showAlert(NSLocalizedString("Can't extend way", comment: ""), message: text)
			}
		}
	}
}
