//
//  Debugger.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/28/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation

func isUnderDebugger() -> Bool {
#if DEBUG
	// Ask Mach kernel about the PTRACE flag
	var info = kinfo_proc()
	var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
	var size = MemoryLayout.stride(ofValue: info)
	let errno = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
	return errno == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
#else
	return false
#endif
}

func DLog(_ args: String...) {
#if DEBUG
	print(args)
#endif
}

func DbgAssert(_ x: Bool) {
#if DEBUG
	isUnderDebugger() {
		assert(x, "unspecified")
	}
#endif
}

func mach_task_self() -> task_t {
	return mach_task_self_
}

func MemoryUsed() -> Double? {
	var info = mach_task_basic_info()
	var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
	let kerr = withUnsafeMutablePointer(to: &info) { infoPtr in
		infoPtr.withMemoryRebound(to: integer_t.self,
		                          capacity: Int(count),
		                          { (machPtr: UnsafeMutablePointer<integer_t>) in
		                          	task_info(
		                          		mach_task_self(),
		                          		task_flavor_t(MACH_TASK_BASIC_INFO),
		                          		machPtr,
		                          		&count)
		                          })
	}
	guard kerr == KERN_SUCCESS else {
		return nil
	}
	return Double(info.resident_size)
}

func TotalDeviceMemory() -> Double? {
	var mib: [Int32] = [CTL_HW, HW_MEMSIZE]
	var memorySize: UInt = 0
	var size = MemoryLayout.stride(ofValue: memorySize)
	let errno = sysctl(&mib, UInt32(mib.count), &memorySize, &size, nil, 0)
	guard errno == 0 else { return nil }
	return Double(memorySize)
}
