//
//  AutocompleteTextField.h
//  Go Map!!
//
//  Created by Bryce on 2/3/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@class CAGradientLayer;
@class AutocompleteTextFieldDelegate;

@interface AutocompleteTextField : UITextField <UITableViewDataSource, UITableViewDelegate>
{
	AutocompleteTextFieldDelegate	*	_myDelegate;

	CGSize								_keyboardSize;
	UITableView						*	_completionTableView;
	CGFloat								_origCellOffset;
	NSArray							*	_filteredCompletions;

	CAGradientLayer					*	_gradientLayer;
}

@property (copy,nonatomic)	NSArray * completions;

-(void)clearFilteredCompletionsInternal;

@end
