//
//  QuadMap.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#include <vector>

#import "OsmObjects.h"
#import "QuadMap.h"
#import "UndoManager.h"


static const double MinRectSize = 360.0 / (1 << 16);

static const OSMRect MAP_RECT = { -180, -90, 360, 180 };


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
	__strong QuadBoxC			*	_owner;

public:
	QuadBoxCC( OSMRect rect, QuadBoxCC * parent, QuadBoxC * owner ) : _rect(rect), _parent(parent), _owner(owner)
	{
		_children[0] = _children[1] = _children[2] = _children[3] = NULL;
		_whole = _busy = _isSplit = false;
		if ( _owner == nil )
			_owner = [[QuadBoxC alloc] initWithThis:this];
	}

	~QuadBoxCC()
	{
		reset();
		_owner = nil;
	}

	const OSMRect rect() const
	{
		return _rect;
	}

	QuadBoxC * owner() const
	{
		return _owner;
	}

	void reset()
	{
		delete _children[ 0 ];	_children[ 0 ] = NULL;
		delete _children[ 1 ];	_children[ 1 ] = NULL;
		delete _children[ 2 ];	_children[ 2 ] = NULL;
		delete _children[ 3 ];	_children[ 3 ] = NULL;
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

	// find a child member could fit into
	int childForRect( const OSMRect & child ) const
	{
		double midX = _rect.origin.x + _rect.size.width*0.5;
		double midY = _rect.origin.y + _rect.size.height*0.5;
		BOOL west = NO;
		BOOL north = NO;
		if ( child.origin.x < midX ) {
			// west
			if ( child.origin.x + child.size.width >= midX )
				return -1;
			west = YES;
		}
		if ( child.origin.y < midY ) {
			// north
			if ( child.origin.y + child.size.height >= midY )
				return -1;
			north = YES;
		}
		return (int)north << 1 | west;
	}

	void missingPieces( std::vector<QuadBoxCC *> & pieces, const OSMRect & target )
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
					_children[child] = new QuadBoxCC( rc, this, nil );
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
				delete _children[child];
				_children[child] = nil;
			}
			if ( _parent ) {
				// if all children of parent exist and are whole then parent is whole as well
				for ( int child = 0; child <= QUAD_LAST; ++child ) {
					QuadBoxCC * c = _parent->_children[child];
					if ( c == nil || !c->_whole )
						return;
				}
				_parent->makeWhole(success);
			}
		} else {
			_busy = NO;
		}
	}

	void enumerateWithBlock( void (^block)(const QuadBoxCC * quad) ) const
	{
		block(this);
		for ( int child = 0; child <= QUAD_LAST; ++child ) {
			QuadBoxCC * q = _children[ child ];
			if ( q ) {
				q->enumerateWithBlock(block);
			}
		}
	}

	NSInteger countBusy() const
	{
		NSInteger c = _busy ? 1 : 0;
		for ( int i = 0; i < 4; ++i ) {
			QuadBoxCC * child = _children[i];
			if ( child )
				c += child->countBusy();
		}
		return c;
	}

	static const NSInteger MAX_MEMBERS_PER_LEVEL = 16;

	void addMember(OsmBaseObject * member, const OSMRect & bbox, int depth)
	{
		if ( depth > 100 ) {
			NSLog(@"deep");
		}

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
				this->addMember( c, c.boundingBox, depth );
			}
		}
		// find a child member could fit into
		NSInteger index = childForRect( bbox );
		if ( index >= 0 ) {
			// add to child quad
			if ( _children[index] == nil ) {
				OSMRect rc = ChildRect( (QUAD_ENUM)index, _rect );
				_children[index] = new QuadBoxCC( rc, this, nil );
			}
			_children[index]->addMember(member,bbox,depth+1);
		} else {
			// add to self
			_members.push_back(member);
		}
	}

	BOOL removeMember( OsmBaseObject * member, const OSMRect & bbox )
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

	void findObjectsInArea( const OSMRect & bbox, void (^block)(OsmBaseObject *) ) const
	{
		for ( const auto & obj : _members ) {
			if ( OSMRectIntersectsRect( obj->_boundingBox, bbox ) )
				block( obj );
		}
		for ( int c = 0; c <= QUAD_LAST; ++c ) {
			QuadBoxCC * child = _children[ c ];
			if ( child && OSMRectIntersectsRect( bbox, child->_rect ) ) {
				child->findObjectsInArea( bbox, block );
			}
		}
	}


	QuadBoxCC * getQuadBoxMember(OsmBaseObject * member, const OSMRect & bbox) const
	{
		auto iter = std::find(_members.begin(), _members.end(), member);
		if ( iter != _members.end() ) {
			return const_cast<QuadBoxCC *>(this);
		}

		// find a child member could fit into
		for ( int child = 0; child <= QUAD_LAST; ++child ) {
			OSMRect rc = ChildRect( (QUAD_ENUM)child, _rect );
			if ( OSMRectIntersectsRect( bbox, rc ) ) {
				return _children[child] ? _children[child]->getQuadBoxMember(member, bbox) : NULL;
			}
		}
		return NULL;
	}

	void encodeWithCoder(NSCoder * coder) const
	{
		if ( _children[0] )	{ [coder encodeObject:_children[0]->owner()	forKey:@"child0"]; }
		if ( _children[1] ) { [coder encodeObject:_children[1]->owner()	forKey:@"child1"]; }
		if ( _children[2] ) { [coder encodeObject:_children[2]->owner()	forKey:@"child2"]; }
		if ( _children[3] ) { [coder encodeObject:_children[3]->owner()	forKey:@"child3"]; }
		[coder encodeBool:_whole												forKey:@"whole"];
		[coder encodeObject:[NSData dataWithBytes:&_rect length:sizeof _rect]	forKey:@"rect"];
		[coder encodeBool:_isSplit												forKey:@"split"];
		//		[coder encodeObject:_parent							forKey:@"parent"];
		//		[coder encodeObject:_members						forKey:@"members"];
	}
	void initWithCoder(NSCoder * coder)
	{
		QuadBoxC * children[4];
		children[0]	= [coder decodeObjectForKey:@"child0"];
		children[1]	= [coder decodeObjectForKey:@"child1"];
		children[2]	= [coder decodeObjectForKey:@"child2"];
		children[3]	= [coder decodeObjectForKey:@"child3"];
		for ( NSInteger i = 0; i < 4; ++i ) {
			if ( children[i] ) {
				_children[i] = children[i].cpp;
				_children[i]->_parent = this;
			} else {
				_children[i] = NULL;
			}
		}
		_whole			= [coder decodeBoolForKey:@"whole"];
		_isSplit		= [coder decodeBoolForKey:@"split"];
		_rect			= *(OSMRect *)[[coder decodeObjectForKey:@"rect"] bytes];
		_parent			= NULL;
		//		_parent			= [coder decodeObjectForKey:@"parent"];
		//		_members		= [coder decodeObjectForKey:@"members"];
	}
	QuadBoxCC( NSCoder * coder, QuadBoxC * owner )
	{
		initWithCoder(coder);
		_owner = owner;
	}
};



