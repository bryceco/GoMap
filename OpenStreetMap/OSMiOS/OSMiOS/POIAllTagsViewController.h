//
//  POICustomTagsViewController.h
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/13/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface TextPair : UITableViewCell
{
	IBOutlet UIView				*	_fixContstraintView;
	IBOutlet NSLayoutConstraint *	_fixConstraint;
}
@property (assign,nonatomic) IBOutlet	UITextField *	text1;
@property (assign,nonatomic) IBOutlet	UITextField *	text2;
@end


@interface AddNewCell : UITableViewCell
@property (assign,nonatomic) IBOutlet	UIButton *	button;
@end


@interface POIAllTagsViewController : UITableViewController
{
	NSMutableArray				*	_tags;
	NSMutableArray				*	_relations;
	NSMutableArray				*	_members;
	IBOutlet UIBarButtonItem	*	_saveButton;
}

- (IBAction)toggleEditing:(id)sender;

@end
