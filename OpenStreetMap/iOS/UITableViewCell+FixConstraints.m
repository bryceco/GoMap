//
//  UITableViewCell+FixConstraints.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/25/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "UITableViewCell+FixConstraints.h"

@implementation UITableViewCell (FixConstraints)

// adjust constraints to be relative to contentView instead of view
- (void)fixConstraints
{
	// http://stackoverflow.com/questions/12600214/contentview-not-indenting-in-ios-6-uitableviewcell-prototype-cell

	for ( NSInteger i = self.constraints.count - 1; i >= 0; i-- ) {
		NSLayoutConstraint * constraint = [self.constraints objectAtIndex:i];

		id firstItem = constraint.firstItem;
		id secondItem = constraint.secondItem;

		if ( firstItem == self && [secondItem isDescendantOfView:self.contentView] ) {
			firstItem = self.contentView;
		} else if ( secondItem == self && [firstItem isDescendantOfView:self.contentView] ) {
			secondItem = self.contentView;
		} else {
			continue;
		}
		NSLayoutConstraint *contentViewConstraint = [NSLayoutConstraint constraintWithItem:firstItem
																				 attribute:constraint.firstAttribute
																				 relatedBy:constraint.relation
																					toItem:secondItem
																				 attribute:constraint.secondAttribute
																				multiplier:constraint.multiplier
																				  constant:constraint.constant];
		[self removeConstraint:constraint];
		[self.contentView addConstraint:contentViewConstraint];
	}
}

@end
