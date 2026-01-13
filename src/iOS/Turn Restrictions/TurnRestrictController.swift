//
//  TurnRestrictController.swift
//  Go Map!!
//
//  Created by Mukul Bakshi on 02/11/17.
//  Copyright © 2017 Bryce Cogswell. All rights reserved.
//

import UIKit

// width of the way line e.g 12, 17, 18 AND shadow width is +4 e.g 16, 21, 22
let DEFAULT_POPUPLINEWIDTH = 12

class TurnRestrictController: UIViewController {
	private var parentWays: [OsmWay] = []
	private var highwayViewArray = [TurnRestrictHwyView]()
	private var selectedFromHwy: TurnRestrictHwyView?
	private var uTurnButton: UIButton!
	private var currentUTurnRelation: OsmRelation?
	private var allRelations: [OsmRelation] = []
	private var editedRelations: [OsmRelation] = []

	@IBOutlet var constraintViewWithTitleHeight: NSLayoutConstraint!
	@IBOutlet var constraintViewWithTitleWidth: NSLayoutConstraint!
	@IBOutlet var viewWithTitle: UIView!
	@IBOutlet var detailView: UIView!
	@IBOutlet var infoButton: UIButton!
	@IBOutlet var detailText: UILabel!
	var centralNode: OsmNode! // the central node

	static func instantiate() -> TurnRestrictController? {
		let storyboard = UIStoryboard(name: "TurnRestrictions", bundle: nil)
		let vc = storyboard.instantiateViewController(withIdentifier: "TurnRestrictController")
		return vc as? TurnRestrictController
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		highwayViewArray = []
		createMapWindow()

		AppDelegate.shared.mapView.editorLayer.mapData.beginUndoGrouping()
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		AppDelegate.shared.mapView.editorLayer.mapData.endUndoGrouping()
	}

	// draw Popup window
	func createMapWindow() {
		view.layoutIfNeeded()

		detailView.clipsToBounds = true

		viewWithTitle.clipsToBounds = true
		viewWithTitle.alpha = 1
		viewWithTitle.layer.borderColor = UIColor.gray.cgColor
		viewWithTitle.layer.borderWidth = 1
		viewWithTitle.layer.cornerRadius = 3

		// get highways that contain selection
		let mapData = AppDelegate.shared.mapView.editorLayer.mapData
		parentWays = mapData.waysContaining(centralNode).filter({ $0.tags["highway"] != nil })

		// Creating roads using adjacent connected nodes
		let conectedNodes = TurnRestrictController.getAdjacentNodes(centralNode, ways: parentWays)
		createHighwayViews(conectedNodes)

		// Ensure detailText is above Highway views
		detailView.bringSubviewToFront(detailText)

		// if there is only one reasonable thing to highlight initially select it
		var fromWay: OsmWay?
		if allRelations.count == 1 {
			// only one relation, so select it
			fromWay = allRelations.last?.member(byRole: "from")?.obj as? OsmWay
		} else {
			// no relations or multiple relations, so select highway already selected by user
			let editor = AppDelegate.shared.mapView.editorLayer!
			fromWay = editor.selectedWay
		}
		if let fromWay = fromWay {
			for hwy in highwayViewArray {
				if hwy.wayObj == fromWay {
					select(fromHighway: hwy)
					break
				}
			}
		}
	}

	class func getAdjacentNodes(_ centerNode: OsmNode?, ways parentWays: [OsmWay]?) -> [OsmNode] {
		var connectedNodes: [OsmNode] = []
		for way in parentWays ?? [] {
			if way.isArea() {
				continue // An area won't have any connected ways to it
			}

			for i in 0..<way.nodes.count {
				let node = way.nodes[i]
				if node == centerNode {
					if i + 1 < way.nodes.count {
						let nodeNext = way.nodes[i + 1]
						if !connectedNodes.contains(nodeNext) {
							nodeNext.turnRestrictionParentWay = way
							connectedNodes.append(nodeNext)
						}
					}

					if i > 0 {
						let nodePrev = way.nodes[i - 1]
						if !connectedNodes.contains(nodePrev) {
							nodePrev.turnRestrictionParentWay = way
							connectedNodes.append(nodePrev)
						}
					}
				}
			}
		}
		return connectedNodes
	}

	class func setAssociatedTurnRestrictionWays(_ allWays: [OsmWay]?) {
		for way in allWays ?? [] {
			for node in way.nodes {
				node.turnRestrictionParentWay = way
			}
		}
	}

	// MARK: Create Path From Points

