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


#define STATUS_FIXME		@"fixme"
#define STATUS_KEEPRIGHT	@"keepright"
#define STATUS_WAYPOINT		@"waypoint"


@implementation OsmNoteComment
-(instancetype)initWithNoteXml:(NSXMLElement *)noteElement
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
-(instancetype)initWithGpxWaypointObject:(OsmBaseObject *)object description:(NSString *)description
{
	self = [super init];
	if ( self ) {
		_date = object.timestamp;
		_user = object.user;
		_action = @"waypoint";
		_text = [NSString stringWithFormat:@"%@ (%@ %@): %@", object.friendlyDescription, object.isNode?@"node":object.isWay?@"way":object.isRelation?@"relation":@"", object.ident, description];
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
-(instancetype)initWithNoteXml:(NSXMLElement *)noteElement
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
					OsmNoteComment * comment = [[OsmNoteComment alloc] initWithNoteXml:commentElement];
					if ( comment ) {
						[_comments addObject:comment];
					}
				}
			}
		}
	}
	return self;
}
-(instancetype)initWithGpxWaypointXml:(NSXMLElement *)waypointElement status:(NSString *)status namespace:(NSString *)ns mapData:(OsmMapData *)mapData
{
	self = [super init];
	if ( self ) {
//		<wpt lon="-122.2009985" lat="47.6753189">
//		<name><![CDATA[website, http error]]></name>
//		<desc><![CDATA[The URL (<a target="_blank" href="http://www.stjamesespresso.com/">http://www.stjamesespresso.com/</a>) cannot be opened (HTTP status code 301)]]></desc>
//		<extensions>
//								<schema>21</schema>
//								<id>78427597</id>
//								<error_type>411</error_type>
//								<object_type>node</object_type>
//								<object_id>2627663149</object_id>
//		</extensions></wpt>

		_lon	= [waypointElement attributeForName:@"lon"].stringValue.doubleValue;
		_lat	= [waypointElement attributeForName:@"lat"].stringValue.doubleValue;
		_status = status;

		NSString * description = nil;
		OsmIdentifier osmIdent = -1;
		NSString * osmType = nil;

		for ( NSXMLElement * child in waypointElement.children ) {
			if ( [child.name isEqualToString:@"name"] ) {
				// ignore for now
			} else if ( [child.name isEqualToString:@"desc"] ) {
				description = [child stringValue];
			} else if ( [child.name isEqualToString:@"extensions"] ) {
				for ( NSXMLElement * child2 in child.children ) {
					if ( [child2.name isEqualToString:@"id"] ) {
						// _ident = @( [[child2 stringValue] integerValue] );
					} else if ( [child2.name isEqualToString:@"object_id"] ) {
						osmIdent = [[child2 stringValue] longLongValue];
					} else if ( [child2.name isEqualToString:@"object_type"] ) {
						osmType = [child2 stringValue];
					}
				}
			}
		}

		OsmBaseObject * object = nil;
		if ( description && osmIdent && osmType ) {
			if ( [osmType isEqualToString:@"node"] ) {
				object = [mapData nodeForRef:@(osmIdent)];
			} else if ( [osmType isEqualToString:@"way"] ) {
				object = [mapData wayForRef:@(osmIdent)];
			} else if ( [osmType isEqualToString:@"relation"] ) {
				object = [mapData relationForRef:@(osmIdent)];
			}
		}

		if ( object == nil )
			return nil;

		_ident	= @(object.extendedIdentifier);
		OsmNoteComment * comment = [[OsmNoteComment alloc] initWithGpxWaypointObject:object description:description];
		if ( comment ) {
			_comments = [NSMutableArray arrayWithObjects:comment,nil];
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
		_status = STATUS_FIXME;
		OsmNoteComment * comment = [[OsmNoteComment alloc] initWithFixmeObject:object fixmeKey:fixme];
		_comments = [NSMutableArray arrayWithObject:comment];
	}
	return self;
}
-(BOOL)isFixme
{
	return [_status isEqualToString:STATUS_FIXME];
}
-(BOOL)isKeepRight
{
	return [_status isEqualToString:STATUS_KEEPRIGHT];
}
-(BOOL)isWaypoint
{
	return [_status isEqualToString:STATUS_WAYPOINT];
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


-(void)updateNotesForRegion:(OSMRect)box fixmeData:(OsmMapData *)mapData completion:(void(^)(void))completion
{
	NSString * url = [OSM_API_URL stringByAppendingFormat:@"api/0.6/notes?closed=0&bbox=%f,%f,%f,%f", box.origin.x, box.origin.y, box.origin.x+box.size.width, box.origin.y+box.size.height];
	[[DownloadThreadPool osmPool] dataForUrl:url completeOnMain:NO completion:^(NSData *data, NSError *error) {
		NSMutableArray * newNotes = [NSMutableArray new];
		if ( data && error == nil ) {
			NSString * xmlText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			NSXMLDocument * xmlDoc = [[NSXMLDocument alloc] initWithXMLString:xmlText options:0 error:&error];
			for ( NSXMLElement * noteElement in [xmlDoc.rootElement nodesForXPath:@"./note" error:nil] ) {
				OsmNote * note = [[OsmNote alloc] initWithNoteXml:noteElement];
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


-(void)updateWithGpxWaypoints:(NSString *)xmlText mapData:(OsmMapData *)mapData completion:(void(^)(void))completion
{
	NSXMLDocument * xmlDoc = [[NSXMLDocument alloc] initWithXMLString:xmlText options:0 error:NULL];

	dispatch_async(dispatch_get_main_queue(), ^{

		NSXMLElement * namespace1 = [NSXMLElement namespaceWithName:@"ns1" stringValue:@"http://www.topografix.com/GPX/1/0"];
		NSXMLElement * namespace2 = [NSXMLElement namespaceWithName:@"ns2" stringValue:@"http://www.topografix.com/GPX/1/1"];
		[xmlDoc.rootElement addNamespace:namespace1];
		[xmlDoc.rootElement addNamespace:namespace2];

		for ( NSString * ns in @[ @"ns1:", @"ns2:", @"" ] ) {
			NSString * path = [NSString stringWithFormat:@"./%@gpx/%@wpt",ns,ns];
			NSArray * a = [xmlDoc nodesForXPath:path error:nil];
			for ( NSXMLElement * waypointElement in a ) {
				OsmNote * note = [[OsmNote alloc] initWithGpxWaypointXml:waypointElement status:STATUS_KEEPRIGHT namespace:ns mapData:mapData];
				if ( note ) {
					[_dict setObject:note forKey:note.ident];
				}
			}
		}
		completion();
	});
}


-(void)updateKeepRightForRegion:(OSMRect)box mapData:(OsmMapData *)mapData completion:(void(^)(void))completion
{
	NSString * template = @"http://keepright.at/export.php?format=gpx&ch=0,30,40,50,70,90,100,110,120,130,150,160,180,191,192,193,194,195,196,197,198,201,202,203,204,205,206,207,208,210,220,231,232,270,281,282,283,284,285,291,292,293,294,295,296,297,298,311,312,313,320,350,370,380,401,402,411,412,413&left=%f&bottom=%f&right=%f&top=%f";
	NSString * url = [NSString stringWithFormat:template, box.origin.x, box.origin.y, box.origin.x+box.size.width, box.origin.y+box.size.height ];
	[[DownloadThreadPool osmPool] dataForUrl:url completeOnMain:NO completion:^(NSData *data, NSError *error) {
		if ( data && error == nil ) {
			NSString * xmlText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			[self updateWithGpxWaypoints:xmlText mapData:mapData completion:completion];
		}
	}];
}


-(void)updateRegion:(OSMRect)bbox withDelay:(CGFloat)delay fixmeData:(OsmMapData *)mapData completion:(void(^)(void))completion;
{
	[_workQueue cancelAllOperations];
	[_workQueue addOperationWithBlock:^{
		usleep( 1000*(delay + 0.25) );
	}];
	[_workQueue addOperationWithBlock:^{
		[self updateNotesForRegion:bbox fixmeData:mapData completion:completion];
		[self updateKeepRightForRegion:bbox mapData:mapData completion:completion];
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
				newNote = [[OsmNote alloc] initWithNoteXml:noteElement];
				if ( newNote ) {
					[_dict setObject:newNote forKey:newNote.ident];
				}
			}
		}
		completion( newNote, postErrorMessage ?: @"Update Error" );
	}];
}


@end
