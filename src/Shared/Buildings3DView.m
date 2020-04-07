//
//  Buildings3D.m
//  Go Map!!
//
//  Created by Bryce on 6/2/18.
//  Copyright © 2018 Bryce. All rights reserved.
//

#import "iosapi.h"
#import "Buildings3DView.h"
#import "MapView.h"
#import "PathUtil.h"
#import "VectorMath.h"


extern const double PATH_SCALING;


@interface BuildingProperties : NSObject
{
@public
	OSMPoint	position;
}
@end
@implementation BuildingProperties
-(instancetype)init
{
	self = [super init];
	if ( self ) {
	}
	return self;
}
@end

@implementation Buildings3DView

-(instancetype)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if ( self ) {
		self.scene = [SCNScene scene];

		self.autoenablesDefaultLighting = YES;
		self.backgroundColor = UIColor.clearColor;
#if TARGET_OS_IPHONE
		self.userInteractionEnabled = NO;
#endif

		self.layer.affineTransform = CGAffineTransformMakeScale(1,-1);	// flip y-axis

		SCNNode * root = self.scene.rootNode;

		_centerNode = [SCNNode node];

		// add camera
		SCNCamera * camera = [SCNCamera camera];
		_cameraNode = [SCNNode node];
		_cameraNode.camera = camera;
		_cameraNode.position = SCNVector3Make(30, 30, 30);
		[_centerNode addChildNode:_cameraNode];
		[root addChildNode:_centerNode];
	}
	return self;
}

-(void)setCameraDirection:(double)direction birdsEye:(double)birdsEye distance:(double)distance fromPoint:(OSMPoint)center
{
	[CATransaction begin];
	[CATransaction setDisableActions:YES];

	const double	tScale			= OSMTransformScaleX( self.mapView.screenFromMapTransform );
	const double	pScale			= tScale / PATH_SCALING;

	NSLog(@"scale = %f",pScale);

	_centerNode.position = SCNVector3Make(center.x, center.y, 0);

	distance = 75;
	double dx = sin(birdsEye) * cos(M_PI_2-direction) * distance;
	double dy = sin(birdsEye) * sin(M_PI_2-direction) * distance;
	double dz = cos(birdsEye) * distance;
	_cameraNode.position	= SCNVector3Make(dx,dy,dz);	// camera location relative to _centerNode
	_cameraNode.eulerAngles = SCNVector3Make(-birdsEye, 0, -direction);	// direction to face

	if ( pScale > 1.0 ) {
		self.layer.affineTransform = CGAffineTransformMakeScale(pScale/10,-pScale/10);	// flip y-axis
	}

	for ( SCNNode * node in self.scene.rootNode.childNodes ) {
		BuildingProperties * props = [node valueForKey:@"props"];
		if ( props == nil )
			continue;
		OSMPoint delta = Sub( props->position, center );
		delta = Mult( delta, PATH_SCALING );
		OSMPoint newPos = Add( center, delta );
		node.position = SCNVector3Make(newPos.x, newPos.y, node.position.z);
	}

	[CATransaction commit];
}

-(void)addShapeWithPath:(UIBezierPath *)path height:(double)height position:(OSMPoint)position
{
	// extrude shape from path
	NSMutableArray * colors = [NSMutableArray arrayWithObject:UIColor.greenColor];
	SCNShape * building = [SCNShape shapeWithPath:path extrusionDepth:height];
	for ( NSInteger i = 0; i < colors.count; ++i ) {
		SCNMaterial * material = [SCNMaterial new];
		material.diffuse.contents = colors[i];
		material.locksAmbientWithDiffuse = YES;
		colors[i] = material;
	}
	building.materials = colors;
	//building.firstMaterial.diffuse.contents = [UIImage imageNamed:@"OSM-Logo256"];

	SCNNode * node = [SCNNode nodeWithGeometry:building];
	node.position = SCNVector3Make(position.x, position.y, height/2);

	BuildingProperties * props = [BuildingProperties new];
	props->position = position;
	[node setValue:props forKey:@"props"];

	SCNNode * root = self.scene.rootNode;
	[root addChildNode:node];
}

@end
