//
//  Notes.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/31/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath.h"

@class OsmMapData;
@class OsmBaseObject;


@interface OsmNoteComment : NSObject
@property (readonly,nonatomic)	NSString	*	date;
@property (readonly,nonatomic)	NSString	*	action;
@property (readonly,nonatomic)	NSString	*	text;
@property (readonly,nonatomic)	NSString	*	user;
@end


@interface OsmNote : NSObject
@property (readonly,nonatomic)	NSInteger			tagId;	// a unique value we assign to track note buttons. If > 0 this is the noteID, otherwise it is assigned by us.
@property (readonly,nonatomic)	double				lat;
@property (readonly,nonatomic)	double				lon;
@property (readonly,nonatomic)	NSNumber		*	noteId;	// for Notes this is the note ID, for fixme or Keep Right it is the OSM object ID, for GPX it is the waypoint ID
@property (readonly,nonatomic)	NSString		*	created;
@property (readonly,nonatomic)	NSString		*	status;
@property (readonly,nonatomic)	NSMutableArray	*	comments;
@property (readonly,nonatomic)	BOOL				isFixme;
@property (readonly,nonatomic)	BOOL				isKeepRight;
@property (readonly,nonatomic)	BOOL				isWaypoint;

@property (readonly,nonatomic)	NSString		*	key;	// a unique identifier for a note across multiple downloads


-(instancetype)initWithLat:(double)lat lon:(double)lon;
@end



@interface OsmNotesDatabase : NSObject
{
	NSOperationQueue	*	_workQueue;
	NSMutableDictionary	*	_keepRightIgnoreList;
	NSMutableDictionary	*	_noteForTag;
	NSMutableDictionary *	_tagForKey;
}

@property (weak,nonatomic)		OsmMapData			*	mapData;

-(void)updateRegion:(OSMRect)bbox withDelay:(CGFloat)delay fixmeData:(OsmMapData *)mapData completion:(void(^)(void))completion;
-(void)updateNote:(OsmNote *)note close:(BOOL)close comment:(NSString *)comment completion:(void(^)(OsmNote * newNote, NSString * errorMessage))completion;
-(void)reset;

-(void)ignoreNote:(OsmNote *)note;
-(BOOL)isIgnored:(OsmNote *)note;

-(void)enumerateNotes:(void(^)(OsmNote * note))callback;
-(OsmNote *)noteForTag:(NSInteger)tag;

@end
