//
//  UndoManager.swift
//  Go Map!
//
//  Created by Bryce Cogswell on 8/16/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import Foundation

typealias UndoManagerChangeCallback = () -> Void

class MyUndoManager: NSObject, NSSecureCoding {
	static let supportsSecureCoding = true

	private var runLoopObserver: CFRunLoopObserver?
	private var undoStack: [UndoAction] = []
	private var redoStack: [UndoAction] = []
	private var groupingStack: [Int] = []
	var commentList: [UndoContext] = []

	private(set) var isUndoing = false
	private(set) var isRedoing = false

	/// Set by OsmMapData immediately after creating or decoding the undo manager.
	/// Used by `apply(_:)` to perform spatial-index updates inside operation apply bodies.
	weak var mapData: OsmMapData?

	public static let UndoManagerDidChangeNotification = "UndoManagerDidChangeNotification"

	var canUndo: Bool {
		return undoStack.count > 0
	}

	var canRedo: Bool {
		return redoStack.count > 0
	}

	var countUndoGroups: Int {
		var count = 0
		var group = -1
		for action in undoStack {
			if action.group != group {
				count += 1
				group = action.group
			}
		}
		return count
	}

	var runLoopCounter = 0

	func initCommon() {
		var context = CFRunLoopObserverContext()
		context.info = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
		runLoopObserver = CFRunLoopObserverCreate(
			kCFAllocatorDefault,
			CFRunLoopActivity.afterWaiting.rawValue,
			true,
			CFIndex(0),
			RunLoopObserverCallBack,
			&context)
		CFRunLoopAddObserver(CFRunLoopGetMain(), runLoopObserver, CFRunLoopMode.commonModes)
		//		DLog(@"add observer %@",_runLoopObserver);
	}

	override init() {
		super.init()
		initCommon()
	}

	deinit {
		if runLoopObserver != nil {
			CFRunLoopRemoveObserver(CFRunLoopGetMain(), runLoopObserver, CFRunLoopMode.commonModes)
			//		DLog(@"remove observer %@",_runLoopObserver);
		}
	}

	override var description: String {
		var text = ""
		text += "undo stack:\n"
		text += String(format: "   run loop = %ld\n", runLoopCounter)
		text += "   group = \(groupingStack.last ?? -1)\n"
		for action in undoStack {
			text += "   \(action)\n"
		}
		return text
	}

	func count() -> Int {
		return undoStack.count + redoStack.count
	}

	func postChangeNotification() {
		let notification = Notification(
			name: NSNotification.Name(MyUndoManager.UndoManagerDidChangeNotification),
			object: self)
		NotificationQueue.default.enqueue(
			notification,
			postingStyle: .whenIdle,
			coalesceMask: [.onName, .onSender],
			forModes: nil)
	}

	func removeMostRecentRedo() {
		assert(redoStack.count > 0)

		let group = redoStack.last!.group
		while let last = redoStack.last,
		      last.group == group
		{
			redoStack.removeLast()
		}

		postChangeNotification()
	}

	func removeAllActions() {
		willChangeValue(forKey: "canUndo")
		willChangeValue(forKey: "canRedo")

		assert(!isUndoing && !isRedoing)
		undoStack.removeAll()
		redoStack.removeAll()

		didChangeValue(forKey: "canUndo")
		didChangeValue(forKey: "canRedo")

		postChangeNotification()
	}

