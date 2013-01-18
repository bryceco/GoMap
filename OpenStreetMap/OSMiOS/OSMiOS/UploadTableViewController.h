//
//  UploadTableViewController.h
//  OSMiOS
//
//  Created by Bryce Cogswell on 1/7/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class OsmMapData;

@interface UploadTableViewController : UITableViewController <MFMailComposeViewControllerDelegate>
{
	OsmMapData							*	_mapData;
	NSMutableArray						*	_sectionList;

	IBOutlet UITextView					*	_commentTextView;
	IBOutlet UIBarButtonItem			*	_commitButton;
	IBOutlet UIBarButtonItem			*	_cancelButton;
	IBOutlet UIActivityIndicatorView	*	_progressView;
	IBOutlet UIButton					*	_sendMailButton;
}
-(IBAction)sendMail:(id)sender;
@end

