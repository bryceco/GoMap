//
//  POIDetailsViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "AutocompleteTextField.h"
#import "CommonTagList.h"
#import "DLog.h"
#import "EditorMapLayer.h"
#import "MapView.h"
#import "OsmMapData.h"
#import "OsmObjects.h"
#import "POICommonTagsViewController.h"
#import "POIPresetViewController.h"
#import "POITabBarController.h"
#import "POITabBarController.h"
#import "TagInfo.h"
#import "UITableViewCell+FixConstraints.h"


@interface CommonTagCell : UITableViewCell
@property (assign,nonatomic)	IBOutlet	UILabel					*	nameLabel;
@property (assign,nonatomic)	IBOutlet	UILabel					*	nameLabel2;
@property (assign,nonatomic)	IBOutlet	AutocompleteTextField	*	valueField;
@property (assign,nonatomic)	IBOutlet	AutocompleteTextField	*	valueField2;
@property (strong,nonatomic)				CommonTag				*	commonTag;
@property (strong,nonatomic)				CommonTag				*	commonTag2;
@end

@implementation CommonTagCell
@end



@implementation POICommonTagsViewController


- (void)viewDidLoad
{
    [super viewDidLoad];

	_tags = [CommonTagList new];
}

- (void)loadState
{
	POITabBarController	* tabController = (id)self.tabBarController;
	_saveButton.enabled = [tabController isTagDictChanged];
}

- (NSString *)typeKeyForDict:(NSDictionary *)dict
{
	for ( NSString * tag in [OsmBaseObject typeKeys] ) {
		NSString * value = dict[ tag ];
		if ( value.length ) {
			return tag;
		}
	}
	return nil;
}
- (NSString *)typeStringForDict:(NSDictionary *)dict
{
	NSString * tag = [self typeKeyForDict:dict];
	NSString * value = dict[ tag ];
	if ( value.length ) {
		NSString * text = [NSString stringWithFormat:@"%@ (%@)", value, tag];
		text = [text stringByReplacingOccurrencesOfString:@"_" withString:@" "];
		text = text.capitalizedString;
		return text;
	}
	return nil;
}

#pragma mark - Table view data source

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	[cell fixConstraints];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	// Fix bug on iPad where cell heights come back as -1:
	// CGFloat h = [super tableView:tableView heightForRowAtIndexPath:indexPath];
	return 44.0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	CommonGroup * group = [_tags groupAtIndex:section];
	return group.name;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return _tags.sectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return [_tags tagsInSection:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( YES ) {

		
		NSString * key = [_tags tagAtIndexPath:indexPath].tagKey;
		NSString * cellName = key == nil || [key isEqualToString:@"name"] ? @"CommonTagType" : @"CommonTagSingle";

		CommonTagCell * cell = [tableView dequeueReusableCellWithIdentifier:cellName forIndexPath:indexPath];
		CommonTag * commonTag = [_tags tagAtIndexPath:indexPath];
		cell.nameLabel.text = commonTag.name;
		cell.valueField.placeholder = commonTag.placeholder;
		cell.valueField.delegate = self;
		cell.valueField.textColor = [UIColor colorWithRed:0.22 green:0.33 blue:0.53 alpha:1.0];
		cell.commonTag = commonTag;

		[cell.valueField removeTarget:self action:NULL forControlEvents:UIControlEventAllEvents];
		[cell.valueField addTarget:self action:@selector(textFieldReturn:)			forControlEvents:UIControlEventEditingDidEndOnExit];
		[cell.valueField addTarget:self action:@selector(textFieldChanged:)			forControlEvents:UIControlEventEditingChanged];
		[cell.valueField addTarget:self action:@selector(textFieldEditingDidBegin:)	forControlEvents:UIControlEventEditingDidBegin];

		cell.accessoryType = commonTag.presetList.count ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;

		POITabBarController	* tabController = (id)self.tabBarController;
		NSDictionary * dict = tabController.keyValueDict;

		if ( indexPath.section == 0 && indexPath.row == 0 ) {
			// Type cell
			cell.valueField.text = [self typeStringForDict:dict];
			cell.valueField.enabled = NO;
		} else {
			// Regular cell
			cell.valueField.text = dict[ commonTag.tagKey ];
			cell.valueField.enabled = YES;
		}

		return cell;

	} else {

		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CommonTagDouble" forIndexPath:indexPath];
		return cell;
	}
}

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	CommonTagCell * cell = (id) [tableView cellForRowAtIndexPath:indexPath];
	if ( cell.accessoryType == UITableViewCellAccessoryNone )
		return;
	if ( indexPath.section == 0 && indexPath.row == 0 ) {
		[self performSegueWithIdentifier:@"POITypeSegue" sender:cell];
	} else {
		[self performSegueWithIdentifier:@"POIPresetSegue" sender:cell];
	}
}
-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
	CommonTagCell * cell = sender;
	if ( [segue.destinationViewController isKindOfClass:[POIPresetViewController class]] ) {
		POIPresetViewController * preset = segue.destinationViewController;
		preset.tag = cell.commonTag.tagKey;
		preset.valueDefinitions = cell.commonTag.presetList;
		preset.navigationItem.title = cell.commonTag.name;
	}
}

