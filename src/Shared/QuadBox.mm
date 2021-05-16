//
//  QuadMap.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#include <vector>

//#import "QuadMap.h"
//#import "MyUndoManager.h"

#if DEBUG
#define SHOW_DOWNLOAD_QUADS 0
#endif

#if SHOW_DOWNLOAD_QUADS	// Display query regions as GPX lines
//#import "AppDelegate.h"
#import "MapView.h"
//#import "GpxLayer.h"
#endif

// Don't query the server for regions smaller than this:
static const double MinRectSize = 360.0 / (1 << 16);

static const OSMRect MAP_RECT = { -180, -90, 360, 180 };

static const NSInteger MAX_MEMBERS_PER_LEVEL = 16;
static const NSInteger MAX_DEPTH = 26;	// 2 feet wide

typedef enum {
	QUAD_SE = 0,
	QUAD_SW = 1,
	QUAD_NE = 2,
	QUAD_NW = 3,
	QUAD_LAST = 3
} QUAD_ENUM;

class QuadBoxCC
{
#pragma mark Construction

private:
	OSMRect							_rect;
	std::vector<OsmBaseObject *>	_members;
	QuadBoxCC					*	_parent;
	QuadBoxCC					*	_children[ 4 ];
	double							_downloadDate;
	bool							_whole;				// this quad has already been processed
	bool							_busy;				// this quad is currently being processed
	bool							_isSplit;
	__strong QuadBox			*	_owner;
#if SHOW_DOWNLOAD_QUADS
	GpxTrack					*	_gpxTrack;
#endif

public:
	QuadBoxCC( OSMRect rect, QuadBoxCC * parent, QuadBox * owner ) : _rect(rect), _parent(parent), _owner(owner)
	{
		_children[0] = _children[1] = _children[2] = _children[3] = NULL;
		_whole = _busy = _isSplit = false;
		_downloadDate = 0.0;
		if ( _owner == nil )
			_owner = [[QuadBox alloc] initWithThis:this];
	}

	~QuadBoxCC()
	{
		if ( _parent ) {
			// remove parent's pointer to us
			for ( int c = 0; c < 4; ++c ) {
				if ( _parent->_children[c] == this ) {
					_parent->_children[c] = NULL;
				}
			}
		}

		// delete any children
		for ( int c = 0; c < 4; ++c )
			delete _children[c];
		
		[_owner nullifyCpp];
		_owner = nil;	// remove reference so it can be released

#if SHOW_DOWNLOAD_QUADS
		if ( _gpxTrack ) {
			[[AppDelegate getAppDelegate].mapView.gpxLayer deleteTrack:_gpxTrack];
		}
#endif
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
		[coder encodeDouble:_downloadDate 										forKey:@"date"];
	}
	void initWithCoder(NSCoder * coder)
	{
		QuadBox * children[4];
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
		_downloadDate	= [coder decodeDoubleForKey:@"date"];
		_parent			= NULL;
		_busy			= false;
		_owner			= NULL;

		// if we just upgraded from an older install then we may need to set a download date
		if ( _whole && _downloadDate == 0 )
			_downloadDate = NSDate.timeIntervalSinceReferenceDate;
	}
	QuadBoxCC( NSCoder * coder, QuadBox * owner )
	{
		initWithCoder(coder);
		_owner = owner;
	}

#pragma mark Common

	const OSMRect & rect() const
	{
		return _rect;
	}

	QuadBox * owner() const
	{
		return _owner;
	}

	bool hasChildren() const
	{
		return _children[0] || _children[1] || _children[2] || _children[3];
	}

	QuadBoxCC * parent()
	{
		return _parent;
	}

