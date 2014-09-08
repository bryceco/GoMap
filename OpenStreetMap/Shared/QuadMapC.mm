//
//  QuadMap.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#include <vector>

#import "OsmObjects.h"
#import "QuadMapC.h"
#import "UndoManager.h"


static const double MinRectSize = 360.0 / (1 << 16);

#define QuadBox QuadBoxC
#define QuadMap	QuadMapC



class QuadBoxCC
{
private:
	OSMRect							_rect;
	std::vector<OsmBaseObject *>	_members;
	QuadBoxCC					*	_parent;
	QuadBoxCC					*	_children[ 4 ];
	bool							_whole;
	bool							_busy;
	bool							_isSplit;

public:
	QuadBoxCC( OSMRect rect, QuadBoxCC * parent ) : _rect(rect), _parent(parent)
	{
		_children[0] = _children[1] = _children[2] = _children[3] = NULL;
		_whole = _busy = _isSplit = false;
	}

	const OSMRect rect()
	{
		return _rect;
	}

	void reset()
	{
		_children[ 0 ] = nil;
		_children[ 1 ] = nil;
		_children[ 2 ] = nil;
		_children[ 3 ] = nil;
		_whole	= false;
		_busy = false;
		_isSplit = false;
		_members.clear();
	}

	static inline OSMRect ChildRect( QUAD_ENUM child, OSMRect parent )
	{
		assert(child <= QUAD_LAST);
		switch ( child ) {
			case QUAD_NW:
				return OSMRectMake(parent.origin.x, parent.origin.y, parent.size.width*0.5, parent.size.height*0.5);
			case QUAD_SW:
				return OSMRectMake(parent.origin.x, parent.origin.y+parent.size.height*0.5, parent.size.width*0.5, parent.size.height*0.5);
			case QUAD_SE:
				return OSMRectMake(parent.origin.x+parent.size.width*0.5, parent.origin.y+parent.size.height*0.5, parent.size.width*0.5, parent.size.height*0.5);
			case QUAD_NE:
				return OSMRectMake(parent.origin.x+parent.size.width*0.5, parent.origin.y, parent.size.width*0.5, parent.size.height*0.5);
		}
	}

	void missingPieces( std::vector<QuadBoxCC *> & pieces, OSMRect target )
	{
		if ( _whole || _busy )
			return;
		if ( ! OSMRectIntersectsRect(target, _rect ) )
			return;
		if ( _rect.size.width <= MinRectSize || _rect.size.width <= target.size.width/8 ) {
			_busy = YES;
			pieces.push_back(this);
			return;
		}
		if ( OSMRectContainsRect(target, _rect) ) {
			if ( _children[0] == nil && _children[1] == nil && _children[2] == nil && _children[3] == nil ) {
				_busy = YES;
				pieces.push_back(this);
				return;
			}
		}

		for ( int child = 0; child <= QUAD_LAST; ++child ) {
			OSMRect rc = ChildRect( (QUAD_ENUM)child, _rect );
			if ( OSMRectIntersectsRect( target, rc ) ) {

				if ( _children[child] == nil ) {
					_children[child] = new QuadBoxCC( rc, this);
				}

				_children[child]->missingPieces(pieces,target);
			}
		}
	}

	// This runs after we attempted to download a quad.
	// If the download succeeded we can mark this region and its children as whole.
	void makeWhole(BOOL success)
	{
		assert(_parent);
		if ( _parent->_whole ) {
			// parent was made whole (somehow) before we completed, so nothing to do
			return;
		}

#if DEBUG
		BOOL isCorrectChild = NO;
		for ( int child = 0; child <= QUAD_LAST; ++child ) {
			if ( this == _parent->_children[child] ) {
				isCorrectChild = YES;
				break;
			}
		}
		assert( isCorrectChild );
#endif

		if ( success ) {
			_whole = YES;
			_busy = NO;
			for ( int child = 0; child <= QUAD_LAST; ++child ) {
				_children[child] = nil;
			}
			for ( int child = 0; child <= QUAD_LAST; ++child ) {
				QuadBoxCC * c = _parent->_children[child];
				if ( c == nil || !c->_whole )
					return;
			}
			_parent->makeWhole(success);
		} else {
			_busy = NO;
		}
	}

	void enumerateWithBlock( void (^block)(QuadBoxCC * quad) )
	{
		block(this);
		for ( int child = 0; child <= QUAD_LAST; ++child ) {
			QuadBoxCC * q = _children[ child ];
			if ( q ) {
				q->enumerateWithBlock(block);
			}
		}
	}

	NSInteger quadCount()
	{
		__block NSInteger c = 0;
		this->enumerateWithBlock(^(QuadBoxCC *quad) {
			++c;
		});
		return c;
	}
	NSInteger memberCount()
	{
		__block NSInteger c = 0;
		this->enumerateWithBlock(^(QuadBoxCC *quad) {
			c += quad->_members.size();
		});
		return c;
	}

