//
//  AutocompleteTextField.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/3/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#import "AutocompleteTextField.h"


@interface AutocompleteTextFieldDelegate : NSObject<UITextFieldDelegate>
@property (strong,nonatomic)	id<UITextFieldDelegate>		realDelegate;
@property (weak,nonatomic)		AutocompleteTextField	*	owner;
@end

@implementation AutocompleteTextFieldDelegate

-(void)dealloc
{
	_realDelegate = nil;
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
#if 0
	[self.owner performSelector:@selector(updateAutocompleteForString:) withObject:self.owner.text];
#endif
}
- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
	if ( [_realDelegate respondsToSelector:@selector(textFieldShouldEndEditing:)])
		return [_realDelegate textFieldShouldEndEditing:textField];
	return YES;
}
- (void)textFieldDidEndEditing:(UITextField *)textField
{
	[_owner clearFilteredCompletionsInternal];

	if ( [_realDelegate respondsToSelector:@selector(textFieldDidEndEditing:)])
		[_realDelegate textFieldDidEndEditing:textField];
}
- (BOOL)textFieldShouldClear:(UITextField *)textField
{
	BOOL result = [_realDelegate respondsToSelector:@selector(textFieldShouldClear:)] ? [_realDelegate textFieldShouldClear:textField] : YES;
	if ( result ) {
		[self.owner performSelector:@selector(updateAutocompleteForString:) withObject:@""];
	}
	return result;
}
- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	if ( [_realDelegate respondsToSelector:@selector(textFieldShouldReturn:)])
		return [_realDelegate textFieldShouldReturn:textField];
	return YES;
}
- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
	BOOL result = [_realDelegate respondsToSelector:@selector(textField:shouldChangeCharactersInRange:replacementString:)] ? [_realDelegate textField:textField shouldChangeCharactersInRange:range replacementString:string] : YES;
	if ( result ) {
		NSString * newString = [self.owner.text stringByReplacingCharactersInRange:range withString:string];
		[self.owner performSelector:@selector(updateAutocompleteForString:) withObject:newString];
	}
	return result;
}

@end

// this needs to be shared, because sometimes we'll create a new autocomplete text field when the keyboard is already showing,
// so it never gets a chance to retrieve the size:
static CGRect	s_keyboardFrame;



@implementation AutocompleteTextField
@synthesize completions = _allCompletions;

static const CGFloat GradientHeight = 20.0;

- (id)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)   name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChange:) name:UIKeyboardWillChangeFrameNotification object:nil];

	_myDelegate = [AutocompleteTextFieldDelegate new];
	_myDelegate.owner = self;
	super.delegate = _myDelegate;

	return self;
}

-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	_myDelegate = nil;
}

- (id)initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		assert(NO);
	}
	return self;
}

-(void)setDelegate:(id<UITextFieldDelegate>)delegate
{
	_myDelegate.realDelegate = delegate;
	super.delegate = _myDelegate;
}

-(id<UITextFieldDelegate>)delegate
{
	return _myDelegate.realDelegate;
}

-(void)clearFilteredCompletionsInternal
{
	_filteredCompletions = nil;
	[self updateCompletionTableView];
}

-(void)setCompletions:(NSArray *)completions
{
	_allCompletions = completions;
	if ( self.delegate != _myDelegate ) {
		_myDelegate.realDelegate = self.delegate;
		super.delegate = _myDelegate;
	}
}
-(NSArray *)completions
{
	return _allCompletions;
}


