//
//  AutocompleteTextField.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/3/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class CAGradientLayer;
@class AutocompleteTextFieldDelegate;

@interface AutocompleteTextField : UITextField <UITableViewDataSource, UITableViewDelegate>
{
	AutocompleteTextFieldDelegate	*	_myDelegate;

	UITableView						*	_completionTableView;
	CGFloat								_origCellOffset;
	NSArray							*	_filteredCompletions;

	CAGradientLayer					*	_gradientLayer;
}

@property (copy,nonatomic)	NSArray * completions;
@property (copy,nonatomic)	void (^didSelect)(void);

-(void)clearFilteredCompletionsInternal;
-(void)updateAutocompleteForString:(NSString *)text;

@end
