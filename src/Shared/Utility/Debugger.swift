//
//  Debugger.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/28/21.
//  Copyright © 2021 Bryce. All rights reserved.
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
