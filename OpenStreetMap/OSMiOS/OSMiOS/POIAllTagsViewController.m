//
//  POICustomTagsViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/13/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "OsmMapData.h"
#import "OsmObjects.h"
#import "POIAllTagsViewController.h"
#import "POITabBarController.h"
#import "TagInfo.h"
#import "UITableViewCell+FixConstraints.h"


#define RELATION_TAGS 1024


@implementation TextPair

- (void)willTransitionToState:(UITableViewCellStateMask)state
{
	[super willTransitionToState:state];

	// don't allow editing text while deleting
	if ( state & (UITableViewCellStateShowingEditControlMask | UITableViewCellStateShowingDeleteConfirmationMask) ) {
		[_text1 resignFirstResponder];
		[_text2 resignFirstResponder];
	}
}


- (void)awakeFromNib
{
	[self fixConstraints];
}

@end


@implementation AddNewCell
@end


@implementation POIAllTagsViewController

- (void)viewDidLoad
{
	[super viewDidLoad];

	UIBarButtonItem * editButton = self.editButtonItem;
	[editButton setTarget:self];
	[editButton setAction:@selector(toggleEditing:)];
	self.navigationItem.rightBarButtonItems = @[ self.navigationItem.rightBarButtonItem, editButton ];
}

- (void)loadState
{
	// fetch values from tab controller
	POITabBarController * tabController = (id)self.tabBarController;
	_tags		= [NSMutableArray arrayWithCapacity:tabController.keyValueDict.count];
	_relations	= tabController.relationList;

	[tabController.keyValueDict enumerateKeysAndObjectsUsingBlock:^(NSString * tag, NSString * value, BOOL *stop) {
		[_tags addObject:[NSMutableArray arrayWithObjects:tag,value,nil]];
	}];

	[_tags sortUsingComparator:^NSComparisonResult( NSArray * obj1, NSArray * obj2 ) {
		NSString * tag1 = obj1[0];
		NSString * tag2 = obj2[0];
		BOOL tiger1 = [tag1 hasPrefix:@"tiger:"] || [tag1 hasPrefix:@"gnis:"];
		BOOL tiger2 = [tag2 hasPrefix:@"tiger:"] || [tag2 hasPrefix:@"gnis:"];
		if ( tiger1 == tiger2 ) {
			return [tag1 compare:tag2];
		} else {
			return tiger1 - tiger2;
		}
	}];

	[self.tableView reloadData];

	_saveButton.enabled = [tabController isTagDictChanged];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self loadState];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	if ( section == 0 )
		return @"Tags";
	else
		return @"Relations";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if ( section == 0 ) {
		// tags
		return _tags.count + 1;
	} else {
		// relations
		return _relations.count;
	}
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 ) {
		if ( indexPath.row == _tags.count ) {
			AddNewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"AddCell" forIndexPath:indexPath];
			[cell.button removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
			[cell.button addTarget:self action:@selector(addTagCell:) forControlEvents:UIControlEventTouchUpInside];
			cell.tag = -1;
			return cell;
		}
		TextPair * cell = [tableView dequeueReusableCellWithIdentifier:@"TagCell" forIndexPath:indexPath];
		NSArray * kv = _tags[ indexPath.row ];
		// assign text contents of fields
		cell.text1.enabled = YES;
		cell.text2.enabled = YES;
		cell.text1.text = kv[0];
		cell.text2.text = kv[1];
		// assign tags so we can map changes back to rows
		cell.text1.tag = 2*indexPath.row;
		cell.text2.tag = 2*indexPath.row + 1;
		return cell;
	} else {
		if ( indexPath.row == _relations.count ) {
			UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"AddCell" forIndexPath:indexPath];
			cell.tag = -1;
			return cell;
		}
		POITabBarController * tabController = (id)self.tabBarController;
		TextPair *cell = [tableView dequeueReusableCellWithIdentifier:@"RelationCell" forIndexPath:indexPath];
		cell.text1.enabled = NO;
		cell.text2.enabled = NO;
		cell.text1.tag = RELATION_TAGS + 2*indexPath.row;
		cell.text2.tag = RELATION_TAGS + 2*indexPath.row + 1;
		OsmRelation	* relation = _relations[ indexPath.row ];
		NSString * relationName = [relation.tags objectForKey:@"name"];
		if ( relationName == nil )
			relationName = relation.ident.stringValue;
		cell.text1.text = relationName;
		cell.text2.text = nil;
		for ( OsmMember * member in relation.members ) {
			if ( member.ref == tabController.selection ) {
				cell.text2.text = member.role;
				break;
			}
		}

		return cell;
	}
}



