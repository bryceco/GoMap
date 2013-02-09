//
//  AutocompleteTextField.m
//  Go Map!!
//
//  Created by Bryce on 2/3/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#import "AutocompleteTextField.h"

@implementation AutocompleteTextField
@synthesize completions = _allCompletions;


- (id)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidChange:) name:UIKeyboardDidChangeFrameNotification object:nil];

	return self;
}

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
	_allCompletions = completions;
	if ( self.delegate != self ) {
		_realDelegate = self.delegate;
		super.delegate = self;
	}
}
-(NSArray *)completions
{
	return _allCompletions;
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

	_filteredCompletions = nil;
	[self updateCompletionTableView];
}
- (BOOL)textFieldShouldClear:(UITextField *)textField
{
	[self performSelector:@selector(updateAutocomplete) withObject:nil afterDelay:0.0];

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
	[self performSelector:@selector(updateAutocomplete) withObject:nil afterDelay:0.0];
	
	if ( [_realDelegate respondsToSelector:@selector(textField:shouldChangeCharactersInRange:replacementString:)])
		return [_realDelegate textField:textField shouldChangeCharactersInRange:range replacementString:string];
	return YES;
}


- (CGSize)keyboardSizeFromNotification:(NSNotification *)notification
{
	NSDictionary *userInfo = [notification userInfo];
	CGRect rect = [[userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	rect = [self.superview convertRect:rect fromView:nil];
//	NSLog(@"kb = %@",NSStringFromCGSize(rect.size));
	return rect.size;
}

- (void) keyboardWillShow:(NSNotification *)nsNotification
{
	_keyboardSize = [self keyboardSizeFromNotification:nsNotification];

	if ( _filteredCompletions.count ) {
		[self updateAutocomplete];
	}
}
- (void) keyboardDidChange:(NSNotification *)nsNotification
{
	_keyboardSize = [self keyboardSizeFromNotification:nsNotification];

	if ( _completionTableView ) {
		CGRect rect = [self frameForCompletionTableView];
		_completionTableView.frame = rect;
	}
	if ( _filteredCompletions.count ) {
		[self updateAutocomplete];
	}
}

-(CGRect)frameForCompletionTableView
{
	UITableViewCell * cell = (id)[self.superview superview];
	UITableView * tableView = (id)[cell superview];
	UIScrollView * scrollView = (id)tableView.superview;
	UIView * view = scrollView.superview;

	CGRect rect;
	rect.origin.x = cell.frame.origin.x;
	rect.origin.y = cell.frame.origin.y + cell.frame.size.height;
	rect.size.width = cell.frame.size.width;
	rect.size.height = view.frame.size.height - _keyboardSize.height - cell.frame.size.height;
	return rect;
}

- (void)updateCompletionTableView
{
	if ( _filteredCompletions.count ) {
		if ( _completionTableView == nil ) {

			const CGFloat BackgroundGray = 0.88;

			UITableViewCell * cell = (id)[self.superview superview];
			UITableView * tableView = (id)[cell superview];
			assert( [tableView isKindOfClass:[UITableView class]] );

			// add completion table to tableview
			CGRect rect = [self frameForCompletionTableView];
			_completionTableView = [[UITableView alloc] initWithFrame:rect style:UITableViewStylePlain];
			_completionTableView.backgroundColor = [UIColor colorWithWhite:BackgroundGray alpha:1.0];
			_completionTableView.separatorColor = [UIColor colorWithWhite:0.7 alpha:1.0];
			_completionTableView.dataSource = self;
			_completionTableView.delegate = self;
			[tableView addSubview:_completionTableView];

			_gradientLayer = [CAGradientLayer layer];
			_gradientLayer.colors = @[
						(id)[UIColor colorWithWhite:0.0 alpha:0.6].CGColor,
						(id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor ];
			CGRect rcGradient = rect;
			rcGradient.size.height = 20;
			_gradientLayer.frame = rcGradient;
			[tableView.layer addSublayer:_gradientLayer];

			// scroll cell to top
			CGRect cellFrame = cell.frame;
			[tableView setContentOffset:CGPointMake(0,cellFrame.origin.y) animated:YES];
			tableView.scrollEnabled = NO;
		}
		[_completionTableView reloadData];

	} else {
		[_completionTableView removeFromSuperview];
		_completionTableView = nil;

		[_gradientLayer removeFromSuperlayer];
		_gradientLayer = nil;

		UITableViewCell * cell = (id)[self.superview superview];
		UITableView * tableView = (id)[cell superview];
		NSIndexPath * cellIndexPath = [tableView indexPathForCell:cell];
		[tableView scrollToRowAtIndexPath:cellIndexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];

		tableView.scrollEnabled = YES;
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	self.text = _filteredCompletions[ indexPath.row ];

	[self sendActionsForControlEvents:UIControlEventEditingChanged];
	// [[NSNotificationCenter defaultCenter] postNotificationName:UITextFieldTextDidChangeNotification object:self userInfo:nil];

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
		cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
	}
	cell.textLabel.text = [_filteredCompletions objectAtIndex:indexPath.row];
    return cell;
}


- (void)updateAutocomplete
{
	NSString * text = self.text;
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

@end
