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



@implementation AutocompleteTextField
@synthesize completions = _allCompletions;

static const CGFloat GradientHeight = 20.0;

- (id)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)   name:UIKeyboardWillShowNotification object:nil];
//	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidShow:)   name:UIKeyboardDidShowNotification object:nil];
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


- (CGSize)keyboardSizeFromNotification:(NSNotification *)notification
{
	NSDictionary *userInfo = [notification userInfo];
	CGRect rect = [[userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	rect = [self.superview convertRect:rect fromView:nil];
	return rect.size;
}

- (void) keyboardWillShow:(NSNotification *)nsNotification
{
	_keyboardSize = [self keyboardSizeFromNotification:nsNotification];

	if ( self.editing && _filteredCompletions.count ) {
		[self updateAutocomplete];
	}
}
- (void)keyboardDidShow:(NSNotification *)notification
{
#if 0
	dispatch_async(dispatch_get_main_queue(), ^{
		[self updateAutocompleteForString:@""];
	});
#endif
}

- (void) keyboardWillChange:(NSNotification *)nsNotification
{
	_keyboardSize = [self keyboardSizeFromNotification:nsNotification];

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
#if 1
	UITableViewCell * cell = (id)self.superview;
	while ( cell && ![cell isKindOfClass:[UITableViewCell class]] )
		cell = (id)cell.superview;
	UITableView * tableView = (id)cell.superview;
	while ( tableView && ![tableView isKindOfClass:[UITableView class]] ) {
		tableView = (id)tableView.superview;
	}
	UIWindow * window = (id)tableView.superview;
	while ( window && ![window isKindOfClass:[UIWindow class]] )
		window = (id)window.superview;

	CGRect cellRC = [self convertRect:self.frame toView:tableView];
	CGRect tableRC = [tableView convertRect:tableView.frame toView:nil];

	CGRect rect;
	rect.origin.x = 0;
	rect.origin.y = cellRC.origin.y + cellRC.size.height;
	rect.size.width = tableView.frame.size.width;
	rect.size.height = tableView.frame.size.height - cellRC.origin.y - tableView.frame.origin.y - _keyboardSize.height;
	rect.size.height = window.frame.size.height - tableRC.origin.y - _keyboardSize.height - cell.frame.size.height;
#else
	UITableViewCell * cell = (id)[self.superview superview];
	UITableView * tableView = (id)[cell superview];
	if ( [tableView isKindOfClass:[UITableViewCell class]] ) {
		// ios 7
		tableView = (id)tableView.superview.superview;
		cell = (id)cell.superview;
	}
	UIScrollView * scrollView = (id)tableView.superview;
	UIView * view = scrollView.superview;

	CGRect rect;
	rect.origin.x = cell.frame.origin.x;
	rect.origin.y = cell.frame.origin.y + cell.frame.size.height;
	rect.size.width = cell.frame.size.width;
	rect.size.height = view.frame.size.height - _keyboardSize.height - cell.frame.size.height;
	return rect;
#endif
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
				// iOS 7
				tableView = (id)tableView.superview;
			}

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

			// scroll cell to top
#if 1
			NSIndexPath * p = [tableView indexPathForCell:cell];
			[tableView scrollToRowAtIndexPath:p atScrollPosition:UITableViewScrollPositionTop animated:NO];
#else
			CGRect cellFrame = cell.frame;
			cellFrame = [cell.superview convertRect:cellFrame toView:tableView];
			if ( iOS7 ) {
#if 0
				cellFrame.origin.y += tableView.contentOffset.y;
#else
				cellFrame.origin.y -= 45 + 20;	// cell height + status bar height?
#endif
			}
			[tableView setContentOffset:CGPointMake(0,cellFrame.origin.y) animated:YES];
#endif
			tableView.scrollEnabled = NO;
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
