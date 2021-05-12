//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  OsmMapLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/5/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

let SHOW_3D = 1
private let DefaultHitTestRadius: CGFloat = 10.0 // how close to an object do we need to tap to select it
private let DragConnectHitTestRadius = DefaultHitTestRadius * 0.6 // how close to an object do we need to drag a node to connect to it
let MinIconSizeInPixels = 0.0
let FADE_INOUT = 0
let SINGLE_SIDED_WALLS = 1
let PATH_SCALING = 256 * 256.0 // scale up sizes in paths so Core Animation doesn't round them off
let DEFAULT_LINECAP = CAShapeLayerLineCap.square.rawValue
let DEFAULT_LINEJOIN = CAShapeLayerLineJoin.miter.rawValue
private let Pixels_Per_Character: CGFloat = 8.0

let NodeHighlightRadius: CGFloat = 6.0

class EditorMapLayer: CALayer {
    var iconSize = CGSize.zero
    var highwayScale = 0.0
    var shownObjects: [OsmBaseObject]?
    var fadingOutSet: NSMutableSet?
    var highlightLayers: [CALayer]?
    var isPerformingLayout = false
    var baseLayer: CATransformLayer?
    
    var enableObjectFilters = false // turn all filters on/on
    var showLevel = false // filter for building level
    var showLevelRange: String? // range of levels for building level
    var showPoints = false
    var showTrafficRoads = false
    var showServiceRoads = false
    var showPaths = false
    var showBuildings = false
    var showLanduse = false
    var showBoundaries = false
    var showWater = false
    var showRail = false
    var showPower = false
    var showPastFuture = false
    var showOthers = false
    var mapView: MapView?
    var whiteText = false
    var selectedNode: OsmNode?
    var selectedWay: OsmWay?
    var selectedRelation: OsmRelation?
    private(set) var selectedPrimary: OsmBaseObject? // way or node, but not a node in a selected way
    private(set) var mapData: OsmMapData?
    var addNodeInProgress = false
    private(set) var atVisibleObjectLimit = false
    private weak var geekbenchScoreProvider: GeekbenchScoreProviding?
    
