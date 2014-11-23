//
//  HeightViewController.h
//  Go Map!!
//
//  Created by Bryce on 11/19/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>

@class CLLocation;


@interface HeightViewController : UIViewController
{
	AVCaptureSession			*	_captureSession;
	AVCaptureVideoPreviewLayer	*	_previewLayer;
	double							_cameraFOV;

	IBOutlet UILabel			*	_distanceLabel;
	IBOutlet UIButton			*	_doneButton;
	NSMutableArray				*	_rulerViews;
	NSMutableArray				*	_rulerLayers;
	CMMotionManager				*	_coreMotion;
	NSInteger						_zeroOffset;
	BOOL							_isExiting;
}



@end
