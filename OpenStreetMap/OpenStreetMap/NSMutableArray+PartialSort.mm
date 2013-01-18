//
//  NSMutableArray+PartialSort.m
//  OpenStreetMap
//
//  Created by Bryce on 1/16/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import <vector>
#import <algorithm>

#import "NSMutableArray+PartialSort.h"

@implementation NSMutableArray (PartialSort)

-(void)partialSortK:(NSInteger)k compare:(BOOL (*)(id o1, id o2))lessThan
{
	if ( k >= self.count )
		return;

	// copy everything to std::vector
	std::vector<id>	v;
	v.reserve( self.count );
	for ( id object in self ) {
		v.push_back( object );
	}

	// partition
	std::nth_element( &v[0], &v[k], &v[v.size()], lessThan );

	// copy everything back
	[self removeAllObjects];
	for ( auto it = v.begin(); it < v.end(); ++it ) {
		id obj = *it;
		[self addObject:obj];
	}
}

@end