    init(mapView: MapView?) {
        super.init()
        self.mapView = mapView
        geekbenchScoreProvider = GeekbenchScoreProvider()
        
        let appDelegate = AppDelegate.shared
        
        whiteText = true
        
        fadingOutSet = NSMutableSet()
        
        // observe changes to geometry
        self.mapView?.addObserver(self, forKeyPath: "screenFromMapTransform", options: 0, context: nil)
        
        OsmmapData?.setEditorMapLayerForArchive(self)
        
        let defaults = UserDefaults.standard
        defaults.register(
            defaults: [
                "editor.enableObjectFilters": NSNumber(value: false),
                "editor.showLevel": NSNumber(value: false),
                "editor.showLevelRange": "",
                "editor.showPoints": NSNumber(value: true),
                "editor.showTrafficRoads": NSNumber(value: true),
                "editor.showServiceRoads": NSNumber(value: true),
                "editor.showPaths": NSNumber(value: true),
                "editor.showBuildings": NSNumber(value: true),
                "editor.showLanduse": NSNumber(value: true),
                "editor.showBoundaries": NSNumber(value: true),
                "editor.showWater": NSNumber(value: true),
                "editor.showRail": NSNumber(value: true),
                "editor.showPower": NSNumber(value: true),
                "editor.showPastFuture": NSNumber(value: true),
                "editor.showOthers": NSNumber(value: true)
            ])
        
        
        enableObjectFilters = defaults.bool(forKey: "editor.enableObjectFilters")
        showLevel = defaults.bool(forKey: "editor.showLevel")
        showLevelRange = defaults.object(forKey: "editor.showLevelRange")
        showPoints = defaults.bool(forKey: "editor.showPoints")
        showTrafficRoads = defaults.bool(forKey: "editor.showTrafficRoads")
        showServiceRoads = defaults.bool(forKey: "editor.showServiceRoads")
        showPaths = defaults.bool(forKey: "editor.showPaths")
        showBuildings = defaults.bool(forKey: "editor.showBuildings")
        showLanduse = defaults.bool(forKey: "editor.showLanduse")
        showBoundaries = defaults.bool(forKey: "editor.showBoundaries")
        showWater = defaults.bool(forKey: "editor.showWater")
        showRail = defaults.bool(forKey: "editor.showRail")
        showPower = defaults.bool(forKey: "editor.showPower")
        showPastFuture = defaults.bool(forKey: "editor.showPastFuture")
        showOthers = defaults.bool(forKey: "editor.showOthers")
        
        var t = CACurrentMediaTime()
        mapData = OsmMapData()
        t = CACurrentMediaTime() - t
#if os(iOS)
        if (mapData != nil) && (mapView?.enableAutomaticCacheManagement ?? false) {
            mapData?.discardStaleData()
        } else if (mapData != nil) && t > 5.0 {
            // need to pause before posting the alert because the view controller isn't ready here yet
            DispatchQueue.main.async(execute: { [self] in
                let text = NSLocalizedString("Your OSM data cache is getting large, which may lead to slow startup and shutdown times.\n\nYou may want to clear the cache (under Display settings) to improve performance.", comment: "")
                let alertView = UIAlertController(title: NSLocalizedString("Cache size warning", comment: ""), message: text, preferredStyle: .alert)
                alertView.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
                self.mapView?.mainViewController.present(alertView, animated: true)
            })
        }
#endif
        if mapData == nil {
            mapData = OsmMapData()
            mapData?.purgeHard() // force database to get reset
        }
        
        mapData?.credentialsUserName = appDelegate?.userName
        mapData?.credentialsPassword = appDelegate?.userPassword
        
        weak var weakSelf = self
        mapData?.undoContextForComment = { comment in
            let strongSelf = weakSelf
            if strongSelf == nil {
                return nil
            }
            var trans = strongSelf?.mapView?.screenFromMapTransform
            let location = Data(bytes: &trans, count: MemoryLayout.size(ofValue: trans))
            var dict: [AnyHashable : Any] = [:]
            dict["comment"] = comment ?? ""
            dict["location"] = location
            let pushpin = strongSelf?.mapView?.pushpinPosition
            if !(pushpin?.x.isNaN ?? false) {
                dict["pushpin"] = NSCoder.string(for: strongSelf?.mapView?.pushpinPosition ?? CGPoint.zero)
            }
            if strongSelf?.selectedRelation != nil {
                if let selectedRelation = strongSelf?.selectedRelation {
                    dict["selectedRelation"] = selectedRelation
                }
            }
            if strongSelf?.selectedWay != nil {
                if let selectedWay = strongSelf?.selectedWay {
                    dict["selectedWay"] = selectedWay
                }
            }
            if strongSelf?.selectedNode != nil {
                if let selectedNode = strongSelf?.selectedNode {
                    dict["selectedNode"] = selectedNode
                }
            }
            return dict
        }
        
        baseLayer = CATransformLayer()
        if let baseLayer = baseLayer {
            addSublayer(baseLayer)
        }
        
#if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(fontSizeDidChange(_:)), name: UIContentSizeCategory.didChangeNotification, object: nil)
#endif
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func observeValue(forKeyPath keyPath: String, of object: Any, change: [NSKeyValueChangeKey : Any], context: UnsafeMutableRawPointer?) {
        if (object as? NSObject) == mapView && (keyPath == "screenFromMapTransform") {
            updateMapLocation()
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    @objc func fontSizeDidChange(_ notification: Notification?) {
        resetDisplayLayers()
    }
    
    func setBounds(_ bounds: CGRect) {
        super.setBounds(bounds)
        baseLayer?.frame = bounds
        baseLayer?.bounds = bounds // need to set both of these so bounds stays in sync with superlayer bounds
        updateMapLocation()
    }
    
    func save() {
        mapData?.save()
    }
    
    func setEnableObjectFilters(_ enableObjectFilters: Bool) {
        if enableObjectFilters != self.enableObjectFilters {
            self.enableObjectFilters = enableObjectFilters
            UserDefaults.standard.set(self.enableObjectFilters, forKey: "editor.enableObjectFilters")
        }
    }
    
    func setShowLevelRange(_ showLevelRange: String?) {
        if showLevelRange == self.showLevelRange {
            return
        }
        self.showLevelRange = showLevelRange
        UserDefaults.standard.set(self.showLevelRange, forKey: "editor.showLevelRange")
        mapData?.clearCachedProperties()
    }
    
    //    #define SET_FILTER(name)\
    //    -(void)setShow##name:(BOOL)on {\
    //        if ( on != _show##name ) {\
    //            _show##name = on;\
    //            [[NSUserDefaults standardUserDefaults] setBool:_show##name forKey:@"editor.show"#name];\
    //            [_mapData clearCachedProperties];\
    //        }\
    //    }
    //    SET_FILTER(Level)
    //    SET_FILTER(Points)
    //    SET_FILTER(TrafficRoads)
    //    SET_FILTER(ServiceRoads)
    //    SET_FILTER(Paths)
    //    SET_FILTER(Buildings)
    //    SET_FILTER(Landuse)
    //    SET_FILTER(Boundaries)
    //    SET_FILTER(Water)
    //    SET_FILTER(Rail)
    //    SET_FILTER(Power)
    //    SET_FILTER(PastFuture)
    //    SET_FILTER(Others)
    //    #undef SET_FILTER
    
    // MARK: Map data
    let MinIconSizeInPixels: Double = 24
    let MinIconSizeInMeters: Double = 2.0
    
    func updateIconSize() {
        let metersPerPixel: Double = mapView?.metersPerPixel() ?? 0.0
        if MinIconSizeInPixels * metersPerPixel < MinIconSizeInMeters {
            iconSize.width = CGFloat(round(MinIconSizeInMeters / metersPerPixel))
            iconSize.height = CGFloat(round(MinIconSizeInMeters / metersPerPixel))
        } else {
            iconSize.width = CGFloat(MinIconSizeInPixels)
            iconSize.height = CGFloat(MinIconSizeInPixels)
        }
        
#if true
            highwayScale = 2.0
#else
            let laneWidth = 1.0 // meters per lane
            var scale = laneWidth / metersPerPixel
            if scale < 1 {
                scale = 1
            }
            highwayScale = scale
#endif
    }
    
    func purgeCachedDataHard(_ hard: Bool) {
        selectedNode = nil
        selectedWay = nil
        selectedRelation = nil
        if hard {
            mapData?.purgeHard()
        } else {
            mapData?.purgeSoft()
        }
        
        setNeedsLayout()
        updateMapLocation()
    }
    
    func updateMapLocation() {
        if isHidden {
            mapData?.cancelCurrentDownloads()
            return
        }
        
        if mapView?.screenFromMapTransform.a == 1.0 {
            return // identity, we haven't been initialized yet
        }
        
        let box = mapView?.screenLongitudeLatitude()
        if let box = box {
            if (box.size.height <= 0) || (box.size.width <= 0) {
                return
            }
            
            updateIconSize()
            
            mapData?.update(withBox: box, progressDelegate: mapView) { [self] partial, error in
                if let error = error {
                    DispatchQueue.main.async(execute: { [self] in
                        // present error asynchrounously so we don't interrupt the current UI action
                        if !isHidden {
                            // if we've been hidden don't bother displaying errors
                            mapView?.presentError(error, flash: true)
                        }
                    })
                } else {
                    setNeedsLayout()
                }
            }
        }
        setNeedsLayout()
    }
    
    func didReceiveMemoryWarning() {
        purgeCachedDataHard(false)
        save()
    }
    
    // MARK: Draw Ocean
    enum SIDE : Int {
        case left
        case top
        case right
        case bottom
    }
    
    private func AppendNodes(_ list: inout NSMutableArray, _ way: OsmWay, _ addToBack: Bool, _ reverseNodes: Bool) {
        let nodes = reverseNodes ? way.nodes.reversed() : way.nodes.enumerated()
        if addToBack {
            // insert at back of list
            var first = true
            if let nodes = nodes {
                for node in nodes {
                    guard let node = node as? OsmNode else {
                        continue
                    }
                    if first {
                        first = false
                    } else {
                        list.append(node)
                    }
                }
            }
        } else {
            // insert at front of list
            var a = NSMutableArray.init(capacity: way.nodes.count)
            if let nodes = nodes {
                for node in nodes {
                    guard let node = node as? OsmNode else {
                        continue
                    }
                    a.add(node)
                }
            }
            a.removeLastObject()
            let loc = NSIndexSet(indexesIn: NSRange(location: 0, length: a.count))
            for (objectIndex, insertionIndex) in loc.enumerated() {
                list.insert((a)[objectIndex], at: insertionIndex)
                
            }
        }
    }
    
    @inline(__always) private func IsPointInRect(_ pt: OSMPoint, _ rect: OSMRect) -> Bool {
        let delta = 0.0001
        if pt.x < rect.origin.x - delta {
            return false
        }
        if pt.x > rect.origin.x + rect.size.width + delta {
            return false
        }
        if pt.y < rect.origin.y - delta {
            return false
        }
        if pt.y > rect.origin.y + rect.size.height + delta {
            return false
        }
        return true
    }
    
    private func WallForPoint(_ pt: OSMPoint, _ rect: OSMRect) -> SIDE {
        let delta: CGFloat = 0.01
        if CGFloat(abs(pt.x - rect.origin.x)) < delta {
            return SIDE.left
        }
        if CGFloat(abs(pt.y - rect.origin.y)) < delta {
            return SIDE.top
        }
        if CGFloat(abs(pt.x - rect.origin.x - rect.size.width)) < delta {
            return SIDE.right
        }
        if CGFloat(abs(pt.y - rect.origin.y - rect.size.height)) < delta {
            return SIDE.bottom
        }
        assert(false)
        return -1
    }
    
    private func IsClockwisePolygon(_ points: NSArray) -> Bool {
        if points[0] != points.lastObject {
            DLog("bad polygon")
            return false
        }
        if (points.count) < 4 {
            // first and last repeat
            DLog("bad polygon")
            return false
        }
        var area: Double = 0
        var first = true
        var offset: OSMPoint
        var previous: OSMPoint
        for value in points {
            guard let value = value as? OSMPointBoxed else {
                continue
            }
            let point = value.point
            if first {
                offset = point
                previous.y = 0
                previous.x = previous.y
                first = false
            } else {
                let current = OSMPoint(x: (point.x - offset.x), y: (point.y - offset.y))
                area += previous.x * current.y - previous.y * current.x
                previous = current
            }
        }
        area *= 0.5
        return area >= 0
    }
    
    private func RotateLoop(_ loop: inout NSMutableArray, _ viewRect: OSMRect) -> Bool {
        if loop[0] != loop.lastObject {
            DLog("bad loop")
            return false
        }
        if loop.count < 4 {
            DLog("bad loop")
            return false
        }
        loop.removeLastObject()
        var index = 0
        for value in loop {
            guard let value = value as? OSMPointBoxed else {
                continue
            }
            if !OSMRectContainsPoint(viewRect, value.point) {
                break
            }
            index += 1
            if index >= loop.count {
                index = -1
                break
            }
        }
        if index > 0 {
            let set = NSIndexSet(indexesIn: NSRange(location: 0, length: index))
            let a = set.map { loop[$0] }
            for deletionIndex in set.reversed() { loop.remove(deletionIndex) }
            loop.addObjects(from: a)
        }
        loop.add(loop[0])
        return index >= 0
    }
    
    @inline(__always) private func Sort4(_ p: inout [Double]) {
        if p[0] > p[1] {
            let t = p[1]
            p[1] = p[0]
            p[0] = t
        }
        if p[2] > p[3] {
            let t = p[3]
            p[3] = p[2]
            p[2] = t
        }
        if p[0] > p[2] {
            let t = p[2]
            p[2] = p[0]
            p[0] = t
        }
        if p[1] > p[3] {
            let t = p[3]
            p[3] = p[1]
            p[1] = t
        }
        if p[1] > p[2] {
            let t = p[2]
            p[2] = p[1]
            p[1] = t
        }
    }
    
    @inline(__always) private func Sort3(_ p: inout [Double]) {
        if p[0] > p[1] {
            let t = p[1]
            p[1] = p[0]
            p[0] = t
        }
        if p[0] > p[2] {
            let t = p[2]
            p[2] = p[0]
            p[0] = t
        }
        if p[1] > p[2] {
            let t = p[2]
            p[2] = p[1]
            p[1] = t
        }
    }
    
    @inline(__always) private func Sort2(_ p: inout [Double]) {
        if p[0] > p[1] {
            let t = p[1]
            p[1] = p[0]
            p[0] = t
        }
    }
    
    private func ClipLineToRect(_ p1: OSMPoint, _ p2: OSMPoint, _ rect: OSMRect, _ pts: OSMPoint) -> Int {
        if p1.x.isInfinite || p2.x.isInfinite {
            return 0
        }
        
        let top: Double = rect.origin.y
        let bottom: Double = rect.origin.y + rect.size.height
        let left: Double = rect.origin.x
        let right: Double = rect.origin.x + rect.size.width
        
        let dx: Double = p2.x - p1.x
        let dy: Double = p2.y - p1.y
        
        // get distances in terms of 0..1
        // we compute crossings for not only the rectangles walls but also the projections of the walls outside the rectangle,
        // so 4 possible interesection points
        var cross: [Double] = [0]
        var crossSrc: Int = 0
        if dx != 0.0 {
            let vLeft = CGFloat((left - p1.x) / dx)
            let vRight = CGFloat((right - p1.x) / dx)
            if vLeft >= 0 && vLeft <= 1 {
                cross[crossSrc] = Double(vLeft)
                crossSrc += 1
            }
            if vRight >= 0 && vRight <= 1 {
                cross[crossSrc] = Double(vRight)
                crossSrc += 1
            }
        }
        if dy != 0.0 {
            let vTop = CGFloat((top - p1.y) / dy)
            let vBottom = CGFloat((bottom - p1.y) / dy)
            if vTop >= 0 && vTop <= 1 {
                cross[crossSrc] = Double(vTop)
                crossSrc += 1
            }
            if vBottom >= 0 && vBottom <= 1 {
                cross[crossSrc] = Double(vBottom)
                crossSrc += 1
            }
        }
        
        // sort crossings according to distance from p1
        switch crossSrc {
        case 2:
            Sort2(&cross)
        case 3:
            Sort3(&cross)
        case 4:
            Sort4(&cross)
        default:
            break
        }
        
        // get the points that are actually inside the rect (max 2)
        var crossCnt: Int = 0
        for i in 0..<crossSrc {
            let pt = OSMPoint(x: (p1.x + cross[i] * dx), y: (p1.y + cross[i] * dy))
            if IsPointInRect(pt, rect) {
                pts[crossCnt] = pt;
                crossCnt += 1
            }
        }
        
#if DEBUG
            assert(crossCnt <= 2)
            for i in 0..<crossCnt {
                assert(IsPointInRect(pts[i], rect))
            }
#endif
        
        return crossCnt
    }
    
    
    // input is an array of OsmWay
    // output is an array of arrays of OsmNode
    // take a list of ways and return a new list of ways with contiguous ways joined together.
    func joinConnectedWays(_ origList: inout NSMutableArray) -> NSMutableArray {
        // connect ways together forming congiguous runs
        var newList: NSMutableArray = []
        while (origList.count != 0) {
            // find all connected segments
            guard let way = origList.lastObject as? OsmWay else {
                break // didn't find anything to connect to
            }
            origList.remove(way)
            
            var firstNode = way.nodes[0]
            var lastNode = way.nodes.last
            var nodeList: NSMutableArray = NSMutableArray.init(object: firstNode)
            AppendNodes(&nodeList, way, true, false)
            while nodeList[0] != nodeList.lastObject {
                // find a way adjacent to current list
                for way in origList {
                    if lastNode == (way.nodes[0] as? OsmNode) {
                        AppendNodes(&nodeList, way, true, false)
                        lastNode = nodeList.last
                        break
                    }
                    if lastNode == (way.nodes.last as? OsmNode) {
                        AppendNodes(&nodeList, way, true, true)
                        lastNode = nodeList.last
                        break
                    }
                    if firstNode == (way.nodes.last as? OsmNode) {
                        AppendNodes(&nodeList, way, false, false)
                        firstNode = nodeList[0]
                        break
                    }
                    if firstNode == (way.nodes[0] as? OsmNode) {
                        AppendNodes(&nodeList, way, false, true)
                        firstNode = nodeList[0]
                        break
                    }
                }
                origList.remove(way)
            }
            newList.add(nodeList)
        }
        return newList
    }
}
    func convertNodes(toScreenPoints nodeList: inout NSMutableArray) {
        if nodeList.count == 0 {
            return
        }
        let isLoop: Bool = nodeList.count > 1 && nodeList[0] == nodeList.lastObject
        var index = 0, count = nodeList.count
        while index < count {
            if isLoop && index == count - 1 {
                nodeList[index] = nodeList[0]
            } else {
                if let node = nodeList[index] as? OsmNode {
                    let pt: CGPoint = mapView?.screenPoint(forLatitude: node.lat, longitude: node.lon, birdsEye: false)
                    nodeList[index] = OSMPointBoxed.point(withPoint: OSMPointFromCGPoint(pt))
                }
            }
            index += 1
        }
    }
    
    func visibleSegmentsOfWay(_ way: inout NSMutableArray, inView viewRect: OSMRect) -> NSMutableArray {
        // trim nodes in outlines to only internal paths
        var newWays: NSMutableArray = []
        
        var first: Bool = true
        var prevInside: Bool
        let isLoop: Bool = way[0] == way.lastObject
        var prevPoint: OSMPoint
        var index: Int = 0
        var lastEntry: Int = -1
        var trimmedSegment: NSMutableArray? = nil
        
        if isLoop {
            // rotate loop to ensure start/end point is outside viewRect
            let ok: Bool = RotateLoop(&way, viewRect)
            if !ok {
                // entire loop is inside view
                newWays.add(way)
                return newWays
            }
        }
        
        for value in way {
            guard let value = value as? OSMPointBoxed else {
                continue
            }
            let pt = value.point
            let isInside: Bool = OSMRectContainsPoint(viewRect, pt)
            if first {
                first = false
            } else {
                var isEntry = false
                var isExit = false
                if prevInside {
                    if isInside {
                        // still inside
                    } else {
                        // moved to outside
                        isExit = true
                    }
                } else {
                    if isInside {
                        // moved inside
                        isEntry = true
                    } else {
                        // if previous and current are both outside maybe we intersected
                        if LineSegmentIntersectsRectangle(prevPoint, pt, viewRect) && !pt.x.isInfinite && !prevPoint.x.isInfinite {
                            isEntry = true
                            isExit = true
                        } else {
                            // still outside
                        }
                    }
                }
                
                let pts = [OSMPoint](repeating: , count: 2)
                let crossCnt = (isEntry || isExit) ? ClipLineToRect(prevPoint, pt, viewRect, pts) : 0
                if isEntry {
                    // start tracking trimmed segment
                    assert(crossCnt >= 1)
                    let v = OSMPointBoxed.point(with: pts[0])
                    trimmedSegment = [v].compactMap { $0 }
                    if let trimmedSegment = trimmedSegment {
                        newWays.add(trimmedSegment)
                    }
                    lastEntry = index - 1
                }
                if isExit {
                    // end of trimmed segment. If the way began inside the viewrect then trimmedSegment is nil and gets ignored
                    assert(crossCnt >= 1)
                    let v = OSMPointBoxed.point(with: pts[crossCnt - 1])
                    if let v = v {
                        trimmedSegment?.add(v)
                    }
                    trimmedSegment = nil
                } else if isInside {
                    // internal node for trimmed segment
                    trimmedSegment?.add(value)
                }
            }
            prevInside = isInside
            prevPoint = pt
            index += 1
        }
        if lastEntry < 0 {
            // never intersects screen
        } else if trimmedSegment != nil {
            // entered but never exited
            newWays.removeLastObject()
        }
        return newWays
    }
    
    func addPointList(_ list: NSArray, to path: CGMutablePath) {
        var first = true
        for point in list {
            guard let point = point as? OSMPointBoxed else {
                continue
            }
            let p = point.point
            if p.x.isInfinite {
                break
            }
            if first {
                first = false
                path.move(to: CGPoint(x: p.x, y: p.y), transform: .identity)
            } else {
                path.addLine(to: CGPoint(x: p.x, y: p.y), transform: .identity)
            }
        }
    }
    
    func getOceanLayer(_ objectList: [OsmBaseObject]) -> CAShapeLayer? {
        // get all coastline ways
        var outerSegments: NSMutableArray = []
        var innerSegments: NSMutableArray = []
        for object in objectList {
            if (object.isWay()?.isClosed() ?? false) && (object.tags?["natural"] == "water") {
                continue // lakes are not a concern of this function
            }
            if object.isCoastline() {
                if (object.isWay() != nil) {
                    outerSegments.add(object)
                } else if (object.isRelation() != nil) {
                    for mem in (object.isRelation()?.members ?? []) {
                        if mem.ref is OsmWay {
                            if mem.role == "outer" {
                                outerSegments.add(mem.ref)
                            } else if mem.role == "inner" {
                                innerSegments.add(mem.ref)
                            } else {
                                // skip
                            }
                        }
                    }
                }
            }
        }
        if outerSegments.count == 0 {
            return nil
        }
        
        // connect ways together forming congiguous runs
        outerSegments = joinConnectedWays(&outerSegments)
        innerSegments = joinConnectedWays(&innerSegments)
        
        // convert lists of nodes to screen points
        for a in outerSegments {
            var a = a as NSMutableArray
            convertNodes(toScreenPoints: &a)
        }
        for a in innerSegments {
            var a = a as NSMutableArray
            convertNodes(toScreenPoints: &a)
        }
        
        // Delete loops with a degenerate number of nodes. These are typically data errors:
        outerSegments.filter { NSPredicate(block: { array, bindings in
            return array?[0] != array?.last || (array?.count ?? 0) >= 4
        }).evaluate(with: $0) }
//        outerSegments.filter(using: NSPredicate(block: { array, bindings in
//            return array?[0] != array?.last || (array?.count ?? 0) >= 4
//        }) )
        innerSegments.filter { NSPredicate(block: { array, bindings in
            return array?[0] != array?.last || (array?.count ?? 0) >= 4
        }).evaluate(with: $0) }
        
        
        let cgViewRect = bounds
        let viewRect = OSMRect(cgViewRect.origin.x, cgViewRect.origin.y, cgViewRect.size.width, cgViewRect.size.height)
        let viewCenter = CGRectCenter(cgViewRect)
        
#if false
        // discard any segments that begin or end inside the view rectangle
        let innerInvalid = (innerSegments as NSArray).filtered(using: NSPredicate(block: { way, bindings in
            return way?[0] != way?.last && (OSMRectContainsPoint(viewRect, way?[0]?.point()) || OSMRectContainsPoint(viewRect, (way?.last as? OsmWay)?.point()))
        }))
        let outerInvalid = (innerSegments as NSArray).filtered(using: NSPredicate(block: { way, bindings in
            return way?[0] != way?.last && (OSMRectContainsPoint(viewRect, way?[0]?.point()) || OSMRectContainsPoint(viewRect, way?.last?.point()))
        }))
        innerSegments = innerSegments.filter({ !innerInvalid.contains($0) })
        outerSegments = outerSegments.filter({ !outerInvalid.contains($0) })
#endif
        
        // ensure that outer ways are clockwise and inner ways are counterclockwise
        for way in outerSegments {
            guard let way = way as? NSMutableArray else {
                continue
            }
            if way[0] == way.last {
                if !IsClockwisePolygon(way) {
                    // reverse points
                    var i = 0, j = way.count - 1
                    while i < j {
                        way.swapAt(i, j)
                        i += 1
                        j -= 1
                    }
                }
            }
        }
        for way in innerSegments {
            if way[0] == way.last {
                if IsClockwisePolygon(way) {
                    // reverse points
                    var i = 0, j = way.count - 1
                    while i < j {
                        way.swapAt(i, j)
                        i += 1
                        j -= 1
                    }
                }
            }
        }
        
        // trim nodes in segments to only visible paths
        var visibleSegments: NSMutableArray = []
        for way in outerSegments {
            let other = visibleSegmentsOfWay(way, inView: viewRect)
            visibleSegments.append(contentsOf: other)
        }
        for way in innerSegments {
            visibleSegments.append(contentsOf: visibleSegmentsOfWay(way, inView: viewRect))
        }
        
        if visibleSegments.count == 0 {
            // nothing is on screen
            return nil
        }
        
        // pull islands into a separate list
        let islands = (visibleSegments as NSArray).filtered(using: NSPredicate(block: { way, bindings in
            return way?[0] == way?.last
        }))
        visibleSegments = visibleSegments.filter({ !islands.contains($0) })
        
        // get list of all external points
        var pointSet: NSMutableSet = []
        var entryDict: NSMutableDictionary = NSMutableDictionary()
        for way in visibleSegments {
            guard let way = way as? [AnyHashable] else {
                continue
            }
            pointSet.add(way[0])
            pointSet.add(way.last)
            entryDict[way[0]] = way
        }
        
        // sort points clockwise
        var points = Array(pointSet)
        points = (points as NSArray).sortedArray(comparator: { v1, v2 in
            let pt1: OSMPoint = (v1 as? OSMPointBoxed).point
            let pt2: OSMPoint = (v2 as? OSMPointBoxed).point
            let ang1: Double = atan2(pt1?.y - viewCenter.y, pt1?.x - viewCenter.x)
            let ang2: Double = atan2(pt2?.y - viewCenter.y, pt2?.x - viewCenter.x)
            let angle: Double = ang1 - ang2
            let result: ComparisonResult = angle < 0 ? .orderedAscending : angle > 0 ? .orderedDescending : .orderedSame
            return result
        })
        
        // now have a set of discontiguous arrays of coastline nodes. Draw segments adding points at screen corners to connect them
        var haveCoastline = false
        let path = CGMutablePath()
        while (visibleSegments.count != 0) {
            let firstOutline = NSArray.init(object: visibleSegments.lastObject)
            var exit = firstOutline.lastObject as? OSMPointBoxed
            visibleSegments.remove(firstOutline)
            addPointList(firstOutline, to: path)
            
            while true{
                // find next point following exit point
                var nextOutline: NSArray = []
                if let exit = exit {
                    nextOutline = entryDict[exit] as? NSArray ?? []
                } // check if exit point is also entry point
                if nextOutline == nil {
                    // find next entry point following exit point
                    var exitIndex: Int = 0
                    if let exit = exit {
                        exitIndex = points.firstIndex(of: exit) ?? NSNotFound
                    }
                    let entryIndex = ((exitIndex ) + 1) % points.count
                    nextOutline = entryDict[points[entryIndex]] as? NSArray ?? []
                }
                if nextOutline == nil {
                    return nil
                }
                let entry = nextOutline[0] as? OSMPointBoxed
                
                // connect exit point to entry point following clockwise borders
                do {
                    var point1 = exit?.point
                    let point2 = entry?.point
                    let wall1 = WallForPoint(point1, viewRect)
                    let wall2 = WallForPoint(point2, viewRect)
                    
                    switch wall1 {
                    case SIDE.LEFT:
                        if wall2 == 0 && point1.y > point2.y {
                        }
                        point1 = OSMPointMake(viewRect.origin.x, viewRect.origin.y)
                        path.addLine(to: CGPoint(x: point1.x, y: point1.y), transform: .identity)
                    case SIDE.TOP:
                        if wall2 == 1 && point1.x < point2.x {
                        }
                        point1 = OSMPointMake(viewRect.origin.x + viewRect.size.width, viewRect.origin.y)
                        path.addLine(to: CGPoint(x: point1.x, y: point1.y), transform: .identity)
                    case SIDE.RIGHT:
                        if wall2 == 2 && point1.y < point2.y {
                        }
                        point1 = OSMPointMake(viewRect.origin.x + viewRect.size.width, viewRect.origin.y + viewRect.size.height)
                        path.addLine(to: CGPoint(x: point1.x, y: point1.y), transform: .identity)
                    case SIDE.BOTTOM:
                        if wall2 == 3 && point1.x > point2.x {
                        }
                        point1 = OSMPointMake(viewRect.origin.x, viewRect.origin.y + viewRect.size.height)
                        path.addLine(to: CGPoint(x: point1.x, y: point1.y), transform: .identity)
                    default:
                        break
                    }
                }
                
            }
            
            haveCoastline = true
            if nextOutline == firstOutline {
                break
            }
            if let nextOutline = nextOutline {
                if !visibleSegments.contains(where: nextOutline) {
                    return nil
                }
            }
            for value in nextOutline ?? [] {
                guard let value = value as? OSMPointBoxed else {
                    continue
                }
                let pt = value.point
                path.addLine(to: CGPoint(x: pt.x, y: pt.y), transform: .identity)
            }
            
            exit = nextOutline?.last as? OSMPointBoxed
            visibleSegments.removeAll { $0 as AnyObject === nextOutline as AnyObject }
        }
        // draw islands
        for island in islands {
            addPointList(island, toPath: path)
            
            if !haveCoastline && IsClockwisePolygon(island) {
                // this will still fail if we have an island with a lake in it
                haveCoastline = true
            }
        }
        
        // if no coastline then draw water everywhere
        if !haveCoastline {
            path.move(to: CGPoint(x: viewRect.origin.x, y: viewRect.origin.y), transform: .identity)
            path.addLine(to: CGPoint(x: viewRect.origin.x + viewRect.size.width, y: viewRect.origin.y), transform: .identity)
            path.addLine(to: CGPoint(x: viewRect.origin.x + viewRect.size.width, y: viewRect.origin.y + viewRect.size.height), transform: .identity)
            path.addLine(to: CGPoint(x: viewRect.origin.x, y: viewRect.origin.y + viewRect.size.height), transform: .identity)
            path.closeSubpath()
        }
        
        let layer = CAShapeLayer()
        layer.path = path
        layer.frame = bounds
        layer.bounds = bounds
        layer.fillColor = UIColor(red: 0, green: 0, blue: 1, alpha: 0.1).cgColor
        layer.strokeColor = UIColor.blue.cgColor
        layer.lineJoin = DEFAULT_LINEJOIN
        layer.lineCap = DEFAULT_LINECAP
        layer.lineWidth = 2.0
        layer.zPosition = Z_OCEAN
        
        return layer
    }

    // MARK: Common Drawing
    func ImageScaledToSize(_ image: UIImage?, _ iconSize: CGFloat) -> UIImage? {
        if image == nil {
            return nil
        }
        #if os(iOS)
        var size = CGSize(width: Int(iconSize * UIScreen.main.scale), height: Int(iconSize * UIScreen.main.scale))
        let ratio = (image?.size.height ?? 0.0) / (image?.size.width ?? 0.0)
        if ratio < 1.0 {
            size.height *= ratio
        } else if ratio > 1.0 {
            size.width /= ratio
        }
        UIGraphicsBeginImageContext(size)
        image?.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        let newIcon = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newIcon
        #else
        let newSize = NSSize(size, size)
        let smallImage = NSImage(size: newSize)
        smallImage.lockFocus()
        icon.size = newSize
        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(at: NSPoint.zero, from: CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height), operation: NSCompositeCopy, fraction: 1.0)
        smallImage.unlockFocus()
        return smallImage
        #endif
    }
    
    
    func IconScaledForDisplay(_ icon: UIImage?) -> UIImage? {
        return ImageScaledToSize(icon, CGFloat(MinIconSizeInPixels))
    }
    
    
    func path(for way: OsmWay?) -> CGPath? {
        let path = CGMutablePath()
        var first = true
        if let nodes = way?.nodes {
            for node in nodes {
                guard let node = node as? OsmNode else {
                    continue
                }
                let pt = mapView?.screenPoint(forLatitude: node.lat, longitude: node.lon, birdsEye: false)
                if pt.x.isInfinite {
                    break
                }
                if first {
                    path.move(to: CGPoint(x: pt.x, y: pt.y), transform: .identity)
                    first = false
                } else {
                    path.addLine(to: CGPoint(x: pt.x, y: pt.y), transform: .identity)
                }
            }
        }
        return path
    }
    
    func zoomLevel() -> Int {
        return Int(floor(mapView?.zoom))
    }
    
    static var defaultColorShopColor: UIColor?
    static var treeColor: UIColor?
    static var amenityColor: UIColor?
    static var tourismColor: UIColor?
    static var medicalColor: UIColor?
    static var poiColor: UIColor?
    static var stopColor: UIColor? = {
        shopColor = UIColor(red: 0xac / 255.0, green: 0x39 / 255.0, blue: 0xac / 255, alpha: 1.0)
        treeColor = UIColor(red: 18 / 255.0, green: 122 /? 255.0, blue: 56 / 255, alpha: 1.0?)
        amenityColor = UIColor(red: 0x73 / 255.0, green: 0x4a / 255.0, blue: 0x08 / 255, alpha: 1.0)
        tourismColor = UIColor(red: 0x00 / 255.0, green: 0x92 / 255.0, blue: 0xda / 255, alpha: 1.0)
        medicalColor = UIColor(red: 0xda / 255.0, green: 0x00 / 255.0, blue: 0x92 / 255, alpha: 1.0)
        poiColor = UIColor.blue
        var stopColor = UIColor(red: 196 / 255.0, green: 4 / 255.0, blue: 4 / 255, alpha: 1.0)
        return stopColor
    }()
    
    func defaultColor(for object: OsmBaseObject?) -> UIColor? {
        // TODO: [Swiftify] ensure that the code below is executed only once (`dispatch_once()` is deprecated)
        {
            shopColor = UIColor(red: 0xac / 255.0, green: 0x39 / 255.0, blue: 0xac / 255, alpha: 1.0)
            treeColor = UIColor(red: 18 / 255.0, green: 122 / 255.0, blue: 56 / 255, alpha: 1.0)
            amenityColor = UIColor(red: 0x73 / 255.0, green: 0x4a / 255.0, blue: 0x08 / 255, alpha: 1.0)
            tourismColor = UIColor(red: 0x00 / 255.0, green: 0x92 / 255.0, blue: 0xda / 255, alpha: 1.0)
            medicalColor = UIColor(red: 0xda / 255.0, green: 0x00 / 255.0, blue: 0x92 / 255, alpha: 1.0)
            poiColor = UIColor.blue
            stopColor = UIColor(red: 196 / 255.0, green: 4 / 255.0, blue: 4 / 255, alpha: 1.0)
        }
        if object?.tags["shop"] != nil {
            return defaultColorShopColor
        } else if object?.tags["amenity"] != nil || object?.tags["building"] != nil || object?.tags["leisure"] != nil {
            return amenityColor
        } else if object?.tags["tourism"] != nil || object?.tags["transport"] != nil {
            return tourismColor
        } else if object?.tags["medical"] != nil {
            return medicalColor
        } else if object?.tags["name"] != nil {
            return poiColor
        } else if object?.tags["natural"] == "tree" {
            return treeColor
        } else if object?.isNode && (object?.tags["highway"] == "stop") {
            return stopColor
        }
        return nil
    }
    
    private func HouseNumberForObjectTags(_ tags: [AnyHashable : Any]?) -> String? {
        let houseNumber = tags?["addr:housenumber"] as? String
        if let houseNumber = houseNumber {
            let unitNumber = tags?["addr:unit"] as? String
            if let unitNumber = unitNumber {
                return "\(houseNumber)/\(unitNumber)"
            }
        }
        return houseNumber
    }
    
    
    func invoke(alongScreenClippedWay way: OsmWay?, block: @escaping (_ p1: OSMPoint, _ p2: OSMPoint, _ isEntry: Bool, _ isExit: Bool) -> Bool) {
        let viewRect = OSMRectFromCGRect(bounds)
        var prevInside: Bool
        var prev = OSMPoint(0)
        var first = true
        
        if let nodes = way?.nodes {
            for node in nodes {
                guard let node = node as? OsmNode else {
                    continue
                }
                
                let pt = OSMPointFromCGPoint(mapView?.screenPoint(forLatitude: node.lat, longitude: node.lon, birdsEye: false))
                let inside = OSMRectContainsPoint(viewRect, pt)
                
                if first {
                    first = false
                }
                let cross = [OSMPoint](repeating: , count: 2)
                var crossCnt = 0
                if !(prevInside && inside) {
                    crossCnt = ClipLineToRect(prev, pt, viewRect, cross)
                    if crossCnt == 0 {
                        // both are outside and didn't cross
                    }
                }
                
                let p1 = prevInside ? prev : cross[0]
                let p2 = inside ? pt : cross[crossCnt - 1]
                
                let proceed = block(p1, p2, !prevInside, !inside)
                if !proceed {
                    break
                }
                prevInside = inside
            }
        }
    }
    
    func invoke(alongScreenClippedWay way: OsmWay?, offset initialOffset: Double, interval: Double, block: @escaping (_ pt: OSMPoint, _ direction: OSMPoint) -> Void) {
        var offset = initialOffset
        invoke(alongScreenClippedWay: way, block: { p1, p2, isEntry, isExit in
            if isEntry {
                offset = initialOffset
            }
            var dx: Double = p2.x - p1.x
            var dy: Double = p2.y - p1.y
            let len = hypot(dx, dy)
            dx /= len
            dy /= len
            while offset < len {
                // found it
                let pos = OSMPoint(p1.x + offset * dx, p1.y + offset * dy)
                let dir = OSMPoint(dx, dy)
                block(pos, dir)
                offset += interval
            }
            offset -= len
            return true
        })
    }
    
    // clip a way to the path inside the viewable rect so we can draw a name on it
    func pathClipped(toViewRect way: OsmWay?, length pLength: UnsafeMutablePointer<Double>?) -> CGPath? {
        var pLength = pLength
        var path: CGMutablePath? = nil
        var length = 0.0
        var firstPoint = OSMPoint(0)
        var lastPoint = OSMPoint(0)
        
        invoke(alongScreenClippedWay: way, block: { p1, p2, isEntry, isExit in
            if path == nil {
                path = CGMutablePath()
                path?.move(to: CGPoint(x: p1.x, y: p1.y), transform: .identity)
                firstPoint = p1
            }
            path?.addLine(to: CGPoint(x: p2.x, y: p2.y), transform: .identity)
            lastPoint = p2
            length += hypot(p1.x - p2.x, p1.y - p2.y)
            if isExit {
                return false
            }
            return true
        })
        if path != nil {
            // orient path so text draws right-side up
            let dx: Double = lastPoint.x - firstPoint.x
            if dx < 0 {
                // reverse path
                let path2 = PathReversed(path)
                
                path = path2
            }
        }
        if pLength != nil {
            pLength = UnsafeMutablePointer<Double>(mutating: &length)
        }
        
        return path
    }
    
    // MARK: CAShapeLayer drawing
    
    let ZSCALE = 0.001
    private let Z_BASE: CGFloat = -1
    private let Z_OCEAN = CGFloat(Double(Z_BASE) + 1 * ZSCALE)
    private let Z_AREA = CGFloat(Double(Z_BASE) + 2 * ZSCALE)
    private let Z_HALO = CGFloat(Double(Z_BASE) + 3 * ZSCALE)
    private let Z_CASING = CGFloat(Double(Z_BASE) + 4 * ZSCALE)
    private let Z_LINE = CGFloat(Double(Z_BASE) + 5 * ZSCALE)
    private let Z_TEXT = CGFloat(Double(Z_BASE) + 6 * ZSCALE)
    private let Z_ARROW = CGFloat(Double(Z_BASE) + 7 * ZSCALE)
    private let Z_NODE = CGFloat(Double(Z_BASE) + 8 * ZSCALE)
    private let Z_TURN = CGFloat(Double(Z_BASE) + 9 * ZSCALE) // higher than street signals, etc
    private let Z_BUILDING_WALL = CGFloat(Double(Z_BASE) + 10 * ZSCALE)
    private let Z_BUILDING_ROOF = CGFloat(Double(Z_BASE) + 11 * ZSCALE)
    private let Z_HIGHLIGHT_WAY = CGFloat(Double(Z_BASE) + 12 * ZSCALE)
    private let Z_HIGHLIGHT_NODE = CGFloat(Double(Z_BASE) + 13 * ZSCALE)
    private let Z_HIGHLIGHT_ARROW = CGFloat(Double(Z_BASE) + 14 * ZSCALE)
    
    func buildingWallLayer(for p1: OSMPoint, point p2: OSMPoint, height: Double, hue: Double) -> CALayer? {
        var dir = Sub(p2, p1)
        let length = Mag(dir)
        let angle = atan2(dir.y, dir.x)
        
        dir.x /= length
        dir.y /= length
        
        let intensity = angle / .pi
        if intensity < 0 {
            intensity += 1
        }
        let color = UIColor(hue: CGFloat((37 + hue) / 360.0), saturation: 0.61, brightness: CGFloat(0.5 + intensity / 2), alpha: 1.0)
        
        let wall = CALayerWithProperties()
        wall.anchorPoint = CGPoint(x: 0, y: 0)
        wall.zPosition = Z_BUILDING_WALL
        #if SINGLE_SIDED_WALLS
        wall.doubleSided = false
        #else
        wall.doubleSided = true
        #endif
        wall.opaque = true
        wall.frame = CGRect(x: 0, y: 0, width: CGFloat(length * PATH_SCALING), height: CGFloat(height))
        wall.backgroundColor = color.cgColor
        wall.position = CGPointFromOSMPoint(p1)
        wall.borderWidth = 1.0
        wall.borderColor = UIColor.black.cgColor
        
        let t1 = CATransform3DMakeRotation(.pi / 2, dir.x, dir.y, 0)
        let t2 = CATransform3DMakeRotation(CGFloat(angle), 0, 0, 1)
        let t = CATransform3DConcat(t2, t1)
        wall.transform = t
        
        let props = wall.properties
        props?.transform = t
        props?.position = p1
        props?.lineWidth = 1.0
        props?.is3D = true
        
        return wall
    }
    
    func getShapeLayers(for object: OsmBaseObject?) -> [CALayer & LayerPropertiesProviding]? {
        if object?.shapeLayers {
            return object?.shapeLayers
        }
        
        let renderInfo = object?.renderInfo
        var layers: [AnyHashable] = []
        
        if object?.isNode {
            layers.append(contentsOf: shapeLayers(forNode: object?.isNode))
        }
        
        // casing
        if object?.isWay || object?.isRelation.isMultipolygon {
            if renderInfo?.lineWidth && !object?.isWay()?.isArea() {
                var refPoint: OSMPoint
                let path = object?.linePathForObject(withRefPoint: &refPoint)
                if let path = path {
                    
                    do {
                        let layer = CAShapeLayerWithProperties()
                        layer.anchorPoint = CGPoint(x: 0, y: 0)
                        layer.position = CGPointFromOSMPoint(refPoint)
                        layer.path = path
                        layer.strokeColor = UIColor.black.cgColor
                        layer.fillColor = nil
                        layer.lineWidth = (1 + (renderInfo?.lineWidth ?? 0)) * highwayScale
                        layer.lineCap = DEFAULT_LINECAP
                        layer.lineJoin = DEFAULT_LINEJOIN
                        layer.zPosition = Z_CASING
                        let props = layer.properties
                        props?.position = refPoint
                        props?.lineWidth = layer.lineWidth
                        let bridge = object?.tags["bridge"] as? String
                        if bridge != nil && !OsmTags.isOsmBooleanFalse(bridge) {
                            props?.lineWidth += 4
                        }
                        let tunnel = object?.tags["tunnel"] as? String
                        if tunnel != nil && !OsmTags.isOsmBooleanFalse(tunnel) {
                            props?.lineWidth += 2
                            layer.strokeColor = UIColor.brown.cgColor
                        }
                        
                        layers.append(layer)
                    }
                    
                    // provide a halo for streets that don't have a name
                    if mapView?.enableUnnamedRoadHalo && object?.isWay.needsNoNameHighlight {
                        // it lacks a name
                        let haloLayer = CAShapeLayerWithProperties()
                        haloLayer.anchorPoint = CGPoint(x: 0, y: 0)
                        haloLayer.position = CGPointFromOSMPoint(refPoint)
                        haloLayer.path = path
                        haloLayer.strokeColor = UIColor.red.cgColor
                        haloLayer.fillColor = nil
                        haloLayer.lineWidth = (2 + (renderInfo?.lineWidth ?? 0)) * highwayScale
                        haloLayer.lineCap = DEFAULT_LINECAP
                        haloLayer.lineJoin = DEFAULT_LINEJOIN
                        haloLayer.zPosition = Z_HALO
                        let haloProps = haloLayer.properties
                        haloProps?.position = refPoint
                        haloProps?.lineWidth = haloLayer.lineWidth
                        
                        layers.append(haloLayer)
                    }
                }
            }
        }
        // way (also provides an outline for areas)
        if object.isWay || object.isRelation.isMultipolygon {
            var refPoint = OSMPoint(0, 0)
            let path = object.linePathForObject(withRefPoint: &refPoint)
            
            if let path = path {
                var lineWidth = renderInfo.lineWidth * highwayScale
                if lineWidth == 0 {
                    lineWidth = 1
                }
                
                let layer = CAShapeLayerWithProperties()
                layer.anchorPoint = CGPoint(x: 0, y: 0)
                let bbox = path.boundingBoxOfPath
                layer.bounds = CGRect(x: 0, y: 0, width: bbox.size.width, height: bbox.size.height)
                layer.position = CGPointFromOSMPoint(refPoint)
                layer.path = path
                layer.strokeColor = (renderInfo.lineColor ?? UIColor.black).cgColor
                layer.fillColor = nil
                layer.lineWidth = lineWidth
                layer.lineCap = DEFAULT_LINECAP
                layer.lineJoin = DEFAULT_LINEJOIN
                layer.zPosition = Z_LINE
                
                let props = layer.properties
                props?.position = refPoint
                props?.lineWidth = layer.lineWidth
                layers.append(layer)
            }
        }
        
        // Area
        if object.isWay.isArea || object.isRelation.isMultipolygon {
            if renderInfo.areaColor && !object.isCoastline {
                
                var refPoint: OSMPoint
                let path = object.shapePathForObject(withRefPoint: &refPoint)
                if let path = path {
                    // draw
                    let alpha: CGFloat = object.tags["landuse"] != nil ? 0.15 : 0.25
                    let layer = CAShapeLayerWithProperties()
                    layer.anchorPoint = CGPoint(x: 0, y: 0)
                    layer.path = path
                    layer.position = CGPointFromOSMPoint(refPoint)
                    layer.fillColor = renderInfo.areaColor.withAlphaComponent(alpha).cgColor
                    layer.lineCap = DEFAULT_LINECAP
                    layer.lineJoin = DEFAULT_LINEJOIN
                    layer.zPosition = Z_AREA
                    let props = layer.properties
                    props?.position = refPoint
                    
                    layers.append(layer)
                    #if SHOW_3D
                    // if its a building then add walls for 3D
                    if object.tags["building"] != nil {
                        
                        // calculate height in meters
                        let value = object.tags["height"] as? String
                        var height = Double(value ?? "") ?? 0.0
                        if height != 0.0 {
                            // height in meters?
                            var v1: Double = 0
                            var v2: Double = 0
                            let scanner = Scanner(string: value ?? "")
                            if scanner.scanDouble(UnsafeMutablePointer<Double>(mutating: &v1)) {
                                scanner.scanCharacters(from: CharacterSet.whitespacesAndNewlines, into: nil)
                                if scanner.scanString("'", into: nil) {
                                    // feet
                                    if scanner.scanDouble(UnsafeMutablePointer<Double>(mutating: &v2)) {
                                        if scanner.scanString("\"", into: nil) {
                                            // inches
                                        } else {
                                            // malformed
                                        }
                                    }
                                    height = (v1 * 12 + v2) * 0.0254 // meters/inch
                                } else if scanner.scanString("ft", into: nil) {
                                    height *= 0.3048 // meters/foot
                                } else if scanner.scanString("yd", into: nil) {
                                    height *= 0.9144 // meters/yard
                                }
                            }
                        } else {
                            height = (object.tags["building:levels"] as? NSNumber).doubleValue
                            #if DEBUG
                            if height == 0 {
                                let layerNum = object.tags["layer"] as? String
                                if let layerNum = layerNum {
                                    height = Double(layerNum) ?? 0.0 + 1
                                }
                            }
                            #endif
                            if height == 0 {
                                height = 1
                            }
                            height *= 3
                        }
                        let hue = Double(object.ident.int64Value % 20 - 10)
                        var hasPrev = false
                        var prevPoint: OSMPoint
                        CGPathApplyBlockEx(path, { [self] type, points in
                            if type == .moveToPoint {
                                prevPoint = Add(refPoint, Mult(OSMPointFromCGPoint(points?[0]), 1 / PATH_SCALING))
                                hasPrev = true
                            } else if type == .addLineToPoint && hasPrev {
                                let pt = Add(refPoint, Mult(OSMPointFromCGPoint(points?[0]), 1 / PATH_SCALING))
                                let wall = buildingWallLayer(for: pt, point: prevPoint, height: height, hue: hue)
                                if let wall = wall {
                                    layers.append(wall)
                                }
                                prevPoint = pt
                            } else {
                                hasPrev = false
                            }
                        })
                        if true {
                            // get roof
                            let color = UIColor(hue: 0, saturation: 0.05, brightness: 0.75 + hue / 100, alpha: 1.0)
                            let roof = CAShapeLayerWithProperties()
                            roof.anchorPoint = CGPoint(x: 0, y: 0)
                            let bbox = path.boundingBoxOfPath
                            roof.bounds = CGRect(x: 0, y: 0, width: bbox.size.width, height: bbox.size.height)
                            roof.position = CGPointFromOSMPoint(refPoint)
                            roof.path = path
                            roof.fillColor = color.cgColor
                            roof.strokeColor = UIColor.black.cgColor
                            roof.lineWidth = 1.0
                            roof.lineCap = DEFAULT_LINECAP
                            roof.lineJoin = DEFAULT_LINEJOIN
                            roof.zPosition = Z_BUILDING_ROOF
                            roof.doubleSided = true
                            
                            let t = CATransform3DMakeTranslation(0, 0, height)
                            props = roof.properties
                            props.position = refPoint
                            props.transform = t
                            props.is3D = true
                            props.lineWidth = 1.0
                            roof.transform = t
                            layers.append(roof)
                        }
                    }
                    #endif    // SHOW_3D
                    
                }
            }
        }
        
        // Names
        if object.isWay || object.isRelation.isMultipolygon {
            
            // get object name, or address if no name
            var name = object.givenName
            if name == nil {
                name = HouseNumberForObjectTags(object.tags)
            }
            
            if name != "" {
                
                let isHighway = object.isWay && !object.isWay.isArea
                if isHighway {
                    
                    // These are drawn dynamically
                } else {
                    
                    let point = object.isWay ? object.isWay.centerPoint : object.isRelation.centerPoint
                    let pt = MapPointForLatitudeLongitude(point.y, point.x)
                    
                    let layer = CurvedGlyphLayer(string: name) as? CATextLayerWithProperties
                    layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                    layer?.position = CGPoint(x: pt.x, y: pt.y)
                    layer?.zPosition = Z_TEXT
                    
                    let props = layer?.properties
                    props?.position = pt
                    
                    if let layer = layer {
                        layers.append(layer)
                    }
                }
            }
        }
        
        // Turn Restrictions
        if mapView?.enableTurnRestriction {
            if object.isRelation.isRestriction {
                let viaMembers = object.isRelation.members(byRole: "via")
                for viaMember in viaMembers {
                    guard let viaMember = viaMember as? OsmMember else {
                        continue
                    }
                    let viaMemberObject = viaMember.ref
                    if viaMemberObject is OsmBaseObject {
                        if viaMemberObject?.isNode || viaMemberObject?.isWay {
                            let latLon = viaMemberObject?.selectionPoint
                            let pt = MapPointForLatitudeLongitude(latLon?.y, latLon?.x)
                            
                            let restrictionLayerIcon = CALayerWithProperties()
                            restrictionLayerIcon.bounds = CGRect(x: 0, y: 0, width: CGFloat(MinIconSizeInPixels), height: CGFloat(MinIconSizeInPixels))
                            restrictionLayerIcon.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                            restrictionLayerIcon.position = CGPoint(x: pt.x, y: pt.y)
                            if viaMember.isWay && (object.tags["restriction"] == "no_u_turn") {
                                restrictionLayerIcon.contents = UIImage(named: "no_u_turn")?.cgImage
                            } else {
                                restrictionLayerIcon.contents = UIImage(named: "restriction_sign")?.cgImage
                            }
                            restrictionLayerIcon.zPosition = Z_TURN
                            let restrictionIconProps = restrictionLayerIcon.properties
                            restrictionIconProps?.position = pt
                            
                            layers.append(restrictionLayerIcon)
                        }
                    }
                }
            }
        }
        object.shapeLayers = layers
        return layers
    }
    
    // use the "marker" icon
    
    static let genericIconMarkerIcon: UIImage? = {
        markerIcon = UIImage(named: "maki-marker")
        var markerIcon = IconScaledForDisplay(genericIconMarkerIcon)
        return markerIcon
    }()
    
    func genericIcon() -> UIImage? {
        // `dispatch_once()` call was converted to a static variable initializer
        return genericIconMarkerIcon
    }
    
    /// Determines the `CALayer` instances required to present the given `node` on the map.
    /// - Parameter node: The `OsmNode` instance to get the layers for.
    /// - Returns: A list of `CALayer` instances that are used to represent the given `node` on the map.
    func shapeLayers(for node: OsmNode?) -> [CALayer]? {
        var layers: [CALayer & LayerPropertiesProviding]? = []
        
        let directionLayers = directionShapeLayers(with: node)
        if directionLayers != nil {
            layers?.append(contentsOf: directionLayers)
        }
        
        let pt = MapPointForLatitudeLongitude(node?.lat, node?.lon)
        var drawRef = true
        
        // fetch icon
        let feature = PresetsDatabase.shared.matchObjectTags(
            toFeature: node?.tags,
            geometry: node?.geometryName,
            includeNSI: false)
        var icon = feature?.iconScaled24
        if icon == nil {
            if node?.tags["amenity"] != nil || node?.tags["name"] != nil {
                icon = genericIcon()
            }
        }
        if let icon = icon {
            /// White circle as the background
            let backgroundLayer = CALayer()
            backgroundLayer.bounds = CGRect(x: 0, y: 0, width: CGFloat(MinIconSizeInPixels), height: CGFloat(MinIconSizeInPixels))
            backgroundLayer.backgroundColor = UIColor.white.cgColor
            backgroundLayer.cornerRadius = Int(MinIconSizeInPixels) / 2
            backgroundLayer.masksToBounds = true
            backgroundLayer.anchorPoint = CGPoint.zero
            backgroundLayer.borderColor = UIColor.darkGray.cgColor
            backgroundLayer.borderWidth = 1.0
            backgroundLayer.isOpaque = true
            
            /// The actual icon image serves as a `mask` for the icon's color layer, allowing for "tinting" of the icons.
            let iconMaskLayer = CALayer()
            let padding: CGFloat = 4
            iconMaskLayer.frame = CGRect(x: padding, y: padding, width: CGFloat(MinIconSizeInPixels) - padding * 2, height: CGFloat(MinIconSizeInPixels) - padding * 2)
            iconMaskLayer.contents = icon.cgImage
            
            let iconLayer = CALayer()
            iconLayer.bounds = CGRect(x: 0, y: 0, width: CGFloat(MinIconSizeInPixels), height: CGFloat(MinIconSizeInPixels))
            let iconColor = defaultColor(forObject: node)
            iconLayer.backgroundColor = (iconColor ?? UIColor.black).cgColor
            iconLayer.mask = iconMaskLayer
            iconLayer.anchorPoint = CGPoint.zero
            iconLayer.isOpaque = true
            
            let layer = CALayerWithProperties()
            layer.addSublayer(backgroundLayer)
            layer.addSublayer(iconLayer)
            layer.bounds = CGRect(x: 0, y: 0, width: CGFloat(MinIconSizeInPixels), height: CGFloat(MinIconSizeInPixels))
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: pt.x, y: pt.y)
            layer.zPosition = Z_NODE
            layer.opaque = true
            
            let props = layer.properties
            props?.position = pt
            layers?.append(layer)
        } else {
            
            // draw generic box
            let color = defaultColor(forObject: node)
            let houseNumber = color != nil ? nil : HouseNumberForObjectTags(node?.tags)
            if let houseNumber = houseNumber {
                
                let layer = CurvedGlyphLayer(string: houseNumber) as? CATextLayerWithProperties
                layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                layer.position = CGPoint(x: pt.x, y: pt.y)
                layer.zPosition = Z_TEXT
                let props = layer?.properties
                props?.position = pt
                
                drawRef = false
                
                if let layer = layer {
                    layers?.append(layer)
                }
            } else {
                
                // generic box
                let layer = CAShapeLayerWithProperties()
                let rect = CGRect(
                    x: CGFloat(round(Int(MinIconSizeInPixels) / 4)),
                    y: CGFloat(round(Int(MinIconSizeInPixels) / 4)),
                    width: CGFloat(round(Int(MinIconSizeInPixels) / 2)),
                    height: CGFloat(round(Int(MinIconSizeInPixels) / 2)))
                let path = CGPath(rect: rect, transform: nil)
                layer.path = path
                layer.frame = CGRect(
                    x: Int(-MinIconSizeInPixels) / 2,
                    y: Int(-MinIconSizeInPixels) / 2,
                    width: CGFloat(MinIconSizeInPixels),
                    height: CGFloat(MinIconSizeInPixels))
                layer.position = CGPoint(x: pt.x, y: pt.y)
                layer.strokeColor = (color ?? UIColor.black).cgColor
                layer.fillColor = nil
                layer.lineWidth = 2.0
                layer.backgroundColor = UIColor.white.cgColor
                layer.borderColor = UIColor.darkGray.cgColor
                layer.borderWidth = 1.0
                layer.cornerRadius = Int(MinIconSizeInPixels) / 2
                layer.zPosition = Z_NODE
                
                let props = layer.properties
                props?.position = pt
                
                layers?.append(layer)
            }
        }
        
        if drawRef {
            let ref = node?.tags["ref"] as? String
            if let ref = ref {
                let label = CurvedGlyphLayer(string: ref) as? CATextLayerWithProperties
                label?.anchorPoint = CGPoint(x: 0.0, y: 0.5)
                label?.position = CGPoint(x: pt.x, y: pt.y)
                label?.zPosition = Z_TEXT
                label?.properties.position = pt
                label?.properties.offset = CGPoint(x: 12, y: 0)
                if let label = label {
                    layers?.append(label)
                }
            }
        }
        
        return layers
    }
    
