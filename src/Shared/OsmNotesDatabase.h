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
@property (readonly,nonatomic)	NSString	*_Nonnull	date;
@property (readonly,nonatomic)	NSString	*_Nonnull	action;
@property (readonly,nonatomic)	NSString	*_Nonnull	text;
@property (readonly,nonatomic)	NSString	*_Nonnull	user;
@end


@interface OsmNote : NSObject
@property (readonly,nonatomic)	NSInteger			tagId;	// a unique value we assign to track note buttons. If > 0 this is the noteID, otherwise it is assigned by us.
@property (readonly,nonatomic)	double				lat;
@property (readonly,nonatomic)	double				lon;
@property (readonly,nonatomic)	NSNumber		*_Nonnull	noteId;	// for Notes this is the note ID, for fixme or Keep Right it is the OSM object ID, for GPX it is the waypoint ID
@property (readonly,nonatomic)	NSString		*_Nonnull	created;
@property (readonly,nonatomic)	NSString		*_Nonnull	status;
@property (readonly,nonatomic)	NSMutableArray<OsmNoteComment *>	*_Nonnull	comments;
@property (readonly,nonatomic)	BOOL				isFixme;
@property (readonly,nonatomic)	BOOL				isKeepRight;
@property (readonly,nonatomic)	BOOL				isWaypoint;

@property (readonly,nonatomic)	NSString		*_Nonnull	key;	// a unique identifier for a note across multiple downloads


-(instancetype _Nonnull)initWithLat:(double)lat lon:(double)lon;
@end



@interface OsmNotesDatabase : NSObject
{
	NSOperationQueue	*	_workQueue;
	NSMutableDictionary	*	_keepRightIgnoreList;
	NSMutableDictionary	*	_noteForTag;
	NSMutableDictionary *	_tagForKey;
}

@property (weak,nonatomic)		OsmMapData			*_Nullable	mapData;

-(void)updateRegion:(OSMRect)bbox withDelay:(CGFloat)delay fixmeData:(OsmMapData *_Nonnull)mapData completion:(void(^_Nonnull)(void))completion;
-(void)updateNote:(OsmNote *_Nonnull)note close:(BOOL)close comment:(NSString *_Nonnull)comment completion:(void(^_Nonnull)(OsmNote *_Nullable newNote, NSString *_Nullable errorMessage))completion;
-(void)reset;

-(void)ignoreNote:(OsmNote *_Nonnull)note;
-(BOOL)isIgnored:(OsmNote *_Nonnull)note;

-(void)enumerateNotes:(void(^_Nonnull)(OsmNote *_Nonnull note))callback;
-(OsmNote *_Nullable)noteForTag:(NSInteger)tag;

@end
