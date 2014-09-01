//
//  BingMetadataViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 1/6/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "MapView.h"
#import "BingMetadataViewController.h"
#import "MercatorTileLayer.h"

// http://www.microsoft.com/maps/attribution.aspx


@implementation BingMetadataViewController


- (void)viewDidLoad
{
    [super viewDidLoad];

	[self.activityIndicator startAnimating];

	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
	OSMRect viewRect = [appDelegate.mapView viewportLongitudeLatitude];
	NSInteger zoomLevel = [appDelegate.mapView.aerialLayer zoomLevel];
	if ( zoomLevel > 21 )
		zoomLevel = 21;

	[appDelegate.mapView.aerialLayer metadata:^(NSData * data, NSError * error){
		[self.activityIndicator stopAnimating];
		
		if ( data && !error ) {
			id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];

			NSMutableArray * attrList = [NSMutableArray new];

			NSArray * resourceSets = [json objectForKey:@"resourceSets"];
			for ( id resourceSet in resourceSets ) {
				id resources = [resourceSet objectForKey:@"resources"];
				for ( id resource in resources ) {
					NSString * vintageStart = [resource objectForKey:@"vintageStart"];
					NSString * vintageEnd   = [resource objectForKey:@"vintageEnd"];
					id providers = [resource objectForKey:@"imageryProviders"];
					if ( providers != [NSNull null] ) {
						for ( id provider in providers ) {
							NSString * attribution = [provider objectForKey:@"attribution"];
							NSArray * areas = [provider objectForKey:@"coverageAreas"];
							for ( NSDictionary * area in areas ) {
								NSInteger zoomMin = [[area objectForKey:@"zoomMin"] integerValue];
								NSInteger zoomMax = [[area objectForKey:@"zoomMax"] integerValue];
								NSArray * bbox = [area objectForKey:@"bbox"];
								OSMRect rect = {
									[bbox[1] doubleValue],
									[bbox[0] doubleValue],
									[bbox[3] doubleValue],
									[bbox[2] doubleValue]
								};
								rect.size.width  -= rect.origin.x;
								rect.size.height -= rect.origin.y;
								if ( zoomLevel >= zoomMin && zoomLevel <= zoomMax && OSMRectIntersectsRect(viewRect, rect) ) {
									if ( vintageStart && vintageEnd && vintageStart != (id)[NSNull null] && vintageEnd != (id)[NSNull null] ) {
										attribution = [NSString stringWithFormat:@"%@\n   %@ - %@",attribution, vintageStart, vintageEnd];
									}
									[attrList addObject:attribution];
								}
							}
						}
					}
				}
			}

			[attrList sortUsingComparator:^NSComparisonResult(NSString * obj1, NSString * obj2) {
				if ( [obj1 rangeOfString:@"Microsoft"].location != NSNotFound )
					return -1;
				if ( [obj2 rangeOfString:@"Microsoft"].location != NSNotFound )
					return 1;
				return [obj1 compare:obj2];
			}];

			NSString * text = [attrList componentsJoinedByString:@"\n\n• "];
			self.textView.text = [NSString stringWithFormat:NSLocalizedString(@"Background imagery %@",nil), text];

		} else if ( error ) {
			self.textView.text = [NSString stringWithFormat:NSLocalizedString(@"Error fetching metadata: %@",nil), error.localizedDescription];
		} else {
			self.textView.text = NSLocalizedString(@"An unknown error occurred fetching metadata",nil);
		}
	}];
}

-(IBAction)cancel:(id)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