	/// Applies the inverse of all undo actions belonging to `groupIds`, permanently
	/// discarding those edits without pushing anything to the redo stack.
	/// The redo stack is cleared entirely (same policy as `removeGroups`).
	///
	/// Safe to call on a `ConnectedObjects` supergroup because its object set is
	/// guaranteed disjoint from every other supergroup on the stack.
	func discardGroups(_ groupIds: Set<Int>) {
		guard let mapData = mapData else { return }

		willChangeValue(forKey: "canUndo")
		willChangeValue(forKey: "canRedo")

		assert(!isUndoing && !isRedoing)

		// Apply inverses in reverse stack order (newest first) so multi-step edits
		// on the same object unwind correctly.
		var affectedObjects: Set<OsmBaseObject> = []
		for i in stride(from: undoStack.count - 1, through: 0, by: -1) {
			let action = undoStack[i]
			guard groupIds.contains(action.group) else { continue }
			action.type.apply(to: mapData)
			affectedObjects.formUnion(action.type.modifyObjects)
		}

		// Remove the reverted actions and wipe the redo stack.
		undoStack.removeAll { groupIds.contains($0.group) }
		redoStack.removeAll()

		// Recompute isModified: an object is still modified only if it remains
		// on the undo stack.
		let liveModified = Set(undoStack.flatMap { $0.type.modifyObjects })
		for obj in affectedObjects {
			obj.setModified(liveModified.contains(obj))
		}

		didChangeValue(forKey: "canUndo")
		didChangeValue(forKey: "canRedo")

		postChangeNotification()
	}

	/// Removes all undo actions belonging to the given groups and clears the redo stack.
	/// The redo stack is always cleared because any pending redos are based on pre-upload
	/// object state and are irrecoverably stale after a server upload.
	func removeGroups(_ groupIds: Set<Int>) {
		willChangeValue(forKey: "canUndo")
		willChangeValue(forKey: "canRedo")

		assert(!isUndoing && !isRedoing)
		undoStack.removeAll { groupIds.contains($0.group) }
		redoStack.removeAll()

		didChangeValue(forKey: "canUndo")
		didChangeValue(forKey: "canRedo")

		postChangeNotification()
	}

	// MARK: - Forward-edit entry point

	/// Executes `type` immediately and pushes the inverse onto the appropriate stack.
	/// For actions that modify objects, marks them modified and appends comments to `commentList`.
	func apply(_ type: OsmEditOperation) {
		guard let mapData = mapData else { return }

		willChangeValue(forKey: "canUndo")
		willChangeValue(forKey: "canRedo")

		if case let .comment(ctx) = type {
			commentList.append(ctx)
		}

		let inverseType = type.apply(to: mapData)
		let group = groupingStack.last ?? runLoopCounter
		let inverse = UndoAction(type: inverseType, group: group)

		if isUndoing {
			redoStack.append(inverse)
		} else if isRedoing {
			undoStack.append(inverse)
		} else {
			undoStack.append(inverse)
			redoStack.removeAll()
		}

		// Forward edits always mark objects as modified.
		for obj in type.modifyObjects {
			obj.setModified(true)
		}

		didChangeValue(forKey: "canUndo")
		didChangeValue(forKey: "canRedo")

		postChangeNotification()
	}

	func doComment(_ comment: UndoContext) {
		apply(.comment(comment))
	}

	func registerUndoComment(_ comment: UndoContext) {
		apply(.comment(comment))
	}

	func doActionGroup(fromStack stack: inout [UndoAction]) {
		guard stack.last != nil else { return }
		let currentGroup = stack.last!.group
		var affectedObjects: Set<OsmBaseObject> = []

		while stack.last?.group == currentGroup,
		      let action = stack.popLast()
		{
			if case let .comment(ctx) = action.type {
				commentList.append(ctx)
			}
			guard let mapData = mapData else { continue }
			let inverseType = action.type.apply(to: mapData)
			let inverse = UndoAction(type: inverseType, group: action.group)
			if isUndoing {
				redoStack.append(inverse)
			} else {
				undoStack.append(inverse)
			}
			affectedObjects.formUnion(action.type.modifyObjects)
		}

		// Recompute isModified for affected objects.
		// After undo: an object is still modified only if it remains on the undo stack.
		// After redo: all affected objects are back on the undo stack, so always modified.
		if isUndoing {
			let liveModified = Set(stack.flatMap { $0.type.modifyObjects })
			for obj in affectedObjects {
				obj.setModified(liveModified.contains(obj))
			}
		} else {
			for obj in affectedObjects {
				obj.setModified(true)
			}
		}
	}

