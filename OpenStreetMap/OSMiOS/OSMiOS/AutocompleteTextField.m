//
//  AutocompleteTextField.m
//  Go Map!!
//
//  Created by Bryce on 2/3/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import "AutocompleteTextField.h"

@implementation AutocompleteTextField
@synthesize completions = _completions;


- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
		super.delegate = self;
    }
    return self;
}

-(void)setDelegate:(id<UITextFieldDelegate>)delegate
{
	_realDelegate = delegate;
	super.delegate = self;
}

-(id<UITextFieldDelegate>)delegate
{
	return _realDelegate;
}


-(void)setCompletions:(NSArray *)completions
{
	_completions = completions;
	if ( self.delegate != self ) {
		_realDelegate = self.delegate;
		super.delegate = self;
	}
	[self updateAutocomplete];
}
-(NSArray *)completions
{
	return _completions;
}


- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
	if ( [_realDelegate respondsToSelector:@selector(textFieldShouldBeginEditing:)])
		return [_realDelegate textFieldShouldBeginEditing:textField];
	return YES;
}
- (void)textFieldDidBeginEditing:(UITextField *)textField
{
	if ( [_realDelegate respondsToSelector:@selector(textFieldDidBeginEditing:)])
		[_realDelegate textFieldDidBeginEditing:textField];
}
- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
	if ( [_realDelegate respondsToSelector:@selector(textFieldShouldEndEditing:)])
		return [_realDelegate textFieldShouldEndEditing:textField];
	return YES;
}
- (void)textFieldDidEndEditing:(UITextField *)textField
{
	if ( [_realDelegate respondsToSelector:@selector(textFieldDidEndEditing:)])
		[_realDelegate textFieldDidEndEditing:textField];
}
- (BOOL)textFieldShouldClear:(UITextField *)textField
{
	if ( [_realDelegate respondsToSelector:@selector(textFieldShouldClear:)])
		return [_realDelegate textFieldShouldClear:textField];
	return YES;
}
- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	if ( [_realDelegate respondsToSelector:@selector(textFieldShouldReturn:)])
		return [_realDelegate textFieldShouldReturn:textField];
	return YES;
}





- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
	if ( string.length == 0 && range.location+range.length == textField.text.length ) {
		// deleting from tail, so disable autocomplete until next change
		_pauseAutocomplete = YES;
	}
	if ( [_realDelegate respondsToSelector:@selector(textField:shouldChangeCharactersInRange:replacementString:)])
		return [_realDelegate textField:textField shouldChangeCharactersInRange:range replacementString:string];
	return YES;
}


- (void)updateAutocomplete
{
	if ( _pauseAutocomplete ) {
		_pauseAutocomplete = NO;
		return;
	}

	NSString * text = self.text;

	for ( NSString * s in _completions ) {

		if ( [s rangeOfString:text options:NSCaseInsensitiveSearch].location == 0 ) {

			NSInteger pos = text.length;
			self.text = s;

			UITextPosition * start = [self positionFromPosition:self.beginningOfDocument offset:pos];
			UITextPosition * end = self.endOfDocument;
			UITextRange * range = [self textRangeFromPosition:start toPosition:end];
			[self setSelectedTextRange:range];
			return;
		}
	}
}

@end