    func directionShapeLayer(for node: OsmNode?, withDirection direction: NSRange) -> (CALayer & LayerPropertiesProviding)? {
        var heading: CGFloat = Double(direction.location) - 90.0
        if direction.length != 0 {
            heading += CGFloat(direction.length / 2)
        }
        
        let layer = CAShapeLayerWithProperties.layer()
        
        layer?.fillColor = UIColor(white: 0.2, alpha: 0.5).cgColor
        layer?.strokeColor = UIColor(white: 1.0, alpha: 0.5).cgColor
        layer?.lineWidth = 1.0
        
        layer?.zPosition = Z_NODE
        
        let pt = MapPointForLatitudeLongitude(node?.lat, node?.lon)
        
        let screenAngle = OSMTransformRotation(mapView?.screenFromMapTransform)
        layer?.affineTransform = CGAffineTransform(rotationAngle: CGFloat(screenAngle))
        
        let radius: CGFloat = 30.0
        let fieldOfViewRadius: CGFloat = direction.length ?? 55
        let path = CGMutablePath()
        path.addArc(
            center: CGPoint(x: 0.0,
                            y: 0.0),
            radius: radius,
            startAngle: radiansFromDegrees(heading - fieldOfViewRadius / 2),
            endAngle: radiansFromDegrees(heading + fieldOfViewRadius / 2),
            clockwise: false,
            transform: .identity)
        path.addLine(to: CGPoint(x: 0, y: 0), transform: .identity)
        path.closeSubpath()
        layer?.path = path
        
        let layerProperties = layer?.properties
        layerProperties?.position = pt
        layerProperties?.isDirectional = true
        
        return layer
    }
    
