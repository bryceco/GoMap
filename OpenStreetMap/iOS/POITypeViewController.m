//
//  NewItemController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "iosapi.h"
#import "CommonTagList.h"
#import "OsmObjects.h"
#import "POITabBarController.h"
#import "POITypeViewController.h"


static const NSInteger MOST_RECENT_DEFAULT_COUNT = 5;
static const NSInteger MOST_RECENT_SAVED_MAXIMUM = 100;

@implementation POITypeViewController

static NSMutableArray	*	mostRecentArray;
static NSInteger			mostRecentMaximum;


+(void)loadMostRecentForGeometry:(NSString *)geometry
{
	NSNumber * max = [[NSUserDefaults standardUserDefaults] objectForKey:@"mostRecentTypesMaximum"];
	mostRecentMaximum = max ? max.integerValue : MOST_RECENT_DEFAULT_COUNT;

	NSString * defaults = [NSString stringWithFormat:@"mostRecentTypes.%@", geometry];
	NSArray * a = [[NSUserDefaults standardUserDefaults] objectForKey:defaults];
	mostRecentArray = [NSMutableArray arrayWithCapacity:a.count+1];
	for ( NSString * featureName in a ) {
		CommonTagFeature * tagInfo = [CommonTagFeature commonTagFeatureWithName:featureName];
		if ( tagInfo ) {
			[mostRecentArray addObject:tagInfo];
		}
	}
}

-(NSString *)currentSelectionGeometry
{
	POITabBarController * tabController = (id)self.tabBarController;
	OsmBaseObject * selection = tabController.selection;
	NSString * geometry = [selection geometryName];
	if ( geometry == nil )
		geometry = GEOMETRY_NODE;	// a brand new node
	return geometry;
}


- (void)viewDidLoad
{
	[super viewDidLoad];

	NSString * geometry = [self currentSelectionGeometry];
	if ( geometry == nil )
		geometry = GEOMETRY_NODE;	// a brand new node

	[self.class loadMostRecentForGeometry:geometry];

	if ( _parentCategory == nil ) {
		_isTopLevel = YES;
		_typeArray = [CommonTagList featuresForGeometry:geometry];
	} else {
		_typeArray = _parentCategory.members;
	}
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return _isTopLevel ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	if ( _isTopLevel ) {
		return section == 0 ? NSLocalizedString(@"Most recent",nil) : NSLocalizedString(@"All choices",nil);
	} else {
		return nil;
	}
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if ( _searchArrayAll ) {
		return section == 0 ? _searchArrayRecent.count : _searchArrayAll.count;
	} else {
		if ( _isTopLevel && section == 0 ) {
			NSInteger count = mostRecentArray.count;
			return count < mostRecentMaximum ? count : mostRecentMaximum;
		} else {
			return _typeArray.count;
		}
	}
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( _searchArrayAll ) {
		UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"FinalCell" forIndexPath:indexPath];
		CommonTagFeature * feature = indexPath.section == 0 ? _searchArrayRecent[ indexPath.row ] : _searchArrayAll[ indexPath.row ];
		cell.textLabel.text			= feature.friendlyName;
		cell.imageView.image		= feature.icon;
		cell.detailTextLabel.text	= feature.summary;
		return cell;
	}

	if ( _isTopLevel && indexPath.section == 0 ) {
		// most recents
		UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"FinalCell" forIndexPath:indexPath];
		CommonTagFeature * feature = mostRecentArray[ indexPath.row ];
		cell.textLabel.text			= feature.friendlyName;
		cell.imageView.image		= feature.icon;
		cell.detailTextLabel.text	= feature.summary;
		cell.accessoryType			= UITableViewCellAccessoryNone;
		return cell;
	} else {
		// type array
		id tagInfo = _typeArray[ indexPath.row ];
		if ( [tagInfo isKindOfClass:[CommonTagCategory class]] ) {
			CommonTagCategory * category = tagInfo;
			UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"SubCell" forIndexPath:indexPath];
			cell.textLabel.text = category.friendlyName;
			return cell;
		} else {
			CommonTagFeature * feature = tagInfo;
			UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"FinalCell" forIndexPath:indexPath];
			cell.textLabel.text			= feature.friendlyName;
			cell.imageView.image		= feature.icon;
			cell.detailTextLabel.text	= feature.summary;

			POITabBarController * tabController = (id)self.tabBarController;
			NSString * geometry = [self currentSelectionGeometry];
			NSString * currentFeature = [CommonTagList featureNameForObjectDict:tabController.keyValueDict geometry:geometry];
			BOOL selected = [currentFeature isEqualToString:feature.featureName];
			cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
			return cell;
		}
	}
}

