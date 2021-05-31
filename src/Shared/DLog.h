//
//  DLog.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 1/17/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#ifndef OpenStreetMap_DLog_h
#define OpenStreetMap_DLog_h

#if defined(DEBUG)

#define DLog(...)		NSLog( __VA_ARGS__ )
#define DbgAssert(x)	NSCAssert((x),@"unspecified")

#else

#define DLog(...)		(void)0
#define DbgAssert(x)	(void)0

#endif

#import <Foundation/Foundation.h>
#import "mach/mach.h"
inline static double MemoryUsed(void)
{
	struct task_basic_info info;
	mach_msg_type_number_t size = sizeof(info);
	kern_return_t kerr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &size);
	return (kerr == KERN_SUCCESS) ? info.resident_size : 0; // size in bytes
}

#endif
