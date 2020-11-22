//
//  POIAttributesViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/25/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <SafariServices/SafariServices.h>
#import "AppDelegate.h"
#import "EditorMapLayer.h"
#import "MapView.h"
#import "POIAttributesViewController.h"
#import "POITabBarController.h"

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
	ROW_CHANGESET,
};

@implementation POIAttributesViewController

enum {
	SECTION_METADATA = 0,
	SECTION_NODE_LATLON = 1,
	SECTION_WAY_EXTRA = 1,
	SECTION_WAY_NODES = 2,
};

- (void)viewDidLoad
{
    [super viewDidLoad];

	AppDelegate * appDelegate = AppDelegate.shared;
	OsmBaseObject * object = appDelegate.mapView.editorLayer.selectedPrimary;
	self.title	= object.isNode ? NSLocalizedString(@"Node attributes",nil)
				: object.isWay ? NSLocalizedString(@"Way attributes",nil)
				: object.isRelation ? NSLocalizedString(@"Relation attributes",nil)
				: NSLocalizedString(@"Attributes",@"node/way/relation attributes");
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	POITabBarController	* tabController = (id)self.tabBarController;
	_saveButton.enabled = [tabController isTagDictChanged];
}

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	OsmBaseObject * object = AppDelegate.shared.mapView.editorLayer.selectedPrimary;
	return object.isNode ? 2 : object.isWay ? 3 : 1;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	OsmBaseObject * object = AppDelegate.shared.mapView.editorLayer.selectedPrimary;

	if ( section == SECTION_METADATA ) {
		return 6;
	}
	if ( object.isNode ) {
		if ( section == SECTION_NODE_LATLON )
			return 1;	// longitude/latitude
	} else if ( object.isWay ) {
		if ( section == SECTION_WAY_EXTRA ) {
			return 1;
		} else if ( section == SECTION_WAY_NODES ) {
			return object.isWay.nodes.count;	// all nodes
		}
	}
	return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	AppDelegate * appDelegate = AppDelegate.shared;
	OsmBaseObject * object = appDelegate.mapView.editorLayer.selectedPrimary;

	AttributeCustomCell * cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
	cell.accessoryType	= UITableViewCellAccessoryNone;

	if ( indexPath.section == SECTION_METADATA ) {

		switch ( indexPath.row ) {
			case ROW_IDENTIFIER:
				cell.title.text = NSLocalizedString(@"Identifier",@"OSM node/way/relation identifier");
				cell.value.text = object.ident.stringValue;
				cell.accessoryType	= object.ident.longLongValue > 0 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
				break;
			case ROW_USER:
				cell.title.text = NSLocalizedString(@"User",@"OSM user name");
				cell.value.text = object.user;
				cell.accessoryType	= object.user.length > 0 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
				break;
			case ROW_UID:
				cell.title.text = NSLocalizedString(@"UID",@"OSM numeric user ID");
				cell.value.text = @(object.uid).stringValue;
				break;
			case ROW_MODIFIED:
				cell.title.text = NSLocalizedString(@"Modified",@"last modified date");
				cell.value.text = [NSDateFormatter localizedStringFromDate:object.dateForTimestamp dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
				break;
			case ROW_VERSION:
				cell.title.text = NSLocalizedString(@"Version",@"OSM object versioh");
				cell.value.text = @(object.version).stringValue;
				cell.accessoryType	= object.ident.longLongValue > 0 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
				break;
			case ROW_CHANGESET:
				cell.title.text = NSLocalizedString(@"Changeset",@"OSM changeset identifier");
				cell.value.text = @(object.changeset).stringValue;
				cell.accessoryType = object.ident.longLongValue > 0 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
				break;
			default:
				assert(NO);
		}

	} else if ( object.isNode ) {
		if ( indexPath.section == SECTION_NODE_LATLON ) {
			OsmNode * node = object.isNode;
			cell.title.text = NSLocalizedString(@"Lat/Lon",@"coordinates");
			cell.value.text = [NSString stringWithFormat:@"%f,%f", node.lat, node.lon];
		}
	} else if ( object.isWay ) {
		if ( indexPath.section == SECTION_WAY_EXTRA ) {
			double len = object.isWay.lengthInMeters;
			long nodes = object.isWay.nodes.count;
			cell.title.text = NSLocalizedString(@"Length",nil);
			cell.value.text = len >= 10 ? [NSString stringWithFormat:NSLocalizedString(@"%.0f meters, %ld nodes",@"way length if > 10m"), len, nodes]
										: [NSString stringWithFormat:NSLocalizedString(@"%.1f meters, %ld nodes",@"way length if < 10m"), len, nodes];
			cell.accessoryType = UITableViewCellAccessoryNone;
		} else if ( indexPath.section == SECTION_WAY_NODES ) {
			OsmWay * way = object.isWay;
			OsmNode * node = way.nodes[ indexPath.row ];
			cell.title.text = NSLocalizedString(@"Node",nil);
			NSString * name = [node friendlyDescription];
			if ( ![name hasPrefix:@"("] )
				name = [NSString stringWithFormat:@"%@ (%@)", name, node.ident];
			else
				name = node.ident.stringValue;
			cell.value.text = name;
		}
	} else {
		// shouldn't be here
		assert(NO);
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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	OsmBaseObject * object = AppDelegate.shared.mapView.editorLayer.selectedPrimary;
    if ( object == nil ) {
        return;
    }

    NSString *urlString = nil;

    if ( indexPath.row == ROW_IDENTIFIER ) {
        NSString * type = object.isNode ? @"node" : object.isWay ? @"way" : object.isRelation ? @"relation" : @"?";
        urlString = [NSString stringWithFormat:@"https://www.openstreetmap.org/browse/%@/%@", type, object.ident];
    } else if ( indexPath.row == ROW_USER ) {
        urlString = [NSString stringWithFormat:@"https://www.openstreetmap.org/user/%@", object.user];
    } else if ( indexPath.row == ROW_VERSION ) {
        NSString * type = object.isNode ? @"node" : object.isWay ? @"way" : object.isRelation ? @"relation" : @"?";
        urlString = [NSString stringWithFormat:@"https://www.openstreetmap.org/browse/%@/%@/history", type, object.ident];
    } else if ( indexPath.row == ROW_CHANGESET ) {
        urlString = [NSString stringWithFormat:@"https://www.openstreetmap.org/browse/changeset/%ld", (long)object.changeset];
    }

    if ( urlString != nil ) {
        NSString * encodedUrlString = [urlString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSURL * url = [NSURL URLWithString:encodedUrlString];

        SFSafariViewController * safariViewController = [[SFSafariViewController alloc] initWithURL:url];
        [self presentViewController:safariViewController animated:YES completion:nil];
    }
}

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Allow the user to copy the latitude/longitude
    return indexPath.section != SECTION_METADATA;
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender
{
    if (indexPath.section != SECTION_METADATA && action == @selector(copy:)) {
        // Allow users to copy latitude/longitude.
        return YES;
    }
    
    return NO;
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender
{
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    if (![cell isKindOfClass:[AttributeCustomCell class]]) {
        // For cells other than `AttributeCustomCell`, we don't know how to get the value.
        return;
    }
    
    AttributeCustomCell *customCell = (AttributeCustomCell *)cell;
    
    if (indexPath.section != SECTION_METADATA && action == @selector(copy:)) {
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
