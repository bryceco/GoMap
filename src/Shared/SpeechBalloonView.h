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
}

- (id)initWithText:(NSString *)text;
- (void) setPoint:(CGPoint)point;
- (void) setTargetView:(UIView *)view;
@end