- (IBAction)textFieldReturn:(id)sender
{
	[sender resignFirstResponder];
}


static BOOL g_doAutocomplete = YES;

- (void)autocompleteTextField:(UITextField *)textField completions:(NSArray *)completions
{
	if ( !g_doAutocomplete ) {
		g_doAutocomplete = YES;
		return;
	}

	NSString * text = textField.text;

	for ( NSString * s in completions ) {
		if ( [s hasPrefix:text] ) {
			NSInteger pos = text.length;
			textField.text = s;

			UITextPosition * start = [textField positionFromPosition:textField.beginningOfDocument offset:pos];
			UITextPosition * end = textField.endOfDocument;
			UITextRange * range = [textField textRangeFromPosition:start toPosition:end];
			[textField setSelectedTextRange:range];
			return;
		}
	}
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
	if ( string.length == 0 && range.location+range.length == textField.text.length ) {
		// deleting from tail, so disable autocomplete until next change
		g_doAutocomplete = NO;
	}
	return YES;
}

- (IBAction)textFieldChanged:(UITextField *)textField
{
	NSInteger tag = textField.tag;
	assert( tag >= 0 );
	BOOL isValue = (tag & 1) != 0;

	if ( tag < RELATION_TAGS ) {

		NSMutableArray * kv = _tags[ tag/2 ];

		if ( isValue ) {
			NSString * key = kv[0];
			NSSet * set = [[TagInfoDatabase sharedTagInfoDatabase] allTagValuesForKey:key];
			NSArray * list = [set allObjects];
			[self autocompleteTextField:textField completions:list];
		} else {
			// get list of keys
			NSSet * set = [[TagInfoDatabase sharedTagInfoDatabase] allTagKeys];
			NSArray * list = [set allObjects];
			[self autocompleteTextField:textField completions:list];
		}

		NSString * text = textField.text;
		text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		// edited tags
		POITabBarController * tabController = (id)self.tabBarController;
		if ( isValue ) {
			// new value
			kv[1] = text;
			if ( [kv[0] length] && [kv[1] length] ) {
				[tabController.keyValueDict setObject:kv[1] forKey:kv[0]];
			} else {
				[tabController.keyValueDict removeObjectForKey:kv[0]];
			}
		} else {
			// new key name
			[tabController.keyValueDict removeObjectForKey:kv[0]];
			kv[0] = text;
			if ( [kv[0] length] && [kv[1] length] ) {
				[tabController.keyValueDict setObject:kv[1] forKey:kv[0]];
			}
		}

		_saveButton.enabled = [tabController isTagDictChanged];
	}
}

- (IBAction)toggleEditing:(id)sender
{
	POITabBarController * tabController = (id)self.tabBarController;

	BOOL editing = !self.tableView.editing;
	self.navigationItem.leftBarButtonItem.enabled = !editing;
	self.navigationItem.rightBarButtonItem.enabled = !editing && [tabController isTagDictChanged];
	[self.tableView setEditing:editing animated:YES];
	UIBarButtonItem * button = sender;
	button.title = editing ? @"Done" : @"Edit";
	button.style = editing ? UIBarButtonItemStyleDone : UIBarButtonItemStyleBordered;
}


// Don't allow deleting the "Add Tag" row
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 ) {
		return indexPath.row < _tags.count;
	} else {
		return indexPath.row < _relations.count;
	}
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( editingStyle == UITableViewCellEditingStyleDelete ) {
		// Delete the row from the data source
		POITabBarController * tabController = (id)self.tabBarController;
		if ( indexPath.section == 0 ) {
			NSArray * kv = _tags[ indexPath.row ];
			NSString * tag = kv[0];
			[tabController.keyValueDict removeObjectForKey:tag];
			[_tags removeObjectAtIndex:indexPath.row];
		} else {
			[_relations removeObjectAtIndex:indexPath.row];
		}
		[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];

		_saveButton.enabled = [tabController isTagDictChanged];

	} else if ( editingStyle == UITableViewCellEditingStyleInsert ) {
		// Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
	}
}

#pragma mark - Table view delegate

- (void)addTagCell:(id)sender
{
	[_tags addObject:[NSMutableArray arrayWithObjects:@"",@"",nil]];
	NSIndexPath * indexPath = [NSIndexPath indexPathForRow:_tags.count-1 inSection:0];
	[self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationBottom];
}

- (void)addRelationCell:(id)sender
{

}

-(IBAction)cancel:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction)done:(id)sender
{
	// dismiss first so text field resigns before we read its value
	[self dismissViewControllerAnimated:YES completion:nil];

	POITabBarController * tabController = (id)self.tabBarController;
	[tabController commitChanges];
}


@end
