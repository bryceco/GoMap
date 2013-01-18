//
//  DLog.h
//  OpenStreetMap
//
//  Created by Bryce on 1/17/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#ifndef OpenStreetMap_DLog_h
#define OpenStreetMap_DLog_h

#if defined(DEBUG)
#define DLog(...) NSLog( __VA_ARGS__ )
#else
#define DLog(...)
#endif

#endif
