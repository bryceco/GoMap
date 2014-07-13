//
//  POIAttributesViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/25/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "EditorMapLayer.h"
#import "MapView.h"
#import "OsmObjects.h"
#import "POIAttributesViewController.h"
#import "POITabBarController.h"
#import "UITableViewCell+FixConstraints.h"
#import "WebPageViewController.h"


@interface AttributeCustomCell : UITableViewCell
@property (assign,nonatomic)	IBOutlet UILabel	*	title;
@property (assign,nonatomic)	IBOutlet UILabel	*	value;
@end

@implementation AttributeCustomCell
@end


@implementation POIAttributesViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];

	OsmBaseObject * object = appDelegate.mapView.editorLayer.selectedPrimary;

	if ( object ) {
		self.title				= [NSString stringWithFormat:@"%@ Attributes", object.isNode ? @"Node" : object.isWay ? @"Way" : object.isRelation ? @"Relation" : @""];
		_identLabel.text		= object.ident.stringValue;
		_userLabel.text			= object.user;
		_uidLabel.text			= @(object.uid).stringValue;
		_dateLabel.text			= [NSDateFormatter localizedStringFromDate:object.dateForTimestamp dateStyle:kCFDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
		_versionLabel.text		= @(object.version).stringValue;
		_changesetLabel.text	= @(object.changeset).stringValue;
	} else {
		self.title				= @"No Object Selected";
		_identLabel.text		= nil;
		_userLabel.text			= nil;
		_uidLabel.text			= nil;
		_dateLabel.text			= nil;
		_versionLabel.text		= nil;
		_changesetLabel.text	= nil;
	}

	// don't show disclosures for newly created objects
	_identCell.accessoryType	= object.ident.longLongValue > 0 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	_userCell.accessoryType		= object.user.length > 0		? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	_versionCell.accessoryType	= object.ident.longLongValue > 0 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	_changesetCell.accessoryType = object.ident.longLongValue > 0 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;


	if ( object.isNode ) {
		OsmNode * node = (id)object;
		_extraCell1.title.text = @"Latitude";
		_extraCell2.title.text = @"Longitude";
		_extraCell1.value.text = @(node.lat).stringValue;
		_extraCell2.value.text = @(node.lon).stringValue;
	} else if ( object.isWay ) {
		OsmWay * way = (id)object;
		_extraCell1.title.text = @"Nodes";
		_extraCell1.value.text = @(way.nodeSet.count).stringValue;
		_extraCell2.title.text = nil;
		_extraCell2.value.text = nil;
	} else {
		_extraCell1.title.text = nil;
		_extraCell1.value.text = nil;
		_extraCell2.title.text = nil;
		_extraCell2.value.text = nil;
	}
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	POITabBarController	* tabController = (id)self.tabBarController;
	_saveButton.enabled = [tabController isTagDictChanged];
}

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	[cell fixConstraints];
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];
	if ( cell.accessoryType == UITableViewCellAccessoryNone )
		return nil;
	return indexPath;
}


- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
	if ( [sender isKindOfClass:[UITableViewCell class]] ) {
		UITableViewCell * cell = sender;
		
		WebPageViewController * web = segue.destinationViewController;

		AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
		OsmBaseObject * object = appDelegate.mapView.editorLayer.selectedPrimary;
		if ( object == nil ) {
			web.url = nil;
			return;
		}

		if ( cell == _identCell ) {
			NSString * type = object.isNode ? @"node" : object.isWay ? @"way" : object.isRelation ? @"relation" : @"?";
			web.title = type.capitalizedString;
			web.url = [NSString stringWithFormat:@"http://www.openstreetmap.org/browse/%@/%@", type, object.ident];
		} else if ( cell == _userCell ) {
			web.title = @"User";
			web.url = [NSString stringWithFormat:@"http://www.openstreetmap.org/user/%@", object.user];
		} else if ( cell == _versionCell ) {
			web.title = @"History";
			NSString * type = object.isNode ? @"node" : object.isWay ? @"way" : object.isRelation ? @"relation" : @"?";
			web.url = [NSString stringWithFormat:@"http://www.openstreetmap.org/browse/%@/%@/history", type, object.ident];
		} else if ( cell == _changesetCell ) {
			web.title = @"Changeset";
			web.url = [NSString stringWithFormat:@"http://www.openstreetmap.org/browse/changeset/%ld", (long)object.changeset];
		} else {
			assert( NO );
		}
	}
	[super prepareForSegue:segue sender:sender];
}

-(IBAction)cancel:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction)done:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];

	POITabBarController * tabController = (id)self.tabBarController;
	[tabController commitChanges];
}


@end
