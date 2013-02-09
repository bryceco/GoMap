//
//  AutocompleteTextField.h
//  Go Map!!
//
//  Created by Bryce on 2/3/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@class CAGradientLayer;

@interface AutocompleteTextField : UITextField <UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate>
{
	id<UITextFieldDelegate>		_realDelegate;

	CGSize						_keyboardSize;
	UITableView				*	_completionTableView;
	CGFloat						_origCellOffset;
	NSArray					*	_filteredCompletions;

	CAGradientLayer			*	_gradientLayer;
}

@property (strong,nonatomic)	NSArray * completions;

@end
