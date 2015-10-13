//
//  Notes.m
//  Go Map!!
//
//  Created by Bryce on 8/31/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#if TARGET_OS_IPHONE
#import "DDXML.h"
#endif

#import "DownloadThreadPool.h"
#import "OsmNotesDatabase.h"
#import "OsmMapData.h"
#import "OsmObjects.h"


static NSArray * FixMeList = nil;


@implementation OsmNoteComment
-(instancetype)initWithXml:(NSXMLElement *)noteElement
{
	self = [super init];
	if ( self ) {
		for ( NSXMLElement * child in noteElement.children ) {
			if ( [child.name isEqualToString:@"date"] ) {
				_date = child.stringValue;
			} else if ( [child.name isEqualToString:@"user"] ) {
				_user = child.stringValue;
			} else if ( [child.name isEqualToString:@"action"] ) {
				_action = child.stringValue;
			} else if ( [child.name isEqualToString:@"text"] ) {
				_text = [child.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			}
		}
	}
	return self;
}
-(instancetype)initWithFixmeObject:(OsmBaseObject *)object fixmeKey:(NSString *)fixme
{
	self = [super init];
	if ( self ) {
		_date = object.timestamp;
		_user = object.user;
		_action = @"fixme";
		_text = [NSString stringWithFormat:@"%@ (%@ %@): %@", object.friendlyDescription, object.isNode?@"node":object.isWay?@"way":object.isRelation?@"relation":@"", object.ident, object.tags[fixme]];
	}
	return self;
}
-(NSString *)description
{
	return [NSString stringWithFormat:@"%@ %@ %@: %@",_date,_user?:@"",_action,_text];
}
@end


@implementation OsmNote
-(instancetype)initWithLat:(double)lat lon:(double)lon
{
	self = [super init];
	if ( self ) {
		_lat		= lat;
		_lon		= lon;
	}
	return self;
}
-(instancetype)initWithXml:(NSXMLElement *)noteElement
{
	self = [super init];
	if ( self ) {
		_lat	= [noteElement attributeForName:@"lat"].stringValue.doubleValue;
		_lon	= [noteElement attributeForName:@"lon"].stringValue.doubleValue;
		for ( NSXMLElement * child in noteElement.children ) {
			if ( [child.name isEqualToString:@"id"] ) {
				_ident = @(child.stringValue.integerValue);
			} else if ( [child.name isEqualToString:@"date_created"] ) {
				_created = child.stringValue;
			} else if ( [child.name isEqualToString:@"status"] ) {
				_status = child.stringValue;
			} else if ( [child.name isEqualToString:@"comments"] ) {
				_comments = [NSMutableArray new];
				for ( NSXMLElement * commentElement in child.children ) {
					OsmNoteComment * comment = [[OsmNoteComment alloc] initWithXml:commentElement];
					if ( comment ) {
						[_comments addObject:comment];
					}
				}
			}
		}
	}
	return self;
}
-(instancetype)initWithFixmeObject:(OsmBaseObject *)object fixmeKey:(NSString *)fixme
{
	self = [super init];
	if ( self ) {
		OSMPoint center = object.isNode ? OSMPointMake(object.isNode.lon, object.isNode.lat) : object.isWay ? object.isWay.centerPoint : object.isRelation.centerPoint;
		_ident	= @(object.extendedIdentifier);
		_lat	= center.y;
		_lon	= center.x;
		_created = object.timestamp;
		_status = @"fixme";
		OsmNoteComment * comment = [[OsmNoteComment alloc] initWithFixmeObject:object fixmeKey:fixme];
		_comments = [NSMutableArray arrayWithObject:comment];
	}
	return self;
}
-(BOOL)isFixme
{
	return [_status isEqualToString:@"fixme"];
}
-(NSString *)description
{
	NSMutableString * text = [NSMutableString stringWithFormat:@"Note %@ - %@:\n", _ident,_status];
	for ( OsmNoteComment * comment in _comments ) {
		[text appendString:[NSString stringWithFormat:@"  %@\n",comment.description]];
	}
	return text;
}
@end


@implementation OsmNotesDatabase

-(instancetype)init
{
	self = [super init];
	if ( self ) {
		_dict = [NSMutableDictionary new];
		_workQueue = [NSOperationQueue new];
		_workQueue.maxConcurrentOperationCount = 1;

		FixMeList = @[ @"fixme", @"FIXME" ];	// there are many others but not frequently used
	}
	return self;
}

-(void)reset
{
	[_workQueue cancelAllOperations];
	[_dict removeAllObjects];
}

#if 0
-(void)updateObject:(OsmBaseObject *)object
{
	NSNumber * ident = @(object.extendedIdentifier);
	[_dict removeObjectForKey:ident];

	for ( NSString * key in FixMeList ) {
		NSString * fixme = object.tags[key];
		if ( fixme.length > 0 ) {
			OsmNote * note = [[OsmNote alloc] initWithFixmeObject:object fixmeKey:key];
			[_dict setObject:note forKey:note.ident];
			break;
		}
	}
}
#endif

-(void)updateForRegion:(OSMRect)box fixmeData:(OsmMapData *)mapData completion:(void(^)(void))completion
{
	NSString * url = [OSM_API_URL stringByAppendingFormat:@"api/0.6/notes?closed=0&bbox=%f,%f,%f,%f", box.origin.x, box.origin.y, box.origin.x+box.size.width, box.origin.y+box.size.height];
	[[DownloadThreadPool osmPool] dataForUrl:url completeOnMain:NO completion:^(NSData *data, NSError *error) {
		NSMutableArray * newNotes = [NSMutableArray new];
		if ( data && error == nil ) {
			NSString * xmlText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			NSXMLDocument * xmlDoc = [[NSXMLDocument alloc] initWithXMLString:xmlText options:0 error:&error];
			for ( NSXMLElement * noteElement in [xmlDoc.rootElement nodesForXPath:@"./note" error:nil] ) {
				OsmNote * note = [[OsmNote alloc] initWithXml:noteElement];
				if ( note ) {
					[newNotes addObject:note];
				}
			}
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			// add downloaded notes
			for ( OsmNote * note in newNotes ) {
				[_dict setObject:note forKey:note.ident];
			}

			// add FIXMEs
			[mapData enumerateObjectsInRegion:box block:^(OsmBaseObject *obj) {
				for ( NSString * key in FixMeList ) {
					NSString * fixme = obj.tags[key];
					if ( fixme.length > 0 ) {
						OsmNote * note = [[OsmNote alloc] initWithFixmeObject:obj fixmeKey:key];
						[_dict setObject:note forKey:note.ident];
						break;
					}
				}
			}];

			completion();
		});
	}];
}

