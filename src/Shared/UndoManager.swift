//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  UndoManager.swift
//  Go Map!
//
//  Created by Bryce Cogswell on 8/16/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import Foundation

private var UndoManagerDidChangeNotification = "UndoManagerDidChangeNotification"
typealias UndoManagerChangeCallback = () -> Void

class UndoManager: NSObject, NSCoding {
    var runLoopObserver: CFRunLoopObserver?
    var undoStack: [UndoAction] = []
    var redoStack: [UndoAction] = []
    
    
    var groupingStack: [AnyHashable]? // for explicit grouping
    var commentList: NSMutableArray?
    
    private(set) var isUndoing = false
    private(set) var isRedoing = false
    
    var canUndo: Bool {
        return (undoStack?.count ?? 0) > 0
    }
    
    var canRedo: Bool {
        return (redoStack?.count ?? 0) > 0
    }
    
    var countUndoGroups: Int {
        var count = 0
        var group = -1
        for action in undoStack ?? [] {
            guard let action = action as? UndoAction else {
                continue
            }
            if action.group != group {
                count += 1
                group = action.group
            }
        }
        return count
    }
    var runLoopCounter = 0
    
    override init() {
        super.init()
        undoStack = []
        redoStack = []
        
        groupingStack = []
        
        var context = CFRunLoopObserverContext()
        context.info = self
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
        text += "   group = \(((groupingStack?.count ?? 0) != 0 ? (groupingStack?.last as? String) : "none") ?? "")\n"
        for action in undoStack ?? [] {
            guard let action = action as? UndoAction else {
                continue
            }
            text += String(format: "   %ld: %@\n", action.group, action.selector ?? "")
        }
        return text
    }
    
    func count() -> Int {
        return (undoStack?.count ?? 0) + (redoStack?.count ?? 0)
    }
    
    func postChangeNotification() {
        let notification = Notification(name: NSNotification.Name(UndoManagerDidChangeNotification), object: self)
        NotificationQueue.default.enqueue(notification, postingStyle: .whenIdle, coalesceMask: [.onName, .onSender], forModes: nil)
    }
    
    func removeMostRecentRedo() {
        assert((redoStack?.count ?? 0))
        
        let group = (redoStack?.last as? UndoAction)?.group ?? 0
        while (redoStack?.count ?? 0) != 0 && (redoStack?.last as? UndoAction)?.group == group {
            redoStack?.removeLast()
        }
        
        postChangeNotification()
    }
    
    func removeAllActions() {
        willChangeValue(forKey: "canUndo")
        willChangeValue(forKey: "canRedo")
        
        assert(!isUndoing && !isRedoing)
        undoStack?.removeAll()
        redoStack?.removeAll()
        
        didChangeValue(forKey: "canUndo")
        didChangeValue(forKey: "canRedo")
        
        postChangeNotification()
    }
    
    func registerUndo(_ action: UndoAction?) {
        action?.group = (groupingStack?.count ?? 0) != 0 ? (groupingStack?.last as? NSNumber)?.intValue ?? 0 : runLoopCounter
        
        willChangeValue(forKey: "canUndo")
        willChangeValue(forKey: "canRedo")
        
        if isUndoing {
            if let action = action {
                redoStack?.append(action)
            }
        } else if isRedoing {
            if let action = action {
                undoStack.append(action)
            }
        } else {
            if let action = action {
                undoStack.append(action)
            }
            redoStack?.removeAll()
        }
        
        didChangeValue(forKey: "canUndo")
        didChangeValue(forKey: "canRedo")
        
        postChangeNotification()
    }
    
    func registerUndo(withTarget target: AnyObject?, selector: Selector, objects: NSArray) {
        assert(target != nil)
        DbgAssert(target?.responds(to: selector) ?? false)
        
        let action = UndoAction(target: target, selector: selector, objects: objects)
        registerUndo(action)
    }
    
