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
	private var commentList: [[String: Any]] = []

	private(set) var isUndoing = false
	private(set) var isRedoing = false

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
			text += String(format: "   %ld: %@\n", action.group, action.selector)
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

	func registerUndo(_ action: UndoAction) {
		action.group = groupingStack.last ?? runLoopCounter

		willChangeValue(forKey: "canUndo")
		willChangeValue(forKey: "canRedo")

		if isUndoing {
			redoStack.append(action)
		} else if isRedoing {
			undoStack.append(action)
		} else {
			undoStack.append(action)
			redoStack.removeAll()
		}

		didChangeValue(forKey: "canUndo")
		didChangeValue(forKey: "canRedo")

		postChangeNotification()
	}

	func registerUndo(withTarget target: AnyObject, selector: Selector, objects: [Any]) {
		DbgAssert(target.responds(to: selector))

		let action = UndoAction(target: target, selector: selector, objects: objects)
		registerUndo(action)
	}

	@objc func doComment(_ comment: [String: Any]) {
		registerUndo(withTarget: self, selector: #selector(doComment(_:)), objects: [comment])
		commentList.append(comment)
	}

	func registerUndoComment(_ comment: [String: Any]) {
		registerUndo(withTarget: self, selector: #selector(doComment(_:)), objects: [comment])
	}

	class func doActionGroup(fromStack stack: inout [UndoAction]) {
		guard let currentGroup = stack.last?.group else { return }

		while stack.last?.group == currentGroup,
		      let action = stack.popLast()
		{
			// print("-- Undo action: '\(action.selector)' \(type(of: action.target))")
			action.perform()
		}
	}

	// returns the oldest comment registered within the undo group
	func undo() -> [String: Any]? {
		commentList = []

		willChangeValue(forKey: "canUndo")
		willChangeValue(forKey: "canRedo")

		assert(!isUndoing && !isRedoing)
		isUndoing = true
		Self.doActionGroup(fromStack: &undoStack)
		isUndoing = false

		didChangeValue(forKey: "canUndo")
		didChangeValue(forKey: "canRedo")

		postChangeNotification()

		return commentList.last
	}

	func redo() -> [String: Any]? {
		commentList = []

		willChangeValue(forKey: "canUndo")
		willChangeValue(forKey: "canRedo")

		assert(!isUndoing && !isRedoing)
		isRedoing = true
		Self.doActionGroup(fromStack: &redoStack)
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
				refs.formUnion(action.osmObjects())
			}
		}
		return refs
	}

	func encode(with coder: NSCoder) {
		if coder.allowsKeyedCoding {
			coder.encode(undoStack, forKey: "undoStack")
			coder.encode(redoStack, forKey: "redoStack")
			coder.encode(runLoopCounter, forKey: "runLoopCounter")
		} else {
			coder.encode(undoStack)
			coder.encode(redoStack)
			coder.encodeBytes(&runLoopCounter, length: MemoryLayout.size(ofValue: runLoopCounter))
		}
	}

	required init?(coder: NSCoder) {
		super.init()
		if coder.allowsKeyedCoding {
			undoStack = coder.decodeObject(forKey: "undoStack") as? [UndoAction] ?? []
			redoStack = coder.decodeObject(forKey: "redoStack") as? [UndoAction] ?? []
			runLoopCounter = coder.decodeInteger(forKey: "runLoopCounter")
		} else {
			undoStack = coder.decodeObject() as? [UndoAction] ?? []
			redoStack = coder.decodeObject() as? [UndoAction] ?? []
			var len = 0
			withUnsafeMutablePointer(to: &len, {
				if let ptr = coder.decodeBytes(withReturnedLength: $0) {
					runLoopCounter = ptr.load(as: type(of: runLoopCounter))
				} else {
					runLoopCounter = 0
				}
			})
		}
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
			groupObjects[action.group, default: []].formUnion(action.osmObjects())
		}

		guard !groupObjects.isEmpty else { return [] }

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

		// Step 5: convert to UndoSuperGroup and sort by minimum group id.
		return components.values
			.map { ConnectedObjects(objects: $0.objects, undoGroups: $0.groupIds) }
			.sorted { $0.minGroupId < $1.minGroupId }
	}
}
