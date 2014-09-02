//
//  POIAttributesViewController.h
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/25/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class AttributeCustomCell;


@interface POIAttributesViewController : UITableViewController
{
	IBOutlet UIBarButtonItem	*	_saveButton;

	IBOutlet UITableViewCell	*	_identCell;
	IBOutlet UITableViewCell	*	_userCell;
	IBOutlet UITableViewCell	*	_versionCell;
	IBOutlet UITableViewCell	*	_changesetCell;

	IBOutlet AttributeCustomCell	*	_extraCell1;
	IBOutlet AttributeCustomCell	*	_extraCell2;

	IBOutlet UILabel *	_identLabel;
	IBOutlet UILabel *	_userLabel;
	IBOutlet UILabel *	_uidLabel;
	IBOutlet UILabel *	_dateLabel;
	IBOutlet UILabel *	_versionLabel;
	IBOutlet UILabel *	_changesetLabel;
}
@end
