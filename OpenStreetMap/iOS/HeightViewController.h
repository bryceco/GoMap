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



@interface HeightViewController : UIViewController
{
	AVCaptureSession			*	_captureSession;
	AVCaptureVideoPreviewLayer	*	_previewLayer;
}



@end
