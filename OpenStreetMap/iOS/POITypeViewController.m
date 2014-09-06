//
//  NewItemController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "iosapi.h"
#import "OsmObjects.h"
#import "POITabBarController.h"
#import "POITypeViewController.h"
#import "TagInfo.h"


static const NSInteger MOST_RECENT_DEFAULT_COUNT = 5;
static const NSInteger MOST_RECENT_SAVED_MAXIMUM = 100;

@implementation POITypeViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	POITabBarController * tabController = (id)self.tabBarController;

	NSString * type = tabController.selection.isWay && ![(OsmWay *)tabController.selection isArea] ? @"way" : @"node";
	if ( _parentName == nil ) {
		_isTopLevel = YES;
		_parentName = nil;
	}
	_typeArray = [[TagInfoDatabase sharedTagInfoDatabase] subitemsOfType:type belongTo:_parentName];

	NSNumber * max = [[NSUserDefaults standardUserDefaults] objectForKey:@"mostRecentTypesMaximum"];
	_mostRecentMaximum = max ? max.integerValue : MOST_RECENT_DEFAULT_COUNT;

	NSArray * a = [[NSUserDefaults standardUserDefaults] objectForKey:@"mostRecentTypes"];
	_mostRecentArray = [NSMutableArray arrayWithCapacity:a.count+1];
	for ( NSArray * kv in a ) {
		TagInfo * tagInfo = [[TagInfoDatabase sharedTagInfoDatabase] tagInfoForKey:kv[0] value:kv[1]];
		if ( tagInfo ) {
			[_mostRecentArray addObject:tagInfo];
		}
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
			NSInteger count = _mostRecentArray.count;
			return count < _mostRecentMaximum ? count : _mostRecentMaximum;
		} else {
			return _typeArray.count;
		}
	}
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( _searchArrayAll ) {
		UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"FinalCell" forIndexPath:indexPath];
		TagInfo * tagInfo = indexPath.section == 0 ? _searchArrayRecent[ indexPath.row ] : _searchArrayAll[ indexPath.row ];
		NSString * text = tagInfo.friendlyName2;
		cell.textLabel.text = text;
		cell.imageView.image = tagInfo.icon;
		cell.detailTextLabel.text = tagInfo.summary;
		return cell;
	}

	if ( _isTopLevel && indexPath.section == 0 ) {
		// most recents
		UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"FinalCell" forIndexPath:indexPath];
		TagInfo * tagInfo = _mostRecentArray[ indexPath.row ];
		cell.textLabel.text = tagInfo.friendlyName2;
		cell.imageView.image = tagInfo.icon;
		cell.detailTextLabel.text = tagInfo.summary;
		cell.accessoryType = UITableViewCellAccessoryNone;
		return cell;
	} else {
		// type array
		id type = _typeArray[ indexPath.row ];
		if ( [type isKindOfClass:[NSString class]] ) {
			UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"SubCell" forIndexPath:indexPath];
			NSString * text = type;
			text = [text stringByReplacingOccurrencesOfString:@"_" withString:@" "];
			text = text.capitalizedString;
			cell.textLabel.text = text;
			return cell;
		} else {
			UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"FinalCell" forIndexPath:indexPath];
			TagInfo * tagInfo = _typeArray[ indexPath.row ];
			cell.textLabel.text = tagInfo.friendlyName ?: tagInfo.friendlyName2;
			cell.imageView.image = tagInfo.icon;
			cell.detailTextLabel.text = tagInfo.summary;
			POITabBarController * tabController = (id)self.tabBarController;
			BOOL selected = [[tabController.keyValueDict valueForKey:tagInfo.key] isEqualToString:tagInfo.value];
			cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
			return cell;
		}
	}
}

-(void)updateMostRecentArrayWithSelection:(TagInfo *)tagInfo
{
	[_mostRecentArray removeObject:tagInfo];
	[_mostRecentArray insertObject:tagInfo atIndex:0];
	if ( _mostRecentArray.count > MOST_RECENT_SAVED_MAXIMUM ) {
		[_mostRecentArray removeLastObject];
	}

	NSMutableArray * a = [[NSMutableArray alloc] initWithCapacity:_mostRecentArray.count];
	for ( tagInfo in _mostRecentArray ) {
		NSArray * kv = @[ tagInfo.key, tagInfo.value ];
		[a addObject:kv];
	}
	[[NSUserDefaults standardUserDefaults] setObject:a forKey:@"mostRecentTypes"];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( _searchArrayAll ) {
		TagInfo * tagInfo = indexPath.section == 0 ? _searchArrayRecent[ indexPath.row ] : _searchArrayAll[ indexPath.row ];
		POITabBarController * tabController = (id) self.tabBarController;
		[tabController setType:tagInfo.key value:tagInfo.value byUser:YES];
		[self updateMostRecentArrayWithSelection:tagInfo];
		[self.navigationController popToRootViewControllerAnimated:YES];
		return;
	}

	if ( _isTopLevel && indexPath.section == 0 ) {
		// mose recents
		TagInfo * tagInfo = _mostRecentArray[ indexPath.row ];
		POITabBarController * tabController = (id) self.tabBarController;
		[tabController setType:tagInfo.key value:tagInfo.value byUser:YES];
		[self updateMostRecentArrayWithSelection:tagInfo];
		[self.navigationController popToRootViewControllerAnimated:YES];
	} else {
		// type list
		id type = _typeArray[ indexPath.row ];
		if ( [type isKindOfClass:[NSString class]] ) {
			POITypeViewController * sub = [self.storyboard instantiateViewControllerWithIdentifier:@"PoiTypeViewController"];
			sub.parentName = type;
			[_searchBar resignFirstResponder];
			[self.navigationController pushViewController:sub animated:YES];
		} else {
			TagInfo * tagInfo = type;
			POITabBarController * tabController = (id) self.tabBarController;
			[tabController setType:tagInfo.key value:tagInfo.value byUser:YES];
			[self updateMostRecentArrayWithSelection:tagInfo];
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
		_searchArrayAll = [[TagInfoDatabase sharedTagInfoDatabase] itemsForTag:_parentName matching:searchText];
		_searchArrayAll = [_searchArrayAll sortedArrayUsingComparator:^NSComparisonResult(TagInfo * t1, TagInfo * t2) {
			BOOL p1 = [t1.value hasPrefix:searchText];
			BOOL p2 = [t2.value hasPrefix:searchText];
			if ( p1 != p2 )
				return p2 - p1;
			return [t1.value compare:t2.value];
		}];

		// place items in order of most recent list
		_searchArrayRecent = [_mostRecentArray filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TagInfo * tagInfo, NSDictionary *bindings) {
			return [tagInfo.value rangeOfString:searchText].location != NSNotFound;
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
		_mostRecentMaximum = count;
		[[NSUserDefaults standardUserDefaults] setInteger:_mostRecentMaximum forKey:@"mostRecentTypesMaximum"];
	}
}

-(IBAction)configure:(id)sender
{
	UIAlertView * alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Show Recent Items",nil) message:NSLocalizedString(@"Number of recent items to display",nil) delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel",nil) otherButtonTitles:NSLocalizedString(@"OK",nil), nil];
	alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	UITextField * textField = [alert textFieldAtIndex:0];
	[textField setKeyboardType:UIKeyboardTypeNumberPad];
	textField.text = [NSString stringWithFormat:@"%ld",(long)_mostRecentMaximum];
	[alert show];
}


-(IBAction)back:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
