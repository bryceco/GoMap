//
//  POIAttributesViewController.m
//  Go Map!!
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
#import "WebPageViewController.h"


@interface AttributeCustomCell : UITableViewCell
@property (assign,nonatomic)	IBOutlet UILabel		*	title;
@property (assign,nonatomic)	IBOutlet UITextField	*	value;
@end

@implementation AttributeCustomCell
@end

enum {
	ROW_IDENTIFIER = 0,
	ROW_USER,
	ROW_UID,
	ROW_MODIFIED,
	ROW_VERSION,
	ROW_CHANGESET
};

@implementation POIAttributesViewController

const NSInteger kCoordinateSection = 1;

- (void)viewDidLoad
{
    [super viewDidLoad];

	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	OsmBaseObject * object = appDelegate.mapView.editorLayer.selectedPrimary;
	if ( object ) {
		self.title				= [NSString stringWithFormat:NSLocalizedString(@"%@ Attributes",nil), object.isNode ? NSLocalizedString(@"Node",nil) : object.isWay ? NSLocalizedString(@"Way",nil) : object.isRelation ? NSLocalizedString(@"Relation",nil) : @""];
	} else {
		self.title				= NSLocalizedString(@"No Object Selected",nil);
	}
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	POITabBarController	* tabController = (id)self.tabBarController;
	_saveButton.enabled = [tabController isTagDictChanged];
}

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	OsmBaseObject * object = appDelegate.mapView.editorLayer.selectedPrimary;
	return object.isNode || object.isWay ? 2 : 1;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if ( section == 0 )
		return 6;

	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	OsmBaseObject * object = appDelegate.mapView.editorLayer.selectedPrimary;
	if ( object.isNode )
		return 2;	// longitude/latitude
	if ( object.isWay )
		return object.isWay.nodes.count;	// all nodes
	if ( object.isRelation )
		return 0;
	return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	OsmBaseObject * object = appDelegate.mapView.editorLayer.selectedPrimary;

	AttributeCustomCell * cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
	cell.accessoryType	= UITableViewCellAccessoryNone;

	if ( indexPath.section == 0 ) {

		switch ( indexPath.row ) {
			case ROW_IDENTIFIER:
				cell.title.text = NSLocalizedString(@"Identifier",nil);
				cell.value.text = object.ident.stringValue;
				cell.accessoryType	= object.ident.longLongValue > 0 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
				break;
			case ROW_USER:
				cell.title.text = NSLocalizedString(@"User",nil);
				cell.value.text = object.user;
				cell.accessoryType	= object.user.length > 0 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
				break;
			case ROW_UID:
				cell.title.text = NSLocalizedString(@"UID",nil);
				cell.value.text = @(object.uid).stringValue;
				break;
			case ROW_MODIFIED:
				cell.title.text = NSLocalizedString(@"Modified",nil);
				cell.value.text = [NSDateFormatter localizedStringFromDate:object.dateForTimestamp dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
				break;
			case ROW_VERSION:
				cell.title.text = NSLocalizedString(@"Version",nil);
				cell.value.text = @(object.version).stringValue;
				cell.accessoryType	= object.ident.longLongValue > 0 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
				break;
			case ROW_CHANGESET:
				cell.title.text = NSLocalizedString(@"Changeset",nil);
				cell.value.text = @(object.changeset).stringValue;
				cell.accessoryType = object.ident.longLongValue > 0 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
				break;
			default:
				assert(NO);
		}

	} else if (indexPath.section == kCoordinateSection) {

		if ( object.isNode ) {
			OsmNode * node = object.isNode;
			switch ( indexPath.row ) {
				case 0:
					cell.title.text = NSLocalizedString(@"Latitude",nil);
					cell.value.text = @(node.lat).stringValue;
					cell.accessoryType	= UITableViewCellAccessoryNone;
					break;
				case 1:
					cell.title.text = NSLocalizedString(@"Longitude",nil);
					cell.value.text = @(node.lon).stringValue;
				default:
					break;
			}
		} else if ( object.isWay ) {
			OsmWay * way = object.isWay;
			OsmNode * node = way.nodes[ indexPath.row ];
			cell.title.text = NSLocalizedString(@"Node",nil);
			NSString * name = [node friendlyDescription];
			if ( ![name hasPrefix:@"("] )
				name = [NSString stringWithFormat:@"%@ (%@)", name, node.ident];
			else
				name = node.ident.stringValue;
			cell.value.text = name;
		} else {
			// shouldn't be here
			assert(NO);
		}
	}
	// do extra work so keyboard won't display if they select a value
	UITextField * value = cell.value;
	value.inputView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
	
	return cell;
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

		AppDelegate * appDelegate = [AppDelegate getAppDelegate];
		OsmBaseObject * object = appDelegate.mapView.editorLayer.selectedPrimary;
		if ( object == nil ) {
			web.url = nil;
			return;
		}

		NSIndexPath * indexPath = [self.tableView indexPathForCell:cell];
		if ( indexPath && indexPath.section == 0 ) {
			if ( indexPath.row == ROW_IDENTIFIER ) {
				NSString * type = object.isNode ? @"node" : object.isWay ? @"way" : object.isRelation ? @"relation" : @"?";
				web.title = type.capitalizedString;
				web.url = [NSString stringWithFormat:@"http://www.openstreetmap.org/browse/%@/%@", type, object.ident];
			} else if ( indexPath.row == ROW_USER ) {
				web.title = NSLocalizedString(@"User",nil);
				web.url = [NSString stringWithFormat:@"http://www.openstreetmap.org/user/%@", object.user];
			} else if ( indexPath.row == ROW_VERSION ) {
				web.title = NSLocalizedString(@"History",nil);
				NSString * type = object.isNode ? @"node" : object.isWay ? @"way" : object.isRelation ? @"relation" : @"?";
				web.url = [NSString stringWithFormat:@"http://www.openstreetmap.org/browse/%@/%@/history", type, object.ident];
			} else if ( indexPath.row == ROW_CHANGESET ) {
				web.title = NSLocalizedString(@"Changeset",nil);
				web.url = [NSString stringWithFormat:@"http://www.openstreetmap.org/browse/changeset/%ld", (long)object.changeset];
			} else {
				assert( NO );
			}
		}

	}
	[super prepareForSegue:segue sender:sender];
}

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Allow the user to copy the latitude/longitude.
    return indexPath.section == kCoordinateSection;
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    if (indexPath.section == kCoordinateSection && action == @selector(copy:)) {
        // Allow users to copy latitude/longitude.
        return YES;
    }
    
    return NO;
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (![cell isKindOfClass:[AttributeCustomCell class]]) {
        // For cells other than `AttributeCustomCell`, we don't know how to get the value.
        return;
    }
    
    AttributeCustomCell *customCell = (AttributeCustomCell *)cell;
    
    if (indexPath.section == kCoordinateSection && action == @selector(copy:)) {
        [UIPasteboard.generalPasteboard setString:customCell.value.text];
    }
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
