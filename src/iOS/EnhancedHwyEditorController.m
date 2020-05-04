//
//  EnhancedHwyEditorController.m
//  Go Kaart!!
//
//  Created by Zack LaVergne on 6/20/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "EnhancedHwyEditorController.h"

#import "AppDelegate.h"
#import "AutocompleteTextField.h"
#import "EditorMapLayer.h"
#import "MapView.h"
#import "MapViewController.h"
#import "OsmNotesDatabase.h"
#import "OsmMapData.h"
#import "OsmMapData+Edit.h"
#import "OsmObjects.h"

typedef enum {
    EMPTY = -2,
    BACKWARD = -1,
    NONE = 0,
    FORWARD = 1
} ONEWAY_STATES;
typedef enum {
		EMPTY_LANE = 0,
		PLUS_CLICKED = +1,
		NO_LANES = -2,
		MINUS_CLICKED = -1,
} LANE_COUNT;

@interface EnhancedHwyEditorController ()
{
    NSMutableArray        *    _parentWays;
    NSMutableArray        *    _highwayViewArray; //    Array of EnhancedHwyEditorView to Store number of ways

	//	NSArray                * _laneCount;
    EnhancedHwyEditorView    *    _selectedFromHwy;
    UIButton            *   _uTurnButton;
    OsmRelation         *   _currentUTurnRelation;
    
    NSMutableArray        *    _allRelations;
    NSMutableArray        *    _editedRelations;
    
    OsmWay              *   _selectedWay;
    ONEWAY_STATES         _onewayState;
		LANE_COUNT           _laneCountState;

    MapView             *   _mapView;
    EditorMapLayer      *   _editorLayer;
    
    NSInteger               _reverseCount;
		NSInteger               _laneCount;
		NSInteger               _laneValues;
}
@end

@implementation EnhancedHwyEditorController
- (void)viewDidLoad
{
    [super viewDidLoad];
    _highwayViewArray = [NSMutableArray new];
    
    _mapView = [AppDelegate getAppDelegate].mapView;
    _editorLayer = _mapView.editorLayer;
    
    [_editorLayer.mapData beginUndoGrouping];
}
- (void)loadState
{
    self.keyValueDict = [NSMutableDictionary new];
    if ( _editorLayer.selectedWay ) {
        [_editorLayer.selectedWay.tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * obj, BOOL *stop) {
            [_keyValueDict setObject:obj forKey:key];
        }];
    }
    _selectedWay = _editorLayer.selectedWay;
    _tags = [NSMutableArray arrayWithCapacity:_selectedWay.tags.count];
    NSMutableArray * nameTags = [[NSMutableArray alloc] init];
    //enumerating through the tags
    [_keyValueDict enumerateKeysAndObjectsUsingBlock:^(NSString * tag, NSString * value, BOOL *stop) {
        [_tags addObject:[NSMutableArray arrayWithObjects:tag, value, nil]];
        if ( [tag hasPrefix:@"name"] ){
            [nameTags addObject:[NSMutableArray arrayWithObjects:tag, value, nil]];
        }

				if(![_keyValueDict objectForKey:@"lanes"]){
						_laneCount = 0;
				} else {
						_laneCount = [[_keyValueDict valueForKey:@"lanes"] intValue];
						_stepper.value = _laneCount;
				}
		}];
		//RIGHT HERE
    if ( nameTags.count > 0 ){
        _nameTags = [[nameTags sortedArrayUsingComparator:^NSComparisonResult(NSArray * obj1,NSArray * obj2) {
            return [obj1[0] compare:obj2[0]];
        }] mutableCopy];
    }
    else {
        // Add a blank name to add it if it doesn't have one
        [nameTags addObject:[NSMutableArray arrayWithObjects:@"name", @"", nil]];
        _nameTags = nameTags;
        [_tags addObject:[NSMutableArray arrayWithObjects:@"name", @"", nil]];
    }

    // Check for `name` presets and add them as options in the list
    for ( CustomPreset * custom in [CustomPresetList shared] ) {
        if ( custom.appliesToKey.length ) {
            NSString * v = _keyValueDict[ custom.appliesToKey ];
            if ( v && (custom.appliesToValue.length == 0 || [v isEqualToString:custom.appliesToValue]) ) {
                // accept
            } else {
                continue;
            }
        }
        if ( [custom.tagKey hasPrefix:@"name"] ){
            [_namePresets addObject:custom.tagKey];
        }
    }

    if ( ![_keyValueDict objectForKey:@"on eway"]){
        _onewayState = EMPTY;
    } else {
        _onewayState = (ONEWAY_STATES)_selectedWay.isOneWay;
    }
    
    [self setOnewayBtnStyle];

