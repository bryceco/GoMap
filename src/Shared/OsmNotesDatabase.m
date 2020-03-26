//
//  Notes.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/31/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#if TARGET_OS_IPHONE
#import "DDXML.h"
#endif

#import "OsmNotesDatabase.h"
#import "OsmMapData.h"


static NSArray * FixMeList = nil;


#define STATUS_FIXME		@"fixme"
#define STATUS_KEEPRIGHT	@"keepright"
#define STATUS_WAYPOINT		@"waypoint"


static NSInteger g_nextTagID = 1;


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
-(instancetype)initWithGpxWaypoint:(NSString *)objectName description:(NSString *)description
{
	self = [super init];
	if ( self ) {
		_date = nil;
		_user = nil;
		_action = @"waypoint";
		_text = [NSString stringWithFormat:@"%@: %@", objectName, description];
	}
	return self;
}
-(NSString *)description
{
	return [NSString stringWithFormat:@"%@: %@", _action, _text];
}
@end


@implementation OsmNote
-(instancetype)initWithLat:(double)lat lon:(double)lon
{
	self = [super init];
	if ( self ) {
		_tagId	= g_nextTagID++;
		_lat	= lat;
		_lon	= lon;
	}
	return self;
}
-(instancetype)initWithNoteXml:(NSXMLElement *)noteElement
{
	self = [super init];
	if ( self ) {
		_tagId	= g_nextTagID++;
		_lat	= [noteElement attributeForName:@"lat"].stringValue.doubleValue;
		_lon	= [noteElement attributeForName:@"lon"].stringValue.doubleValue;
		for ( NSXMLElement * child in noteElement.children ) {
			if ( [child.name isEqualToString:@"id"] ) {
				_noteId = @(child.stringValue.integerValue);
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

		_tagId	= g_nextTagID++;
		_lon	= [waypointElement attributeForName:@"lon"].stringValue.doubleValue;
		_lat	= [waypointElement attributeForName:@"lat"].stringValue.doubleValue;
		_status = status;

		NSString * description = nil;
		NSNumber * osmIdent = nil;
		NSString * osmType = nil;

		for ( NSXMLElement * child in waypointElement.children ) {
			if ( [child.name isEqualToString:@"name"] ) {
				// ignore for now
			} else if ( [child.name isEqualToString:@"desc"] ) {
				description = [child stringValue];
			} else if ( [child.name isEqualToString:@"extensions"] ) {
				for ( NSXMLElement * child2 in child.children ) {
					if ( [child2.name isEqualToString:@"id"] ) {
						_noteId = @( [[child2 stringValue] integerValue] );
					} else if ( [child2.name isEqualToString:@"object_id"] ) {
						osmIdent = @( [[child2 stringValue] longLongValue] );
					} else if ( [child2.name isEqualToString:@"object_type"] ) {
						osmType = [child2 stringValue];
					}
				}
			}
		}

		OsmBaseObject * object = nil;
		OSM_TYPE type = (OSM_TYPE)0;
		if ( osmIdent && osmType ) {
			if ( [osmType isEqualToString:@"node"] ) {
				type = OSM_TYPE_NODE;
				object = [mapData nodeForRef:osmIdent];
			} else if ( [osmType isEqualToString:@"way"] ) {
				type = OSM_TYPE_WAY;
				object = [mapData wayForRef:osmIdent];
			} else if ( [osmType isEqualToString:@"relation"] ) {
				type = OSM_TYPE_RELATION;
				object = [mapData relationForRef:osmIdent];
			}
		}
		NSString * objectName = object ? [NSString stringWithFormat:@"%@ (%@ %@)", object.friendlyDescription, osmType, osmIdent] : [NSString stringWithFormat:@"%@ %@", osmType, osmIdent];

		_noteId	= @( [OsmBaseObject extendedIdentifierForType:type identifier:osmIdent.longLongValue] );
		OsmNoteComment * comment = [[OsmNoteComment alloc] initWithGpxWaypoint:objectName description:description];
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
		OSMPoint center = object.selectionPoint;
		_tagId		= g_nextTagID++;
		_noteId		= @(object.extendedIdentifier);
		_lat		= center.y;
		_lon		= center.x;
		_created	= object.timestamp;
		_status		= STATUS_FIXME;
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
	NSMutableString * text = [NSMutableString stringWithFormat:@"Note %@ - %@:\n", _noteId, _status];
	for ( OsmNoteComment * comment in _comments ) {
		[text appendString:[NSString stringWithFormat:@"  %@\n",comment.description]];
	}
	return text;
}

-(NSString *)key
{
	if ( self.isFixme )
		return [NSString stringWithFormat:@"fixme-%@",_noteId];
	if ( self.isWaypoint )
		return [NSString stringWithFormat:@"waypoint-%@",_noteId];
	if ( self.isKeepRight )
		return [NSString stringWithFormat:@"keepright-%@",_noteId];
	return [NSString stringWithFormat:@"note-%@",_noteId];
}



@end


@implementation OsmNotesDatabase

-(instancetype)init
{
	self = [super init];
	if ( self ) {
		_noteForTag = [NSMutableDictionary new];
		_tagForKey  = [NSMutableDictionary new];
		_workQueue = [NSOperationQueue new];
		_workQueue.maxConcurrentOperationCount = 1;

		FixMeList = @[ @"fixme", @"FIXME" ];	// there are many others but not frequently used
	}
	return self;
}

-(void)reset
{
	[_workQueue cancelAllOperations];
	[_noteForTag removeAllObjects];
	[_tagForKey removeAllObjects];
}

-(void)addOrUpdateNote:(OsmNote *)newNote
{
	NSString * key = newNote.key;
	NSNumber * oldTag = _tagForKey[ key ];
	NSNumber * newTag = @(newNote.tagId);
	if ( oldTag ) {
		// remove any existing tag with the same key
		[_noteForTag removeObjectForKey:oldTag];
	}
	_tagForKey[key] = newTag;
	_noteForTag[newTag] = newNote;
}

-(void)updateNotesForRegion:(OSMRect)box fixmeData:(OsmMapData *)mapData completion:(void(^)(void))completion
{
	NSString * url = [OSM_API_URL stringByAppendingFormat:@"api/0.6/notes?closed=0&bbox=%f,%f,%f,%f", box.origin.x, box.origin.y, box.origin.x+box.size.width, box.origin.y+box.size.height];
	NSURLSessionDataTask * task = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
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
				[self addOrUpdateNote:note];
			}

			// add FIXMEs
			[mapData enumerateObjectsInRegion:box block:^(OsmBaseObject *obj) {
				for ( NSString * key in FixMeList ) {
					NSString * fixme = obj.tags[key];
					if ( fixme.length > 0 ) {
						OsmNote * note = [[OsmNote alloc] initWithFixmeObject:obj fixmeKey:key];
						[self addOrUpdateNote:note];
						break;
					}
				}
			}];

			completion();
		});
	}];
	[task resume];
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
					[self addOrUpdateNote:note];
				}
			}
		}
		completion();
	});
}