	static const NSInteger MAX_MEMBERS_PER_LEVEL = 16;

	void addMember(OsmBaseObject * member, OSMRect bbox)
	{
		if ( !_isSplit && _members.size() < MAX_MEMBERS_PER_LEVEL ) {
#if defined(DEBUG)
			// assert( !_members. containsObject:member] );
#endif
			_members.push_back(member);
			return;
		}
		if ( !_isSplit ) {
			// split self
			_isSplit = YES;
			std::vector<OsmBaseObject *> childList( _members );
			_members.clear();
			for ( const auto & c : childList ) {
				this->addMember( c, c.boundingBox );
			}
		}
		// find a child member could fit into
		NSInteger index = -1;
		for ( int child = 0; child <= QUAD_LAST; ++child ) {
			OSMRect rc = ChildRect( (QUAD_ENUM)child, _rect );
			if ( OSMRectIntersectsRect( bbox, rc ) ) {
				if ( index < 0 ) {
					index = child;	// item crosses this child
				} else {
					index = -1;		// item crosses multiple children, so has to stay in parent
					break;
				}
			}
		}
		if ( index >= 0 ) {
			// add to child quad
			if ( _children[index] == nil ) {
				OSMRect rc = ChildRect( (QUAD_ENUM)index, _rect );
				_children[index] = new QuadBoxCC( rc, this );
			}
			_children[index]->addMember(member,bbox);
		} else {
			// add to self
			_members.push_back(member);
		}
	}

	BOOL removeMember( OsmBaseObject * member, OSMRect bbox )
	{
		auto iter = std::find(_members.begin(), _members.end(), member);
		if ( iter != _members.end() ) {
			_members.erase(iter);
			return YES;
		}
		// find a child member could fit into
		for ( int child = 0; child <= QUAD_LAST; ++child ) {
			OSMRect rc = ChildRect( (QUAD_ENUM)child, _rect );
			if ( OSMRectIntersectsRect( bbox, rc ) ) {
				if ( _children[child]->removeMember( member, bbox) )
					return YES;
			}
		}
		return NO;
	}

	void findObjectsInArea( OSMRect bbox, void (^block)(OsmBaseObject *) )
	{
		for ( const auto & m : _members ) {
			block( m );
		}
		for ( int c = 0; c <= QUAD_LAST; ++c ) {
			QuadBoxCC * child = _children[ c ];
			if ( child && OSMRectIntersectsRect( bbox, child->_rect ) ) {
				child->findObjectsInArea( bbox, block );
			}
		}
	}
};


@implementation QuadBoxC

-(id)initWithRect:(OSMRect)rect
{
	self = [super init];
	if ( self ) {
		_cpp = new QuadBoxCC( rect, NULL );
	}
	return self;
}

-(void)reset
{
	_cpp->reset();
}

-(void)missingPieces:(NSMutableArray *)pieces intersectingRect:(OSMRect)target
{
	std::vector<QuadBoxCC *> missing;
	_cpp->missingPieces(missing, target);
	for ( const auto & iter : missing ) {
		OSMRect rc = iter->rect();
		OSMRectBoxed * box = [OSMRectBoxed rectWithRect:rc];
		[pieces addObject:box];
	}
}

// This runs after we attempted to download a quad.
// If the download succeeded we can mark this region and its children as whole.
-(void)makeWhole:(BOOL)success
{
	_cpp->makeWhole(success);
}

-(NSInteger)quadCount
{
	return _cpp->quadCount();
}

-(NSInteger)memberCount
{
	return _cpp->memberCount();
}

-(void)addMember:(OsmBaseObject *)member bbox:(OSMRect)bbox
{
	_cpp->addMember(member, bbox);
}

-(void)addMember:(OsmBaseObject *)member undo:(UndoManager *)undo
{
	if ( undo ) {
		[undo registerUndoWithTarget:self selector:@selector(removeMember:undo:) objects:@[member,undo]];
	}
	[self addMember:member bbox:member.boundingBox];
}

-(BOOL)removeMember:(OsmBaseObject *)member bbox:(OSMRect)bbox
{
	return _cpp->removeMember(member, bbox);
}

-(BOOL)removeMember:(OsmBaseObject *)member undo:(UndoManager *)undo
{
	BOOL ok = [self removeMember:member bbox:member.boundingBox];
	if ( ok && undo ) {
		[undo registerUndoWithTarget:self selector:@selector(addMember:undo:) objects:@[member,undo]];
	}
	return ok;
}

-(void)enumerateWithBlock:(void (^)(QuadBoxCC * quad))block
{
	_cpp->enumerateWithBlock(block);
}

-(void)findObjectsInArea:(OSMRect)bbox block:(void (^)(OsmBaseObject *))block
{
	_cpp->findObjectsInArea(bbox, block);
}