//lanecount for stepper
		if (![_keyValueDict objectForKey:@"lanes"]){
				_laneCount = EMPTY_LANE;
				NSLog(@"LANES = TRUE");
		} else {
				_laneCount = (LANE_COUNT)_selectedWay.isModified;
				NSLog(@"LANES = FALSE");
		}
		NSLog(@"LANESTEPPER: %f", _stepper.value);
		[lblValue setText:[NSString stringWithFormat:@"%f", [laneStepper value]]];
    [tagTable reloadData];
		saveButton.enabled = [self isTagDictChanged:[self keyValueDictionary]];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self loadState];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    TextPair * cell = [tagTable.visibleCells firstObject];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [cell.text2 becomeFirstResponder];
    [_mapView.editControl.bottomAnchor constraintEqualToAnchor:self.highwayEditorView.topAnchor constant:-11].active = YES;
    [_mapView.editControl.topAnchor constraintEqualToAnchor:self.highwayEditorView.topAnchor constant:-54].active = YES;
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [_mapView.editControl.bottomAnchor constraintEqualToAnchor:[AppDelegate getAppDelegate].mapView.toolbar.topAnchor constant:-11].active = YES;
    [_mapView.editControl.topAnchor constraintEqualToAnchor:_mapView.centerOnGPSButton.bottomAnchor constant:3].active = YES;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [_editorLayer.mapData endUndoGrouping];
}