    @objc func doComment(_ comment: NSDictionary) {
        registerUndo(withTarget: self, selector: #selector(doComment(_:)), objects: [comment])
        commentList?.add(comment)
    }
    
    func registerUndoComment(_ comment: NSDictionary) {
        registerUndo(withTarget: self, selector: #selector(doComment(_:)), objects: [comment])
    }
    
    class func doActionGroup(fromStack stack: inout [UndoAction]) {
        var currentGroup = -1

        while stack.count != 0 {
            let action = stack.last
            assert(action?.group != nil)
            if currentGroup < 0 {
                currentGroup = action?.group ?? 0
            } else if action?.group != currentGroup {
                break
            }
            
            stack.removeLast()
            
            //		DLog(@"-- Undo action: '%@' %@", action.selector, [action.target description] );
            action?.perform()
        }
    }
    
    // returns the oldest comment registered within the undo group
    func undo() -> NSDictionary? {
        commentList = NSMutableArray()

        willChangeValue(forKey: "canUndo")
        willChangeValue(forKey: "canRedo")
        
        assert(!isUndoing && !isRedoing)
        isUndoing = true
        UndoManager.doActionGroup(fromStack: &undoStack)
        isUndoing = false
        
        didChangeValue(forKey: "canUndo")
        didChangeValue(forKey: "canRedo")
        
        postChangeNotification()
        
        let comment = ((commentList?.count ?? 0) == 0 ? nil : commentList?.lastObject) as? NSDictionary
        return comment
    }
    
    func redo() -> NSDictionary? {
        commentList = NSMutableArray()
        
        willChangeValue(forKey: "canUndo")
        willChangeValue(forKey: "canRedo")
        
        assert(!isUndoing && !isRedoing)
        isRedoing = true
        UndoManager.doActionGroup(fromStack: &redoStack)
        isRedoing = false
        
        didChangeValue(forKey: "canUndo")
        didChangeValue(forKey: "canRedo")
        
        postChangeNotification()
        
        let comment = ((commentList?.count ?? 0) == 0 ? nil : commentList?.lastObject) as? NSDictionary
        return comment
    }
    
    func beginUndoGrouping() {
        let group: NSNumber? = ((groupingStack?.count ?? 0) != 0 ? groupingStack?.last : NSNumber(value: runLoopCounter)) as? NSNumber
        if let group = group {
            groupingStack?.append(group)
        }
    }
    
    func endUndoGrouping() {
        groupingStack?.removeLast()
    }
    
    func objectRefs() -> NSSet? {
        var refs = NSMutableSet()
        for action in undoStack {
            refs.add(action.target)
            action.objects
//            refs.addObjects(from: )
        }
        for action in redoStack {
            refs.add(action.target)
            refs.addObjects(from: action.objects)
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
    
    required convenience init?(coder: NSCoder) {
        self.init()
        if coder.allowsKeyedCoding {
            undoStack = coder.decodeObject(forKey: "undoStack") as? [UndoAction] ?? []
            redoStack = coder.decodeObject(forKey: "redoStack") as? [UndoAction] ?? []
            runLoopCounter = coder.decodeInteger(forKey: "runLoopCounter")
        } else {
            var len: Int
            undoStack = coder.decodeObject() as? [UndoAction] ?? []
            redoStack = coder.decodeObject() as? [UndoAction] ?? []
            runLoopCounter = coder.decodeBytes(withReturnedLength: &len)
            runLoopCounter = Int(coder.decodeBytes(withReturnedLength: UnsafeMutablePointer(&len)) ?? 0)
        }
    }
}

private func RunLoopObserverCallBack(_ observer: CFRunLoopObserver?, _ activity: CFRunLoopActivity, _ info: UnsafeMutableRawPointer?) {
    if activity.rawValue & CFRunLoopActivity.afterWaiting.rawValue != 0 {
        let undoManager = info as? UndoManager
        undoManager?.runLoopCounter = (undoManager?.runLoopCounter ?? 0) + 1
    }
}

// MARK: UndoAction
class UndoAction: NSObject, NSCoding {
    private(set) var selector: String?
    private(set) var target: Any?
    private(set) var objects: NSArray?
    var group = 0
    
    init(target: Any?, selector: Selector, objects: NSArray?) {
        DbgAssert(target != nil && selector != nil)
        super.init()
        self.target = target
        self.selector = NSStringFromSelector(selector)
        self.objects = objects
    }
    
    func encode(with coder: NSCoder) {
        DbgAssert(target != nil)
        coder.encode(target, forKey: "target")
        coder.encode(selector, forKey: "selector")
        coder.encode(objects, forKey: "objects")
        coder.encode(group, forKey: "group")
    }
    
    required init?(coder: NSCoder) {
        super.init()
        target = coder.decodeObject(forKey: "target")
        selector = coder.decodeObject(forKey: "selector") as? String
        objects = coder.decodeObject(forKey: "objects")
        group = coder.decodeInteger(forKey: "group")
        DbgAssert(target != nil)
    }
    
    override var description: String {
        if let target = target {
            return String(format: "%@ %@ %@ (%@) %ld", super.description, target, selector ?? "", objects ?? [], group)
        }
        return ""
    }
    
    func perform() {
        if self.selector != nil {
            // method call
            let selector = NSSelectorFromString(self.selector ?? "")
            assert(target != nil)
            assert(objects != nil)
            let sig = target?.methodSignature(for: selector)
            assert(sig)
            assert((objects?.count ?? 0) + 2 == sig?.numberOfArguments())
            let invocation = NSInvocation(methodSignature: sig)
            invocation.selector = selector
            invocation.target = target
            for index in 0..<(objects?.count ?? 0) {
                var obj = objects?[index]
                
                let type = sig?.getArgumentType(at: 2 + index) ?? 0
                switch type {
                case "c":
                    var c = (obj as? NSNumber)?.int8Value ?? 0
                    invocation.setArgument(&c, at: 2 + index)
                case "d":
                    var d = (obj as? NSNumber)?.doubleValue ?? 0.0
                    invocation.setArgument(&d, at: 2 + index)
                case "i":
                    var i = obj?.intValue ?? 0
                    invocation.setArgument(&i, at: 2 + index)
                case "q":
                    var l = (obj as? NSNumber)?.int64Value ?? 0
                    invocation.setArgument(&l, at: 2 + index)
                case "B":
                    var b = (obj as? NSNumber)?.boolValue ?? false
                    invocation.setArgument(&b, at: 2 + index)
                case "@":
                    if obj == nil {
                        obj = nil
                    }
                    invocation.setArgument(&obj, at: 2 + index)
                default:
                    assert(false)
                }
            }
            invocation.invoke()
            return
        }
        
        // unknown action type
        assert(false)
    }
}

// MARK: UndoManager

func DbgAssert(_ x: Bool) {
    assert(x, "unspecified")
}