-(void)encodeWithCoder:(NSCoder *)coder
{
#if 0
	if ( [coder allowsKeyedCoding] ) {
		[coder encodeObject:_children[0]					forKey:@"child0"];
		[coder encodeObject:_children[1]					forKey:@"child1"];
		[coder encodeObject:_children[2]					forKey:@"child2"];
		[coder encodeObject:_children[3]					forKey:@"child3"];
		[coder encodeObject:_parent							forKey:@"parent"];
		[coder encodeBool:_whole							forKey:@"whole"];
		[coder encodeObject:[NSData dataWithBytes:&_rect length:sizeof _rect]	forKey:@"rect"];
		[coder encodeObject:_members						forKey:@"members"];
		[coder encodeBool:_isSplit							forKey:@"split"];
	} else {
		[coder encodeObject:_children[0]];
		[coder encodeObject:_children[1]];
		[coder encodeObject:_children[2]];
		[coder encodeObject:_children[3]];
		[coder encodeObject:_parent];
		[coder encodeBytes:&_whole length:sizeof _whole];
		[coder encodeBytes:&_rect length:sizeof _rect];
		[coder encodeObject:_members];
		[coder encodeBytes:&_isSplit length:sizeof _isSplit];
	}
#endif
}
-(id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if ( self ) {
#if 0
		if ( [coder allowsKeyedCoding] ) {
			_children[0]	= [coder decodeObjectForKey:@"child0"];
			_children[1]	= [coder decodeObjectForKey:@"child1"];
			_children[2]	= [coder decodeObjectForKey:@"child2"];
			_children[3]	= [coder decodeObjectForKey:@"child3"];
			_parent			= [coder decodeObjectForKey:@"parent"];
			_whole			= [coder decodeBoolForKey:@"whole"];
			_isSplit		= [coder decodeBoolForKey:@"split"];
			_rect			= *(OSMRect *)[[coder decodeObjectForKey:@"rect"] bytes];
			_members		= [coder decodeObjectForKey:@"members"];
		} else {
			_children[0]	= [coder decodeObject];
			_children[1]	= [coder decodeObject];
			_children[2]	= [coder decodeObject];
			_children[3]	= [coder decodeObject];
			_parent			= [coder decodeObject];
			_whole			= *(BOOL		*)[coder decodeBytesWithReturnedLength:NULL];
			_isSplit		= *(BOOL		*)[coder decodeBytesWithReturnedLength:NULL];
			_rect			= *(OSMRect		*)[coder decodeBytesWithReturnedLength:NULL];
			_members		= [coder decodeObject];
		}
#endif
	}
	return self;
}

@end


@implementation QuadMap

-(id)initWithRect:(OSMRect)rect
{
	self = [super init];
	if ( self ) {
		_rootQuad = [[QuadBox alloc] initWithRect:rect];
	}
	return self;
}

-(void)mergeDerivedRegion:(QuadMap *)other success:(BOOL)success
{
	assert( other.count == 1 );
	[self makeWhole:other->_rootQuad success:success];
}


-(NSArray *)newQuadsForRect:(OSMRect)newRect
{
	NSMutableArray * quads = [NSMutableArray new];

	assert( newRect.origin.x <= 180 && newRect.origin.x >= -180 );
	if ( newRect.origin.x + newRect.size.width > 180 ) {
		OSMRect half;
		half.origin.x = -180;
		half.size.width = newRect.origin.x + newRect.size.width - 180;
		half.origin.y = newRect.origin.y;
		half.size.height = newRect.size.height;
		[_rootQuad missingPieces:quads intersectingRect:half];
		newRect.size.width = 180 - newRect.origin.x;
	}
	[_rootQuad missingPieces:quads intersectingRect:newRect];
	return quads;
}


-(void)makeWhole:(QuadBox *)quad success:(BOOL)success
{
	[quad makeWhole:success];
}


-(void)addMember:(OsmBaseObject *)member
{
	OSMRect box = [member boundingBox];
	[_rootQuad addMember:member bbox:box];
}

-(void)removeMember:(OsmBaseObject *)member
{
	OSMRect box = [member boundingBox];
	[_rootQuad removeMember:member bbox:box];
}
-(void)findObjectsInArea:(OSMRect)bbox block:(void (^)(OsmBaseObject *))block
{
	[_rootQuad findObjectsInArea:bbox block:block];
}

-(void)enumerateWithBlock:(void (^)(QuadBoxCC * quad))block
{
	[_rootQuad enumerateWithBlock:block];
}

-(NSInteger)count
{
	__block NSInteger c = 0;
	[self enumerateWithBlock:^(QuadBoxCC * quad){
		++c;
	}];
	return c;
}

-(void)encodeWithCoder:(NSCoder *)coder
{
	if ( [coder allowsKeyedCoding] ) {
		[coder encodeObject:_rootQuad forKey:@"rootQuad"];
	} else {
		[coder encodeObject:_rootQuad];
	}
}
-(id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if ( self ) {
		if ( [coder allowsKeyedCoding] ) {
			_rootQuad	= [coder decodeObjectForKey:@"rootQuad"];
		} else {
			_rootQuad	= [coder decodeObject];
		}
	}
	return self;
}

@end
