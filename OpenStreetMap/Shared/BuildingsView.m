//
//  Buildings3DLayer.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/15/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <SceneKit/SceneKit.h>

#import "DLog.h"
#import "BuildingsView.h"
#import "MapView.h"


@implementation BuildingsView

-(id)initWithMapView:(MapView *)mapView;
{
	self = [super init];
	if ( self ) {

		// observe changes to geometry
		_mapView = mapView;
		[_mapView addObserver:self forKeyPath:@"screenFromMapTransform" options:0 context:NULL];

		self.opaque = NO;

		self.userInteractionEnabled = NO;

		[self createObjects];
	}
	return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( object == _mapView && [keyPath isEqualToString:@"screenFromMapTransform"] )  {
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}


- (void)createObjects
{
	// create a new scene
	SCNScene *scene = [[SCNScene alloc] init];

	// create and add a camera to the scene
	SCNNode *cameraNode = [SCNNode node];
	cameraNode.camera = [SCNCamera camera];
	[scene.rootNode addChildNode:cameraNode];

	// place the camera
	cameraNode.position = SCNVector3Make(0, 10, 30);

	// create and add a light to the scene
	SCNNode *lightNode = [SCNNode node];
	lightNode.light = [SCNLight light];
	lightNode.light.type = SCNLightTypeOmni;
	lightNode.position = SCNVector3Make(0, 30, 30);
	[scene.rootNode addChildNode:lightNode];

	// create and add an ambient light to the scene
	SCNNode *ambientLightNode = [SCNNode node];
	ambientLightNode.light = [SCNLight light];
	ambientLightNode.light.type = SCNLightTypeAmbient;
	ambientLightNode.light.color = [NSColor darkGrayColor];
	[scene.rootNode addChildNode:ambientLightNode];

#if 0
	{
		SCNNode * floor = [SCNNode nodeWithGeometry:[SCNFloor floor]];
		//	floor.position = SCNVector3Make(0,0,0);
		//	floor.rotation = SCNVector4Make(1, 0, 0, -M_PI/2);
		SCNMaterial * material = [SCNMaterial material];
		material.diffuse.contents = [NSImage imageNamed:@"skeleton"];
		floor.geometry.materials = @[ material ];
		[scene.rootNode addChildNode:floor];
	}
#endif

#if 0
	{
		SCNNode * sphere = [SCNNode nodeWithGeometry:[SCNSphere sphereWithRadius:2.0]];
		sphere.position = SCNVector3Make(5,2,0);
		SCNMaterial * material = [SCNMaterial material];
		sphere.geometry.materials = @[ material ];
		[scene.rootNode addChildNode:sphere];
	}
#endif

	{
		SCNNode * box1 = [SCNNode nodeWithGeometry:[SCNBox boxWithWidth:4.0 height:9.0 length:1.0 chamferRadius:0]];
		box1.position = SCNVector3Make(0, 4.5, 0);
		for ( SCNMaterial * side in box1.geometry.materials ) {
			side.transparency = 0.7;
		}
		[scene.rootNode addChildNode:box1];
	}

	// set the scene to the view
	self.scene = scene;

	// allows the user to manipulate the camera
	self.allowsCameraControl = YES;

	// show statistics such as fps and timing information
	self.showsStatistics = YES;

	// configure the view
	self.backgroundColor = [NSColor clearColor];
}



@end
