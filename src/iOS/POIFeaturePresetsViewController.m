//
//  POIDetailsViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "AutocompleteTextField.h"
#import "DLog.h"
#import "EditorMapLayer.h"
#import "HeightViewController.h"
#import "MapView.h"
#import "OsmMapData.h"
#import "POIFeaturePresetsViewController.h"
#import "POIPresetValuePickerController.h"
#import "POITabBarController.h"
#import "POIFeaturePickerViewController.h"
#import "RenderInfo.h"


@interface FeaturePresetCell : UITableViewCell
@property (assign,nonatomic)	IBOutlet	UILabel						*	nameLabel;
@property (assign,nonatomic)	IBOutlet	AutocompleteTextField		*	valueField;
@property (strong,nonatomic)				PresetKey					*	presetKey;
@end

@implementation FeaturePresetCell
@end

@implementation POIFeaturePresetsViewController


- (void)viewDidLoad
{
	// have to update presets before call super because super asks for the number of sections
	[self updatePresets];

	[super viewDidLoad];

	self.tableView.estimatedRowHeight = 44.0; // or could use UITableViewAutomaticDimension;
	self.tableView.rowHeight = UITableViewAutomaticDimension;

	if ( _drillDownGroup ) {
		self.navigationItem.leftItemsSupplementBackButton = YES;
		self.navigationItem.leftBarButtonItem = nil;
		self.navigationItem.title = _drillDownGroup.name;
	}
}

-(void)updatePresets
{
	POITabBarController * tabController = (id)self.tabBarController;

	_saveButton.enabled = [tabController isTagDictChanged];
	if (@available(iOS 13.0, *)) {
		self.tabBarController.modalInPresentation = _saveButton.enabled;
	}

	if ( _drillDownGroup == nil ) {

		NSDictionary * dict = tabController.keyValueDict;
		OsmBaseObject * object = tabController.selection;
		NSString * geometry = object ? [object geometryName] : GEOMETRY_NODE;

		// update most recent feature
		PresetFeature * feature = _selectedFeature ?: [PresetsDatabase.shared matchObjectTagsToFeature:dict
																				   geometry:geometry
																				  includeNSI:YES];
		if ( feature ) {
			[POIFeaturePickerViewController loadMostRecentForGeometry:geometry];
			[POIFeaturePickerViewController updateMostRecentArrayWithSelection:feature geometry:geometry];
		}

		__weak POIFeaturePresetsViewController * weakSelf = self;

		_allPresets = [[PresetsForFeature alloc] initWithFeature:feature objectTags:dict geometry:geometry update:^{
				// this may complete much later, even after we've been dismissed
				POIFeaturePresetsViewController * mySelf = weakSelf;
				if ( mySelf && !mySelf->_isEditing ) {
					mySelf->_allPresets = [[PresetsForFeature alloc] initWithFeature:feature objectTags:dict geometry:geometry update:nil];
					[mySelf.tableView reloadData];
				}
			}];
	}

	[self.tableView reloadData];
}

#pragma mark display

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	if ( [self isMovingToParentViewController] ) {
	} else {
		[self updatePresets];
	}
}
-(void)viewWillDisappear:(BOOL)animated
{
	[self resignAll];
	[super viewWillDisappear:animated];
	_selectedFeature = nil;
	_childPushed = YES;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (![self isMovingToParentViewController]) {
        // special case: if this is a new object and the user just selected the feature to be shop/amenity,
        // then automatically select the Name field as the first responder
		POITabBarController * tabController = (id)self.tabBarController;
        if ( tabController.isTagDictChanged ) {
            NSDictionary * dict = tabController.keyValueDict;
            if ( dict.count == 1 && (dict[@"shop"] || dict[@"amenity"]) && dict[@"name"] == nil ) {
                // find name field and make it first responder
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSIndexPath * index = [NSIndexPath indexPathForRow:1 inSection:0];
                    FeaturePresetCell * cell = [self.tableView cellForRowAtIndexPath:index];
                    if ( cell && [cell.presetKey.tagKey isEqualToString:@"name"] ) {
                        [cell.valueField becomeFirstResponder];
                    }
                });
            }
		} else if ( !_childPushed &&
				   tabController.selection.ident.longLongValue <= 0 &&
				   tabController.keyValueDict.count == 0 )
		{
			// if we're being displayed for a newly created node then go straight to the Type picker
			[self performSegueWithIdentifier:@"POITypeSegue" sender:nil];
		}
	}
}

