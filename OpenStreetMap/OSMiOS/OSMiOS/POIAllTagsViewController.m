//
//  POICustomTagsViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/13/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "AutocompleteTextField.h"
#import "EditorMapLayer.h"
#import "MapView.h"
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
	_relations	= [tabController.relationList mutableCopy];

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

- (void)saveState
{
	NSMutableDictionary * dict = [self keyValueDictionary];
	POITabBarController * tabController = (id)self.tabBarController;
	tabController.keyValueDict = dict;
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self loadState];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[self saveState];
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


-(NSMutableDictionary *)keyValueDictionary
{
	NSMutableDictionary * dict = [NSMutableDictionary dictionaryWithCapacity:_tags.count];
	for ( NSArray * kv in _tags ) {

		// strip whitespace around text
		NSString * key = kv[0];
		NSString * val = kv[1];

		key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		val = [val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

		if ( key.length && val.length ) {
			[dict setObject:val forKey:key];
		}
	}
	return dict;
}


- (IBAction)textFieldReturn:(id)sender
{
	[sender resignFirstResponder];
}

- (IBAction)textFieldEditingDidBegin:(UITextField *)textField
{
	NSInteger tag = textField.tag;
	assert( tag >= 0 );
	BOOL isValue = (tag & 1) != 0;

	if ( tag < RELATION_TAGS ) {

		NSMutableArray * kv = _tags[ tag/2 ];

		if ( isValue ) {
			// get list of values for current key
			NSString * key = kv[0];
			NSSet * set = [[TagInfoDatabase sharedTagInfoDatabase] allTagValuesForKey:key];
			AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
			NSMutableSet * values = [appDelegate.mapView.editorLayer.mapData tagValuesForKey:key];
			[values addObjectsFromArray:[set allObjects]];
			NSArray * list = [values allObjects];
			[(AutocompleteTextField *)textField setCompletions:list];
		} else {
			// get list of keys
			NSSet * set = [[TagInfoDatabase sharedTagInfoDatabase] allTagKeys];
			NSArray * list = [set allObjects];
			[(AutocompleteTextField *)textField setCompletions:list];
		}
	}
}

- (IBAction)textFieldEditingDidEnd:(UITextField *)textField
{
}

- (IBAction)textFieldChanged:(UITextField *)textField
{
	NSInteger tag = textField.tag;
	assert( tag >= 0 );
	POITabBarController * tabController = (id)self.tabBarController;

	if ( tag < RELATION_TAGS ) {
		// edited tags
		NSMutableArray * kv = _tags[ tag/2 ];
		BOOL isValue = (tag & 1) != 0;

		if ( isValue ) {
			// new value
			kv[1] = textField.text;
		} else {
			// new key name
			kv[0] = textField.text;
		}
		
		NSMutableDictionary * dict = [self keyValueDictionary];
		_saveButton.enabled = [tabController isTagDictChanged:dict];
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
		// don't allow editing relations here
		return NO;
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
	// Dismiss first so we trigger viewWillDisappear where we save state.
	[self dismissViewControllerAnimated:YES completion:nil];

	POITabBarController * tabController = (id)self.tabBarController;
	[tabController commitChanges];
}

- (BOOL)shouldPerformSegueWithIdentifier:(NSString *)identifier sender:(id)sender
{
	// don't allow switching to relation if current selection is modified
	POITabBarController * tabController = (id)self.tabBarController;
	NSMutableDictionary * dict = [self keyValueDictionary];
	if ( [tabController isTagDictChanged:dict] ) {
		UIAlertView * alert = [[UIAlertView alloc] initWithTitle:@"Object modified" message:@"You must save or discard changes to the current object before editing its associated relation" delegate:nil cancelButtonTitle:@"Okay" otherButtonTitles:nil];
		[alert show];
		return NO;
	}

	// switch to relation
	UITableViewCell * cell = sender;
	NSIndexPath * indexPath = [self.tableView indexPathForCell:cell];
	if ( indexPath.section != 1 ) {
		return NO;
	}

	// change the selected object in the editor to the relation
	OsmRelation	* relation = _relations[ indexPath.row ];
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
	[appDelegate.mapView.editorLayer setSelectedNode:nil];
	[appDelegate.mapView.editorLayer setSelectedWay:nil];
	[appDelegate.mapView.editorLayer setSelectedRelation:relation];
	// dismiss ourself and switch to the relation
	UIViewController * topController = (id)appDelegate.mapView.viewController;
	[appDelegate.mapView refreshPushpinText];	// update pushpin description to the relation
	[self dismissViewControllerAnimated:YES completion:^{
		[topController performSegueWithIdentifier:@"poiSegue" sender:nil];
	}];
	return NO;
}

@end
