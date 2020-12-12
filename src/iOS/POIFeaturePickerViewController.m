//
//  NewItemController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "iosapi.h"
#import "PersistentWebCache.h"
#import "POITabBarController.h"
#import "POIFeaturePickerViewController.h"
#import "PresetsDatabase.h"


static const NSInteger MOST_RECENT_DEFAULT_COUNT = 5;
static const NSInteger MOST_RECENT_SAVED_MAXIMUM = 100;


@interface FeaturePickerCell : UITableViewCell
@property (strong,atomic)		NSString	* featureID;
@property (assign)	IBOutlet	UILabel 	* title;
@property (assign)	IBOutlet	UILabel 	* details;
@property (assign)	IBOutlet	UIImageView	* image;
@end
@implementation FeaturePickerCell
@end


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
	for ( NSString * featureID in a ) {
		PresetFeature * feature = [PresetsDatabase.shared presetFeatureForFeatureID:featureID];
		if ( feature ) {
			[mostRecentArray addObject:feature];
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
		_featureList = [PresetsDatabase featuresAndCategoriesForGeometry:geometry];
	} else {
		_featureList = _parentCategory.members;
	}
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return UITableViewAutomaticDimension;
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
		NSString * countryCode = AppDelegate.shared.mapView.countryCodeForLocation;
		NSLocale * locale = [NSLocale currentLocale];
		NSString * countryName = [locale displayNameForKey:NSLocaleCountryCode value:countryCode];
        
        if (countryCode.length == 0 || countryName.length == 0) {
            // There's nothing to display.
            return nil;
        }
        
		return [NSString stringWithFormat:NSLocalizedString(@"Results for %@ (%@)",@"country name,2-character country code"),countryName,countryCode.uppercaseString];
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
	PresetFeature * feature = nil;
	if ( _searchArrayAll ) {
		feature = indexPath.section == 0 ? _searchArrayRecent[ indexPath.row ] : _searchArrayAll[ indexPath.row ];
	} else if ( _isTopLevel && indexPath.section == 0 ) {
		// most recents
		feature = mostRecentArray[ indexPath.row ];
	} else {
		// type array
		id tagInfo = _featureList[ indexPath.row ];
		if ( [tagInfo isKindOfClass:[PresetCategory class]] ) {
			PresetCategory * category = tagInfo;
			UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"SubCell" forIndexPath:indexPath];
			cell.textLabel.text = category.friendlyName;
			return cell;
		} else {
			feature = tagInfo;
		}
	}

	if ( feature.nsiSuggestion && feature.nsiLogo == nil && feature.logoURL ) {
#if 0
		// use built-in logo files
		if ( feature.nsiLogo == nil ) {
			feature.nsiLogo = feature.iconUnscaled;
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
				NSString * name = [feature.featureID stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
				NSLog(@"%@",name);
				name = [@"presets/brandIcons/" stringByAppendingString:name];
				NSString * path = [[NSBundle mainBundle] pathForResource:name ofType:@"jpg"]
								?: [[NSBundle mainBundle] pathForResource:name ofType:@"png"]
								?: [[NSBundle mainBundle] pathForResource:name ofType:@"gif"]
								?: [[NSBundle mainBundle] pathForResource:name ofType:@"bmp"]
								?: nil;
				UIImage * image = [UIImage imageWithContentsOfFile:path];
				if ( image ) {
					dispatch_async(dispatch_get_main_queue(), ^{
						feature.nsiLogo = image;
						for ( FeaturePickerCell * cell in self.tableView.visibleCells ) {
							if ( [cell isKindOfClass:[FeaturePickerCell class]] ) {
								if ( cell.featureID == feature.featureID ) {
									cell.image.image = image;
								}
							}
						}
					});
				}
			});
		}