-(void)updateRegion:(OSMRect)bbox withDelay:(CGFloat)delay fixmeData:(OsmMapData *)mapData completion:(void(^)(void))completion;
{
	[_workQueue cancelAllOperations];
	[_workQueue addOperationWithBlock:^{
		usleep( 1000*(delay + 0.25) );
	}];
	[_workQueue addOperationWithBlock:^{
		[self updateForRegion:bbox fixmeData:mapData completion:completion];
	}];
}



-(NSString *)description
{
	__block NSMutableString * text = [NSMutableString new];
	[_dict enumerateKeysAndObjectsUsingBlock:^(id key, OsmNote * note, BOOL *stop) {
		[text appendString:[note description]];
	}];
	return text;;
}

-(void)updateNote:(OsmNote *)note close:(BOOL)close comment:(NSString *)comment completion:(void(^)(OsmNote * newNote, NSString * errorMessage))completion
{
	CFStringRef eStr = CFURLCreateStringByAddingPercentEscapes(
															   kCFAllocatorDefault,
															   (CFStringRef)comment,
															   NULL,
															   CFSTR("!'\"/%&=?$#+-~@<>|\\*;:,.()[]{}^! "),
															   kCFStringEncodingUTF8
															   );
	comment = (__bridge_transfer NSString *)eStr;

	NSString * url;
	if ( note.comments == nil ) {
		// brand new note
		url = [OSM_API_URL stringByAppendingFormat:@"api/0.6/notes?lat=%f&lon=%f&text=%@", note.lat, note.lon, comment];
	} else {
		// existing note
		if ( close ) {
			url = [OSM_API_URL stringByAppendingFormat:@"api/0.6/notes/%@/close?text=%@", note.ident, comment];
		} else {
			url = [OSM_API_URL stringByAppendingFormat:@"api/0.6/notes/%@/comment?text=%@", note.ident, comment];
		}
	}

	[_mapData putRequest:url method:@"POST" xml:nil completion:^(NSData *postData,NSString * postErrorMessage) {
		OsmNote * newNote = nil;
		if ( postData && postErrorMessage == nil ) {
			NSString * xmlText = [[NSString alloc] initWithData:postData encoding:NSUTF8StringEncoding];
			NSError * error = nil;
			NSXMLDocument * xmlDoc = [[NSXMLDocument alloc] initWithXMLString:xmlText options:0 error:&error];
			for ( NSXMLElement * noteElement in [xmlDoc.rootElement nodesForXPath:@"./note" error:nil] ) {
				newNote = [[OsmNote alloc] initWithXml:noteElement];
				if ( newNote ) {
					[_dict setObject:newNote forKey:newNote.ident];
				}
			}
		}
		completion( newNote, postErrorMessage ?: @"Update Error" );
	}];
}


@end