- (CGRect)keyboardFrameFromNotification:(NSNotification *)notification
{
	NSDictionary *userInfo = [notification userInfo];
	CGRect rect = [[userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	return rect;
}

- (void) keyboardWillShow:(NSNotification *)nsNotification
{
	s_keyboardFrame = [self keyboardFrameFromNotification:nsNotification];

	if ( self.editing && _filteredCompletions.count ) {
		[self updateAutocomplete];
	}
}

// keyboard size can change if switching languages inside keyboard, etc.
- (void) keyboardWillChange:(NSNotification *)nsNotification
{
	s_keyboardFrame = [self keyboardFrameFromNotification:nsNotification];

	if ( _completionTableView ) {
		CGRect rect = [self frameForCompletionTableView];
		_completionTableView.frame = rect;

		CGRect rcGradient = rect;
		rcGradient.size.height = GradientHeight;

		[CATransaction begin];
		[CATransaction setAnimationDuration:0.0];
		_gradientLayer.frame = rcGradient;
		[CATransaction commit];
	}
	if ( self.editing && _filteredCompletions.count ) {
		[self updateAutocomplete];
	}
}

-(CGRect)frameForCompletionTableView
{
	UITableViewCell * cell = (id)self.superview;
	while ( cell && ![cell isKindOfClass:[UITableViewCell class]] )
		cell = (id)cell.superview;
	UITableView * tableView = (id)cell.superview;
	while ( tableView && ![tableView isKindOfClass:[UITableView class]] ) {
		tableView = (id)tableView.superview;
	}

//	CGRect cellRC = [self convertRect:self.frame toView:tableView];
	CGRect cellRC = [cell convertRect:cell.bounds toView:tableView];
	CGRect keyboardPos = [tableView convertRect:s_keyboardFrame fromView:nil];	// keyboard is in screen coordinates
	CGRect rect;
	rect.origin.x = 0;
	rect.origin.y = cellRC.origin.y + cellRC.size.height;
	rect.size.width = tableView.frame.size.width;
	rect.size.height = keyboardPos.origin.y - rect.origin.y;
	return rect;
}

- (void)updateCompletionTableView
{
	if ( _filteredCompletions.count ) {
		if ( _completionTableView == nil ) {

			UITableViewCell * cell = (id)self.superview;
			while ( cell && ![cell isKindOfClass:[UITableViewCell class]] )
				cell = (id)cell.superview;
			UITableView * tableView = (id)cell.superview;
			while ( tableView && ![tableView isKindOfClass:[UITableView class]] ) {
				tableView = (id)tableView.superview;
			}
			
			// scroll cell to top
			NSIndexPath * p = [tableView indexPathForCell:cell];
			[tableView scrollToRowAtIndexPath:p atScrollPosition:UITableViewScrollPositionTop animated:NO];
			tableView.scrollEnabled = NO;

			// cell doesn't always scroll to the same place, so give it a moment before we add the completion table
			dispatch_async(dispatch_get_main_queue(), ^{
				// add completion table to tableview
				CGRect rect = [self frameForCompletionTableView];
				_completionTableView = [[UITableView alloc] initWithFrame:rect style:UITableViewStylePlain];
				_completionTableView.backgroundColor = [UIColor colorWithWhite:0.88 alpha:1.0];
				_completionTableView.separatorColor = [UIColor colorWithWhite:0.7 alpha:1.0];
				_completionTableView.dataSource = self;
				_completionTableView.delegate = self;
				[tableView addSubview:_completionTableView];

				_gradientLayer = [CAGradientLayer layer];
				_gradientLayer.colors = @[
										  (id)[UIColor colorWithWhite:0.0 alpha:0.6].CGColor,
										  (id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor ];
				CGRect rcGradient = rect;
				rcGradient.size.height = GradientHeight;
				_gradientLayer.frame = rcGradient;
				[tableView.layer addSublayer:_gradientLayer];
			});
		}
		[_completionTableView reloadData];

	} else {
		[_completionTableView removeFromSuperview];
		_completionTableView = nil;

		[_gradientLayer removeFromSuperlayer];
		_gradientLayer = nil;

		UITableViewCell * cell = (id)[self superview];
		while ( cell && ![cell isKindOfClass:[UITableViewCell class]] )
			cell = (id)cell.superview;
		UITableView * tableView = (id)[cell superview];
		while ( tableView && ![tableView isKindOfClass:[UITableView class]] ) {
			tableView = (id)tableView.superview;
		}
		if ( tableView ) {
			NSIndexPath * cellIndexPath = [tableView indexPathForCell:cell];
			[tableView scrollToRowAtIndexPath:cellIndexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
		}
		tableView.scrollEnabled = YES;
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	self.text = _filteredCompletions[ indexPath.row ];

	[self sendActionsForControlEvents:UIControlEventEditingChanged];
	// [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:self userInfo:nil];

	if ( self.didSelect ) {
		self.didSelect();
	}

	// hide completion table view
	_filteredCompletions = nil;
	[self updateCompletionTableView];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return _filteredCompletions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString * CellIdentifier = @"Cell";
	UITableViewCell * cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
	if ( cell == nil ) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
		cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	}
	cell.textLabel.text = [_filteredCompletions objectAtIndex:indexPath.row];
    return cell;
}

- (void)updateAutocompleteForString:(NSString *)text
{
	if ( [text isEqualToString:@" "] )
		text = @"";
	// filter completion list by current text
	if ( text.length ) {
		_filteredCompletions = [_allCompletions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString * object, NSDictionary *bindings) {
			return [object rangeOfString:text options:NSCaseInsensitiveSearch].location == 0;
		}]];
	} else {
		_filteredCompletions = _allCompletions;
	}
	// sort alphabetically
	_filteredCompletions = [_filteredCompletions sortedArrayUsingComparator:^NSComparisonResult(NSString * s1, NSString * s2) {
		return [s1 compare:s2 options:NSCaseInsensitiveSearch];
	}];
	[self updateCompletionTableView];
}

- (void)updateAutocomplete
{
	[self updateAutocompleteForString:self.text];
}

@end
