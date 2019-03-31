//
//  RulerLayer.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/11/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "iosapi.h"
#import "MapView.h"
#import "RulerLayer.h"



@implementation RulerLayer
@synthesize mapView = _mapView;

-(id)init
{
	self = [super init];
	if ( self ) {
		_shapeLayer = [CAShapeLayer layer];
		_shapeLayer.lineWidth = 2;
		_shapeLayer.strokeColor = NSColor.blackColor.CGColor;
		_shapeLayer.fillColor = NULL;

#if TARGET_OS_IPHONE
		UIFont * font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
#else
		NSFont * font = [NSFont labelFontOfSize:12];
#endif
		
		_metricTextLayer					= [CATextLayer layer];
		_britishTextLayer					= [CATextLayer layer];
		_metricTextLayer.font				= (__bridge CGFontRef)font;
		_britishTextLayer.font				= (__bridge CGFontRef)font;
		_metricTextLayer.fontSize			= 12; // font.pointSize;
		_britishTextLayer.fontSize			= 12; // font.pointSize;
		_metricTextLayer.foregroundColor	= NSColor.blackColor.CGColor;
		_britishTextLayer.foregroundColor	= NSColor.blackColor.CGColor;
		_metricTextLayer.alignmentMode		= kCAAlignmentCenter;
		_britishTextLayer.alignmentMode		= kCAAlignmentCenter;
        _metricTextLayer.contentsScale      = UIScreen.mainScreen.scale;
        _britishTextLayer.contentsScale     = UIScreen.mainScreen.scale;

		self.shadowColor					= NSColor.whiteColor.CGColor;
		self.shadowRadius					= 0.0;
		self.shadowOpacity					= 0.4;
		self.shadowOffset					= CGSizeMake(0,0);

		_shapeLayer.shadowOpacity			= 0.0;
		_metricTextLayer.shadowOpacity		= 0.0;
		_britishTextLayer.shadowOpacity		= 0.0;

		[self addSublayer:_shapeLayer];
		[self addSublayer:_metricTextLayer];
		[self addSublayer:_britishTextLayer];
	}
	return self;
}

-(MapView *)mapView
{
	return _mapView;
}
-(void)setMapView:(MapView *)mapView
{
	[_mapView removeObserver:self forKeyPath:@"screenFromMapTransform"];
	_mapView = mapView;
	[_mapView addObserver:self forKeyPath:@"screenFromMapTransform" options:0 context:NULL];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( object == _mapView && [keyPath isEqualToString:@"screenFromMapTransform"] ) {
		[self updateDisplay];
	}
}


-(void)setFrame:(CGRect)frame
{
	[super setFrame:frame];

	_shapeLayer.frame = self.bounds;

	[self updateDisplay];
}


double roundToEvenValue( double value )
{
	double scale = 1;
	for (;;) {
		if ( value < scale * 10 ) {
			if ( floor(value/scale) < 2 ) {
				return 1*scale;
			}
			if ( floor(value/scale) < 5 ) {
				return 2*scale;
			}
			return 5*scale;
		}
		scale *= 10;
	}
}

-(void)updateDisplay
{
	CGRect rc = self.bounds;
	if ( rc.size.width <= 1 || rc.size.height <= 1 )
		return;

	double metersPerPixel = [_mapView metersPerPixel];
	if ( metersPerPixel == 0 )
		return;

	double metricWide = rc.size.width * metersPerPixel;
	double britishWide = metricWide * 3.28084;	// feet per meter

	NSString * metricUnit = @"meter";
	NSString * metricSuffix = @"s";
	if ( metricWide >= 1000 ) {
		metricWide /= 1000;
		metricUnit = @"km";
		metricSuffix = @"";
	} else if ( metricWide < 1.0 ) {
		metricWide *= 100;
		metricUnit = @"cm";
		metricSuffix = @"";
	}
	NSString * britishUnit = @"feet";
	NSString * britishSuffix = @"";
	if ( britishWide >= 5280 ) {
		britishWide /= 5280;
		britishUnit = @"mile";
		britishSuffix = @"s";
	} else if ( britishWide < 1.0 ) {
		britishWide *= 12;
		britishUnit = @"inch";
		britishSuffix = @"es";
	}
	double metricPerPixel = metricWide / rc.size.width;
	double britishPerPixel = britishWide / rc.size.width;

	metricWide = roundToEvenValue( metricWide );
	britishWide = roundToEvenValue( britishWide );

	double metricPixels = round( metricWide / metricPerPixel );
	double britishPixels = round( britishWide / britishPerPixel );

	// metric bar on bottom
	CGMutablePathRef path = CGPathCreateMutable();
	CGPathMoveToPoint(path, NULL, rc.origin.x, rc.origin.y+rc.size.height);
	CGPathAddLineToPoint(path, NULL, rc.origin.x, rc.origin.y+rc.size.height/2);
	CGPathAddLineToPoint(path, NULL, rc.origin.x + metricPixels, rc.origin.y+rc.size.height/2);
	CGPathAddLineToPoint(path, NULL, rc.origin.x + metricPixels, rc.origin.y+rc.size.height);

	// british bar on top
	CGPathMoveToPoint(path, NULL, rc.origin.x, rc.origin.y );
	CGPathAddLineToPoint(path, NULL, rc.origin.x, rc.origin.y+rc.size.height/2);
	CGPathAddLineToPoint(path, NULL, rc.origin.x + britishPixels, rc.origin.y+rc.size.height/2);
	CGPathAddLineToPoint(path, NULL, rc.origin.x + britishPixels, rc.origin.y);

	_shapeLayer.path = path;
	CGPathRelease(path);

	CGRect rect = self.bounds;
	rect.size.width = metricPixels;
	rect.origin.y = round( rc.origin.y + rc.size.height / 2 );
	_metricTextLayer.frame = rect;

	rect.size.width = britishPixels;
	rect.origin.y = round( rc.origin.y );
	_britishTextLayer.frame = rect;

	_metricTextLayer.string  = [NSString stringWithFormat:@"%ld %@%@", (long)metricWide,  metricUnit,  metricWide  > 1 ? metricSuffix  : @"" ];
	_britishTextLayer.string = [NSString stringWithFormat:@"%ld %@%@", (long)britishWide, britishUnit, britishWide > 1 ? britishSuffix : @"" ];

	rect.size.width = MAX(metricPixels,britishPixels);
	rect = CGRectInset( rect, -2, -2 );
	self.shadowPath = CGPathCreateWithRect(rect, NULL);
}

@end
