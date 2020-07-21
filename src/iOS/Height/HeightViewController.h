//
//  HeightViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 11/19/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@class CMMotionManager;

@interface HeightViewController : UIViewController
{
	AVCaptureSession			*	_captureSession;
	AVCaptureVideoPreviewLayer	*	_previewLayer;
	CMMotionManager				*	_coreMotion;
	double							_cameraFOV;
	BOOL							_canZoom;

	IBOutlet UIButton			*	_distanceLabel;
	IBOutlet UIButton			*	_heightLabel;
	IBOutlet UIButton			*	_applyButton;
	IBOutlet UIButton			*	_cancelButton;

	NSMutableDictionary			*	_rulerViews;
	NSMutableDictionary			*	_rulerLayers;
	BOOL							_isExiting;
	CGFloat							_scrollPosition;
	double							_totalZoom;

	NSString					*	_currentHeight;
	NSString					*	_alertHeight;
}

+ (BOOL)unableToInstantiateWithUserWarning:(UIViewController *)vc;
+ (instancetype)instantiate;

@property (copy)				void(^callback)(NSString * newValue);

@end
