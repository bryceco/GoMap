//
//  POICustomTagsViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/13/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "AutocompleteTextField.h"
#import "CommonTagList.h"
#import "EditorMapLayer.h"
#import "MapView.h"
#import "OsmMapData.h"
#import "OsmObjects.h"
#import "POIAllTagsViewController.h"
#import "POITabBarController.h"
#import "PushPinView.h"
#import "TagInfo.h"


#define EDIT_RELATIONS 0


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
	[super awakeFromNib];
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
	_members	= tabController.selection.isRelation ? [((OsmRelation *)tabController.selection).members mutableCopy] : nil;

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

	if ( tabController.selection.isNode ) {
		self.title = NSLocalizedString(@"Node tags",nil);
	} else if ( tabController.selection.isWay ) {
		self.title = NSLocalizedString(@"Way tags",nil);
	} else if ( tabController.selection.isRelation ) {
		NSString * type = tabController.keyValueDict[ @"type" ];
		if ( type.length ) {
			type = [type stringByReplacingOccurrencesOfString:@"_" withString:@" "];
			type = [type capitalizedString];
			self.title = [NSString stringWithFormat:@"%@ tags",type];
		} else {
			self.title = NSLocalizedString(@"Relation tags",nil);
		}
	} else {
		self.title = NSLocalizedString(@"All Tags",nil);
	}

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
	POITabBarController * tabController = (id)self.tabBarController;
	if ( tabController.selection.isRelation )
		return 3;
	else
		return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	if ( section == 0 ) {
		return NSLocalizedString(@"Tags",nil);
	} else if ( section == 1 ) {
		return NSLocalizedString(@"Relations",nil);
	} else {
		return NSLocalizedString(@"Members",nil);
	}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if ( section == 0 ) {
		// tags
		return _tags.count + 1;
	} else if ( section == 1 ) {
		// relations
		return _relations.count;
	} else {
#if EDIT_RELATIONS
		return _members.count + 1;
#else
		return _members.count;
#endif
	}
}

