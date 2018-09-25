//
//  iosapi.h
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#ifndef OSMiOS_iosapi_h
#define OSMiOS_iosapi_h

typedef int64_t OsmIdentifier;

#if TARGET_OS_IPHONE

#define NSColor				UIColor
#define NSEvent				UIEvent
#define NSFont				UIFont
#define NSGraphicsContext	UIGraphicsContext
#define NSImage				UIImage
#define NSProgressIndicator UIActivityIndicatorView
#define NSView				UIView
#define pointValue			CGPointValue
#define valueWithPoint		valueWithCGPoint

#else

#define UIImage				NSImage
#define UIColor				NSColor
#define UIFont				NSFont
#define UIView				NSView
#define UIBezierPath		NSBezierPath
#define UIApplication		NSApplication

#endif

#endif
