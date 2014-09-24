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
#import <Foundation/Foundation.h>
#import "mach/mach.h"

#define DLog(...)		NSLog( __VA_ARGS__ )
#define DbgAssert(x)	NSAssert((x),@"unspecified")

static double MemoryUsedMB(void)
{
	struct task_basic_info info;
	mach_msg_type_number_t size = sizeof(info);
	kern_return_t kerr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &size);
	return (kerr == KERN_SUCCESS) ? info.resident_size*1e-6 : 0; // size in bytes
}

#else

#define DLog(...)		(void)0
#define DbgAssert(x)	(void)0

#endif
#endif
