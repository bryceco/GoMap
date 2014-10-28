//
//  BuildingsLayer.h
//  Go Map!!
//
//  Created by Bryce on 10/27/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

@class MapView;


@interface BuildingsLayer : CATransformLayer
{
    MapView	*	_mapView;
}

-(id)initWithMapView:(MapView *)mapView;

@end