-(void)textFieldEditingDidEnd:(id)sender
{
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 ) {

		// Tags
		if ( indexPath.row == _tags.count ) {
			// Add new tag
			AddNewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"AddCell" forIndexPath:indexPath];
			[cell.button removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
			[cell.button addTarget:self action:@selector(addTagCell:) forControlEvents:UIControlEventTouchUpInside];
			return cell;
		}

		TextPair * cell = [tableView dequeueReusableCellWithIdentifier:@"TagCell" forIndexPath:indexPath];
		NSArray * kv = _tags[ indexPath.row ];
		// assign text contents of fields
		cell.text1.enabled = YES;
		cell.text2.enabled = YES;
		cell.text1.text = kv[0];
		cell.text2.text = kv[1];

		cell.text1.didSelect = ^{ [cell.text2 becomeFirstResponder]; };
		cell.text2.didSelect = ^{};

#if 0
		if ( [kv[0] length] == 0 && [kv[1] length] == 0 ) {
			// empty key/value so set keyboard focus to it
			[cell.text1 becomeFirstResponder];
		}
#endif
		return cell;

	} else if ( indexPath.section == 1 ) {

		// Relations
		if ( indexPath.row == _relations.count ) {
			UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"AddCell" forIndexPath:indexPath];
			return cell;
		}
		TextPair *cell = [tableView dequeueReusableCellWithIdentifier:@"RelationCell" forIndexPath:indexPath];
		cell.text1.enabled = NO;
		cell.text2.enabled = NO;
		OsmRelation	* relation = _relations[ indexPath.row ];
		cell.text1.text = relation.ident.stringValue;
		cell.text2.text = [relation friendlyDescription];

		return cell;

	} else {

		// Members
		if ( indexPath.row == _members.count ) {
			AddNewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"AddCell" forIndexPath:indexPath];
			[cell.button removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
			[cell.button addTarget:self action:@selector(addTagCell:) forControlEvents:UIControlEventTouchUpInside];
			return cell;
		}
		TextPair *cell = [tableView dequeueReusableCellWithIdentifier:@"MemberCell" forIndexPath:indexPath];
#if EDIT_RELATIONS
		cell.text1.enabled = YES;
		cell.text2.enabled = YES;
#else
		cell.text1.enabled = NO;
		cell.text2.enabled = NO;
#endif
		OsmMember	* member = _members[ indexPath.row ];
		if ( [member isKindOfClass:[OsmMember class]] ) {
			OsmBaseObject * ref = member.ref;
			NSString * memberName = [ref isKindOfClass:[OsmBaseObject class]] ? ref.friendlyDescription : [NSString stringWithFormat:@"%@ %@",member.type, member.ref];
			cell.text1.text = member.role;
			cell.text2.text = memberName;
		} else {
			NSArray * values = (id)member;
			cell.text1.text = values[0];
			cell.text2.text = values[1];
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
	UITableViewCell * cell = (id)textField.superview;
	while ( cell && ![cell isKindOfClass:[UITableViewCell class]])
		cell = (id)cell.superview;
	TextPair * pair = (id)cell;
	BOOL isValue = textField == pair.text2;

	NSIndexPath * indexPath = [self.tableView indexPathForCell:cell];

	if ( indexPath.section == 0 ) {

		NSMutableArray * kv = _tags[ indexPath.row ];

		if ( isValue ) {
			// get list of values for current key
			NSString * key = kv[0];
			NSSet * set = [CommonTagList allTagValuesForKey:key];
			AppDelegate * appDelegate = [AppDelegate getAppDelegate];
			NSMutableSet * values = [appDelegate.mapView.editorLayer.mapData tagValuesForKey:key];
			[values addObjectsFromArray:[set allObjects]];
			NSArray * list = [values allObjects];
			[(AutocompleteTextField *)textField setCompletions:list];
		} else {
			// get list of keys
			NSSet * set = [CommonTagList allTagKeys];
			NSArray * list = [set allObjects];
			[(AutocompleteTextField *)textField setCompletions:list];
		}
	}
}

- (IBAction)textFieldChanged:(UITextField *)textField
{
	UITableViewCell * cell = (id)textField.superview;
	while ( cell && ![cell isKindOfClass:[UITableViewCell class]])
		cell = (id)cell.superview;
	NSIndexPath * indexPath = [self.tableView indexPathForCell:cell];

	POITabBarController * tabController = (id)self.tabBarController;

	if ( indexPath.section == 0 ) {
		// edited tags
		TextPair * pair = (id)cell;
		NSMutableArray * kv = _tags[ indexPath.row ];
		BOOL isValue = textField == pair.text2;

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
	button.title = editing ? NSLocalizedString(@"Done",nil) : NSLocalizedString(@"Edit",nil);
	button.style = editing ? UIBarButtonItemStyleDone : UIBarButtonItemStylePlain;
}


// Don't allow deleting the "Add Tag" row
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 ) {
		return indexPath.row < _tags.count;
	} else if ( indexPath.section == 1 ) {
		// don't allow editing relations here
		return NO;
	} else {
#if EDIT_RELATIONS
		return indexPath.row < _members.count;
#else
		return NO;
#endif
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
		} else if ( indexPath.section == 1 ) {
			[_relations removeObjectAtIndex:indexPath.row];
		} else  {
			[_members removeObjectAtIndex:indexPath.row];
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
	UITableViewCell * cell = sender;	// starts out as UIButton
	while ( cell && ![cell isKindOfClass:[UITableViewCell class]] )
		cell = (id)[cell superview];
	NSIndexPath * indexPath = [self.tableView indexPathForCell:cell];
	if ( indexPath.section == 0 ) {
		[_tags addObject:[NSMutableArray arrayWithObjects:@"",@"",nil]];
	} else if ( indexPath.section == 2 ) {
		[_members addObject:[NSMutableArray arrayWithObjects:@"",@"",nil]];
	} else {
		return;
	}
	[self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationBottom];

	// set new cell to show keyboard
	TextPair * newCell = (id)[self.tableView cellForRowAtIndexPath:indexPath];
	[newCell.text1 becomeFirstResponder];
}

-(IBAction)cancel:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction)done:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
	[self saveState];

	POITabBarController * tabController = (id)self.tabBarController;
	[tabController commitChanges];
}

- (BOOL)shouldPerformSegueWithIdentifier:(NSString *)identifier sender:(id)sender
{
	// don't allow switching to relation if current selection is modified
	POITabBarController * tabController = (id)self.tabBarController;
	NSMutableDictionary * dict = [self keyValueDictionary];
	if ( [tabController isTagDictChanged:dict] ) {
		UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Object modified",nil)
																		message:NSLocalizedString(@"You must save or discard changes to the current object before editing its associated relation",nil)
																 preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
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
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	[appDelegate.mapView.editorLayer setSelectedNode:nil];
	[appDelegate.mapView.editorLayer setSelectedWay:nil];
	[appDelegate.mapView.editorLayer setSelectedRelation:relation];

	[appDelegate.mapView placePushpinAtPoint:appDelegate.mapView.pushpinView.arrowPoint object:relation];

	// dismiss ourself and switch to the relation
	UIViewController * topController = (id)appDelegate.mapView.viewController;
	[appDelegate.mapView refreshPushpinText];	// update pushpin description to the relation
	[self dismissViewControllerAnimated:YES completion:^{
		[topController performSegueWithIdentifier:@"poiSegue" sender:nil];
	}];
	return NO;
}

@end
