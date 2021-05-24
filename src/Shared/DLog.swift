//
//  DLog.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 1/17/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import Foundation

//#define OpenStreetMap_DLog_h

//#define DLog(...) NSLog( __VA_ARGS__ )
func DbgAssert(_ x: Any) {
    assert(x, "unspecified")
}

func MemoryUsedMB() -> Double {
    var info: task_basic_info
    var size = MemoryLayout.size(ofValue: info)
    let kerr = task_info(mach_task_self(), TASK_BASIC_INFO, &info as? task_info_t, &size)
    return (kerr == KERN_SUCCESS) ? info.resident_size * 1e-6 : 0 // size in bytes
}

//#define DLog(...) (void)0