#else
		// download brand logo
		feature.nsiLogo = feature.iconUnscaled;
		UIImage * logo = [logoCache objectWithKey:feature.featureID
			fallbackURL:^{
#if 1
				NSString * name = [feature.featureID stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
				NSString * url = [@"http://gomaposm.com/brandIcons/" stringByAppendingString:name];
				return [NSURL URLWithString:url];
#else
				return [NSURL URLWithString:feature.logoURL];
#endif
			} objectForData:^id _Nonnull(NSData * data) {
				extern UIImage * ImageScaledToSize( UIImage * image, CGFloat iconSize );
				UIImage * image = [UIImage imageWithData:data];
				return ImageScaledToSize( image, 60.0 );
			} completion:^(id image) {
				if ( image ) {
					dispatch_async(dispatch_get_main_queue(), ^{
						feature.nsiLogo = image;
						for ( FeaturePickerCell * cell in self.tableView.visibleCells ) {
							if ( [cell isKindOfClass:[FeaturePickerCell class]] ) {
								if ( cell.featureID == feature.featureID ) {
									cell.image.image = image;
								}
							}
						}
					});
				}
			}];
		if ( logo ) {
			feature.nsiLogo = logo;
		}
#endif
	}

	NSString * brand = @"☆ ";
	POITabBarController * tabController = (id)self.tabBarController;
	NSString * geometry = [self currentSelectionGeometry];
	PresetFeature * currentFeature = [PresetsDatabase.shared matchObjectTagsToFeature:tabController.keyValueDict
																 geometry:geometry
																includeNSI:YES];
	FeaturePickerCell * cell = [tableView dequeueReusableCellWithIdentifier:@"FinalCell" forIndexPath:indexPath];
	cell.title.text			= feature.nsiSuggestion ? [brand stringByAppendingString:feature.friendlyName] : feature.friendlyName;
	cell.image.image		= feature.nsiLogo && feature.nsiLogo != feature.iconUnscaled
									? feature.nsiLogo
									: [feature.iconUnscaled imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	if (@available(iOS 13.0, *)) {
		cell.image.tintColor = UIColor.labelColor;
	} else {
		cell.image.tintColor = UIColor.blackColor;
	}
	cell.image.contentMode = UIViewContentModeScaleAspectFit;
	[cell setNeedsUpdateConstraints];
	cell.details.text	= feature.summary;
	cell.accessoryType = currentFeature == feature ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	cell.featureID = feature.featureID;
	return cell;
}

+(void)updateMostRecentArrayWithSelection:(PresetFeature *)feature geometry:(NSString *)geometry
{
	[mostRecentArray filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PresetFeature * f, id bindings) {
		return ! [f.featureID isEqualToString:feature.featureID];
	}]];
	[mostRecentArray insertObject:feature atIndex:0];
	if ( mostRecentArray.count > MOST_RECENT_SAVED_MAXIMUM ) {
		[mostRecentArray removeLastObject];
	}

	NSMutableArray * a = [[NSMutableArray alloc] initWithCapacity:mostRecentArray.count];
	for ( PresetFeature * f in mostRecentArray ) {
		[a addObject:f.featureID];
	}

	NSString * defaults = [NSString stringWithFormat:@"mostRecentTypes.%@", geometry];
	[[NSUserDefaults standardUserDefaults] setObject:a forKey:defaults];
}


-(void)updateTagsWithFeature:(PresetFeature *)feature
{
	NSString * geometry = [self currentSelectionGeometry];
	[self.delegate typeViewController:self didChangeFeatureTo:feature];
	[self.class updateMostRecentArrayWithSelection:feature geometry:geometry];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( _searchArrayAll ) {
		PresetFeature * feature = indexPath.section == 0 ? _searchArrayRecent[ indexPath.row ] : _searchArrayAll[ indexPath.row ];
		[self updateTagsWithFeature:feature];
		[self.navigationController popToRootViewControllerAnimated:YES];
		return;
	}

	if ( _isTopLevel && indexPath.section == 0 ) {
		// most recents
		PresetFeature * feature = mostRecentArray[ indexPath.row ];
		[self updateTagsWithFeature:feature];
		[self.navigationController popToRootViewControllerAnimated:YES];
	} else {
		// type list
		id entry = _featureList[ indexPath.row ];
		if ( [entry isKindOfClass:[PresetCategory class]] ) {
			PresetCategory * category = entry;
			POIFeaturePickerViewController * sub = [self.storyboard instantiateViewControllerWithIdentifier:@"PoiTypeViewController"];
			sub.parentCategory	= category;
			sub.delegate		= self.delegate;
			[_searchBar resignFirstResponder];
			[self.navigationController pushViewController:sub animated:YES];
		} else {
			PresetFeature * feature = entry;
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
		_searchArrayAll = [[PresetsDatabase featuresInCategory:_parentCategory matching:searchText] mutableCopy];
		_searchArrayRecent = [mostRecentArray filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PresetFeature * feature, NSDictionary *bindings) {
			return [feature matchesSearchText:searchText];
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