-(void)typeViewController:(POIFeaturePickerViewController *)typeViewController didChangeFeatureTo:(PresetFeature *)feature
{
	_selectedFeature = feature;
	POITabBarController * tabController = (id) self.tabBarController;
	NSString * geometry = tabController.selection ? [tabController.selection geometryName] : GEOMETRY_NODE;
	PresetFeature * oldFeature = [PresetsDatabase.shared matchObjectTagsToFeature:tabController.keyValueDict
																		 geometry:geometry
																	   includeNSI:YES];

	// remove previous feature tags
	NSDictionary * removeTags = oldFeature.removeTags;
	[removeTags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop) {
		[tabController setFeatureKey:key value:nil];
	}];

	// add new feature tags
	NSDictionary * defaults = [feature defaultValuesForGeometry:geometry];
	[defaults enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop) {
		if ( tabController.keyValueDict[key] == nil ) {
			[tabController setFeatureKey:key value:value];
		}
	}];

	[feature.addTags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop) {
		if ( [value isEqualToString:@"*"] )
			value = @"yes";
		[tabController setFeatureKey:key value:value];
	}];
}

#pragma mark - Table view data source


- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return _drillDownGroup ? 1 : _allPresets.sectionCount + 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	if ( _drillDownGroup )
		return _drillDownGroup.name;
	if ( section == _allPresets.sectionCount )
		return nil;
	if ( section > _allPresets.sectionCount )
		return nil;
	PresetGroup * group = [_allPresets groupAtIndex:section];
	return group.name;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if ( _drillDownGroup )
		return _drillDownGroup.presetKeys.count;
	if ( section == _allPresets.sectionCount )
		return 1;
	if ( section > _allPresets.sectionCount )
		return 0;
	return [_allPresets tagsInSection:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( _drillDownGroup == nil ) {
		if ( indexPath.section == _allPresets.sectionCount ) {
			UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:@"CustomizePresets" forIndexPath:indexPath];
			return cell;
		}
	}

	id rowObject = _drillDownGroup ? _drillDownGroup.presetKeys[ indexPath.row ] : [_allPresets presetAtIndexPath:indexPath];
	if ( [rowObject isKindOfClass:[PresetKey class]] ) {

		PresetKey 	* presetKey	= rowObject;
		NSString * key = presetKey.tagKey;
		NSString * cellName = key.length == 0 ? @"CommonTagType"
							: [key isEqualToString:@"name"] ? @"CommonTagName"
							: @"CommonTagSingle";

		FeaturePresetCell * cell = [tableView dequeueReusableCellWithIdentifier:cellName forIndexPath:indexPath];
		cell.nameLabel.text = presetKey.name;
		cell.valueField.placeholder = presetKey.placeholder;
		cell.valueField.delegate = self;
		cell.presetKey = presetKey;

		cell.valueField.keyboardType = presetKey.keyboardType;
		cell.valueField.autocapitalizationType = presetKey.autocapitalizationType;
		[cell.valueField removeTarget:self action:NULL forControlEvents:UIControlEventAllEvents];
		[cell.valueField addTarget:self action:@selector(textFieldReturn:)			forControlEvents:UIControlEventEditingDidEndOnExit];
		[cell.valueField addTarget:self action:@selector(textFieldChanged:)			forControlEvents:UIControlEventEditingChanged];
		[cell.valueField addTarget:self action:@selector(textFieldEditingDidBegin:)	forControlEvents:UIControlEventEditingDidBegin];
		[cell.valueField addTarget:self action:@selector(textFieldDidEndEditing:)	forControlEvents:UIControlEventEditingDidEnd];
        
		if ( presetKey.presetList.count > 0 || key.length == 0 ) {
			// The user can select from a list of presets.
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		} else if ( [self canMeasureDirectionForKey:presetKey] ) {
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		} else if ( [self canMeasureHeightForKey:presetKey] ) {
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		} else {
            cell.accessoryType = UITableViewCellAccessoryNone;
        }

		POITabBarController	* tabController = (id)self.tabBarController;
		NSDictionary * objectDict = tabController.keyValueDict;

		if ( _drillDownGroup == nil && indexPath.section == 0 && indexPath.row == 0 ) {
			// Type cell
			NSString * text = [_allPresets featureName];
			cell.valueField.text = text;
			cell.valueField.enabled = NO;
		} else {
			// Regular cell
			NSString * value = objectDict[ presetKey.tagKey ];
			value = [presetKey prettyNameForTagValue:value];
			cell.valueField.text = value;
			cell.valueField.enabled = YES;
		}

		return cell;

	} else {

		// drill down cell
		PresetGroup * drillDownGroup = rowObject;
		FeaturePresetCell * cell = [tableView dequeueReusableCellWithIdentifier:@"CommonTagDrillDown" forIndexPath:indexPath];
		cell.nameLabel.text = drillDownGroup.name;
		cell.presetKey = (id)drillDownGroup;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

		return cell;
	}
}

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	FeaturePresetCell * cell = (id) [tableView cellForRowAtIndexPath:indexPath];
	if ( cell.accessoryType == UITableViewCellAccessoryNone )
		return;
    
    // This workaround is necessary because `tableView:cellForRowAtIndexPath:`
    // currently sets `cell.commonPreset` to an instance of `CommonPresetGroup` by casting it to `id`.
    PresetKey *presetKey = nil;
    if ([cell.presetKey isKindOfClass:[PresetKey class]]) {
        presetKey = cell.presetKey;
    }

	if ( _drillDownGroup == nil && indexPath.section == 0 && indexPath.row == 0 ) {
		[self performSegueWithIdentifier:@"POITypeSegue" sender:cell];
	} else if ( [cell.presetKey isKindOfClass:[PresetGroup class]] ) {
		// special case for drill down
		PresetGroup * group = (id)cell.presetKey;
		POIFeaturePresetsViewController * sub = [self.storyboard instantiateViewControllerWithIdentifier:@"PoiCommonTagsViewController"];
		sub.drillDownGroup = group;
		[self.navigationController pushViewController:sub animated:YES];
	} else if ([self canMeasureDirectionForKey:presetKey]) {
		[self measureDirectionForKey:cell.presetKey.tagKey
													value:cell.valueField.text];
	} else if ([self canMeasureHeightForKey:presetKey]) {
		[self measureHeightForKey:cell.presetKey.tagKey];
	} else {
		[self performSegueWithIdentifier:@"POIPresetSegue" sender:cell];
	}
}
-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
	FeaturePresetCell * cell = sender;
	if ( [segue.destinationViewController isKindOfClass:[POIPresetValuePickerController class]] ) {
		POIPresetValuePickerController * preset = segue.destinationViewController;
		preset.tag = cell.presetKey.tagKey;
		preset.valueDefinitions = cell.presetKey.presetList;
		preset.navigationItem.title = cell.presetKey.name;
	} else if ( [segue.destinationViewController isKindOfClass:[POIFeaturePickerViewController class]] ) {
		POIFeaturePickerViewController * dest = (id)segue.destinationViewController;
		dest.delegate = self;
	}
}