-(void)updateKeepRightForRegion:(OSMRect)box mapData:(OsmMapData *)mapData completion:(void(^)(void))completion
{
	NSString * template = @"https://keepright.at/export.php?format=gpx&ch=0,30,40,70,90,100,110,120,130,150,160,180,191,192,193,194,195,196,197,198,201,202,203,204,205,206,207,208,210,220,231,232,270,281,282,283,284,285,291,292,293,294,295,296,297,298,311,312,313,320,350,370,380,401,402,411,412,413&left=%f&bottom=%f&right=%f&top=%f";
	NSString * url = [NSString stringWithFormat:template, box.origin.x, box.origin.y, box.origin.x+box.size.width, box.origin.y+box.size.height ];
	
	NSURLSessionDataTask * task = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		if ( data && error == nil ) {
			NSString * xmlText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			[self updateWithGpxWaypoints:xmlText mapData:mapData completion:completion];
		}
	}];
	[task resume];
}


-(void)updateRegion:(OSMRect)bbox withDelay:(CGFloat)delay fixmeData:(OsmMapData *)mapData completion:(void(^)(void))completion;
{
	[_workQueue cancelAllOperations];
	[_workQueue addOperationWithBlock:^{
		usleep( 1000*(delay + 0.25) );
	}];
	[_workQueue addOperationWithBlock:^{
		[self updateNotesForRegion:bbox fixmeData:mapData completion:completion];
	}];
}


-(void)enumerateNotes:(void(^)(OsmNote * note))callback
{
	[_noteForTag enumerateKeysAndObjectsUsingBlock:^(NSString * key, OsmNote * note, BOOL * stop) {
		callback( note );
	}];
}



-(NSString *)description
{
	__block NSMutableString * text = [NSMutableString new];
	[_noteForTag enumerateKeysAndObjectsUsingBlock:^(id key, OsmNote * note, BOOL *stop) {
		[text appendString:[note description]];
	}];
	return text;;
}

-(void)updateNote:(OsmNote *)note close:(BOOL)close comment:(NSString *)comment completion:(void(^)(OsmNote * newNote, NSString * errorMessage))completion
{
	comment = [comment stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];

	NSString * url;
	if ( note.comments == nil ) {
		// brand new note
		url = [OSM_API_URL stringByAppendingFormat:@"api/0.6/notes?lat=%f&lon=%f&text=%@", note.lat, note.lon, comment];
	} else {
		// existing note
		if ( close ) {
			url = [OSM_API_URL stringByAppendingFormat:@"api/0.6/notes/%@/close?text=%@", note.noteId, comment];
		} else {
			url = [OSM_API_URL stringByAppendingFormat:@"api/0.6/notes/%@/comment?text=%@", note.noteId, comment];
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
					[self addOrUpdateNote:newNote];
				}
			}
		}
		completion( newNote, postErrorMessage ?: @"Update Error" );
	}];
}

-(OsmNote *)noteForTag:(NSInteger)tag
{
	return _noteForTag[ @(tag) ];
}

#pragma mark Ignore list

-(NSMutableDictionary *)ignoreList
{
	if ( _keepRightIgnoreList == nil ) {
		NSString * path = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"keepRightIgnoreList"];
		_keepRightIgnoreList = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
		if ( _keepRightIgnoreList == nil )
			_keepRightIgnoreList = [NSMutableDictionary new];
	}
	return _keepRightIgnoreList;
}

-(void)ignoreNote:(OsmNote *)note
{
	[self.ignoreList setObject:@YES forKey:@(note.tagId)];

	NSString * path = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"keepRightIgnoreList"];
	[NSKeyedArchiver archiveRootObject:_keepRightIgnoreList toFile:path];
}

-(BOOL)isIgnored:(OsmNote *)note
{
	if ( self.ignoreList[@(note.tagId)] )
		return YES;
	return NO;
}


@end
