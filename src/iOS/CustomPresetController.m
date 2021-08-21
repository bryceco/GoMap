//
//  CustomPresetController.h
//  Go Map!!
//
//  Created by Bryce on 8/21/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import "CommonTagList.h"
#import "CustomPresetController.h"
#import "POICommonTagsViewController.h"
#import "UITableViewCell+FixConstraints.h"

@interface CustomPresetController ()
@end

@implementation CustomPresetController

- (void)viewDidLoad
{
	[super viewDidLoad];

	_valueFieldList = @[ _value1Field, _value2Field, _value3Field, _value4Field,  _value5Field,  _value6Field,
						 _value7Field, _value8Field, _value9Field, _value10Field, _value11Field, _value12Field ];

	_nameField.text				= _customPreset.name;
	_appliesToTagField.text		= _customPreset.appliesToKey;
	_appliesToValueField.text	= _customPreset.appliesToValue;
	_keyField.text				= _customPreset.tagKey;

	NSInteger idx = 0;
	for ( UITextField * textField in _valueFieldList ) {
		if ( idx >= _customPreset.presetList.count )
			break;
		CommonPreset * preset = _customPreset.presetList[ idx ];
		textField.text = preset.tagValue;
		++idx;
	}
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	// Fix bug on iPad where cell heights come back as -1:
	// CGFloat h = [super tableView:tableView heightForRowAtIndexPath:indexPath];
	return 44.0;
}

-(IBAction)done:(id)sender
{
	// remove white space from subdomain list
	NSString * name = [_nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString * key  = [_keyField.text  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ( name.length == 0 || key.length == 0 )
		return;
	NSString * appliesToKey = [_appliesToTagField.text	 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString * appliesToVal = [_appliesToValueField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSMutableArray * presets = [NSMutableArray new];
	for ( UITextField * field in _valueFieldList ) {
		NSString * value = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ( value.length ) {
			CommonPreset * preset = [CommonPreset presetWithName:nil tagValue:value];
			[presets addObject:preset];
		}
	}
	UIKeyboardType keyboard = UIKeyboardTypeDefault;
	UITextAutocapitalizationType capitalize = UITextAutocapitalizationTypeNone;
	
	_customPreset = [CustomPreset tagWithName:name tagKey:key placeholder:nil keyboard:keyboard capitalize:capitalize presets:presets];
	_customPreset.appliesToKey = appliesToKey;
	_customPreset.appliesToValue = appliesToVal;
	if ( _completion ) {
		_completion(_customPreset);
	}
	[self.navigationController popViewControllerAnimated:YES];
}

-(IBAction)cancel:(id)sender
{
	[self.navigationController popViewControllerAnimated:YES];
}

-(void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	[cell fixConstraints];
}

-(IBAction)contentChanged:(id)sender
{
	if ( _nameField.text.length > 0 && _keyField.text.length > 0 ) {
		self.navigationItem.rightBarButtonItem.enabled = YES;
	} else {
		self.navigationItem.rightBarButtonItem.enabled = NO;
	}
}


@end