-(IBAction)cancel:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction)done:(id)sender
{
	[self resignAll];
	[self dismissViewControllerAnimated:YES completion:nil];

	POITabBarController * tabController = (id)self.tabBarController;
	[tabController commitChanges];
}

#pragma mark - Table view delegate


- (void)resignAll
{
	if ( self.tableView.window == nil )
		return;
	for (FeaturePresetCell * cell in self.tableView.visibleCells) {
		[cell.valueField resignFirstResponder];
	}
}


- (IBAction)textFieldReturn:(id)sender
{
	[sender resignFirstResponder];
}

-(FeaturePresetCell *)cellForTextField:(UITextField *)textField
{
	FeaturePresetCell * cell = (id) [textField superview];
	while ( cell && ![cell isKindOfClass:[FeaturePresetCell class]] ) {
		cell = (id)cell.superview;
	}
	return cell;
}

- (IBAction)textFieldEditingDidBegin:(AutocompleteTextField *)textField
{
	if ( [textField isKindOfClass:[AutocompleteTextField class]] ) {

		// get list of values for current key
		FeaturePresetCell * cell = [self cellForTextField:textField];
		NSString * key = cell.presetKey.tagKey;
		if ( key == nil )
			return;	// should never happen
		if ( [PresetsDatabase.shared eligibleForAutocomplete:key] ) {
			NSSet * set = [PresetsDatabase.shared allTagValuesForKey:key];
			AppDelegate * appDelegate = AppDelegate.shared;
			NSMutableSet<NSString *> * values = [appDelegate.mapView.editorLayer.mapData tagValuesForKey:key];
			[values addObjectsFromArray:[set allObjects]];
			NSArray * list = [values allObjects];
			textField.autocompleteStrings = list;
		}
	}
	_isEditing = YES;
}

