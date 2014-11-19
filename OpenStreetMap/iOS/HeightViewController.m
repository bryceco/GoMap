//
//  HeightViewController.m
//  Go Map!!
//
//  Created by Bryce on 11/19/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <sys/utsname.h>

#import "AppDelegate.h"
#import "EditorMapLayer.h"
#import "HeightViewController.h"
#import "MapView.h"
#import "OsmObjects.h"
#import "VectorMath.h"


@interface HeightViewController ()
@end


@implementation HeightViewController

- (void)viewDidLoad
{
	[self startCameraPreview];
	[self addRulerLabels];
}


-(double)cameraDegrees
{
	static double cameraAngle = 0;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{

		// field of view = f( resolution, focal length, chip size )
		// angle = 2*atan2(vertical_sensor_size/2,focal length) * 180 / 3.14159

		static struct {
			char *	model;
			double	fov;
			double	focal_length;
			double	vertical_sensor_size;
		} ModelList[] = {
			// http://caramba-apps.com/blog/files/field-of-view-angles-ipad-iphone.html

			{ "iPad5,4",	0, 3.3, 0 },					// iPad Air 2
			{ "iPad4,5",	0 },				// iPad Mini (2nd Generation iPad Mini - Cellular)
			{ "iPad4,4",	0 },				// iPad Mini (2nd Generation iPad Mini - Wifi)
			{ "iPad4,2",	0 },				// iPad Air 5th Generation iPad (iPad Air) - Cellular
			{ "iPad4,1",	0 },				// iPad Air 5th Generation iPad (iPad Air) - Wifi
			{ "iPad3,6",	0 },				// iPad 4 (4th Generation)
			{ "iPad3,5",	0 },				// iPad 4 (4th Generation)
			{ "iPad3,4",	0 },				// iPad 4 (4th Generation)
			{ "iPad3,3",	0 },				// iPad 3 (3rd Generation)
			{ "iPad3,2",	0 },				// iPad 3 (3rd Generation)
			{ "iPad3,1",	0 },				// iPad 3 (3rd Generation)
			{ "iPad2,7",	0 },				// iPad Mini (Original)
			{ "iPad2,6",	0 },				// iPad Mini (Original)
			{ "iPad2,5",	0 },				// iPad Mini (Original)
			{ "iPad2,4",	43.47 },				// iPad 2
			{ "iPad2,3",	43.47 },				// iPad 2
			{ "iPad2,2",	43.47 },				// iPad 2
			{ "iPad2,1",	43.47 },				// iPad 2

			{ "iPhone7,2",	0, 4.15, 4.89 },				// iPhone 6+
			{ "iPhone7,1",	0, 4.15, 4.89 },				// iPhone 6
			{ "iPhone6,2",	0, 4.12, 4.89 },				// iPhone 5s (model A1457, A1518, A1528 (China), A1530 | Global)
			{ "iPhone6,1",	0, 4.12, 4.89 },				// iPhone 5s model A1433, A1533 | GSM)
			{ "iPhone5,4",	0, 4.10, 4.54 },				// iPhone 5c (model A1507, A1516, A1526 (China), A1529 | Global)
			{ "iPhone5,3",	0, 4.10, 4.54 },				// iPhone 5c (model A1456, A1532 | GSM)
			{ "iPhone5,2",	58.498, 4.10, 4.592 },				// iPhone 5 (model A1429, everything else)
			{ "iPhone5,1",	58.498, 4.10, 4.592 },				// iPhone 5 (model A1428, AT&T/Canada)
			{ "iPhone4,1",	56.423, 4.28, 4.592 },				// iPhone 4S
			{ "iPhone3,1",	61.048, 3.85, 4.54 },				// iPhone 4
			{ "iPhone2,1",	49.871, 3.85, 3.58 },				// iPhone 3GS
			{ "iPhone1,1",	49.356, 3.85, 3.538 },				// iPhone 3

			{ "iPod4,1",	0 },				// iPod Touch (Fifth Generation)
			{ "iPod4,1",	0 },				// iPod Touch (Fourth Generation)
		};

		struct utsname systemInfo = { 0 };
		uname(&systemInfo);
		for ( int i = 0; i < sizeof ModelList/sizeof ModelList[0]; ++i ) {
			if ( ModelList[i].vertical_sensor_size == 0 )
				continue;
			if ( ModelList[i].focal_length == 0 )
				continue;
			double a = 2*atan2(ModelList[i].vertical_sensor_size/2,ModelList[i].focal_length) * 180 / M_PI;
			assert( ModelList[i].fov == 0 || fabs(a - ModelList[i].fov) < 0.01 );
			if ( strcmp( systemInfo.machine, ModelList[i].model ) == 0 ) {
				cameraAngle = a;
			}
		}

		if ( cameraAngle == 0 )
			cameraAngle = 58.498;	// wild guess
	});
	return cameraAngle;
}

