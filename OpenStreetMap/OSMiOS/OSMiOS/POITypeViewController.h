//
//  NewItemController.h
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface POITypeViewController : UITableViewController <UISearchBarDelegate, UIAlertViewDelegate>
{
	NSArray					*	_typeArray;
	NSArray					*	_searchArrayRecent;
	NSArray					*	_searchArrayAll;
	NSMutableArray			*	_mostRecentArray;
	NSInteger					_mostRecentMaximum;
	IBOutlet UISearchBar    *	_searchBar;
	BOOL						_isTopLevel;
}
@property (copy,nonatomic) NSString *	rootType;

-(IBAction)back:(id)sender;
-(IBAction)configure:(id)sender;

@end
