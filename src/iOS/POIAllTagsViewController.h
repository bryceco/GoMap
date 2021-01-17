//
//  POICustomTagsViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/13/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface TextPairTableCell : UITableViewCell
@property (assign,nonatomic) IBOutlet	AutocompleteTextField *	text1;
@property (assign,nonatomic) IBOutlet	AutocompleteTextField *	text2;
@property (assign,nonatomic) IBOutlet	UIButton			  * infoButton;
@end

@interface POIAllTagsViewController : UITableViewController
{
	NSMutableArray				*	_tags;
	NSMutableArray				*	_relations;
	NSMutableArray				*	_members;
	IBOutlet UIBarButtonItem	*	_saveButton;
	BOOL							_childViewPresented;
	NSString					*	_featureID;
	UITextField					*	_currentTextField;
}

- (IBAction)toggleTableRowEditing:(id)sender;

@end