	// returns the oldest comment registered within the undo group
	func undo() -> UndoContext? {
		commentList = []

		willChangeValue(forKey: "canUndo")
		willChangeValue(forKey: "canRedo")

		assert(!isUndoing && !isRedoing)
		isUndoing = true
		doActionGroup(fromStack: &undoStack)
		isUndoing = false

		didChangeValue(forKey: "canUndo")
		didChangeValue(forKey: "canRedo")

		postChangeNotification()

		return commentList.last
	}

	func redo() -> UndoContext? {
		commentList = []

		willChangeValue(forKey: "canUndo")
		willChangeValue(forKey: "canRedo")

		assert(!isUndoing && !isRedoing)
		isRedoing = true
		doActionGroup(fromStack: &redoStack)
		isRedoing = false

		didChangeValue(forKey: "canUndo")
		didChangeValue(forKey: "canRedo")

		postChangeNotification()

		return commentList.last
	}

	func beginUndoGrouping() {
		let group = groupingStack.last ?? runLoopCounter
		groupingStack.append(group)
	}

	func endUndoGrouping() {
		groupingStack.removeLast()
	}

	func objectRefs() -> Set<OsmBaseObject> {
		var refs: Set<OsmBaseObject> = []
		for stack in [undoStack, redoStack] {
			for action in stack {
				refs.formUnion(action.osmObjects)
			}
		}
		return refs
	}

	func encode(with coder: NSCoder) {
		coder.encode(undoStack, forKey: "undoStack")
		coder.encode(redoStack, forKey: "redoStack")
		coder.encode(runLoopCounter, forKey: "runLoopCounter")
	}

	required init?(coder: NSCoder) {
		super.init()
		undoStack = coder.decodeObject(of: [NSArray.self, UndoAction.self], forKey: "undoStack") as? [UndoAction] ?? []
		redoStack = coder.decodeObject(of: [NSArray.self, UndoAction.self], forKey: "redoStack") as? [UndoAction] ?? []
		runLoopCounter = coder.decodeInteger(forKey: "runLoopCounter")
		initCommon()
	}
}

private func RunLoopObserverCallBack(
	_ observer: CFRunLoopObserver?,
	_ activity: CFRunLoopActivity,
	_ info: UnsafeMutableRawPointer?)
{
	if (activity.rawValue & CFRunLoopActivity.afterWaiting.rawValue) != 0 {
		let undoManager = Unmanaged<MyUndoManager>.fromOpaque(info!).takeUnretainedValue()
		undoManager.runLoopCounter += 1
	}
}

/// A supergroup is a collection of undo groups that share at least one OSM object,
/// merged together with the full set of objects those groups touch.
struct ConnectedObjects {
	/// All OSM objects referenced by any action in any of the constituent groups.
	let objects: Set<OsmBaseObject>
	/// The original group identifiers that were merged into this supergroup.
	let undoGroups: Set<Int>

	var minGroupId: Int { undoGroups.min()! }
}

extension ConnectedObjects: CustomStringConvertible {
	public var description: String {
		let groups = undoGroups.sorted().map(String.init).joined(separator: ", ")
		let objs = objects
			.sorted { $0.ident < $1.ident }
			.map { obj -> String in
				switch obj {
				case let n as OsmNode: return "node(\(n.ident))"
				case let w as OsmWay: return "way(\(w.ident))"
				case let r as OsmRelation: return "relation(\(r.ident))"
				default: return "object(\(obj.ident))"
				}
			}
			.joined(separator: ", ")
		return "groups [\(groups)] → [\(objs)]"
	}
}

extension MyUndoManager {
	func printConnectedObjects() {
		let groups = connectedObjects()
		print("ConnectedObjects (\(groups.count) component\(groups.count == 1 ? "" : "s")):")
		for (i, component) in groups.enumerated() {
			print("  \(i + 1). \(component)")
		}
	}

