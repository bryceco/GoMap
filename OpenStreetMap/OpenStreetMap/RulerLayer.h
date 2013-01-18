//
//  RulerLayer.h
//  OpenStreetMap
//
//  Created by Bryce on 10/11/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
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
