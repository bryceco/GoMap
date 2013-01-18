//
//  UploadViewController.h
//  OSMiOS
//
//  Created by Bryce on 12/19/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@class OsmMapData;

@interface UploadViewController : UIViewController <MFMailComposeViewControllerDelegate>
{
	OsmMapData							*	_mapData;
	IBOutlet UITextView					*	_xmlTextView;
	IBOutlet UITextView					*	_commentTextView;
	IBOutlet UIBarButtonItem			*	_commitButton;
	IBOutlet UIBarButtonItem			*	_cancelButton;
	IBOutlet UIActivityIndicatorView	*	_progressView;
	IBOutlet UIButton					*	_sendMailButton;
}
-(IBAction)sendMail:(id)sender;
@end