	func createHighwayViews(_ adjacentNodesArray: [OsmNode]) {
		let centerNodePos = screenPoint(forLatLon: centralNode!.latLon)
		let detailViewCenter = CGPoint(x: detailView.bounds.midX, y: detailView.bounds.midY)
		let positionOffset = centerNodePos.minus(detailViewCenter)

		detailText.text = NSLocalizedString("Select a highway approaching the intersection", comment: "")

		// Get relations related to restrictions
		allRelations = []
		for relation in centralNode?.parentRelations ?? [] {
			if relation.isRestriction(),
			   relation.members.count >= 3
			{
				allRelations.append(relation)
			}
		}

		editedRelations = allRelations

		// create highway views
		for node in adjacentNodesArray {
			// get location of node
			var nodePoint = screenPoint(forLatLon: node.latLon)
			nodePoint = nodePoint.minus(positionOffset)

			// force highway segment to extend from center node to edge of view
			let size = detailView.bounds.size
			let direction = OSMPoint(
				x: Double(nodePoint.x - detailViewCenter.x),
				y: Double(nodePoint.y - detailViewCenter.y))
			let distTop = DistanceToVector(
				OSMPoint(detailViewCenter),
				direction,
				OSMPoint.zero,
				OSMPoint(x: Double(size.width), y: 0))
			let distLeft = DistanceToVector(
				OSMPoint(detailViewCenter),
				direction,
				OSMPoint.zero,
				OSMPoint(x: 0, y: Double(size.height)))
			let distRight = DistanceToVector(
				OSMPoint(detailViewCenter),
				direction,
				OSMPoint(x: Double(size.width), y: 0),
				OSMPoint(x: 0, y: Double(size.height)))
			let distBottom = DistanceToVector(
				OSMPoint(detailViewCenter),
				direction,
				OSMPoint(x: 0, y: Double(size.height)),
				OSMPoint(x: Double(size.width), y: 0))
			var best = Double(Float.greatestFiniteMagnitude)
			if distTop > 0, distTop < best {
				best = distTop
			}
			if distLeft > 0, distLeft < best {
				best = distLeft
			}
			if distRight > 0, distRight < best {
				best = distRight
			}
			if distBottom > 0, distBottom < best {
				best = distBottom
			}
			nodePoint = CGPoint(
				x: CGFloat(Double(detailViewCenter.x) + best * direction.x),
				y: CGFloat(Double(detailViewCenter.y) + best * direction.y))

			// highway path
			let bezierPath = UIBezierPath()
			bezierPath.move(to: detailViewCenter)
			bezierPath.addLine(to: nodePoint)

			// Highlight shape
			let highlightLayer = CAShapeLayer()
			highlightLayer.lineWidth = CGFloat(DEFAULT_POPUPLINEWIDTH + 10)
			highlightLayer.strokeColor = UIColor.cyan.cgColor
			highlightLayer.lineCap = .round
			highlightLayer.path = bezierPath.cgPath
			highlightLayer.bounds = detailView.bounds
			highlightLayer.position = detailViewCenter
			highlightLayer.isHidden = true

			// Highway shape
			let highwayLayer = CAShapeLayer()
			highwayLayer.lineWidth = CGFloat(DEFAULT_POPUPLINEWIDTH)
			highwayLayer.lineCap = .round
			highwayLayer.path = bezierPath.cgPath
			highwayLayer.strokeColor = node.turnRestrictionParentWay.renderInfo?.lineColor?.cgColor
				?? UIColor.black.cgColor
			highwayLayer.bounds = detailView.bounds
			highwayLayer.position = detailViewCenter
			highwayLayer.masksToBounds = false

			// Highway view
			let hwyView = TurnRestrictHwyView(frame: detailView.bounds,
			                                  wayObj: node.turnRestrictionParentWay,
			                                  centerNode: centralNode,
			                                  connectedNode: node,
			                                  centerPoint: detailViewCenter,
			                                  endPoint: nodePoint,
			                                  parentWaysArray: parentWays,
			                                  highwayLayer: highwayLayer,
			                                  highlightLayer: highlightLayer)
			hwyView.backgroundColor = UIColor.clear

			hwyView.layer.insertSublayer(highwayLayer, at: 0)
			hwyView.layer.insertSublayer(highlightLayer, below: highwayLayer)

			hwyView.createOneWayArrowsForHighway()
			hwyView.arrowButton.isHidden = true
			hwyView.restrictionChangedCallback = { objLine in
				self.toggleTurnRestriction(objLine)
			}
			hwyView.highwaySelectedCallback = { [self] objLine in
				select(fromHighway: objLine)
			}

			detailView.addSubview(hwyView)
			highwayViewArray.append(hwyView)
		}

		// Place green circle in center
		let centerView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
		centerView.backgroundColor = UIColor.green
		centerView.layer.cornerRadius = centerView.frame.size.height / 2
		centerView.center = detailViewCenter
		detailView.addSubview(centerView)
		detailView.bringSubviewToFront(centerView)

		view.backgroundColor = UIColor.clear

		// Create U-Turn restriction button
		uTurnButton = UIButton(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
		uTurnButton.imageView?.contentMode = .scaleAspectFit
		uTurnButton.center = detailViewCenter
		uTurnButton.layer.borderWidth = 1.0
		uTurnButton.layer.cornerRadius = 2.0
		uTurnButton.layer.borderColor = UIColor.black.cgColor

		uTurnButton.setImage(UIImage(named: "uTurnAllow"), for: .normal)
		uTurnButton.setImage(UIImage(named: "no_u_turn"), for: .selected)
		uTurnButton.addTarget(self, action: #selector(uTurnButtonClicked(_:)), for: .touchUpInside)
		detailView.addSubview(uTurnButton)
		uTurnButton.isHidden = true
	}

	@IBAction func infoButtonPressed(_ sender: Any) {
		let message = NSLocalizedString(
			"""
			Turn restrictions specify which roads you can turn onto when entering an intersection from a given direction.\n\n\
			Select the highway from which you are approaching the intersection, then tap an arrow to toggle whether the destination road is a permitted route.
			""",
			comment: "")
		let alert = UIAlertController(
			title: NSLocalizedString("Turn Restrictions", comment: ""),
			message: message,
			preferredStyle: .alert)
		alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
		present(alert, animated: true)
	}

	func textForTurn(from fromHwy: TurnRestrictHwyView, to toHwy: TurnRestrictHwyView) -> String? {
		let fromName = fromHwy.wayObj.friendlyDescription()
		let toName = toHwy.wayObj.friendlyDescription()
		switch toHwy.restriction {
		case .NONE:
			return String.localizedStringWithFormat(
				NSLocalizedString("Travel ALLOWED from %@ to %@", comment: ""),
				fromName,
				toName)
		case .NO:
			return String.localizedStringWithFormat(
				NSLocalizedString("Travel PROHIBITED from %@ to %@", comment: ""),
				fromName,
				toName)
		case .ONLY:
			return String.localizedStringWithFormat(
				NSLocalizedString("Travel ONLY from %@ to %@", comment: ""),
				fromName,
				toName)
		}
	}

	// Select a new "From" highway
	func select(fromHighway selectedHwy: TurnRestrictHwyView) {
		selectedFromHwy = selectedHwy

		let editor = AppDelegate.shared.mapView.editorLayer!
		editor.selectedWay = selectedHwy.wayObj

		selectedHwy.wayObj = selectedHwy.connectedNode.turnRestrictionParentWay
		uTurnButton.isHidden = selectedFromHwy?.wayObj.isOneWay != ONEWAY.NONE

		let angle = TurnRestrictHwyView.heading(from: selectedHwy.endPoint, to: selectedHwy.centerPoint)
		uTurnButton.transform = CGAffineTransform(rotationAngle: .pi + CGFloat(angle))

		currentUTurnRelation = findRelation(
			inList: editedRelations,
			from: selectedFromHwy?.wayObj,
			via: centralNode,
			to: selectedFromHwy?.wayObj)
		uTurnButton.isSelected = currentUTurnRelation != nil

		let friendlyDescription = selectedHwy.wayObj.friendlyDescription()
		detailText.text = String.localizedStringWithFormat(NSLocalizedString("Travel from %@", comment: ""),
		                                                   friendlyDescription)

		// highway exits center one-way
		let selectedHwyIsOneWayExit = selectedHwy.isOneWayExitingCenter()

		for highway in highwayViewArray {
			selectedHwy.wayObj = selectedHwy.connectedNode.turnRestrictionParentWay

			if highway == selectedHwy {
				// highway is selected
				highway.highlightLayer.isHidden = false
				highway.arrowButton.isHidden = true
			} else {
				// highway is deselected, so display restrictions applied to it
				highway.highlightLayer.isHidden = true
				highway.arrowButton.isHidden = false

				let relation = findRelation(
					inList: editedRelations,
					from: selectedHwy.wayObj,
					via: centralNode,
					to: highway.wayObj)
				highway.objRel = relation

				var restriction = ""
				if let relation = relation {
					restriction = relation.tags["restriction"] ?? ""
					if restriction == "",
					   let lastObject = relation.extendedKeys(forKey: "restriction").last
					{
						restriction = relation.tags[lastObject] ?? ""
					}
				}

				if restriction.hasPrefix("no_") {
					highway.restriction = .NO
				} else if restriction.hasPrefix("only_") {
					highway.restriction = .ONLY
				} else {
					highway.restriction = .NONE
				}
				setTurnRestrictionIconForHighway(highway)

				if selectedHwyIsOneWayExit {
					highway.arrowButton.isHidden = true
				} else if highway.isOneWayEnteringCenter() {
					// highway is one way into intersection, so we can't turn onto it
					highway.arrowButton.isHidden = true
				}
			}
		}

		detailView.bringSubviewToFront(detailText)
		detailView.bringSubviewToFront(infoButton)
	}

	func applyTurnRestriction(_ mapData: OsmMapData,
	                          from fromWay: OsmWay,
	                          from fromNode: OsmNode,
	                          to toWay: OsmWay,
	                          to toNode: OsmNode,
	                          restriction: String) -> OsmRelation?
	{
		var relation = findRelation(inList: allRelations, from: fromWay, via: centralNode, to: toWay)
		var newWays: [OsmWay] = []
		AppDelegate.shared.mapView.editorLayer.mapData.consistencyCheck()
		relation = mapData.updateTurnRestrictionRelation(
			relation,
			via: centralNode,
			from: fromWay,
			fromWayNode: fromNode,
			to: toWay,
			toWayNode: toNode,
			turn: restriction,
			newWays: &newWays,
			willSplit: nil)
		AppDelegate.shared.mapView.editorLayer.mapData.consistencyCheck()
		if newWays.count != 0 {
			// had to split some ways to create restriction, so process them
			parentWays.append(contentsOf: newWays)
			TurnRestrictController.setAssociatedTurnRestrictionWays(parentWays)
			for hwy in highwayViewArray {
				hwy.wayObj = hwy.connectedNode.turnRestrictionParentWay
			}
		}
		if let relation = relation {
			if !allRelations.contains(relation) {
				allRelations.append(relation)
			}
		}
		if let relation = relation {
			if !editedRelations.contains(relation) {
				editedRelations.append(relation)
			}
		}

		return relation
	}

	func removeTurnRestriction(_ mapData: OsmMapData, relation: OsmRelation) {
		do {
			let canDelete = try mapData.canDelete(relation)
			canDelete()
		} catch {
			let alert = UIAlertController(
				title: NSLocalizedString("The restriction cannot be deleted", comment: ""),
				message: error.localizedDescription,
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
			present(alert, animated: true)
		}
	}

	class func turnTypeForIntersection(from fromHwy: TurnRestrictHwyView, to toHwy: TurnRestrictHwyView) -> String {
		let angle = toHwy.turnAngleDegrees(from: fromHwy.endPoint) // -180..180

		if fabs(angle) < 23.0 {
			return "straight_on"
		} else if toHwy.wayObj.isOneWay != ONEWAY.NONE,
		          fromHwy.wayObj.isOneWay != ONEWAY.NONE,
		          fabs(fabs(angle) - 180.0) < 40.0
		{
			// more likely a u-turn if both are one-way
			return "u_turn"
		} else if fabs(fabs(angle) - 180.0) < 23.0 {
			return "u_turn"
		} else if angle < 0.0 {
			return "left_turn"
		} else {
			return "right_turn"
		}
	}

	func restrictionName(forHighway targetHwy: TurnRestrictHwyView) -> String? {
		if targetHwy.restriction != .NONE,
		   let fromHwy = selectedFromHwy
		{
			var restrictionName = TurnRestrictController.turnTypeForIntersection(from: fromHwy, to: targetHwy)
			if targetHwy.restriction == .ONLY {
				restrictionName = "only_" + restrictionName
			} else {
				restrictionName = "no_" + restrictionName
			}

			return restrictionName
		}
		return nil
	}

	func setTurnRestrictionIconForHighway(_ targetHwy: TurnRestrictHwyView) {
		if let name = restrictionName(forHighway: targetHwy) {
			targetHwy.arrowButton.setImage(UIImage(named: name), for: .normal)
		} else {
			targetHwy.arrowButton.setImage(UIImage(named: "arrowAllow"), for: .normal)
		}
		targetHwy.rotateButtonForDirection()
	}

	// Enable/disable a left/right/straight turn restriction
	func toggleTurnRestrictionUnsafe(_ targetHwy: TurnRestrictHwyView) {
		let appDelegate = AppDelegate.shared
		let mapData = appDelegate.mapView.editorLayer.mapData

		switch targetHwy.restriction {
		case .NO:
			targetHwy.restriction = .ONLY
		case .NONE:
			targetHwy.restriction = .NO
		case .ONLY:
			targetHwy.restriction = .NONE
		}

		if targetHwy.restriction != .NONE {
			let restrictionName = self.restrictionName(forHighway: targetHwy)!
			targetHwy.objRel = applyTurnRestriction(mapData,
			                                        from: selectedFromHwy!.wayObj,
			                                        from: selectedFromHwy!.connectedNode,
			                                        to: targetHwy.wayObj,
			                                        to: targetHwy.connectedNode,
			                                        restriction: restrictionName)
		} else {
			// Remove Relation
			if targetHwy.objRel != nil {
				removeTurnRestriction(mapData, relation: targetHwy.objRel!)
				editedRelations.removeAll { $0 === targetHwy.objRel }
				targetHwy.objRel = nil
			}
		}

		setTurnRestrictionIconForHighway(targetHwy)

		detailText.text = textForTurn(from: selectedFromHwy!, to: targetHwy)

		appDelegate.mapView.editorLayer.selectedWay = selectedFromHwy?.wayObj
		appDelegate.mapView.editorLayer.setNeedsLayout()
	}

	func toggleTurnRestriction(_ targetHwy: TurnRestrictHwyView) {
		if targetHwy.objRel != nil, targetHwy.objRel?.tags["restriction"] == nil {
			// it contains a restriction relation we don't understand
			let alert = UIAlertController(
				title: NSLocalizedString("Warning", comment: ""),
				message: NSLocalizedString(
					"The turn contains an unrecognized turn restriction style. Proceeding will destroy it.",
					comment: ""),
				preferredStyle: .alert)
			alert
				.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
			alert
				.addAction(UIAlertAction(title: NSLocalizedString("Modify", comment: ""),
				                         style: .destructive, handler: { [self] _ in
				                         	toggleTurnRestrictionUnsafe(targetHwy)
				                         }))
			present(alert, animated: true)
		} else {
			toggleTurnRestrictionUnsafe(targetHwy)
		}
	}

	// Use clicked the U-Turn button
	@objc func uTurnButtonClicked(_ sender: UIButton) {
		let appDelegate = AppDelegate.shared
		let mapData = appDelegate.mapView.editorLayer.mapData

		sender.isSelected = !sender.isSelected

		let isRestricting = sender.isSelected

		if isRestricting {
			let str = "no_u_turn"
			currentUTurnRelation = applyTurnRestriction(
				mapData,
				from: selectedFromHwy!.wayObj,
				from: selectedFromHwy!.connectedNode,
				to: selectedFromHwy!.wayObj,
				to: selectedFromHwy!.connectedNode,
				restriction: str)
		} else {
			if currentUTurnRelation != nil {
				removeTurnRestriction(mapData, relation: currentUTurnRelation!)
				editedRelations.removeAll { $0 === currentUTurnRelation }
				currentUTurnRelation = nil
			}
		}

		if let friendlyDescription = selectedFromHwy?.wayObj.friendlyDescription() {
			detailText.text = isRestricting
				? String.localizedStringWithFormat(
					NSLocalizedString("U-Turn from %@ prohibited", comment: ""),
					friendlyDescription)
				: String.localizedStringWithFormat(
					NSLocalizedString("U-Turn from %@ allowed", comment: ""),
					friendlyDescription)
		}

		appDelegate.mapView.editorLayer.setNeedsLayout()
	}

	// Getting restriction relation by From node, To node and Via node
	func findRelation(
		inList relationList: [OsmRelation],
		from fromTarget: OsmWay?,
		via viaTarget: OsmNode?,
		to toTarget: OsmWay?) -> OsmRelation?
	{
		if let fromTarget = fromTarget,
		   let viaTarget = viaTarget,
		   let toTarget = toTarget
		{
			for relation in relationList {
				if relation.member(byRole: "from")?.obj as? OsmWay === fromTarget,
				   relation.member(byRole: "via")?.obj as? OsmNode === viaTarget,
				   relation.member(byRole: "to")?.obj as? OsmWay === toTarget
				{
					return relation
				}
			}
		}
		return nil
	}

	// Close the window if user touches outside it
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		let locationPoint = touches.first?.location(in: view)
		let viewPoint = viewWithTitle.convert(locationPoint ?? CGPoint.zero, from: view)

		if !viewWithTitle.point(inside: viewPoint, with: event) {
			dismiss(animated: true)
		}
	}

	// Convert location point to CGPoint
	func screenPoint(forLatLon pt: LatLon) -> CGPoint {
		return AppDelegate.shared.mapView.viewPort.mapTransform.screenPoint(forLatLon: pt, birdsEye: false)
	}
}