    func directionLayerForNode(in way: OsmWay?, node: OsmNode?, facing second: Int) -> CALayer? {
        if second < 0 || second >= (way?.nodes.count ?? 0) {
            return nil
        }
        let nextNode = way?.nodes[second] as? OsmNode
        // compute angle to next node
        let p1 = MapPointForLatitudeLongitude(node?.lat, node?.lon)
        let p2 = MapPointForLatitudeLongitude(nextNode?.lat, nextNode?.lon)
        let angle = atan2(p2.y - p1.y, p2.x - p1.x)
        var direction = 90 + Int(round(angle * 180 / .pi)) // convert to north-facing clockwise direction
        if direction < 0 {
            direction += 360
        }
        return directionShapeLayer(for: node, withDirection: NSRange(location: direction, length: 0))
    }
    
    /// Determines the `CALayer` instance required to draw the direction of the given `node`.
    /// - Parameter node: The node to get the layer for.
    /// - Returns: A `CALayer` instance for rendering the given node's direction.
    func directionShapeLayers(with node: OsmNode?) -> [CALayer & LayerPropertiesProviding]? {
        let direction = node?.direction
        if direction?.location != NSNotFound {
            if let direction = direction {
                return [directionShapeLayer(for: node, withDirection: direction)].compactMap { $0 }
            }
            return nil
        }
        
        let highway = node?.tags["highway"] as? String
        if highway == nil {
            return nil
        }
        var directionValue: String? = nil
        if highway == "traffic_signals" {
            directionValue = node?.tags["traffic_signals:direction"] as? String
        } else if highway == "stop" {
            directionValue = node?.tags["direction"] as? String
        }
        if let directionValue = directionValue {
            if isDirection != IS_NONE {
                var wayList = mapData?.waysContaining(node) // this is expensive, only do if necessary
                if let filtered = (wayList as NSArray).filtered(using: NSPredicate(block: { way, bindings in
                    return way?.tags["highway"] != nil
                })) as? [OsmWay] {
                    wayList = filtered
                }
                if wayList.count > 0 {
                    if wayList.count > 1 && isDirection != IS_ALL {
                        return nil // the direction isn't well defined
                    }
                    var list = [AnyHashable](repeating: 0, count: 2 * wayList.count) // sized for worst case
                    for way in wayList {
                        var pos: Int? = nil
                        if let node = node {
                            pos = way.nodes.firstIndex(of: node) ?? NSNotFound
                        }
                        if isDirection != IS_FORWARD {
                            let layer = directionLayerForNode(in: way, node: node, facing: (pos ?? 0) + 1)
                            if let layer = layer {
                                list.append(layer)
                            }
                        }
                        if isDirection != IS_BACKWARD {
                            let layer = directionLayerForNode(in: way, node: node, facing: (pos ?? 0) - 1)
                            if let layer = layer {
                                list.append(layer)
                            }
                        }
                    }
                    return list as? [CALayer & LayerPropertiesProviding]
                }
            }
        }
        return nil
    }
    
