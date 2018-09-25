//
//  RulerLayer.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/11/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

@class MapView;


@interface RulerLayer : CALayer
{
	CAShapeLayer	*	_shapeLayer;
	CATextLayer		*	_metricTextLayer;
	CATextLayer		*	_britishTextLayer;
}
@property (assign,nonatomic) MapView	*	mapView;

-(void)updateDisplay;

@end