	double downloadDate() const
	{
		return _downloadDate;
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
		_downloadDate = 0.0;
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
	inline int childForPoint( OSMPoint point ) const
	{
		BOOL west  = point.x < _rect.origin.x + _rect.size.width*0.5;
		BOOL north = point.y < _rect.origin.y + _rect.size.height*0.5;
		return (int)north << 1 | west;
	}
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

	void enumerateWithBlock( void (^block)(const QuadBoxCC *) ) const
	{
		block(this);
		for ( int child = 0; child <= QUAD_LAST; ++child ) {
			QuadBoxCC * q = _children[ child ];
			if ( q ) {
				q->enumerateWithBlock(block);
			}
		}
	}

	QuadBoxCC * quadForRect(OSMRect target)
	{
		for ( int c = 0; c < 4; ++c ) {
			QuadBoxCC * child = _children[c];
			if ( child && OSMRectContainsRect(child->rect(), target) ) {
				return child->quadForRect(target);
			}
		}
		return this;
	}


#pragma mark Region

	void missingPieces( std::vector<QuadBoxCC *> & missing, const OSMRect & needed )
	{
		if ( _whole || _busy )
			return;
		if ( ! OSMRectIntersectsRect(needed, _rect ) )
			return;
		if ( _rect.size.width <= MinRectSize || _rect.size.width <= needed.size.width/2 || _rect.size.height <= needed.size.height/2 ) {
			_busy = YES;
			missing.push_back(this);
			return;
		}
		if ( OSMRectContainsRect(needed, _rect) ) {
			if ( !hasChildren() ) {
				_busy = YES;
				missing.push_back(this);
				return;
			}
		}

		for ( int child = 0; child <= QUAD_LAST; ++child ) {
			OSMRect rc = ChildRect( (QUAD_ENUM)child, _rect );
			if ( OSMRectIntersectsRect( needed, rc ) ) {

				if ( _children[child] == nil ) {
					_children[child] = new QuadBoxCC( rc, this, nil );
				}

				_children[child]->missingPieces(missing,needed);
			}
		}
	}

	// This runs after we attempted to download a quad.
	// If the download succeeded we can mark this region and its children as whole.
	void makeWhole(BOOL success)
	{
		if ( _parent && _parent->_whole ) {
			// parent was made whole (somehow) before we completed, so nothing to do
			if ( this->countBusy() == 0 ) {
				delete this;
			}
			return;
		}

		if ( success ) {
			_downloadDate = NSDate.timeIntervalSinceReferenceDate;
			_whole = YES;
			_busy = NO;
#if SHOW_DOWNLOAD_QUADS	// Display query regions as GPX lines
			_gpxTrack = [[AppDelegate getAppDelegate].mapView.gpxLayer createGpxRect:CGRectFromOSMRect(_rect)];
#endif
			for ( int child = 0; child <= QUAD_LAST; ++child ) {
				if ( _children[child] && _children[child]->countBusy() == 0 ) {
					delete _children[child];
				}
				_children[child] = nil;
			}
			if ( _parent ) {
				// if all children of parent exist and are whole then parent is whole as well
				bool childrenComplete = true;
				for ( int child = 0; child <= QUAD_LAST; ++child ) {
					QuadBoxCC * c = _parent->_children[child];
					if ( c == nil || !c->_whole ) {
						childrenComplete = false;
						break;
					}
				}
				if ( childrenComplete ) {
#if 1
					// we want to have fine granularity during discard phase, so don't delete children by taking the makeWhole() path
					_parent->_whole = YES;
#else
					_parent->makeWhole(success);
#endif
				}
			}
		} else {
			_busy = NO;
		}
	}

	NSInteger count() const
	{
		__block NSInteger c = 0;
		enumerateWithBlock(^(const QuadBoxCC * quad) {
			c += quad->_members.size();
		});
		return c;
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

	bool discardQuadsOlderThanDate( double date )
	{
		if ( _busy )
			return NO;

		if ( _downloadDate && _downloadDate < date ) {
			_parent->_whole = NO;
			delete this;
			return YES;
		} else {
			bool changed = NO;
			for ( int c = 0; c < 4; ++c ) {
				QuadBoxCC * child = _children[c];
				if ( child ) {
					bool del = child->discardQuadsOlderThanDate(date);
					if ( del ) {
						changed = YES;
					}
				}
			}
			if ( changed && !_whole && _downloadDate == 0 && !hasChildren() && _parent ) {
				delete this;
			}
			return changed;
		}
	}

	// discard the oldest "fraction" of quads, or oldestDate, whichever is more
	// return the cutoff date selected
	NSDate * discardOldestQuads(double fraction,NSDate * oldest)
	{
		if ( fraction ) {
			// get a list of all quads that have downloads
			__block std::vector<const QuadBoxCC *> list;
			this->enumerateWithBlock(^(const QuadBoxCC * quad) {
				if ( quad->_downloadDate ) {
					list.push_back(quad);
				}
			});
			// sort ascending by date
			std::sort( list.begin(), list.end(), ^(const QuadBoxCC *a, const QuadBoxCC * b){return a->_downloadDate < b->_downloadDate;} );

			int index = (int)(list.size() * fraction);
			double date2 = list[ index ]->downloadDate();
			if ( date2 > oldest.timeIntervalSinceReferenceDate )
				oldest = [NSDate dateWithTimeIntervalSinceReferenceDate:date2];	// be more aggressive and prune even more
		}
		return this->discardQuadsOlderThanDate(oldest.timeIntervalSinceReferenceDate) ? oldest : nil;
	}

	bool pointIsCovered( OSMPoint point ) const
	{
		if ( _downloadDate ) {
			return true;
		} else {
			int c = childForPoint(point);
			QuadBoxCC * child = _children[c];
			return child && child->pointIsCovered(point);
		}
	}
	// if any node is covered then return true (don't delete object)
	static bool nodesAreCovered( const QuadBoxCC * root, NSArray * nodeList )
	{
		const QuadBoxCC * quad = root;
		for ( OsmNode * node in nodeList ) {
			OSMPoint point = node.location;
			// move up until we find a quad containing the point
			BOOL found;
			while ( !(found = OSMRectContainsPoint( quad->rect(), point )) && quad->_parent ) {
				quad = quad->_parent;
			}
			if ( !found )
				goto next_node;
			// recurse down until we find a quad with a download date
			while ( quad->downloadDate() == 0 ) {
				int c = quad->childForPoint(point);
				QuadBoxCC * child = quad->_children[c];
				if ( child == NULL )
					goto next_node;
				quad = child;
			}
			return true;
		next_node:
			(void)0;
		}
		return false;
	}


#pragma mark Spatial

	void addMember(OsmBaseObject * member, const OSMRect & bbox, int depth)
	{
		if ( !_isSplit && (depth >= MAX_DEPTH || _members.size() < MAX_MEMBERS_PER_LEVEL) ) {
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
			QuadBoxCC * c = _children[child];
			if ( c == NULL )
				continue;
			OSMRect rc = ChildRect( (QUAD_ENUM)child, _rect );
			if ( OSMRectIntersectsRect( bbox, rc ) ) {
				if ( c->removeMember( member, bbox) )
					return YES;
			}
		}
		return NO;
	}

	static void findObjectsInAreaNonRecurse( const QuadBoxCC * top, const OSMRect & bbox, void (^block)(OsmBaseObject *) )
	{
		std::vector<const QuadBoxCC *>	stack;
		stack.reserve(32);
		stack.push_back(top);

		while ( !stack.empty() ) {

			const QuadBoxCC * q = stack.back();
			stack.pop_back();

			for ( const auto & obj : q->_members ) {
				// need to do this because we aren't using the accessor (for perf reasons) which would do it for us
				if ( obj->_boundingBox.origin.x == 0 && obj->_boundingBox.origin.y == 0 && obj->_boundingBox.size.width == 0 && obj->_boundingBox.size.height == 0 ) {
					[obj computeBoundingBox];
				}
				if ( OSMRectIntersectsRect( obj->_boundingBox, bbox ) ) {
					block( obj );
				}
			}
			for ( int c = 0; c <= QUAD_LAST; ++c ) {
				QuadBoxCC * child = q->_children[ c ];
				if ( child && OSMRectIntersectsRect( bbox, child->_rect ) ) {
					stack.push_back(child);
				}
			}
		}
	}

	void findObjectsInArea( const OSMRect & bbox, void (^block)(OsmBaseObject *) ) const
	{
		for ( const auto & obj : _members ) {
			// need to do this because we aren't using the accessor (for perf reasons) which would do it for us
			if ( obj->_boundingBox.origin.x == 0 && obj->_boundingBox.origin.y == 0 && obj->_boundingBox.size.width == 0 && obj->_boundingBox.size.height == 0 )
				[obj computeBoundingBox];

			if ( OSMRectIntersectsRect( obj->_boundingBox, bbox ) ) {
				block( obj );
			}
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

	void deleteObjectsWithPredicate( BOOL(^predicate)(OsmBaseObject * obj) )
	{
		auto last = std::remove_if( _members.begin(), _members.end(), predicate );
		_members.erase( last, _members.end() );

		for ( int c = 0; c <= QUAD_LAST; ++c ) {
			QuadBoxCC * child = _children[ c ];
			if ( child ) {
				child->deleteObjectsWithPredicate( predicate );
			}
		}
	}

	static void consistencyCheck( const QuadBoxCC * top, OsmBaseObject * object )
	{
		std::vector<const QuadBoxCC *>	stack;
		stack.reserve(32);
		stack.push_back(top);
		int foundCount = 0;

		while ( !stack.empty() ) {

			const QuadBoxCC * q = stack.back();
			stack.pop_back();

			for ( const auto & member : q->_members ) {
				if ( member == object ) {
					++foundCount;
					assert( foundCount == 1 );
					assert( OSMRectContainsRect( q->_rect, object.boundingBox ) );
				}
			}
			for ( int c = 0; c <= QUAD_LAST; ++c ) {
				QuadBoxCC * child = q->_children[ c ];
				if ( child ) {
					stack.push_back(child);
				}
			}
		}
		assert( foundCount == 1 );
	}
};





@implementation QuadBox

#pragma mark Common

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
	delete _cpp;
	_cpp = NULL;
}

-(void)reset
{
	_cpp->reset();
}

-(void)nullifyCpp
{
	_cpp = NULL;	// done only when _cpp deleted itself, and doesn't want us to use it any more in case somebody still has a reference to us
}
-(void)deleteCpp
{
	delete _cpp;	// done when we need to be destroyed, and don't want _cpp to maintain a reference to us anymore
	_cpp = NULL;
}

-(NSString *)description
{
#if TARGET_OS_IPHONE
	return NSStringFromCGRect(CGRectFromOSMRect(_cpp->rect()));
#else
	return NSStringFromRect(CGRectFromOSMRect(_cpp->rect()));
#endif
}

-(OSMRect)rect
{
	return _cpp->rect();
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

-(NSInteger)count
{
	return _cpp->count();
}

#pragma mark Region

-(double)downloadDate
{
	return _cpp->downloadDate();
}

-(void)missingPieces:(NSMutableArray *)pieces intersectingRect:(OSMRect)target
{
	std::vector<QuadBoxCC *> missing;
	_cpp->missingPieces(missing, target);
	for ( const auto & iter : missing ) {
		QuadBoxCC & q = *iter;
		QuadBox * box = q.owner();
		[pieces addObject:box];
	}
}

// This runs after we attempted to download a quad.
// If the download succeeded we can mark this region and its children as whole.
-(void)makeWhole:(BOOL)success
{
	if ( _cpp == NULL ) {
		// this should only happen if the user cleared the cache while data was downloading?
		return;
	}
	_cpp->makeWhole(success);
}

-(BOOL)nodesAreCovered:(NSArray *)nodeList
{
	return QuadBoxCC::nodesAreCovered(_cpp, nodeList);
}
-(BOOL)pointIsCovered:(OSMPoint)point
{
	return _cpp->pointIsCovered(point);
}



#pragma mark Spatial

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

-(void)findObjectsInArea:(OSMRect)bbox block:(void (^)(OsmBaseObject *))block
{
	_cpp->findObjectsInAreaNonRecurse(_cpp,bbox,block);
}

-(void)consistencyCheckObject:(OsmBaseObject *)object
{
	_cpp->consistencyCheck( _cpp, object );
}

#pragma mark Discard objects

-(BOOL)discardQuadsOlderThanDate:(NSDate *)date
{
	return _cpp->discardQuadsOlderThanDate(date.timeIntervalSinceReferenceDate);
}
-(NSDate *)discardOldestQuads:(double)fraction oldest:(NSDate *)oldest
{
	return _cpp->discardOldestQuads(fraction,oldest);
}
-(void)deleteObjectsWithPredicate:(BOOL(^)(OsmBaseObject * obj))predicate
{
	_cpp->deleteObjectsWithPredicate(predicate);
}



#pragma mark find sibling quadkeys

typedef enum DIRECTION {
	Up = 0,
	Down = 1,
	Left = 2,
	Right = 3
} DIRECTION;

static void replaceCharacterInString( NSMutableString * string, NSInteger index, unichar replacement )
{
	[string replaceCharactersInRange:NSMakeRange(index,1) withString:[NSString stringWithCharacters:&replacement length:1]];
}
static char keyCharTranslate( char keyChar, DIRECTION direction )
{
	switch ( direction ) {
		case Left:
		case Right:
			return "1032"[keyChar-'0'];
		case Up:
		case Down:
			return "2301"[keyChar-'0'];
	}
	assert(NO);
}
static void keyTranslate( NSMutableString * key, int index, DIRECTION direction )
{
	if ( key.length == 0 ) {
		return;
	}

	char savedChar = [key characterAtIndex:index];
	char replacement = keyCharTranslate(savedChar, direction);
	replaceCharacterInString(key, index, replacement );

	if ( index > 0 ) {
		if(((savedChar == '0') && (direction == Left  || direction == Up))   ||
		   ((savedChar == '1') && (direction == Right || direction == Up))   ||
		   ((savedChar == '2') && (direction == Left  || direction == Down)) ||
		   ((savedChar == '3') && (direction == Right || direction == Down)))
		{
			keyTranslate( key, index - 1, direction );
		}
	}
}
NSString * sibling( NSString * quadkey, DIRECTION direction )
{
	NSMutableString * key = [quadkey mutableCopy];
	keyTranslate( key, (int)key.length-1, direction );
	return [NSString stringWithString:key];
}

@end