+(void)updateMostRecentArrayWithSelection:(CommonTagFeature *)feature geometry:(NSString *)geometry
{
	[mostRecentArray removeObject:feature];
	[mostRecentArray insertObject:feature atIndex:0];
	if ( mostRecentArray.count > MOST_RECENT_SAVED_MAXIMUM ) {
		[mostRecentArray removeLastObject];
	}

	NSMutableArray * a = [[NSMutableArray alloc] initWithCapacity:mostRecentArray.count];
	for ( CommonTagFeature * f in mostRecentArray ) {
		[a addObject:f.featureName];
	}

	NSString * defaults = [NSString stringWithFormat:@"mostRecentTypes.%@", geometry];
	[[NSUserDefaults standardUserDefaults] setObject:a forKey:defaults];
}


-(void)updateTagsWithFeature:(CommonTagFeature *)feature
{
	NSString * geometry = [self currentSelectionGeometry];
	[self.delegate typeViewController:self didChangeFeatureTo:feature];
	[self.class updateMostRecentArrayWithSelection:feature geometry:geometry];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( _searchArrayAll ) {
		CommonTagFeature * tagInfo = indexPath.section == 0 ? _searchArrayRecent[ indexPath.row ] : _searchArrayAll[ indexPath.row ];
		[self updateTagsWithFeature:tagInfo];
		[self.navigationController popToRootViewControllerAnimated:YES];
		return;
	}

	if ( _isTopLevel && indexPath.section == 0 ) {
		// most recents
		CommonTagFeature * tagInfo = mostRecentArray[ indexPath.row ];
		[self updateTagsWithFeature:tagInfo];
		[self.navigationController popToRootViewControllerAnimated:YES];
	} else {
		// type list
		id entry = _typeArray[ indexPath.row ];
		if ( [entry isKindOfClass:[CommonTagCategory class]] ) {
			CommonTagCategory * category = entry;
			POITypeViewController * sub = [self.storyboard instantiateViewControllerWithIdentifier:@"PoiTypeViewController"];
			sub.parentCategory	= category;
			sub.delegate		= self.delegate;
			[_searchBar resignFirstResponder];
			[self.navigationController pushViewController:sub animated:YES];
		} else {
			CommonTagFeature * feature = entry;
			[self updateTagsWithFeature:feature];
			[self.navigationController popToRootViewControllerAnimated:YES];
		}
	}
}


- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
	if ( searchText.length == 0 ) {
		// no search
		_searchArrayAll = nil;
		_searchArrayRecent = nil;
		[_searchBar performSelector:@selector(resignFirstResponder) withObject:nil afterDelay:0.1];
	} else {
		// searching
		_searchArrayAll = [[CommonTagList featuresInCategory:_parentCategory matching:searchText] mutableCopy];
		_searchArrayAll = [_searchArrayAll sortedArrayUsingComparator:^NSComparisonResult(CommonTagFeature * t1, CommonTagFeature * t2) {
			BOOL p1 = [t1.friendlyName hasPrefix:searchText];
			BOOL p2 = [t2.friendlyName hasPrefix:searchText];
			if ( p1 != p2 )
				return p2 - p1;
			return [t1.friendlyName compare:t2.friendlyName];
		}];

		_searchArrayRecent = [mostRecentArray filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CommonTagFeature * tagInfo, NSDictionary *bindings) {
			return [tagInfo matchesSearchText:searchText];
		}]];
	}
	[self.tableView reloadData];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if ( buttonIndex == 1 ) {
		UITextField * textField = [alertView textFieldAtIndex:0];
		NSInteger count = [textField.text integerValue];
		if ( count < 0 )
			count = 0;
		else if ( count > 99 )
			count = 99;
		mostRecentMaximum = count;
		[[NSUserDefaults standardUserDefaults] setInteger:mostRecentMaximum forKey:@"mostRecentTypesMaximum"];
	}
}

-(IBAction)configure:(id)sender
{
	UIAlertView * alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Show Recent Items",nil) message:NSLocalizedString(@"Number of recent items to display",nil) delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel",nil) otherButtonTitles:NSLocalizedString(@"OK",nil), nil];
	alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	UITextField * textField = [alert textFieldAtIndex:0];
	[textField setKeyboardType:UIKeyboardTypeNumberPad];
	textField.text = [NSString stringWithFormat:@"%ld",(long)mostRecentMaximum];
	[alert show];
}


-(IBAction)back:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
