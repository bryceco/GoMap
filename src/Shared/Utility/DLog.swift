//
//  DLog.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 1/17/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import Foundation

// #define OpenStreetMap_DLog_h

// #define DLog(...) NSLog( __VA_ARGS__ )
func DbgAssert(_ x: Bool) {
#if DEBUG
	assert(x, "unspecified")
#endif
}

func mach_task_self() -> task_t {
	return mach_task_self_
}

func MemoryUsed() -> Double {
	var info = mach_task_basic_info()
	var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
	let kerr = withUnsafeMutablePointer(to: &info) { infoPtr in
		infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { (machPtr: UnsafeMutablePointer<integer_t>) in
			task_info(
				mach_task_self(),
				task_flavor_t(MACH_TASK_BASIC_INFO),
				machPtr,
				&count)
		}
	}
	guard kerr == KERN_SUCCESS else {
		return 0.0
	}
	return Double(info.resident_size)
}
