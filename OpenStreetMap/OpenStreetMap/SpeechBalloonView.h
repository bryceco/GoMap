//
//  SpeechBalloonView.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 12/11/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#if TARGET_OS_IPHONE
#import "iosapi.h"
#import <Foundation/Foundation.h>
#else
#import <Cocoa/Cocoa.h>
#endif

@interface SpeechBalloonView : NSView
{
	CGMutablePathRef	_path;
	void			(^_balloonPress)(void);
	void			(^_disclosurePress)(void);
}

- (id)initWithText:(NSString *)text balloonPress:(void(^)(void))balloonPress disclosurePress:(void(^)(void))disclosurePress;
- (void) setPoint:(CGPoint)point;
@end