#if 0
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 && indexPath.row == 0 )
		return NO;
	return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.row == [_tags tagsInSection:indexPath.section]-1 )
		return UITableViewCellEditingStyleInsert;
	else
		return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (editingStyle == UITableViewCellEditingStyleDelete) {
		// Delete the row from the data source
		[_tags removeTagAtIndexPath:indexPath];
		[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
	} else if (editingStyle == UITableViewCellEditingStyleInsert) {
		// Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
	}
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath
{
	CommonTag * tag = [_tags tagAtIndexPath:fromIndexPath];
	[_tags removeTagAtIndexPath:fromIndexPath];
	[_tags insertTag:tag atIndexPath:toIndexPath];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ( indexPath.section == 0 && indexPath.row == 0 )
		return NO;
//	if ( indexPath.section == 4 && indexPath.row == _tags.list.count-1 )
//		return NO;
	return YES;
}
#endif

#pragma mark display

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	[self loadState];

	if ( [self isMovingToParentViewController] ) {
	} else {
		// reload cells when coming back from preset picker
		POITabBarController * tabController = (id)self.tabBarController;
		NSDictionary * dict = tabController.keyValueDict;

		OsmBaseObject * object = tabController.selection;
		NSString * geometry = object.isWay ? ((OsmWay *)object).isArea ? GEOMETRY_AREA : GEOMETRY_WAY :
							object.isNode ? ((OsmNode *)object).wayCount > 0 ? GEOMETRY_VERTEX : GEOMETRY_NODE :
							object.isRelation ? ((OsmRelation *)object).isMultipolygon ? GEOMETRY_AREA : GEOMETRY_WAY :
							@"unkown";

		NSString * key = [self typeKeyForDict:dict];
		[_tags setPresetsForKey:key value:dict[key] geometry:geometry];
		[self.tableView reloadData];
#if 0
		for ( CommonTagCell * cell in self.tableView.visibleCells ) {
			if ( cell.commonTag.tag == nil ) {
				// type cell
				cell.valueField.text = [self typeStringForDict:dict];
			} else {
				cell.valueField.text = dict[ cell.commonTag.tag ];
			}
		}
#endif
	}
}

-(void)viewWillDisappear:(BOOL)animated
{
	[self resignAll];
	[super viewWillDisappear:animated];
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
	for (CommonTagCell * cell in self.tableView.visibleCells) {
		[cell.valueField resignFirstResponder];
		[cell.valueField2 resignFirstResponder];
	}
}


- (IBAction)textFieldReturn:(id)sender
{
	[sender resignFirstResponder];
}

-(CommonTagCell *)cellForTextField:(UITextField *)textField
{
	CommonTagCell * cell = (id) [textField superview];
	while ( cell && ![cell isKindOfClass:[CommonTagCell class]] ) {
		cell = (id)cell.superview;
	}
	return cell;
}

- (IBAction)textFieldEditingDidBegin:(UITextField *)textField
{
	if ( [textField isKindOfClass:[AutocompleteTextField class]] ) {

		// get list of values for current key
		CommonTagCell * cell = [self cellForTextField:textField];
		NSString * key = cell.commonTag.tagKey;
		if ( key == nil )
			return;	// should never happen
		NSSet * set = [[TagInfoDatabase sharedTagInfoDatabase] allTagValuesForKey:key];
		AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
		NSMutableSet * values = [appDelegate.mapView.editorLayer.mapData tagValuesForKey:key];
		[values addObjectsFromArray:[set allObjects]];
		NSArray * list = [values allObjects];
		[(AutocompleteTextField *)textField setCompletions:list];
	}
}

- (IBAction)textFieldChanged:(UITextField *)textField
{
	_saveButton.enabled = YES;
}

- (IBAction)textFieldDidEndEditing:(UITextField *)textField
{
	CommonTagCell * cell = [self cellForTextField:textField];
	NSString * key = cell.commonTag.tagKey;
	if ( key == nil )
		return;	// should never happen
	NSString * value = textField.text;
	value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	textField.text = value;

	POITabBarController * tabController = (id)self.tabBarController;

	if ( value.length ) {
		[tabController.keyValueDict setObject:value forKey:key];
	} else {
		[tabController.keyValueDict removeObjectForKey:key];
	}

	_saveButton.enabled = [tabController isTagDictChanged];
}

@end
