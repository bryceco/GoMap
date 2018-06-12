//
//  Buildings3D.h
//  Go Map!!
//
//  Created by Bryce on 6/2/18.
//  Copyright © 2018 Bryce. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <SceneKit/SceneKit.h>

#import "VectorMath.h"

@class MapView;


@interface Buildings3DView : SCNView
{
	SCNNode			*	_centerNode;
	SCNNode			*	_cameraNode;
	NSMutableArray 	*	_buildingList;
}

@property (assign,nonatomic) MapView * mapView;

-(void)addShapeWithPath:(UIBezierPath *)path height:(double)height position:(OSMPoint)position;
-(void)setCameraDirection:(double)direction birdsEye:(double)birdsEye distance:(double)distance fromPoint:(OSMPoint)center;

@end