@implementation QuadBoxC

-(instancetype)initWithRect:(OSMRect)rect
{
	self = [super init];
	if ( self ) {
		_cpp = new QuadBoxCC( rect, NULL, self );
	}
	return self;
}

-(instancetype)init
{
	return [self initWithRect:MAP_RECT];
}

-(instancetype)initWithThis:(QuadBoxCC *)cpp
{
	self = [super init];
	if ( self ) {
		assert(cpp);
		_cpp = cpp;
	}
	return self;
}



-(void)dealloc
{
}

-(void)reset
{
	_cpp->reset();
}

-(OSMRect)rect
{
	return _cpp->rect();
}

-(void)missingPieces:(NSMutableArray *)pieces intersectingRect:(OSMRect)target
{
	std::vector<QuadBoxCC *> missing;
	_cpp->missingPieces(missing, target);
	for ( const auto & iter : missing ) {
		QuadBoxCC & q = *iter;
		QuadBoxC * box = q.owner();
		[pieces addObject:box];
	}
}

// This runs after we attempted to download a quad.
// If the download succeeded we can mark this region and its children as whole.
-(void)makeWhole:(BOOL)success
{
	_cpp->makeWhole(success);
}

-(void)addMember:(OsmBaseObject *)member bbox:(OSMRect)bbox
{
	if ( bbox.origin.x == 0 && bbox.origin.y == 0 && bbox.size.width == 0 && bbox.size.height == 0 )
		return;
	_cpp->addMember(member, bbox, 0);
}

-(BOOL)removeMember:(OsmBaseObject *)member bbox:(OSMRect)bbox
{
	return _cpp->removeMember(member, bbox);
}

-(instancetype)getQuadBoxMember:(OsmBaseObject *)member bbox:(OSMRect)bbox
{
	QuadBoxCC * c = _cpp->getQuadBoxMember(member, bbox);
	if ( c )
		return c->owner();
	return nil;
}





-(void)enumerateWithBlock:(void (^)(const struct QuadBoxCC * quad))block
{
	_cpp->enumerateWithBlock(block);
}

-(void)findObjectsInArea:(OSMRect)bbox block:(void (^)(OsmBaseObject *))block
{
	_cpp->findObjectsInArea(bbox, block);
}


-(void)encodeWithCoder:(NSCoder *)coder
{
	_cpp->encodeWithCoder(coder);
}
-(id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if ( self ) {
		_cpp = new QuadBoxCC( coder, self );
	}
	return self;
}

@end
