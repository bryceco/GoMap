//
//  NewItemController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "iosapi.h"
#import "CommonPresetList.h"
#import "POITabBarController.h"
#import "POIFeaturePickerViewController.h"
#import "PersistentWebCache.h"


static const NSInteger MOST_RECENT_DEFAULT_COUNT = 5;
static const NSInteger MOST_RECENT_SAVED_MAXIMUM = 100;

@implementation POIFeaturePickerViewController

static NSMutableArray	*	mostRecentArray;
static NSInteger			mostRecentMaximum;

static PersistentWebCache * logoCache;	// static so memory cache persists each time we appear


+(void)loadMostRecentForGeometry:(NSString *)geometry
{
	NSNumber * max = [[NSUserDefaults standardUserDefaults] objectForKey:@"mostRecentTypesMaximum"];
	mostRecentMaximum = max ? max.integerValue : MOST_RECENT_DEFAULT_COUNT;

	NSString * defaults = [NSString stringWithFormat:@"mostRecentTypes.%@", geometry];
	NSArray * a = [[NSUserDefaults standardUserDefaults] objectForKey:defaults];
	mostRecentArray = [NSMutableArray arrayWithCapacity:a.count+1];
	for ( NSString * featureName in a ) {
		CommonPresetFeature * tagInfo = [CommonPresetFeature commonPresetFeatureWithName:featureName];
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

	if ( logoCache == nil ) {
		logoCache = [[PersistentWebCache alloc] initWithName:@"presetLogoCache" memorySize:5*1000000];
	}

	self.tableView.estimatedRowHeight = 44.0; // or could use UITableViewAutomaticDimension;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	
	NSString * geometry = [self currentSelectionGeometry];
	if ( geometry == nil )
		geometry = GEOMETRY_NODE;	// a brand new node

	[self.class loadMostRecentForGeometry:geometry];

	if ( _parentCategory == nil ) {
		_isTopLevel = YES;
		_featureList = [CommonPresetList featuresForGeometry:geometry];
	} else {
		_featureList = _parentCategory.members;
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

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
	if ( _isTopLevel && section == 1 ) {
		NSString * countryCode = [AppDelegate getAppDelegate].mapView.countryCodeForLocation;
		return [NSString stringWithFormat:NSLocalizedString(@"Results for country code: %@",nil),countryCode.uppercaseString];
	}
	return nil;
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
			return _featureList.count;
		}
	}
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	CommonPresetFeature * feature = nil;
	if ( _searchArrayAll ) {
		feature = indexPath.section == 0 ? _searchArrayRecent[ indexPath.row ] : _searchArrayAll[ indexPath.row ];
	} else if ( _isTopLevel && indexPath.section == 0 ) {
		// most recents
		feature = mostRecentArray[ indexPath.row ];
	} else {
		// type array
		id tagInfo = _featureList[ indexPath.row ];
		if ( [tagInfo isKindOfClass:[CommonPresetCategory class]] ) {
			CommonPresetCategory * category = tagInfo;
			UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"SubCell" forIndexPath:indexPath];
			cell.textLabel.text = category.friendlyName;
			return cell;
		} else {
			feature = tagInfo;
		}
	}

	if ( feature.suggestion && feature.logoImage == nil && feature.logoURL ) {
		feature.logoImage = feature.icon;

		void(^completion)(UIImage * image) = ^(UIImage * image){
			dispatch_async(dispatch_get_main_queue(), ^{
				feature.logoImage = image;
				UITableViewCell * cell = [self.tableView cellForRowAtIndexPath:indexPath];
				cell.imageView.image = image;
			});
		};
		UIImage * logo = [logoCache objectWithKey:feature.featureName
			fallbackURL:^{
				return feature.logoURL;
			} objectForData:^id _Nonnull(NSData * data) {
				extern UIImage * IconScaledForDisplay(UIImage *icon);
				UIImage * image = [UIImage imageWithData:data];
				return IconScaledForDisplay(image);
			} completion:^(id image) {
				if ( image )
					completion(image);
			}];
		if ( logo ) {
			feature.logoImage = logo;
		}
	}

	NSString * brand = @"☆ ";
	POITabBarController * tabController = (id)self.tabBarController;
	NSString * geometry = [self currentSelectionGeometry];
	NSString * currentFeature = [CommonPresetList featureNameForObjectDict:tabController.keyValueDict geometry:geometry];
	UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"FinalCell" forIndexPath:indexPath];
	cell.textLabel.text			= feature.suggestion ? [brand stringByAppendingString:feature.friendlyName] : feature.friendlyName;
	cell.imageView.image		= feature.logoImage && feature.logoImage != feature.icon
									? feature.logoImage
									: [feature.icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	[cell.imageView setupTintColorForDarkMode];
	cell.imageView.contentMode	= UIViewContentModeScaleAspectFit;
	cell.detailTextLabel.text	= feature.summary;
	cell.accessoryType = [currentFeature isEqualToString:feature.featureName] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

+(void)updateMostRecentArrayWithSelection:(CommonPresetFeature *)feature geometry:(NSString *)geometry
{
	[mostRecentArray removeObject:feature];
	[mostRecentArray insertObject:feature atIndex:0];
	if ( mostRecentArray.count > MOST_RECENT_SAVED_MAXIMUM ) {
		[mostRecentArray removeLastObject];
	}

	NSMutableArray * a = [[NSMutableArray alloc] initWithCapacity:mostRecentArray.count];
	for ( CommonPresetFeature * f in mostRecentArray ) {
		[a addObject:f.featureName];
	}

	NSString * defaults = [NSString stringWithFormat:@"mostRecentTypes.%@", geometry];
	[[NSUserDefaults standardUserDefaults] setObject:a forKey:defaults];
}


-(void)updateTagsWithFeature:(CommonPresetFeature *)feature
{
	NSString * geometry = [self currentSelectionGeometry];
	[self.delegate typeViewController:self didChangeFeatureTo:feature];
	[self.class updateMostRecentArrayWithSelection:feature geometry:geometry];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( _searchArrayAll ) {
		CommonPresetFeature * tagInfo = indexPath.section == 0 ? _searchArrayRecent[ indexPath.row ] : _searchArrayAll[ indexPath.row ];
		[self updateTagsWithFeature:tagInfo];
		[self.navigationController popToRootViewControllerAnimated:YES];
		return;
	}

	if ( _isTopLevel && indexPath.section == 0 ) {
		// most recents
		CommonPresetFeature * tagInfo = mostRecentArray[ indexPath.row ];
		[self updateTagsWithFeature:tagInfo];
		[self.navigationController popToRootViewControllerAnimated:YES];
	} else {
		// type list
		id entry = _featureList[ indexPath.row ];
		if ( [entry isKindOfClass:[CommonPresetCategory class]] ) {
			CommonPresetCategory * category = entry;
			POIFeaturePickerViewController * sub = [self.storyboard instantiateViewControllerWithIdentifier:@"PoiTypeViewController"];
			sub.parentCategory	= category;
			sub.delegate		= self.delegate;
			[_searchBar resignFirstResponder];
			[self.navigationController pushViewController:sub animated:YES];
		} else {
			CommonPresetFeature * feature = entry;
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
	} else {
		// searching
		_searchArrayAll = [[CommonPresetList featuresInCategory:_parentCategory matching:searchText] mutableCopy];
		_searchArrayRecent = [mostRecentArray filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CommonPresetFeature * tagInfo, NSDictionary *bindings) {
			return [tagInfo matchesSearchText:searchText];
		}]];
	}
	[self.tableView reloadData];
}

-(IBAction)configure:(id)sender
{
	UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Show Recent Items",nil) message:NSLocalizedString(@"Number of recent items to display",nil) preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
		[textField setKeyboardType:UIKeyboardTypeNumberPad];
		textField.text = [NSString stringWithFormat:@"%ld",(long)mostRecentMaximum];
	}];
	[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
		UITextField * textField = alert.textFields[0];
		NSInteger count = [textField.text integerValue];
		if ( count < 0 )
			count = 0;
		else if ( count > 99 )
			count = 99;
		mostRecentMaximum = count;
		[[NSUserDefaults standardUserDefaults] setInteger:mostRecentMaximum forKey:@"mostRecentTypesMaximum"];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}


-(IBAction)back:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
