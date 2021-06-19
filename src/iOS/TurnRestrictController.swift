//
//  TurnRestrictController.swift
//  Go Map!!
//
//  Created by Mukul Bakshi on 02/11/17.
//  Copyright © 2017 Bryce Cogswell. All rights reserved.
//

import UIKit

//width of the way line e.g 12, 17, 18 AND shadow width is +4 e.g 16, 21, 22
let DEFAULT_POPUPLINEWIDTH = 12

class TurnRestrictController: UIViewController {
    private var _parentWays: [OsmWay] = []
    private var _highwayViewArray = [TurnRestrictHwyView]() //	Array of TurnRestrictHwyView to Store number of ways
    private var _selectedFromHwy: TurnRestrictHwyView?
    private var _uTurnButton: UIButton?
    private var _currentUTurnRelation: OsmRelation?
    private var _allRelations: [OsmRelation] = []
    private var _editedRelations: [OsmRelation] = []

    @IBOutlet var constraintViewWithTitleHeight: NSLayoutConstraint!
    @IBOutlet var constraintViewWithTitleWidth: NSLayoutConstraint!
    @IBOutlet var viewWithTitle: UIView!
    @IBOutlet var detailView: UIView!
    @IBOutlet var infoButton: UIButton!
    @IBOutlet var detailText: UILabel!
    var centralNode: OsmNode! // the central node

    override func viewDidLoad() {
        super.viewDidLoad()
        _highwayViewArray = []
        createMapWindow()

        AppDelegate.shared.mapView.editorLayer.mapData.beginUndoGrouping()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        AppDelegate.shared.mapView.editorLayer.mapData.endUndoGrouping()
    }

    // To dray Popup window
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
		var parentWays = mapData.waysContaining(centralNode)
		parentWays = parentWays.filter({ $0.tags["highway"] != nil	})
		_parentWays = parentWays

		// Creating roads using adjacent connected nodes
        let conectedNodes = TurnRestrictController.getAdjacentNodes(centralNode, ways: self._parentWays)
        createHighwayViews(conectedNodes)

