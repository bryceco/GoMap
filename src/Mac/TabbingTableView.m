//
//  MyTableView.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/4/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "TabbingTableView.h"

@implementation TabbingTableView

- (void) textDidEndEditing: (NSNotification *) notification
{
	NSInteger editedColumn = self.editedColumn;
	NSInteger editedRow = self.editedRow;
	NSInteger lastColumn = self.tableColumns.count - 1;

	NSDictionary *userInfo = [notification userInfo];

	int textMovement = [[userInfo valueForKey:@"NSTextMovement"] intValue];

	[super textDidEndEditing: notification];

	if ( editedColumn == lastColumn  &&  textMovement == NSTabTextMovement  &&  editedRow < self.numberOfRows-1 ) {
		// the tab key was hit while in the last column,
		// so go to the left most cell in the next row
		[self selectRowIndexes:[NSIndexSet indexSetWithIndex:editedRow+1] byExtendingSelection:NO];
		[self editColumn:0 row:editedRow+1  withEvent:nil select:YES];
	} else if ( editedColumn == 0  &&  textMovement == NSBacktabTextMovement  &&  editedRow > 0 ) {
		[self selectRowIndexes:[NSIndexSet indexSetWithIndex:editedRow-1] byExtendingSelection:NO];
		[self editColumn:lastColumn row:editedRow-1  withEvent:nil select:YES];
	}
}

@end
