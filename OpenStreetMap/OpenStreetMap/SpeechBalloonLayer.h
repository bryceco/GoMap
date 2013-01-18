//
//  SpeechBalloonLayer.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 11/11/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

@interface SpeechBalloonLayer : CAShapeLayer
{
	CATextLayer	*	_textLayer;
}
@property (copy,nonatomic)	NSString	*	text;
@end