# pragma mark - Table view data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _nameTags.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TextPair * cell = [tableView dequeueReusableCellWithIdentifier:@"TagCell" forIndexPath:indexPath];
    NSArray * kv = _nameTags[ indexPath.row ];
    // assign text contents of fields
    cell.text1.enabled = YES;
    cell.text2.enabled = YES;
    cell.text1.text = kv[0];
    cell.text2.text = kv[1];
    
    cell.text1.didSelect = ^{ [cell.text2 becomeFirstResponder]; };
    cell.text2.didSelect = ^{};
    
    return cell;
};

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
    
    NSIndexPath * indexPath = [tagTable indexPathForCell:cell];
    
    if ( indexPath.section == 0 ) {
        
        NSMutableArray * kv = _nameTags[ indexPath.row ];
        
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

- (void)keyboardWillChangeFrame:(NSNotification *)notification
{
    NSDictionary * userInfo = [notification userInfo];
    CGRect keyboardFrame = [[userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];

    bottomViewConstraint = [_highwayEditorView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-keyboardFrame.size.height];
    bottomViewConstraint.active = YES;
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

- (IBAction)textFieldChanged:(UITextField *)textField
{
    UITableViewCell * cell = (id)textField.superview;
    while ( cell && ![cell isKindOfClass:[UITableViewCell class]])
        cell = (id)cell.superview;
    NSIndexPath * indexPath = [tagTable indexPathForCell:cell];

    if ( indexPath.section == 0 ) {
        // edited tags
        TextPair * pair = (id)cell;
        NSMutableArray * kv = _nameTags[ indexPath.row ];
        NSMutableArray * tagKv;
        for ( NSMutableArray * lw in _tags ) {
            if ( lw[0] == kv[0] ) {
                tagKv = lw;
            }
        }
        BOOL isValue = textField == pair.text2;

        if ( isValue ) {
            // new value
            kv[1] = textField.text;
            tagKv[1] = textField.text;
        } else {
            // new key name
            kv[0] = textField.text;
            tagKv[0] = textField.text;
        }

        NSMutableDictionary * dict = [self keyValueDictionary];

        saveButton.enabled = [self isTagDictChanged:dict];
    }
}

// Close the window if user touches outside it
-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    UITouch * touch = [touches anyObject];
    CGPoint point = [touch locationInView:_mapView];
    CGPoint editControlPoint = [touch locationInView:_mapView.editControl];

    if ( [_mapView.editControl hitTest:editControlPoint withEvent:event]) {
        NSUInteger segmentSize = _mapView.editControl.bounds.size.width / _mapView.editControl.numberOfSegments;
        NSUInteger touchedSegment = editControlPoint.x / segmentSize;
        _mapView.editControl.selectedSegmentIndex = touchedSegment;
        [self dismissViewControllerAnimated:NO completion:^{
            [_mapView editControlAction:_mapView.editControl];
        }];

        return;
    }
    
    OsmBaseObject * hit = [_mapView.editorLayer osmHitTest:point radius:DefaultHitTestRadius testNodes:NO ignoreList:nil segment:nil];
    if ( hit.isWay ) {
        _editorLayer.selectedWay = (id)hit;
        [self loadState];
        TextPair * cell = [tagTable.visibleCells firstObject];
        [cell.text2 becomeFirstResponder];
        return;
    }
    
    if ( touch.view != _highwayEditorView ) {
        [self dismissViewControllerAnimated:true completion:nil];
    }
}

// Convert location point to CGPoint
-(CGPoint)screenPointForLatitude:(double)latitude longitude:(double)longitude
{
    OSMPoint pt = MapPointForLatitudeLongitude( latitude, longitude );
    pt = OSMPointApplyTransform( pt, _screenFromMapTransform );
    return CGPointFromOSMPoint(pt);
}

- (IBAction)onewayPressed {
    NSMutableArray * onewayTag;
    NSInteger * index = 0;
    for ( NSMutableArray * kv in _tags ){
        if ( [kv[0] isEqualToString:@"oneway"] )
            onewayTag = kv;
        index++;
    }
    
    switch (_onewayState) {
        case EMPTY:
            [_tags addObject:[NSMutableArray arrayWithObjects:@"oneway", @"no", nil]];
            _onewayState = NONE;
            break;
            
        case BACKWARD:
            onewayTag[1] = @"no";
            _onewayState = NONE;
            break;
        
        case NONE:
            onewayTag[1] = @"yes";
            _onewayState = FORWARD;
            break;
        
        case FORWARD:
            [_tags removeObject: onewayTag];
            _onewayState = EMPTY;
            
        default:
            break;
    }
    
    [self setOnewayBtnStyle];
    saveButton.enabled = [self isTagDictChanged:[self keyValueDictionary]];
}

- (IBAction)reversePressed {
    NSString * error = nil;
    EditAction reverse = [_editorLayer.mapData canReverseWay:_selectedWay error:&error];
    if ( reverse )
        reverse();
    if ( error ) {
        UIAlertController * alertError = [UIAlertController alertControllerWithTitle:error message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alertError addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alertError animated:YES completion:nil];
    }
    
    [_editorLayer setNeedsLayout];
    if ( ![self isTagDictChanged:[self keyValueDictionary]] ) {
        _reverseCount += 1;
        saveButton.enabled = _reverseCount %2 != 0;
    }
}

- (IBAction)laneStepperPressed:(UIStepper *)sender {
		NSString * error = nil;
			EditAction laneAdded;
			double value =  [sender value];
		NSLog(@"LANE STEPPER VALUE: %d", (int) _stepper.value);
			[lblValue setText:[NSString stringWithFormat:@"%d", (int)value]];
			if(laneAdded)
					[lblValue setText:[NSString stringWithFormat:@"%f", [laneStepper value]]];
			if(error) {
					UIAlertController * alertError = [UIAlertController alertControllerWithTitle:error message:nil preferredStyle:UIAlertControllerStyleAlert];
					[alertError addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
					[self presentViewController:alertError animated:YES completion:nil];
			}
			[_editorLayer setNeedsLayout];
			if ( ![self isTagDictChanged:[self keyValueDictionary]] ) {
					 NSMutableArray * laneTag;
						 NSInteger * index = 0;
						 for ( NSMutableArray * kv in _tags ){
								 if ( [kv[0] isEqualToString:@"lanes"] )
										 laneTag = kv;
								 index++;
					}
					switch (_laneCount) {
								case EMPTY_LANE:
									[_tags addObject:[NSMutableArray arrayWithObjects:@"lanes", "no" , nil]];
									_laneCount = EMPTY_LANE;
										break;

								case MINUS_CLICKED:
										_laneCount = MINUS_CLICKED;
										break;

								case PLUS_CLICKED:
										_laneCount = PLUS_CLICKED;
										break;

								default:
										break;
					}
			}
		saveButton.enabled = [self isTagDictChanged:[self keyValueDictionary]];
}

- (IBAction)done {
    [self dismissViewControllerAnimated:true completion:nil];
		[self saveState];
    
    [self commitChanges];
}

- (IBAction)saveState {
    NSMutableDictionary * dict = [self keyValueDictionary];
    _keyValueDict = dict;
}

- (void)setOnewayBtnStyle {
    switch (_onewayState) {
        case ONEWAY_NONE:
            [oneWayButton setBackgroundColor:[UIColor redColor]];
            break;
        case ONEWAY_FORWARD:
            [oneWayButton setBackgroundColor:[UIColor greenColor]];
            break;
        case ONEWAY_BACKWARD:
            [oneWayButton setBackgroundColor:[UIColor blackColor]];
            [oneWayButton.titleLabel setTextColor:[UIColor redColor]];
        default:
            [oneWayButton setBackgroundColor:[UIColor lightGrayColor]];
            break;
    }
}

- (BOOL)isTagDictChanged:(NSDictionary *)newDictionary
{
    AppDelegate * appDelegate = [AppDelegate getAppDelegate];
    
    NSDictionary * tags = appDelegate.mapView.editorLayer.selectedPrimary.tags;
    if ( tags.count == 0 )
        return newDictionary.count != 0;
    
    return ![newDictionary isEqual:tags];
}

- (void)commitChanges
{
    AppDelegate * appDelegate = [AppDelegate getAppDelegate];
    [appDelegate.mapView setTagsForCurrentObject:self.keyValueDict];
    [appDelegate.mapView updateEditControl];
}

@end