        // if there is only one reasonable thing to highlight initially select it
        var fromWay: OsmWay? = nil
        if _allRelations.count == 1 {
            // only one relation, so select it
			fromWay = _allRelations.last?.member(byRole: "from")?.obj as? OsmWay
		} else {
            // no relations or multiple relations, so select highway already selected by user
            let editor = AppDelegate.shared.mapView.editorLayer
            fromWay = editor.selectedWay
        }
        if let fromWay = fromWay {
            for hwy in _highwayViewArray {
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

    //MARK: Create Path From Points
    func createHighwayViews(_ adjacentNodesArray: [OsmNode]) {
		let centerNodePos = screenPoint(forLatitude: centralNode!.latLon.lat, longitude: centralNode!.latLon.lon)
		let detailViewCenter = CGPoint(x: detailView.bounds.midX, y: detailView.bounds.midY)
		let positionOffset = centerNodePos.minus(detailViewCenter)

        detailText.text = NSLocalizedString("Select a highway approaching the intersection", comment: "")

        // Get relations related to restrictions
        _allRelations = []
		for relation in centralNode?.parentRelations ?? [] {
			if relation.isRestriction(),
			   relation.members.count >= 3
			{
				_allRelations.append(relation)
			}
		}

        _editedRelations = _allRelations

        // create highway views
        for node in adjacentNodesArray {
            // get location of node
			var nodePoint = screenPoint(forLatitude: node.latLon.lat, longitude: node.latLon.lon)
			nodePoint = nodePoint.minus(positionOffset)

            // force highway segment to extend from center node to edge of view
            let size = detailView.bounds.size
			let direction = OSMPoint(x: Double(nodePoint.x - detailViewCenter.x), y: Double(nodePoint.y - detailViewCenter.y))
			let distTop = DistanceToVector(OSMPoint(detailViewCenter), direction, OSMPoint.zero, OSMPoint(x: Double(size.width), y: 0))
			let distLeft = DistanceToVector(OSMPoint(detailViewCenter), direction, OSMPoint.zero, OSMPoint(x: 0, y: Double(size.height)))
			let distRight = DistanceToVector(OSMPoint(detailViewCenter), direction, OSMPoint(x: Double(size.width), y: 0), OSMPoint(x: 0, y: Double(size.height)))
			let distBottom = DistanceToVector(OSMPoint(detailViewCenter), direction, OSMPoint(x: 0, y: Double(size.height)), OSMPoint(x: Double(size.width), y: 0))
            var best: Double = Double(Float.greatestFiniteMagnitude)
            if distTop > 0 && distTop < best {
                best = distTop
            }
            if distLeft > 0 && distLeft < best {
                best = distLeft
            }
            if distRight > 0 && distRight < best {
                best = distRight
            }
            if distBottom > 0 && distBottom < best {
                best = distBottom
            }
            nodePoint = CGPoint(x: CGFloat(Double(detailViewCenter.x) + best * direction.x), y: CGFloat(Double(detailViewCenter.y) + best * direction.y))

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
            highwayLayer.strokeColor = node.turnRestrictionParentWay.renderInfo?.lineColor?.cgColor ?? UIColor.black.cgColor
            highwayLayer.bounds = detailView.bounds
            highwayLayer.position = detailViewCenter
            highwayLayer.masksToBounds = false

            // Highway view
            let hwyView = TurnRestrictHwyView(frame: detailView.bounds)
            hwyView.wayObj = node.turnRestrictionParentWay
            hwyView.centerNode = centralNode
            hwyView.connectedNode = node
            hwyView.centerPoint = detailViewCenter
            hwyView.endPoint = nodePoint
            hwyView.parentWaysArray = _parentWays
            hwyView.highwayLayer = highwayLayer
            hwyView.highlightLayer = highlightLayer
            hwyView.backgroundColor = UIColor.clear

            hwyView.layer.addSublayer(highwayLayer)
            hwyView.layer.insertSublayer(highlightLayer, below: highwayLayer)

            hwyView.createTurnRestrictionButton()
            hwyView.createOneWayArrowsForHighway()
            hwyView.arrowButton?.isHidden = true
            hwyView.restrictionChangedCallback = { objLine in
				self.toggleTurnRestriction( objLine )
            }
            hwyView.highwaySelectedCallback = { [self] objLine in
                select(fromHighway: objLine)
            }

            detailView.addSubview(hwyView)
            _highwayViewArray.append( hwyView )
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
        _uTurnButton = UIButton(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        _uTurnButton?.imageView?.contentMode = .scaleAspectFit
        _uTurnButton?.center = detailViewCenter
        _uTurnButton?.layer.borderWidth = 1.0
        _uTurnButton?.layer.cornerRadius = 2.0
        _uTurnButton?.layer.borderColor = UIColor.black.cgColor

        _uTurnButton?.setImage(UIImage(named: "uTurnAllow"), for: .normal)
        _uTurnButton?.setImage(UIImage(named: "no_u_turn"), for: .selected)
        _uTurnButton?.addTarget(self, action: #selector(uTurnButtonClicked(_:)), for: .touchUpInside)
        if let _uTurnButton = _uTurnButton {
            detailView.addSubview(_uTurnButton)
        }
        _uTurnButton?.isHidden = true
    }

    @IBAction func infoButtonPressed(_ sender: Any) {
        let message = NSLocalizedString(
            """
                Turn restrictions specify which roads you can turn onto when entering an intersection from a given direction.\n\n\
                Select the highway from which you are approaching the intersection, then tap an arrow to toggle whether the destination road is a permitted route.
                """,
            comment: "")
        let alert = UIAlertController(title: NSLocalizedString("Turn Restrictions", comment: ""), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
        present(alert, animated: true)
    }

    func textForTurn(from fromHwy: TurnRestrictHwyView, to toHwy: TurnRestrictHwyView) -> String? {
		if let fromName = fromHwy.wayObj?.friendlyDescription(),
		   let toName = toHwy.wayObj?.friendlyDescription()
		{
			switch toHwy.restriction {
				case .NONE:
					return String.localizedStringWithFormat(NSLocalizedString("Travel ALLOWED from %@ to %@", comment: ""), fromName, toName)
				case .NO:
					return String.localizedStringWithFormat(NSLocalizedString("Travel PROHIBITED from %@ to %@", comment: ""), fromName, toName)
				case .ONLY:
					return String.localizedStringWithFormat(NSLocalizedString("Travel ONLY from %@ to %@", comment: ""), fromName, toName)
				default:
					break
			}
		}
        return nil
    }

    // Select a new "From" highway
    func select(fromHighway selectedHwy: TurnRestrictHwyView) {
        _selectedFromHwy = selectedHwy

        let editor = AppDelegate.shared.mapView.editorLayer
        editor.selectedWay = selectedHwy.wayObj

		selectedHwy.wayObj = selectedHwy.connectedNode?.turnRestrictionParentWay
		_uTurnButton?.isHidden = _selectedFromHwy?.wayObj?.isOneWay != ONEWAY._NONE

        let angle = TurnRestrictHwyView.heading(from: selectedHwy.endPoint, to: selectedHwy.centerPoint)
		_uTurnButton?.transform = CGAffineTransform(rotationAngle: .pi + CGFloat(angle))

        _currentUTurnRelation = findRelation(
            _editedRelations,
            from: _selectedFromHwy?.wayObj,
            via: centralNode,
            to: _selectedFromHwy?.wayObj)
        _uTurnButton?.isSelected = _currentUTurnRelation != nil

        if let friendlyDescription = selectedHwy.wayObj?.friendlyDescription() {
            detailText.text = String.localizedStringWithFormat(NSLocalizedString("Travel from %@", comment: ""), friendlyDescription)
        }

        // highway exits center one-way
        let selectedHwyIsOneWayExit = selectedHwy.isOneWayExitingCenter()

        for highway in _highwayViewArray {
            selectedHwy.wayObj = selectedHwy.connectedNode?.turnRestrictionParentWay

			if highway == selectedHwy {

                // highway is selected
                highway.highlightLayer?.isHidden = false
                highway.arrowButton?.isHidden = true
            } else {

                // highway is deselected, so display restrictions applied to it
                highway.highlightLayer?.isHidden = true

				guard let relation = findRelation(_editedRelations, from: selectedHwy.wayObj, via: centralNode, to: highway.wayObj)
				else { return }

				highway.objRel = relation
				highway.arrowButton?.isHidden = false

                var restriction = relation.tags["restriction"]
                if restriction == nil,
				   let lastObject = relation.extendedKeys(forKey: "restriction").last
				{
					restriction = relation.tags[lastObject]
				}
				guard let restriction = restriction else { return }

				if restriction.hasPrefix("no_") {
					highway.restriction = .NO
                } else if restriction.hasPrefix("only_") {
					highway.restriction = .ONLY
                } else {
					highway.restriction = .NONE
                }
                setTurnRestrictionIconForHighway(highway)

                if selectedHwyIsOneWayExit {
                    highway.arrowButton?.isHidden = true
                } else if highway.isOneWayEnteringCenter() {
                    highway.arrowButton?.isHidden = true // highway is one way into intersection, so we can't turn onto it
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
        var relation = findRelation(_allRelations, from: fromWay, via: centralNode, to: toWay)
		var newWays: [OsmWay] = []
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
        if newWays.count != 0 {
            // had to split some ways to create restriction, so process them
			_parentWays.append(contentsOf: newWays)
			TurnRestrictController.setAssociatedTurnRestrictionWays(_parentWays)
			for hwy in _highwayViewArray {
				hwy.wayObj = hwy.connectedNode?.turnRestrictionParentWay
			}
        }
        if let relation = relation {
            if !_allRelations.contains(relation) {
                _allRelations.append(relation)
            }
        }
        if let relation = relation {
            if !_editedRelations.contains(relation) {
                _editedRelations.append(relation)
            }
        }

        return relation
    }

    func removeTurnRestriction(_ mapData: OsmMapData, relation: OsmRelation) {
        var error: String? = nil
		let canDelete = mapData.canDelete(relation, error: &error)
        if let canDelete = canDelete {
            canDelete()
        } else {
            let alert = UIAlertController(title: NSLocalizedString("The restriction cannot be deleted", comment: ""), message: error as String?, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
            present(alert, animated: true)
        }
    }

    class func turnTypeForIntersection(from fromHwy: TurnRestrictHwyView, to toHwy: TurnRestrictHwyView) -> String? {
        let angle = toHwy.turnAngleDegrees(from: fromHwy.endPoint) // -180..180

		if fabs(angle) < 23.0 {
            return "straight_on"
		} else if (toHwy.wayObj?.isOneWay ?? ONEWAY._NONE) != ONEWAY._NONE &&
					(fromHwy.wayObj?.isOneWay ?? ONEWAY._NONE) != ONEWAY._NONE &&
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
		   let fromHwy = _selectedFromHwy
		{
			var restrictionName = TurnRestrictController.turnTypeForIntersection(from: fromHwy, to: targetHwy)
			if targetHwy.restriction == .ONLY {
                restrictionName = "only_" + (restrictionName ?? "")
            } else {
                restrictionName = "no_" + (restrictionName ?? "")
            }

            return restrictionName
        }
		return nil
    }

    func setTurnRestrictionIconForHighway(_ targetHwy: TurnRestrictHwyView) {
        let name = restrictionName(forHighway: targetHwy)
        if let name = name {
            targetHwy.arrowButton?.setImage(UIImage(named: name), for: .normal)
        } else {
            targetHwy.arrowButton?.setImage(UIImage(named: "arrowAllow"), for: .normal)
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
            default:
                break
        }

		if targetHwy.restriction != .NONE {

            let restrictionName = self.restrictionName(forHighway: targetHwy)!
            targetHwy.objRel = applyTurnRestriction(mapData,
													from: _selectedFromHwy!.wayObj!,
													from: _selectedFromHwy!.connectedNode!,
													to: targetHwy.wayObj!,
													to: targetHwy.connectedNode!,
													restriction: restrictionName)
        } else {

            // Remove Relation
            if targetHwy.objRel != nil {
                removeTurnRestriction(mapData, relation: targetHwy.objRel!)
				_editedRelations.removeAll { $0 === targetHwy.objRel }
                targetHwy.objRel = nil
            }
        }

        setTurnRestrictionIconForHighway(targetHwy)

		detailText.text = textForTurn(from: _selectedFromHwy!, to: targetHwy)

        appDelegate.mapView.editorLayer.selectedWay = _selectedFromHwy?.wayObj
        appDelegate.mapView.editorLayer.setNeedsLayout()
    }

    func toggleTurnRestriction(_ targetHwy: TurnRestrictHwyView) {
		if targetHwy.objRel != nil && targetHwy.objRel?.tags["restriction"] == nil {
			// it contains a restriction relation we don't understand
            let alert = UIAlertController(title: NSLocalizedString("Warning", comment: ""), message: NSLocalizedString("The turn contains an unrecognized turn restriction style. Proceeding will destroy it.", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: NSLocalizedString("Modify", comment: ""), style: .destructive, handler: { [self] action in
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
			_currentUTurnRelation = applyTurnRestriction(mapData, from: _selectedFromHwy!.wayObj!, from: _selectedFromHwy!.connectedNode!, to: _selectedFromHwy!.wayObj!, to: _selectedFromHwy!.connectedNode!, restriction: str)
		} else {
            if _currentUTurnRelation != nil {
				removeTurnRestriction(mapData, relation: _currentUTurnRelation!)
				_editedRelations.removeAll { $0 === _currentUTurnRelation }
				_currentUTurnRelation = nil
            }
        }

        if let friendlyDescription = _selectedFromHwy?.wayObj?.friendlyDescription() {
            detailText.text = isRestricting
                ? String.localizedStringWithFormat(NSLocalizedString("U-Turn from %@ prohibited", comment: ""), friendlyDescription)
                : String.localizedStringWithFormat(NSLocalizedString("U-Turn from %@ allowed", comment: ""), friendlyDescription)
        }

        appDelegate.mapView.editorLayer.setNeedsLayout()
    }

    // Getting restriction relation by From node, To node and Via node
    func findRelation(
        _ relationList: [OsmRelation],
        from fromTarget: OsmWay?,
        via viaTarget: OsmNode?,
        to toTarget: OsmWay?
    ) -> OsmRelation? {
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
	func screenPoint(forLatitude latitude: Double, longitude: Double) -> CGPoint {
		// FIXME: why doesn't this use the mapView function directly?
		var pt = MapTransform.mapPoint(forLatLon: LatLon(latitude: latitude, longitude: longitude))
		pt = pt.withTransform( AppDelegate.shared.mapView.screenFromMapTransform )
		return CGPoint(pt)
	}
}