	/// Returns an array of ConnectedObjects derived from the undo stack.
	///
	/// Each undo group is first mapped to the set of OSM objects it touches (via action
	/// targets and arguments).  Any two groups that share an OSM object are then merged
	/// into a single supergroup.  Transitive merges are applied so that if A shares an
	/// object with B and B shares a different object with C, all three form one supergroup.
	///
	/// The result is sorted by each supergroup's minimum constituent group id.
	func connectedObjects() -> [ConnectedObjects] {
		// Step 1: collect the set of OSM objects touched by each group.
		var groupObjects: [Int: Set<OsmBaseObject>] = [:]
		for action in undoStack {
			groupObjects[action.group, default: []].formUnion(action.osmObjects)
		}

		guard !groupObjects.isEmpty else {
			// Undo stack is empty — fall back to isModified on each object.
			// This handles upgrades where an incompatible undo archive was discarded
			// but per-object modification flags (encoded separately) survived.
			guard let mapData = mapData else { return [] }
			// Use the same predicate as modificationCount(): for deleted objects, any
			// existing-server object (ident > 0) needs to be uploaded; for non-deleted
			// objects, check isModified.
			func needsUpload(_ obj: OsmBaseObject) -> Bool {
				obj.deleted ? obj.ident > 0 : obj.isModified
			}
			let modified: Set<OsmBaseObject> = Set(
				mapData.nodes.values.filter(needsUpload) +
					mapData.ways.values.filter(needsUpload) +
					mapData.relations.values.filter(needsUpload))
			guard !modified.isEmpty else { return [] }
			return [ConnectedObjects(objects: modified, undoGroups: [0])]
		}

		// Step 2: build reverse map — object → [groupId].
		var groupsForObject: [OsmBaseObject: [Int]] = [:]
		for (groupId, objects) in groupObjects {
			for obj in objects {
				groupsForObject[obj, default: []].append(groupId)
			}
		}

		// Step 3: union-find over group ids.
		var parent: [Int: Int] = Dictionary(uniqueKeysWithValues: groupObjects.keys.map { ($0, $0) })

		func find(_ id: Int) -> Int {
			var id = id
			while parent[id] != id {
				id = parent[id]!
			}
			return id
		}

		func union(_ a: Int, _ b: Int) {
			let ra = find(a)
			let rb = find(b)
			if ra != rb {
				parent[ra] = rb
			}
		}

		// Merge groups that share at least one OSM object.
		for groups in groupsForObject.values where groups.count > 1 {
			for i in 1..<groups.count {
				union(groups[0], groups[i])
			}
		}

		// Step 4: collect groups into components keyed by their root.
		var components: [Int: (groupIds: Set<Int>, objects: Set<OsmBaseObject>)] = [:]
		for (groupId, objects) in groupObjects {
			let root = find(groupId)
			components[root, default: ([], [])].groupIds.insert(groupId)
			components[root]!.objects.formUnion(objects)
		}

		// Step 5: separate components that have uploadable objects from no-ops
		// (e.g. objects created then deleted without ever reaching the server).
		func needsUpload(_ obj: OsmBaseObject) -> Bool {
			obj.deleted ? obj.ident > 0 : obj.isModified
		}
		var uploadable: [(groupIds: Set<Int>, objects: Set<OsmBaseObject>)] = []
		var noOpGroupIds: Set<Int> = []
		for component in components.values {
			if component.objects.contains(where: needsUpload) {
				uploadable.append(component)
			} else {
				noOpGroupIds.formUnion(component.groupIds)
			}
		}

		// Attach no-op group IDs to the most recently edited uploadable component
		// so they get cleaned up when that component is uploaded or discarded.
		if !noOpGroupIds.isEmpty, !uploadable.isEmpty {
			let mostRecentIndex = uploadable.indices.max {
				(uploadable[$0].groupIds.max() ?? 0) < (uploadable[$1].groupIds.max() ?? 0)
			}!
			uploadable[mostRecentIndex].groupIds.formUnion(noOpGroupIds)
		}

		// Step 6: convert to ConnectedObjects and sort by minimum group id.
		return uploadable
			.map { ConnectedObjects(objects: $0.objects, undoGroups: $0.groupIds) }
			.sorted { $0.minGroupId < $1.minGroupId }
	}
}