- (IBAction)textFieldChanged:(UITextField *)textField
{
	_saveButton.enabled = YES;
	if (@available(iOS 13.0, *)) {
		self.tabBarController.modalInPresentation = _saveButton.enabled;
	}
}

- (IBAction)textFieldDidEndEditing:(UITextField *)textField
{
	FeaturePresetCell * cell = [self cellForTextField:textField];
	NSString * key = cell.presetKey.tagKey;
	if ( key == nil )
		return;	// should never happen

	NSString * prettyValue = textField.text;
	prettyValue = [prettyValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	textField.text = prettyValue;

	// convert to raw value if necessary
	NSString * tagValue = [cell.presetKey tagValueForPrettyName:prettyValue];
	_isEditing = NO;
    [self updateTagWithValue:tagValue forKey:key];
}

- (void)updateTagWithValue:(NSString *)value forKey:(NSString *)key {
    POITabBarController * tabController = (id)self.tabBarController;
    
    if ( value.length ) {
        [tabController.keyValueDict setObject:value forKey:key];
    } else {
        [tabController.keyValueDict removeObjectForKey:key];
    }
    
    _saveButton.enabled = [tabController isTagDictChanged];
	if (@available(iOS 13.0, *)) {
		self.tabBarController.modalInPresentation = _saveButton.enabled;
	}
}

-(BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
	const int MAX_LENGTH = 255;
    NSUInteger oldLength = [textField.text length];
    NSUInteger replacementLength = [string length];
    NSUInteger rangeLength = range.length;
    NSUInteger newLength = oldLength - rangeLength + replacementLength;
    BOOL returnKey = [string rangeOfString: @"\n"].location != NSNotFound;
    return newLength <= MAX_LENGTH || returnKey;
}

/**
 Determines whether the `DirectionViewController` can be used to measure the value for the tag with the given key.
 
 @param key The key of the tag that should be measured.
 @return YES if the key can be measured using the `DirectionViewController`, NO if not.
 */
- (BOOL)canMeasureDirectionForKey:(PresetKey *)key
{
	if ( key.presetList.count > 0 )
		return NO;
    NSArray<NSString *> *keys = @[@"direction", @"camera:direction"];
    if ( [keys containsObject:key.tagKey] )
		return YES;
	return NO;
}

- (void)measureDirectionForKey:(NSString *)key value:(NSString *)value
{
    DirectionViewController *directionViewController = [[DirectionViewController alloc] initWithKey:key
                                                                                              value:value
																						   setValue:^(NSString * newValue) {
		[self updateTagWithValue:newValue forKey:key];
	}];
    [self.navigationController pushViewController:directionViewController animated:YES];
}

- (BOOL)canMeasureHeightForKey:(PresetKey *)key
{
	return key.presetList.count == 0 && [key.tagKey isEqualToString:@"height"];
}
- (void)measureHeightForKey:(NSString *)key
{
	if ( [HeightViewController unableToInstantiateWithUserWarning:self] ) {
		return;
	}
	HeightViewController * vc = [HeightViewController instantiate];
	vc.callback = ^(NSString *newValue) {
		[self updateTagWithValue:newValue forKey:key];
	};
	[self.navigationController pushViewController:vc animated:YES];
}

@end
