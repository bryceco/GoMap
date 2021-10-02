//
//  UndoManager.swift
//  Go Map!
//
//  Created by Bryce Cogswell on 8/16/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import Foundation

typealias UndoManagerChangeCallback = () -> Void

class MyUndoManager: NSObject, NSCoding {
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
				if let target = action.target as? OsmBaseObject {
					refs.insert(target)
				}
				for obj in action.objects {
					if let osm = obj as? OsmBaseObject {
						// argmuments that are an object
						refs.insert(osm)
					} else if let dict = obj as? [String: Any] {
						// also comments can point to objects for selectedNode, etc.
						refs.formUnion(dict.values.compactMap({ $0 as? OsmBaseObject }))
					}
				}
				refs.formUnion(action.objects.compactMap({ $0 as? OsmBaseObject }))
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
			var len: Int = 0
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