-(double)distanceToObject
{
	AppDelegate * delegate = [[UIApplication sharedApplication] delegate];
	CLLocationCoordinate2D userLoc = delegate.mapView.currentLocation.coordinate;
	OsmBaseObject * object = delegate.mapView.editorLayer.selectedPrimary;
	OSMPoint userPt = { userLoc.longitude, userLoc.latitude };

	double dist = MAXFLOAT;
	for ( OsmNode * node in object.nodeSet ) {
		OSMPoint nodePt = { node.lon, node.lat };
		double d = GreatCircleDistance( userPt, nodePt );
		if ( d < dist )
			dist = d;
	}
	return dist;
}

-(void)addRulerLabels
{
	double dist = [self distanceToObject];
	double cameraAngle = [self cameraDegrees];

	CGRect rc = self.view.bounds;

	int DivCount = 10;
	for ( int div = 0; div <= DivCount; ++div ) {
		double angle = cameraAngle * div / DivCount;
		double s = sin( angle * M_PI/180 );
		double height = s * dist;
		double pixels = round( (1-s) * rc.size.height );

		UILabel * label = [[UILabel alloc] init];
		label.layer.anchorPoint = CGPointMake(0, 1);
		label.text = [NSString stringWithFormat:@"%.1f meters", height];
		label.font = [UIFont systemFontOfSize:16];
		label.backgroundColor	= UIColor.whiteColor;
		label.textColor			= [UIColor blackColor];
		[label sizeToFit];
		label.center			= CGPointMake( 5, pixels );
		[self.view addSubview:label];

		CAShapeLayer * layer = [[CAShapeLayer alloc] init];
		UIBezierPath * path = [[UIBezierPath alloc] init];
		[path moveToPoint:CGPointMake(0, pixels)];
		[path addLineToPoint:CGPointMake(rc.size.width, pixels)];
		layer.path = path.CGPath;
		layer.strokeColor = [UIColor whiteColor].CGColor;
		layer.frame = self.view.bounds;
		[self.view.layer addSublayer:layer];
	}
}

-(BOOL)startCameraPreview
{
	_captureSession = [[AVCaptureSession alloc] init];

	AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	if ( videoDevice == nil )
		return NO;
	NSError *error;
	AVCaptureDeviceInput * videoIn = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
	if ( error )
		return NO;
	if ( ![_captureSession canAddInput:videoIn] )
		return NO;
	[_captureSession addInput:videoIn];

	_previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_captureSession];
	_previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

	_previewLayer.bounds = self.view.layer.bounds;
	_previewLayer.position = CGRectCenter(self.view.layer.bounds);
	_previewLayer.zPosition = -1;	// buttons and labels need to be above video
	[self.view.layer addSublayer:_previewLayer];

	[_captureSession startRunning];

	return YES;
}

-(IBAction)done:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:^{
	}];
}

@end
