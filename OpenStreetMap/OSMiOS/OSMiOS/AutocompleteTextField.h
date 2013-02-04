//
//  AutocompleteTextField.h
//  Go Map!!
//
//  Created by Bryce on 2/3/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface AutocompleteTextField : UITextField <UITextFieldDelegate>
{
	BOOL						_pauseAutocomplete;
	id<UITextFieldDelegate>		_realDelegate;
}

@property (strong,nonatomic)	NSArray * completions;

@end
