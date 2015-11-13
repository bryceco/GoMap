//
//  POIAttributesViewController.h
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/25/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class AttributeCustomCell;


@interface POIAttributesViewController : UITableViewController <UITableViewDataSource,UITableViewDelegate>
{
	IBOutlet UIBarButtonItem	*	_saveButton;
}
@end