    func getShapeLayersForHighlights() -> [CALayer]? {
        let geekScore = geekbenchScoreProvider.geekbenchScore()
        let nameLimit = Int(5 + (geekScore - 500) / 200) // 500 -> 5, 2500 -> 10
        var nameSet = []
        var layers: [AnyHashable] = []
        let regularColor = UIColor.cyan
        let relationColor = UIColor(red: 66 / 255.0, green: 188 / 255.0, blue: 244 / 255.0, alpha: 1.0)
        
        // highlighting
        var highlights = []
        if selectedNode {
            highlights.insert(selectedNode)
        }
        if selectedWay {
            highlights.insert(selectedWay)
        }
        if selectedRelation {
            let members = selectedRelation.allMemberObjects()
            highlights.union(members)
        }
        
        for object in highlights {
            guard let object = object as? OsmBaseObject else {
                continue
            }
            // selected is false if its highlighted because it's a member of a selected relation
            let selected = object == selectedNode || object == selectedWay
            
            if object.isWay {
                let path = self.path(forWay: object.isWay)
                var lineWidth: CGFloat = selected ? 1.0 : 2.0
                let wayColor = selected ? regularColor : relationColor
                
                if lineWidth == 0 {
                    lineWidth = 1
                }
                lineWidth += 2 // since we're drawing highlight 2-wide we don't want it to intrude inward on way
                
                let layer = CAShapeLayerWithProperties()
                layer.strokeColor = wayColor.cgColor
                layer.lineWidth = lineWidth
                layer.path = path
                layer.fillColor = UIColor.clear.cgColor
                layer.zPosition = Z_HIGHLIGHT_WAY
                
                let props = layer.properties
                props?.lineWidth = layer.lineWidth
                
                layers.append(layer)
                
                // Turn Restrictions
                if mapView?.enableTurnRestriction {
                    for relation in object.parentRelations {
                        if relation.isRestriction && relation.member(byRole: "from").ref == object {
                            // the From member of the turn restriction is the selected way
                            if selectedNode == nil || relation.member(byRole: "via").ref == selectedNode {
                                // highlight if no node, is selected, or the selected node is the via node
                                //    BOOL isConditionalRestriction = relation.rags
                                for member in relation.members {
                                    if member.isWay && (member.ref is OsmWay) {
                                        let way = member.ref
                                        let turnPath = self.path(for: way)
                                        let haloLayer = CAShapeLayerWithProperties()
                                        haloLayer.anchorPoint = CGPoint(x: 0, y: 0)
                                        haloLayer.path = turnPath
                                        if member.ref == object && (member.role != "to") {
                                            haloLayer.strokeColor = UIColor.black.withAlphaComponent(0.75).cgColor
                                        } else if relation.tags["restriction"].hasPrefix("only_") {
                                            haloLayer.strokeColor = UIColor.blue.withAlphaComponent(0.75).cgColor
                                        } else if relation.tags["restriction"].hasPrefix("no_") {
                                            haloLayer.strokeColor = UIColor.red.withAlphaComponent(0.75).cgColor
                                        } else {
                                            haloLayer.strokeColor = UIColor.orange.withAlphaComponent(0.75).cgColor // some other kind of restriction
                                        }
                                        haloLayer.fillColor = nil
                                        haloLayer.lineWidth = ((way?.renderInfo.lineWidth ?? 0.0) + 6) * highwayScale
                                        haloLayer.lineCap = CAShapeLayerLineCap.round
                                        haloLayer.lineJoin = CAShapeLayerLineJoin.round
                                        haloLayer.zPosition = Z_HALO
                                        let haloProps = haloLayer.properties
                                        haloProps?.lineWidth = haloLayer.lineWidth
                                        
                                        if ((member.role == "to") && member.ref == object) || ((member.role == "via") && member.isWay) {
                                            haloLayer.lineDashPattern = [NSNumber(value: 10 * highwayScale), NSNumber(value: 10 * highwayScale)]
                                        }
                                        
                                        layers.append(haloLayer)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // draw nodes of way
                let nodes = object == selectedWay ? object.nodeSet : nil
                for node in nodes ?? [] {
                    guard let node = node as? OsmNode else {
                        continue
                    }
                    let layer2 = CAShapeLayer()
                    let rect = CGRect(x: CGFloat(-NodeHighlightRadius), y: CGFloat(-NodeHighlightRadius), width: 2 * Int(NodeHighlightRadius), height: 2 * Int(NodeHighlightRadius))
                    layer2.position = mapView?.screenPoint(forLatitude: node.lat, longitude: node.lon, birdsEye: false)
                    layer2.strokeColor = node == selectedNode ? UIColor.yellow.cgColor : UIColor.green.cgColor
                    layer2.fillColor = UIColor.clear.cgColor
                    layer2.lineWidth = 3.0
                    layer2.shadowColor = UIColor.black.cgColor
                    layer2.shadowRadius = 2.0
                    layer2.shadowOpacity = 0.5
                    layer2.shadowOffset = CGSize(width: 0, height: 0)
                    layer2.masksToBounds = false
                    
                    path = node.hasInterestingTags() ? CGPath(rect: rect, transform: nil) : CGPath(ellipseIn: rect, transform: nil)
                    layer2.path = path
                    layer2.zPosition = Z_HIGHLIGHT_NODE + (node == selectedNode ? 0.1 * ZSCALE : 0)
                    layers.append(layer2)
                }
            } else if object.isNode() {
                // draw square around selected node
                let node = object as? OsmNode
                let pt = mapView?.screenPoint(forLatitude: node?.lat, longitude: node?.lon, birdsEye: false)
                
                let layer = CAShapeLayer()
                var rect = CGRect(x: Int(-MinIconSizeInPixels) / 2, y: Int(-MinIconSizeInPixels) / 2, width: CGFloat(MinIconSizeInPixels), height: CGFloat(MinIconSizeInPixels))
                rect = rect.insetBy(dx: -3, dy: -3)
                let path = CGPath(rect: rect, transform: nil)
                layer.path = path
                
                layer.anchorPoint = CGPoint(x: 0, y: 0)
                layer.position = CGPoint(x: pt.x, y: pt.y)
                layer.strokeColor = selected ? UIColor.green.cgColor : UIColor.white.cgColor
                layer.fillColor = UIColor.clear.cgColor
                layer.lineWidth = 2.0
                
                layer.zPosition = Z_HIGHLIGHT_NODE
                layers.append(layer)
            }
        }
        
        // Arrow heads and street names
        for object in shownObjects {
            let isHighlight = highlights.contains(object)
            if object.isOneWay || isHighlight {
                
                // arrow heads
                invoke(alongScreenClippedWay: object.isWay, offset: 50, interval: 100, block: { loc, dir in
                    // draw direction arrow at loc/dir
                    let reversed = object.isOneWay == ONEWAY_BACKWARD
                    let len: Double = reversed ? -15 : 15
                    let width: Double = 5
                    
                    let p1 = OSMPoint(loc.x - dir.x * len + dir.y * width, loc.y - dir.y * len - dir.x * width)
                    let p2 = OSMPoint(loc.x - dir.x * len - dir.y * width, loc.y - dir.y * len + dir.x * width)
                    
                    let arrowPath = CGMutablePath()
                    arrowPath.move(to: CGPoint(x: p1.x, y: p1.y), transform: .identity)
                    arrowPath.addLine(to: CGPoint(x: loc.x, y: loc.y), transform: .identity)
                    arrowPath.addLine(to: CGPoint(x: p2.x, y: p2.y), transform: .identity)
                    arrowPath.addLine(to: CGPoint(x: CGFloat(loc.x - dir.x * len * 0.5), y: CGFloat(loc.y - dir.y * len * 0.5)), transform: .identity)
                    arrowPath.closeSubpath()
                    
                    let arrow = CAShapeLayer()
                    arrow.path = arrowPath
                    arrow.lineWidth = 1
                    arrow.fillColor = UIColor.black.cgColor
                    arrow.strokeColor = UIColor.white.cgColor
                    arrow.lineWidth = 0.5
                    arrow.zPosition = isHighlight ? Z_HIGHLIGHT_ARROW : Z_ARROW
                    
                    layers.append(arrow)
                })
            }
            
            // street names
            if nameLimit > 0 {
                
                var parentRelation: OsmRelation? = nil
                object.isWay.parentRelations.enumerateObjects({ parent, idx, stop in
                    if parent?.isBoundary || parent?.isWaterway {
                        parentRelation = parent
                        stop = UnsafeMutablePointer<ObjCBool>(mutating: &true)
                    }
                })
                
                if (object.isWay && !object.isWay.isArea) || parentRelation != nil {
                    var name = object.givenName
                    if name == nil {
                        name = parentRelation?.givenName ?? ""
                    }
                    if name != "" {
                        if !nameSet.contains(name) {
                            var length = 0.0
                            let path = pathClipped(toViewRect: object.isWay, length: &length)
                            if length >= Double(name.count * Pixels_Per_Character) {
                                let layer = CurvedGlyphLayer(string: name, along: path)
                                let a = layer.glyphLayers()
                                if a.count != 0 {
                                    layers.append(contentsOf: a)
                                    nameLimit -= 1
                                    nameSet.append(name)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return layers
        
    }
    
    /// Determines whether text layers that display street names should be rasterized.
    /// - Returns: The value to use for the text layer's `shouldRasterize` property.
    func shouldRasterizeStreetNames() -> Bool {
        return geekbenchScoreProvider.geekbenchScore() < 2500
    }
    
    func resetDisplayLayers() {
        // need to refresh all text objects
        mapData?.enumerateObjects({ obj in
            obj?.shapeLayers = nil
        })
        baseLayer.sublayers = nil
        setNeedsLayout()
    }
    
    // MARK: Select objects and draw
    
    
    func getVisibleObjects() -> [AnyHashable]? {
        let box = mapView?.screenLongitudeLatitude()
        var a = [AnyHashable](repeating: 0, count: mapData?.wayCount)
        mapData?.enumerateObjects(inRegion: box, block: { obj in
            var show = obj?.isShown
            if show == TRISTATE_UNKNOWN {
                if !obj?.deleted {
                    if obj?.isNode {
                        if (obj as? OsmNode)?.wayCount == 0 || obj?.hasInterestingTags() {
                            show = TRISTATE_YES
                        }
                    } else if obj?.isWay {
                        show = TRISTATE_YES
                    } else if obj?.isRelation {
                        show = TRISTATE_YES
                    }
                }
                obj?.isShown = show == TRISTATE_YES ? TRISTATE_YES : TRISTATE_NO
            }
            if show == TRISTATE_YES {
                if let obj = obj {
                    a.append(obj)
                }
            }
        })
        return a
    }
    
    static var filterObjectsTraffic_roads: [AnyHashable : Any]?
    static var service_roads: [AnyHashable : Any]?
    static var paths: [AnyHashable : Any]?
    static var past_futures: [AnyHashable : Any]?
    static var parking_buildings: [AnyHashable : Any]?
    static var natural_water: [AnyHashable : Any]?
    static var landuse_water: [AnyHashable : Any]?
    
    func filterObjects(_ objects: inout [AnyHashable]) {
#if os(iOS)
        var predLevel: ((OsmBaseObject?) -> Bool)? = nil
        
        if showLevel {
            // set level predicate dynamically since it depends on the the text range
            let levelFilter = FilterObjectsViewController.levels(for: showLevelRange)
            if levelFilter.count != 0 {
                predLevel = { object in
                    let objectLevel = object?.tags["level"] as? String
                    if objectLevel == nil {
                        return true
                    }
                    var floorSet: [AnyHashable]? = nil
                    var floor = 0.0
                    if objectLevel?.contains(";") ?? false {
                        floorSet = objectLevel?.components(separatedBy: ";")
                    } else {
                        floor = Double(objectLevel ?? "") ?? 0.0
                    }
                    for filterRange in levelFilter {
                        guard let filterRange = filterRange as? [AnyHashable] else {
                            continue
                        }
                        if filterRange.count == 1 {
                            // filter is a single floor
                            let filterValue = (filterRange[0] as? NSNumber).doubleValue
                            if let floorSet = floorSet {
                                // object spans multiple floors
                                for s in floorSet {
                                    guard let s = s as? String else {
                                        continue
                                    }
                                    let f = Double(s) ?? 0.0
                                    if f == filterValue {
                                        return true
                                    }
                                }
                            } else {
                                if floor == filterValue {
                                    return true
                                }
                            }
                        } else if filterRange.count == 2 {
                            // filter is a range
                            let filterLow = (filterRange[0] as? NSNumber).doubleValue
                            let filterHigh = (filterRange[1] as? NSNumber).doubleValue
                            if let floorSet = floorSet {
                                // object spans multiple floors
                                for s in floorSet {
                                    guard let s = s as? String else {
                                        continue
                                    }
                                    let f = Double(s) ?? 0.0
                                    if f >= filterLow && f <= filterHigh {
                                        return true
                                    }
                                }
                            } else {
                                // object is a single value
                                if floor >= filterLow && floor <= filterHigh {
                                    return true
                                }
                            }
                        } else {
                            assert(false)
                        }
                    }
                    return false
                }
            }
        }
        if filterObjectsTraffic_roads == nil {
            filterObjectsTraffic_roads = [
                "motorway": NSNumber(value: true),
                "motorway_link": NSNumber(value: true),
                "trunk": NSNumber(value: true),
                "trunk_link": NSNumber(value: true),
                "primary": NSNumber(value: true),
                "primary_link": NSNumber(value: true),
                "secondary": NSNumber(value: true),
                "secondary_link": NSNumber(value: true),
                "tertiary": NSNumber(value: true),
                "tertiary_link": NSNumber(value: true),
                "residential": NSNumber(value: true),
                "unclassified": NSNumber(value: true),
                "living_street": NSNumber(value: true)
            ]
            service_roads = [
                "service": NSNumber(value: true),
                "road": NSNumber(value: true),
                "track": NSNumber(value: true)
            ]
            paths = [
                "path": NSNumber(value: true),
                "footway": NSNumber(value: true),
                "cycleway": NSNumber(value: true),
                "bridleway": NSNumber(value: true),
                "steps": NSNumber(value: true),
                "pedestrian": NSNumber(value: true),
                "corridor": NSNumber(value: true)
            ]
            past_futures = [
                "proposed": NSNumber(value: true),
                "construction": NSNumber(value: true),
                "abandoned": NSNumber(value: true),
                "dismantled": NSNumber(value: true),
                "disused": NSNumber(value: true),
                "razed": NSNumber(value: true),
                "demolished": NSNumber(value: true),
                "obliterated": NSNumber(value: true)
            ]
            parking_buildings = [
                "multi-storey": NSNumber(value: true),
                "sheds": NSNumber(value: true),
                "carports": NSNumber(value: true),
                "garage_boxes": NSNumber(value: true)
            ]
            natural_water = [
                "water": NSNumber(value: true),
                "coastline": NSNumber(value: true),
                "bay": NSNumber(value: true)
            ]
            landuse_water = [
                "pond": NSNumber(value: true),
                "basin": NSNumber(value: true),
                "reservoir": NSNumber(value: true),
                "salt_pond": NSNumber(value: true)
            ]
        }
        private let predPoints: ((OsmBaseObject?) -> Bool)? = { object in
            return object?.isNode && object?.isNode.wayCount == 0
        }
        private let predTrafficRoads: ((OsmBaseObject?) -> Bool)? = { object in
            if let tags = object?.tags["highway"] {
                return object?.isWay && traffic_roads[tags]
            }
            return false
        }
        private let predServiceRoads: ((OsmBaseObject?) -> Bool)? = { object in
            if let tags = object?.tags["highway"] {
                return object?.isWay && service_roads[tags]
            }
            return false
        }
        private let predPaths: ((OsmBaseObject?) -> Bool)? = { object in
            if let tags = object?.tags["highway"] {
                return object?.isWay && paths[tags]
            }
            return false
        }
        private let predBuildings: ((OsmBaseObject?) -> Bool)? = { object in
            var v: String?
            if let tags = object?.tags["parking"] {
                return object?.tags["building:part"] != nil || ((v = object?.tags["building"] as? String) != nil && (v != "no")) || (object?.tags["amenity"] == "shelter") || parking_buildings[tags]
            }
            return false
        }
        private let predWater: ((OsmBaseObject?) -> Bool)? = { object in
            if let tags = object?.tags["natural"], let tags1 = object?.tags["landuse"] {
                return object?.tags["waterway"] != nil || natural_water[tags] || landuse_water[tags1]
            }
            return false
            
        }
        private let predLanduse: ((OsmBaseObject?) -> Bool)? = { object in
            return (object?.isWay.isArea || object?.isRelation.isMultipolygon) && !predBuildings?(object) && !predWater?(object)
        }
        private let predBoundaries: ((OsmBaseObject?) -> Bool)? = { object in
            if object?.tags["boundary"] != nil {
                let highway = object?.tags["highway"] as? String
                return !(traffic_roads[highway ?? ""] || service_roads[highway ?? ""] || paths[highway ?? ""])
            }
            return false
        }
        private let predRail: ((OsmBaseObject?) -> Bool)? = { object in
            if object?.tags["railway"] != nil || (object?.tags["landuse"] == "railway") {
                let highway = object?.tags["highway"] as? String
                return !(traffic_roads[highway ?? ""] || service_roads[highway ?? ""] || paths[highway ?? ""])
            }
            return false
        }
        private let predPower: ((OsmBaseObject?) -> Bool)? = { object in
            return object?.tags["power"] != nil
        }
        private let predPastFuture: ((OsmBaseObject?) -> Bool)? = { object in
            // contains a past/future tag, but not in active use as a road/path/cycleway/etc..
            let highway = object?.tags["highway"] as? String
            if traffic_roads[highway ?? ""] || service_roads[highway ?? ""] || paths[highway ?? ""] {
                return false
            }
            var ok = false
            object?.tags.enumerateKeysAndObjects({ key, value, stop in
                if past_futures[key ?? ""] || past_futures[value ?? ""] {
                    stop = UnsafeMutablePointer<ObjCBool>(mutating: &true)
                    ok = true
                }
            })
            return ok
        }
        
        let predicate = NSPredicate(block: { object, bindings in
            if predLevel && !predLevel(object) {
                return false
            }
            let matchAny = false
            //            #define MATCH(name)\
            //                    if ( _show##name || _showOthers ) { \
            //                        BOOL match = pred##name(object); \
            //                        if ( match && _show##name ) return YES; \
            //                        matchAny |= match; \
            //                    }
            //                    MATCH(Points);
            //                    MATCH(TrafficRoads);
            //                    MATCH(ServiceRoads);
            //                    MATCH(Paths);
            //                    MATCH(PastFuture);
            //                    MATCH(Buildings);
            //                    MATCH(Landuse);
            //                    MATCH(Boundaries);
            //                    MATCH(Water);
            //                    MATCH(Rail);
            //                    MATCH(Power);
            //                    MATCH(Water);
            //            #undef MATCH
            if showOthers && !matchAny {
                if object?.isWay && object?.parentRelations.count == 1 && (object?.parentRelations.last as? OsmRelation)?.isMultipolygon {
                    return false // follow parent filter instead
                }
                return true
            }
            return false
        })
        
        // filter everything
        objects.filter { predicate.evaluate(with: $0) }
        
        var add = []
        var remove = []
        for obj in objects {
            // if we are showing relations we need to ensure the members are visible too
            if obj.isRelation.isMultipolygon {
                let set = obj.isRelation.allMemberObjects()
                for o in set {
                    guard let o = o as? OsmBaseObject else {
                        continue
                    }
                    if o.isWay {
                        add.insert(o)
                    }
                }
            }
            // if a way belongs to relations which are hidden, and it has no other tags itself, then hide it as well
            if obj.isWay && obj.parentRelations.count > 0 && !obj.hasInterestingTags {
                var hidden = true
                for parent in obj.parentRelations {
                    if !(parent.isMultipolygon || parent.isBoundary) || objects.contains(parent) {
                        hidden = false
                        break
                    }
                }
                if hidden {
                    remove.insert(obj)
                }
            }
        }
        for o in remove {
            guard let o = o as? OsmBaseObject else {
                continue
            }
            objects.removeAll { $0 as AnyObject === o as AnyObject }
        }
        for o in add {
            guard let o = o as? OsmBaseObject else {
                continue
            }
            objects.append(o)
        }
        #endif
    }
    
    func getObjectsToDisplay() -> [OsmBaseObject]? {
        #if os(iOS)
        let geekScore = geekbenchScoreProvider.geekbenchScore()
        #if true || DEBUG
        var objectLimit = Int(50 + (geekScore - 500) / 40) // 500 -> 50, 2500 -> 10
        objectLimit *= 3
        #else
        let minObj = 50 // score = 500
        let maxObj = 300 // score = 2500
        var objectLimit = Int(Double(minObj) + Double((maxObj - minObj)) * (geekScore - 500) / 2000)
        #endif
        #else
        var objectLimit = 500
        #endif
        
        // get objects in visible rect
        var objects = getVisibleObjects()
        
        atVisibleObjectLimit = objects.count >= objectLimit // we want this to reflect the unfiltered count
        
        if enableObjectFilters {
            filterObjects(objects)
        }
        
        // get renderInfo for objects
        for object in objects {
            guard let object = object as? OsmBaseObject else {
                continue
            }
            if object.renderInfo == nil {
                object.renderInfo = RenderInfoDatabase.sharedRenderInfoDatabase.renderInfo(for: object)
            }
            if object.renderPriorityCached == 0 {
                object.renderPriorityCached = object.renderInfo.renderPriority(for: object)
            }
        }
        
        // sort from big to small objects, and remove excess objects
        //    [objects countSortOsmObjectVisibleSizeWithLargest:objectLimit];
        
        // sometimes there are way too many address nodes that clog up the view, so limit those items specifically
        objectLimit = objects.count
        let addressCount = 0
        while addressCount < objectLimit {
            let obj = objects[objectLimit - addressCount - 1] as? OsmBaseObject
            if !obj?.renderInfo.isAddressPoint() {
                break
            }
            addressCount += 1
        }
        if addressCount > 50 {
            let range = NSIndexSet(indexesIn: NSRange(location: objectLimit - addressCount, length: addressCount))
            for deletionIndex in range.reversed() { objects.remove(at: deletionIndex) }
        }
        
        return objects as? [OsmBaseObject]
    }
    
    func layoutSublayersSafe() {
        if mapView?.birdsEyeRotation {
            var t = CATransform3DIdentity
            t.m34 = -1.0 / mapView?.birdsEyeDistance
            t = CATransform3DRotate(t, mapView?.birdsEyeRotation, 1.0, 0, 0)
            baseLayer.sublayerTransform = t
        } else {
            baseLayer.sublayerTransform = CATransform3DIdentity
        }
        
        let previousObjects = shownObjects
        
        shownObjects = getObjectsToDisplay()
        shownObjects.append(contentsOf: Array(fadingOutSet))
        
        // remove layers no longer visible
        var removals = Set<AnyHashable>(previousObjects)
        for object in shownObjects {
            removals.remove(object)
        }
        // use fade when removing objects
        if removals.count != 0 {
            #if FADE_INOUT
            CATransaction.begin()
            CATransaction.setAnimationDuration(1.0)
            CATransaction.setCompletionBlock({
                for object in removals {
                    fadingOutSet.removeAll { $0 as AnyObject === object as AnyObject }
                    shownObjects.removeAll { $0 as AnyObject === object as AnyObject }
                    for layer in object.shapeLayers {
                        if layer.opacity < 0.1 {
                            layer.removeFromSuperlayer()
                        }
                    }
                }
            })
            for object in removals {
                fadingOutSet.union(removals)
                for layer in object.shapeLayers {
                    layer.opacity = 0.01
                }
            }
            CATransaction.commit()
            #else
            for object in removals {
                for layer in object.shapeLayers {
                    layer.removeFromSuperlayer()
                }
            }
            #endif
        }
        
        #if FADE_INOUT
        CATransaction.begin()
        CATransaction.setAnimationDuration(1.0)
        #endif
        
        let tRotation = OSMTransformRotation(mapView?.screenFromMapTransform)
        let tScale = OSMTransformScaleX(mapView?.screenFromMapTransform)
        let pScale = tScale / PATH_SCALING
        let pixelsPerMeter = 0.8 * 1.0 / mapView?.metersPerPixel()
        
        for object in shownObjects {
            
            let layers = getShapeLayers(for: object)
            
            for layer in layers {
                guard let layer = layer as? (CALayer & LayerPropertiesProviding) else {
                    continue
                }
                
                // configure the layer for presentation
                let isShapeLayer = layer is CAShapeLayer
                let props = layer.properties
                let pt = props?.position
                var pt2 = mapView?.screenPoint(fromMapPoint: pt, birdsEye: false)
                
                if props?.is3D || (isShapeLayer && !object.isNode) {
                    
                    // way or area -- need to rotate and scale
                    if props?.is3D {
                        if mapView?.birdsEyeRotation == 0.0 {
                            layer.removeFromSuperlayer()
                            continue
                        }
                        var t = CATransform3DMakeTranslation(pt2.x - pt?.x, pt2.y - pt?.y, 0)
                        t = CATransform3DScale(t, CGFloat(pScale), CGFloat(pScale), CGFloat(pixelsPerMeter))
                        t = CATransform3DRotate(t, CGFloat(tRotation), 0, 0, 1)
                        if let transform = props?.transform {
                            t = CATransform3DConcat(transform, t)
                        }
                        layer.transform = t
                        if !isShapeLayer {
                            layer.borderWidth = (props?.lineWidth ?? 0.0) / pScale // wall
                        }
                    } else {
                        var t = CGAffineTransform(translationX: pt2.x - pt?.x, y: pt2.y - pt?.y)
                        t = t.scaledBy(x: CGFloat(pScale), y: CGFloat(pScale))
                        t = t.rotated(by: CGFloat(tRotation))
                        layer.affineTransform = t
                    }
                    
                    if isShapeLayer {
                    } else {
                        // its a wall, so bounds are already height/length of wall
                    }
                    
                    if isShapeLayer {
                        let shape = layer as? CAShapeLayer
                        shape?.lineWidth = CGFloat((props?.lineWidth ?? 0.0) / pScale)
                    }
                } else {
                    
                    // node or text -- no scale transform applied
                    if layer is CATextLayer {
                        
                        // get size of building (or whatever) into which we need to fit the text
                        if object.isNode {
                            // its a node with text, such as an address node
                        } else {
                            // its a label on a building or polygon
                            let rcMap = mapView?.mapRect(forLatLonRect: object.boundingBox)
                            let rcScreen = mapView?.boundingScreenRect(forMapRect: rcMap)
                            if layer.bounds.size.width >= 1.1 * rcScreen.size.width {
                                // text label is too big so hide it
                                layer.removeFromSuperlayer()
                                continue
                            }
                        }
                    } else if layer.properties.isDirectional {
                        
                        // a direction layer (direction=*), so it needs to rotate with the map
                        layer.affineTransform = CGAffineTransform(rotationAngle: CGFloat(tRotation))
                    } else {
                        
                        // its an icon or a generic box
                    }
                    
                    let scale = UIScreen.main.scale
                    pt2.x = round(Double(pt2.x * scale)) / Double(scale)
                    pt2.y = round(Double(pt2.y * scale)) / Double(scale)
                    layer.position = CGPoint(x: pt2.x + props?.offset.x, y: pt2.y + props?.offset.y)
                }
                
                // add the layer if not already present
                if layer.superlayer == nil {
                    #if FADE_INOUT
                    layer.removeAllAnimations()
                    layer.opacity = 1.0
                    #endif
                    baseLayer.addSublayer(layer)
                }
            }
        }
        
        #if FADE_INOUT
        CATransaction.commit()
        #endif
        
        // draw highlights: these layers are computed in screen coordinates and don't need to be transformed
        for layer in highlightLayers {
            // remove old highlights
            layer.removeFromSuperlayer()
        }
        
        // get highlights
        highlightLayers = getShapeLayersForHighlights()
        
        // get ocean
        let ocean = getOceanLayer(shownObjects)
        if let ocean = ocean {
            highlightLayers.append(ocean)
        }
        for layer in highlightLayers {
            // add new highlights
            baseLayer.addSublayer(layer)
        }
        
        // NSLog(@"%ld layers", (long)self.sublayers.count);
    }
    
    func layoutSublayers() {
        if hidden {
            return
        }
        
        if highwayScale == 0.0 {
            // Make sure stuff is initialized for current view. This is only necessary because layout code is called before bounds are set
            updateIconSize()
        }
        
        isPerformingLayout = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutSublayersSafe()
        CATransaction.commit()
        isPerformingLayout = false
    }
    
    func setNeedsLayout() {
        if isPerformingLayout {
            return
        }
        super.setNeedsLayout()
    }
    
    // MARK: Hit Testing
    @inline(__always) private func HitTestLineSegment(_ point: CLLocationCoordinate2D, _ maxDegrees: OSMSize, _ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) -> CGFloat {
        var line1 = OSMPoint(coord1.longitude - point.longitude, coord1.latitude - point.latitude)
        var line2 = OSMPoint(coord2.longitude - point.longitude, coord2.latitude - point.latitude)
        let pt = OSMPoint(0, 0)
        
        // adjust scale
        line1.x /= maxDegrees.width
        line1.y /= maxDegrees.height
        line2.x /= maxDegrees.width
        line2.y /= maxDegrees.height
        
        let dist = DistanceFromPointToLineSegment(pt, line1, line2)
        return dist
    }
    
    
    class func osmHitTest(_ way: OsmWay?, location: CLLocationCoordinate2D, maxDegrees: OSMSize, segment: UnsafeMutablePointer<Int>?) -> CGFloat {
        var segment = segment
        let previous: CLLocationCoordinate2D
        let seg = -1
        var bestDist: CGFloat = 1000000
        if let nodes = way?.nodes {
            for node in nodes {
                guard let node = node as? OsmNode else {
                    continue
                }
                if seg >= 0 {
                    let coord = CLLocationCoordinate2D(latitude: node.lat, longitude: node.lon)
                    let dist = HitTestLineSegment(location, maxDegrees, coord, previous)
                    if dist < bestDist {
                        bestDist = dist
                        segment = UnsafeMutablePointer<Int>(mutating: &seg)
                    }
                }
                seg += 1
                previous.latitude = node.lat
                previous.longitude = node.lon
            }
        }
        return bestDist
    }
    
    class func osmHitTest(_ node: OsmNode?, location: CLLocationCoordinate2D, maxDegrees: OSMSize) -> CGFloat {
        let delta = OSMPoint((location.longitude - (node?.lon ?? 0)) / maxDegrees.width, (location.latitude - (node?.lat ?? 0)) / maxDegrees.height)
        let dist = hypot(delta.x, delta.y)
        return dist
    }
    
    // distance is in units of the hit test radius (WayHitTestRadius)
    class func osmHitTestEnumerate(
        _ point: CGPoint,
        radius: CGFloat,
        mapView: MapView?,
        objects: [OsmBaseObject]?,
        testNodes: Bool,
        ignoreList: [OsmBaseObject]?,
        block: @escaping (_ obj: OsmBaseObject?, _ dist: CGFloat, _ segment: Int) -> Void
    ) {
        let location = mapView?.longitudeLatitude(forScreenPoint: point, birdsEye: true)
        let viewCoord = mapView?.screenLongitudeLatitude()
        let pixelsPerDegree = OSMSize(mapView?.bounds.size.width / viewCoord?.size.width, mapView?.bounds.size.height / viewCoord?.size.height)
        
        let maxDegrees = OSMSize(radius / pixelsPerDegree.width, radius / pixelsPerDegree.height)
        let NODE_BIAS = 0.5 // make nodes appear closer so they can be selected
        
        var parentRelations = []
        for object in objects ?? [] {
            if object.deleted {
                continue
            }
            
            if object.isNode {
                let node = object as? OsmNode
                if let node = node {
                    if !(ignoreList?.contains(node) ?? false) {
                        if testNodes || node?.wayCount == 0 {
                            var dist = self.osmHitTest(node, location: location, maxDegrees: maxDegrees)
                            dist *= CGFloat(NODE_BIAS)
                            if dist <= 1.0 {
                                block(node, dist, 0)
                                parentRelations.formUnion(Set(node?.parentRelations))
                            }
                        }
                    }
                }
            } else if object.isWay {
                let way = object as? OsmWay
                if let way = way {
                    if !(ignoreList?.contains(way) ?? false) {
                        var seg = 0
                        let distToWay = self.osmHitTest(way, location: location, maxDegrees: maxDegrees, segment: &seg)
                        if distToWay <= 1.0 {
                            block(way, distToWay, seg)
                            parentRelations.formUnion(Set(way?.parentRelations))
                        }
                    }
                }
                if testNodes {
                    if let nodes = way?.nodes {
                        for node in nodes {
                            guard let node = node as? OsmNode else {
                                continue
                            }
                            if ignoreList?.contains(node) ?? false {
                                continue
                            }
                            var dist = self.osmHitTest(node, location: location, maxDegrees: maxDegrees)
                            dist *= CGFloat(NODE_BIAS)
                            if dist < 1.0 {
                                block(node, dist, 0)
                                parentRelations.formUnion(Set(node.parentRelations))
                            }
                        }
                    }
                }
            } else if object.isRelation.isMultipolygon {
                let relation = object as? OsmRelation
                if let relation = relation {
                    if !(ignoreList?.contains(relation) ?? false) {
                        var bestDist: CGFloat = 10000.0
                        if let members = relation?.members {
                            for member in members {
                                guard let member = member as? OsmMember else {
                                    continue
                                }
                                let way = member.ref
                                if way is OsmWay {
                                    if let way = way {
                                        if !(ignoreList?.contains(way) ?? false) {
                                            if (member.role == "inner") || (member.role == "outer") {
                                                var seg = 0
                                                var dist = self.osmHitTest(way, location: location, maxDegrees: maxDegrees, segment: &seg)
                                                if dist < bestDist {
                                                    bestDist = dist
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        if bestDist <= 1.0 {
                            block(relation, bestDist, 0)
                        }
                    }
                }
            }
        }
        for relation in parentRelations {
            guard let relation = relation as? OsmRelation else {
                continue
            }
            // for non-multipolygon relations, like turn restrictions
            block(relation, 1.0, 0)
        }
    }
    
    // default hit test when clicking on the map, or drag-connecting
    func osmHitTest(_ point: CGPoint, radius: CGFloat, isDragConnect: Bool, ignoreList: [OsmBaseObject]?, segment pSegment: UnsafeMutablePointer<Int>?) -> OsmBaseObject? {
        var pSegment = pSegment
        if hidden {
            return nil
        }
        
        var bestDist: CGFloat = 1000000
        var best: [AnyHashable : Any] = [:]
        EditorMapLayer.osmHitTestEnumerate(point, radius: radius, mapView: mapView, objects: shownObjects, testNodes: isDragConnect, ignoreList: ignoreList, block: { obj, dist, segment in
            if dist < bestDist {
                bestDist = dist
                best.removeAll()
                best[obj] = NSNumber(value: segment)
            } else if dist == bestDist {
                best[obj] = NSNumber(value: segment)
            }
        })
        if bestDist > 1.0 {
            return nil
        }
        
        var pick: OsmBaseObject? = nil
        if best.count > 1 {
            if isDragConnect {
                // prefer to connecct to a way in a relation over the relation itself, which is opposite what we do when selecting by tap
                for obj in best {
                    guard let obj = obj as? OsmBaseObject else {
                        continue
                    }
                    if !obj.isRelation {
                        pick = obj
                        break
                    }
                }
            } else {
                // performing selection by tap
                if pick == nil && selectedRelation {
                    // pick a way that is a member of the relation if possible
                    for member in selectedRelation.members {
                        if best[member.ref] != nil {
                            pick = member.ref
                            break
                        }
                    }
                }
                if pick == nil && selectedPrimary == nil {
                    // nothing currently selected, so prefer relations
                    for obj in best {
                        guard let obj = obj as? OsmBaseObject else {
                            continue
                        }
                        if obj.isRelation {
                            pick = obj
                            break
                        }
                    }
                }
            }
        }
        if pick == nil {
            pick = (best as NSDictionary).keyEnumerator().nextObject() as? OsmBaseObject
        }
        if pSegment != nil {
            if let pick = pick {
                pSegment = UnsafeMutablePointer<Int>(mutating: (best[pick] as? NSNumber).intValue)
            }
        }
        return pick
    }
    
    // return all nearby objects
    func osmHitTestMultiple(_ point: CGPoint, radius: CGFloat) -> [OsmBaseObject]? {
        var objectSet = []
        EditorMapLayer.osmHitTestEnumerate(point, radius: radius, mapView: mapView, objects: shownObjects, testNodes: true, ignoreList: nil, block: { obj, dist, segment in
            objectSet.insert(obj)
        })
        var objectList = Array(objectSet)
        objectList = (objectList as NSArray).sortedArray(comparator: { o1, o2 in
            let diff = (o1?.isRelation ? 2 : o1?.isWay ? 1 : 0) - (o2?.isRelation ? 2 : o2?.isWay ? 1 : 0)
            if diff != 0 {
                return ComparisonResult(rawValue: -diff)!
            }
            let diff2 = o1?.ident.int64Value ?? 0 - o2?.ident.int64Value ?? 0
            return diff2 < 0 ? .orderedAscending : diff2 > 0 ? .orderedDescending : .orderedSame
        }) as? [AnyHashable] ?? objectList
        return objectList
    }
    
    // drill down to a node in the currently selected way
    func osmHitTestNode(inSelectedWay point: CGPoint, radius: CGFloat) -> OsmNode? {
        if selectedWay == nil {
            return nil
        }
        var hit: OsmBaseObject? = nil
        var bestDist: CGFloat = 1000000
        EditorMapLayer.osmHitTestEnumerate(point, radius: radius, mapView: mapView, objects: selectedWay.nodes, testNodes: true, ignoreList: nil, block: { obj, dist, segment in
            if dist < bestDist {
                bestDist = dist
                hit = obj
            }
        })
        if bestDist <= 1.0 {
            assert(hit?.isNode)
            return hit?.isNode
        }
        return nil
    }
    
    // MARK: Copy/Paste
    
    func copyTags(_ object: OsmBaseObject?) -> Bool {
        UserDefaults.standard.set(object?.tags, forKey: "copyPasteTags")
        return (object?.tags.count ?? 0) > 0
    }
    
    func canPasteTags() -> Bool {
        let copyPasteTags = UserDefaults.standard.object(forKey: "copyPasteTags") as? [AnyHashable : Any]
        return (copyPasteTags?.count ?? 0) > 0
    }
    
    func pasteTagsMerge(_ object: OsmBaseObject?) {
        // Merge tags
        let copyPasteTags = UserDefaults.standard.object(forKey: "copyPasteTags") as? [AnyHashable : Any]
        let newTags = MergeTags(object?.tags, copyPasteTags, true)
        mapData?.setTags(newTags, for: object)
        setNeedsLayout()
    }
    
    func pasteTagsReplace(_ object: OsmBaseObject?) {
        // Replace all tags
        let copyPasteTags = UserDefaults.standard.object(forKey: "copyPasteTags") as? [AnyHashable : Any]
        mapData?.setTags(copyPasteTags, for: object)
        setNeedsLayout()
    }
    
    // MARK: Editing
    
    func adjust(_ node: OsmNode?, byDistance delta: CGPoint) {
        var pt = mapView?.screenPoint(forLatitude: node?.lat, longitude: node?.lon, birdsEye: true)
        pt.x += delta.x
        pt.y -= delta.y
        let loc = mapView?.longitudeLatitude(forScreenPoint: pt, birdsEye: true)
        mapData?.setLongitude(loc.longitude, latitude: loc.latitude, for: node)
        
        setNeedsLayout()
    }
    
    func duplicate(_ object: OsmBaseObject?, withOffset offset: OSMPoint) -> OsmBaseObject? {
        let newObject = mapData?.duplicate(object, withOffset: offset)
        setNeedsLayout()
        return newObject
    }
    
    func createNode(at point: CGPoint) -> OsmNode? {
        let loc = mapView?.longitudeLatitude(forScreenPoint: point, birdsEye: true)
        let node = mapData?.createNode(atLocation: loc)
        setNeedsLayout()
        return node
    }
    
    func createWay(with node: OsmNode?) -> OsmWay? {
        let way = mapData?.createWay()
        var dummy: String?
        let add = mapData?.canAddNode(to: way, at: 0, error: &dummy)
        add(node)
        setNeedsLayout()
        return way
    }
    
    // MARK: Editing actions that modify data and can fail
    
    func canAddNode(to way: OsmWay?, at index: Int, error: String?) -> EditActionWithNode {
        let action = mapData?.canAddNode(to: way, at: index, error: error)
        if action == nil {
            return nil
        }
        return { [self] node in
            action(node)
            setNeedsLayout()
        }
    }
    
    func canDeleteSelectedObject(_ error: String?) -> EditAction {
        if selectedNode {
            
            // delete node from selected way
            var action: EditAction
            if selectedWay {
                action = mapData?.canDeleteNode(selectedNode, fromWay: selectedWay, error: error)
            } else {
                action = mapData?.canDeleteNode(selectedNode, error: error)
            }
            if action != nil {
                let way = selectedWay
                return { [self] in
                    // deselect node after we've removed it from ways
                    action()
                    self.selectedNode = nil
                    if way?.deleted {
                        self.selectedWay = nil
                    }
                    setNeedsLayout()
                }
            }
        } else if selectedWay {
            
            // delete way
            var action = mapData?.canDeleteWay(selectedWay, error: error)
            if action != nil {
                return { [self] in
                    action()
                    self.selectedNode = nil
                    self.selectedWay = nil
                    setNeedsLayout()
                }
            }
        } else if selectedRelation {
            var action = mapData?.canDeleteRelation(selectedRelation, error: error)
            if action != nil {
                return { [self] in
                    action()
                    self.selectedNode = nil
                    self.selectedWay = nil
                    self.selectedRelation = nil
                    setNeedsLayout()
                }
            }
        }
        
        return nil
    }
    
    // MARK: Highlighting and Selection
    func setNeedsDisplayFor(_ object: OsmBaseObject?) {
        setNeedsLayout()
    }
    
    func selectedPrimary() -> OsmBaseObject? {
        return selectedNode ?? selectedWay ?? selectedRelation
    }
    
    func selectedNode() -> OsmNode? {
        return selectedNode
    }
    
    func selectedWay() -> OsmWay? {
        return selectedWay
    }
    
    func selectedRelation() -> OsmRelation? {
        return selectedRelation
    }
    
    func setSelectedNode(_ selectedNode: OsmNode?) {
        assert(selectedNode == nil || selectedNode?.isNode)
        if selectedNode != self.selectedNode {
            self.selectedNode = selectedNode
            setNeedsDisplayFor(selectedNode)
            mapView?.updateEditControl()
        }
    }
    
    func setSelectedWay(_ selectedWay: OsmWay) {
        assert(selectedWay == nil || selectedWay.isWay)
        if selectedWay != self.selectedWay {
            self.selectedWay = selectedWay
            setNeedsDisplayFor(selectedWay)
            mapView?.updateEditControl()
        }
    }
    
    func setSelectedRelation(_ selectedRelation: OsmRelation) {
        assert(selectedRelation == nil || selectedRelation.isRelation)
        if selectedRelation != self.selectedRelation {
            self.selectedRelation = selectedRelation
            setNeedsDisplayFor(selectedRelation)
            mapView?.updateEditControl()
        }
    }
    
    // MARK: Properties
    
    func setHidden(_ hidden: Bool) {
        let wasHidden = self.hidden
        super.setHidden(hidden)
        
        if wasHidden && !hidden {
            updateMapLocation()
        }
    }
    
    func setWhiteText(_ whiteText: Bool) {
        if self.whiteText != whiteText {
            self.whiteText = whiteText
            CurvedGlyphLayer.whiteOnBlack = self.whiteText
            resetDisplayLayers()
        }
    }
    
    // MARK: Coding
    
    override func encode(with coder: NSCoder) {
    }
    
    required init?(coder: NSCoder) {
        // This is just here for completeness. The current object will be substituted during decode.
        super.init()
    }
    
}
