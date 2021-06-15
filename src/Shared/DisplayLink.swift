//
//  DisplayLink.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/9/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

class DisplayLink {
    
#if os(iOS)
	var _displayLink: CADisplayLink!
#else
    let _displayLink: CVDisplayLink
#endif
	var blockDict = [String : (()->Void)]()
    
    private static let g_shared = DisplayLink()
    
    class func shared() -> DisplayLink {
        // `dispatch_once()` call was converted to a static variable initializer
        return g_shared
    }
    
    init() {
		_displayLink = CADisplayLink(target: self, selector: #selector(step))
#if os(iOS)
        _displayLink.isPaused = true
        _displayLink.add(to: RunLoop.main, forMode: .default)
#else
        let displayID = CGMainDisplayID()
        CVDisplayLinkCreateWithCGDisplay(displayID, &displayLink)
        CVDisplayLinkSetOutputCallback(displayLink, displayLinkCallback, &self)
#endif
    }

	@objc func step() {
		for (_,block) in blockDict {
			block()
		}
	}

#if os(iOS)
#else
    func displayLinkOutputCallback(displayLink: CVDisplayLink, _ inNow: UnsafePointer<CVTimeStamp>, _ inOutputTime: UnsafePointer<CVTimeStamp>, _ flagsIn: CVOptionFlags, _ flagsOut: UnsafeMutablePointer<CVOptionFlags>, _ displayLinkContext: UnsafeMutablePointer<Void>) -> CVReturn {
        let myself = displayLinkContext as? DisplayLink
        myself?.update(nil)
    }
#endif
    
    func duration() -> Double {
#if os(iOS)
        return _displayLink.duration
#else
        return CVDisplayLinkGetActualOutputVideoRefreshPeriod(displayLink)
#endif
    }
    
    func timestamp() -> CFTimeInterval {
#if os(iOS)
        return _displayLink.timestamp
#else
        return CACurrentMediaTime()
#endif
    }
    
    func addName(_ name: String, block: @escaping () -> Void) {
        blockDict[name] = block
#if os(iOS)
        _displayLink.isPaused = false
#else
        CVDisplayLinkStart(displayLink)
#endif
    }
    
    func hasName(_ name: String) -> Bool {
		return blockDict[name] != nil
    }
    
    func removeName(_ name: String) {
		blockDict.removeValue(forKey: name)
        
        if blockDict.count == 0 {
#if os(iOS)
            _displayLink.isPaused = true
#else
            CVDisplayLinkStop(displayLink)
#endif
        }
    }
    
    deinit {
#if os(iOS)
        _displayLink.remove(from: RunLoop.main, forMode: .default)
#else
        CVDisplayLinkRelease(displayLink)
#endif
    }
}
