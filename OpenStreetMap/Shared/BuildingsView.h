//
//  EditorLayerGL.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/15/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <SceneKit/SceneKit.h>

@class MapView;



@interface BuildingsView : SCNView
{
	MapView			*	_mapView;
}

-(id)initWithMapView:(MapView *)mapView;

@end
