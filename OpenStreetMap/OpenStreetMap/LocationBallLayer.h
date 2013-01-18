//
//  LocationBallLayer.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 12/27/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

@interface LocationBallLayer : CALayer
{
	CAShapeLayer	*	_headingLayer;
}
@property (assign,nonatomic)	BOOL		showHeading;
@property (assign,nonatomic)	CGFloat		heading;	// radians
@property (assign,nonatomic)	CGFloat		headingAccuracy;
@end
