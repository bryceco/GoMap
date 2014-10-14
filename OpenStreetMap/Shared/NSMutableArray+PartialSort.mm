//
//  NSMutableArray+PartialSort.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 1/16/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#import <vector>
#import <algorithm>

#import "NSMutableArray+PartialSort.h"
#import "OsmObjects.h"



@implementation NSMutableArray (PartialSort)

-(void)partialSortK:(NSInteger)k compare:(BOOL (*)(id o1, id o2))lessThan
{
	// copy everything to std::vector
	std::vector<id>	v;
	v.reserve( self.count );
	for ( id object in self ) {
		v.push_back( object );
	}

	if ( k >= self.count ) {
		std::sort( &v[0], &v[v.size()], lessThan );
	} else {
		std::partial_sort( &v[0], &v[k], &v[v.size()], lessThan );
	}

	// copy everything back
	[self removeAllObjects];
	for ( auto it = v.begin(), e = v.end(); it < e; ++it ) {
		id obj = *it;
		[self addObject:obj];
	}
}

-(void)nthElement:(NSInteger)k compare:(BOOL (*)(id, id))lessThan
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



static BOOL VisibleSizeLessStrict( OsmBaseObject * obj1, OsmBaseObject * obj2 )
{
	long long diff = obj1->renderPriorityCached - obj2->renderPriorityCached;
	if ( diff == 0 )
		diff = obj1.ident.longLongValue - obj2.ident.longLongValue;	// older objects are bigger
	return diff > 0;	// sort descending
}

-(void)partialSortOsmObjectVisibleSize:(NSInteger)k
{
	// copy everything to std::vector
	std::vector<id>	v;
	v.reserve( self.count );
	for ( id object in self ) {
		v.push_back( object );
	}

	if ( k >= self.count ) {
		std::sort( &v[0], &v[v.size()], VisibleSizeLessStrict );
	} else {
		std::partial_sort( &v[0], &v[k], &v[v.size()], VisibleSizeLessStrict );
	}

	// copy everything back
	[self removeAllObjects];
	for ( auto it = v.begin(), e = v.end(); it < e; ++it ) {
		id obj = *it;
		[self addObject:obj];
	}
}

@end
