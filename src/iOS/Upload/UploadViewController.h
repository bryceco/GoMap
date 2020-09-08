//
//  UploadViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/19/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class OsmMapData;

@interface UploadViewController : UIViewController <UITextViewDelegate,MFMailComposeViewControllerDelegate>
{
	OsmMapData							*	_mapData;
	IBOutlet UIView						*	_commentContainerView;
	IBOutlet UITextView					*	_xmlTextView;
	IBOutlet UITextView					*	_commentTextView;
	IBOutlet UITextField				*	_sourceTextField;
	IBOutlet UIBarButtonItem			*	_commitButton;
	IBOutlet UIBarButtonItem			*	_cancelButton;
	IBOutlet UIActivityIndicatorView	*	_progressView;
	IBOutlet UIButton					*	_sendMailButton;
	IBOutlet UIButton					*	_editXmlButton;
	IBOutlet UIButton					*	_clearCommentButton;
}
-(IBAction)editXml:(id)sender;
-(IBAction)sendMail:(id)sender;
@end
