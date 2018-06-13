//
//  Buildings3D.m
//  Go Map!!
//
//  Created by Bryce on 6/2/18.
//  Copyright © 2018 Bryce. All rights reserved.
//

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
		self.userInteractionEnabled = NO;
		self.backgroundColor = UIColor.clearColor;

		self.layer.affineTransform = CGAffineTransformMakeScale(1,-1);	// flip y-axis

		SCNNode * root = self.scene.rootNode;

#if 0
		CGFloat boxSize = 5.0;
		SCNGeometry * box = [SCNBox boxWithWidth:boxSize height:boxSize length:boxSize chamferRadius:0.0];
		box.firstMaterial = [SCNMaterial new];
		box.firstMaterial.diffuse.contents          = [UIColor redColor];
		box.firstMaterial.locksAmbientWithDiffuse   = YES;
		_centerNode = [SCNNode nodeWithGeometry:box];
#else
		_centerNode = [SCNNode node];
#endif

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

#if 0
-(void)updateMaterialsForGeometry:(SCNGeometry *)geometry
{
	if ( geometry.geometryElementCount != geometry.materials.count ) {
		NSMutableArray * colors = [NSMutableArray arrayWithCapacity:geometry.geometryElementCount];
		SCNGeometrySource * vertexData = nil;
		for ( SCNGeometrySource * source in geometry.geometrySources ) {
			if ( source.semantic == SCNGeometrySourceSemanticVertex ) {
				vertexData = source;
				break;
			}
		}
		if ( vertexData == nil ) {
			return;
		}
		for ( SCNGeometryElement * element in geometry.geometryElements ) {

		}
	}
}
#endif

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


-(SCNGeometry *)buildingGeometryForPath:(UIBezierPath *)path height:(double)height colors:(NSMutableArray *)colors
{
	double hue = random() % 20 - 10;
	[colors removeAllObjects];
	[colors addObject:[UIColor colorWithHue:0 saturation:0.05 brightness:0.75+hue/100 alpha:1.0]];
	[colors addObject:colors.lastObject];	// duplicate roof and floor

	// get list of points in path
	int32_t pointCount = (int32_t) CGPathPointCount( path.CGPath );
	CGPoint points[ pointCount ];
	CGPathGetPoints( path.CGPath, points );
	--pointCount;	// don't need to repeat the start/end point

	SCNVector3 vertices[ 2*pointCount ];
	for ( NSInteger i = 0; i < pointCount; ++i ) {
		vertices[i] 			= SCNVector3Make(points[i].x, points[i].y, 0.0);
		vertices[pointCount+i]	= SCNVector3Make(points[i].x, points[i].y, height);

		// get color for wall segment
		CGPoint next = points[(i+1)%pointCount];
		double angle = atan2(next.y-points[i].y, next.x-points[i].x);
		double intensity = angle/M_PI;
		if ( intensity < 0 )
			++intensity;
		UIColor	* color = [UIColor colorWithHue:(37+hue)/360.0 saturation:0.61 brightness:0.5+intensity/2 alpha:1.0];
		[colors addObject:color];
	}
	SCNGeometrySource * geoSource = [SCNGeometrySource geometrySourceWithVertices:vertices count:pointCount*2];
	NSMutableArray * elements = [NSMutableArray new];

	// roof and floor
	int32_t floor[ pointCount+1 ];
	int32_t roof[ pointCount+1 ];
	floor[0] = pointCount;
	roof[0] = pointCount;
	for ( int32_t i = 0; i < pointCount; ++i ) {
		floor[1+i] = i;
		roof[1+i] = pointCount+i;
	}
	NSData * floorData = [NSData dataWithBytes:floor length:sizeof floor];
	NSData * roofData = [NSData dataWithBytes:roof length:sizeof roof];
	SCNGeometryElement * geoFloor = [SCNGeometryElement geometryElementWithData:floorData primitiveType:SCNGeometryPrimitiveTypePolygon primitiveCount:1 bytesPerIndex:sizeof floor[0]];
	SCNGeometryElement * geoRoof  = [SCNGeometryElement geometryElementWithData:roofData  primitiveType:SCNGeometryPrimitiveTypePolygon primitiveCount:1 bytesPerIndex:sizeof roof[0]];
	[elements addObject:geoFloor];
	[elements addObject:geoRoof];

	for ( int32_t w = 0; w < pointCount; ++w ) {
		int32_t wall[ 5 ] = {
			4,	// number of points
			w,
			(w+1)%pointCount,
			(w+1)%pointCount+pointCount,
			w+pointCount
		};
		NSData * data = [NSData dataWithBytes:wall length:sizeof wall];
		SCNGeometryElement * element = [SCNGeometryElement geometryElementWithData:data primitiveType:SCNGeometryPrimitiveTypePolygon primitiveCount:1 bytesPerIndex:sizeof wall[0]];
		[elements addObject:element];
	}

	SCNGeometry * geom = [SCNGeometry geometryWithSources:@[geoSource] elements:elements];
	return geom;
}


-(void)addShapeWithPath:(UIBezierPath *)path height:(double)height position:(OSMPoint)position
{
#if 0
	// build walls ourself
	NSMutableArray * colors = [NSMutableArray new];
	SCNGeometry * building = [self buildingGeometryForPath:path height:height colors:colors];
#else
	// extrude shape from path
	NSMutableArray * colors = [NSMutableArray arrayWithObject:UIColor.greenColor];
	SCNShape * building = [SCNShape shapeWithPath:path extrusionDepth:height];
#endif
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
