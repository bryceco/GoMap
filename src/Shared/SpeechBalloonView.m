//
//  SpeechBalloonView.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 12/11/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "SpeechBalloonLayer.h"
#import "SpeechBalloonView.h"

static const CGFloat arrowWidth = 16;
static const CGFloat arrowHeight = 16;

@implementation SpeechBalloonView

+ (Class)layerClass
{
	return [CAShapeLayer class];
}

- (id)initWithText:(NSString *)text balloonPress:(void(^)(void))balloonPress disclosurePress:(void (^)(void))disclosurePress
{
	self = [super initWithFrame:CGRectMake(0,0,0,0)];
	if ( self ) {

		_balloonPress = balloonPress;
		_disclosurePress = disclosurePress;

#if !TARGET_OS_IPHONE
		self.wantsLayer = YES;
#endif
		CAShapeLayer * shapeLayer = (id)self.layer;

		// shape layer
		shapeLayer.fillColor = NSColor.grayColor.CGColor;
		shapeLayer.strokeColor = NSColor.blackColor.CGColor;

		// disclosure button view
#if TARGET_OS_IPHONE
		UIButton * button = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
		CGRect buttonRect = button.frame;
		[button addTarget:self action:@selector(disclosurePress:) forControlEvents:UIControlEventTouchUpInside];
#else
		CGRect buttonRect = CGRectMake( 0, 0, 20, 20);
		NSButton * button = [[NSButton alloc] initWithFrame:buttonRect];
		[button setButtonType:NSOnOffButton];
		[button setBezelStyle:NSDisclosureBezelStyle];
		[button highlight:NO];
		[button setTitle:nil];
		button.wantsLayer = YES;
#endif

		// text layer
		CATextLayer * textLayer = [CATextLayer layer];
#if TARGET_OS_IPHONE
		CGFontRef font = CGFontCreateWithFontName( (__bridge CFStringRef) @"Helvetica-Bold" );
		textLayer.font = font;
		CGFontRelease(font);
#else
		NSFont * font = [[NSFontManager sharedFontManager] convertFont:[NSFont labelFontOfSize:12] toHaveTrait:NSBoldFontMask];
		textLayer.font = (__bridge CFTypeRef)font;
#endif
		textLayer.fontSize = 16;
		textLayer.alignmentMode = kCAAlignmentLeft;
		textLayer.string = text;
		textLayer.foregroundColor = NSColor.whiteColor.CGColor;
		[shapeLayer addSublayer:textLayer];

		CGSize textSize = textLayer.preferredFrameSize;

		CGSize boxSize = textSize;
		boxSize.width += 35;
		boxSize.height = 30;

		// creat path with arrow
		const CGFloat cornerRadius = 4;
		_path = CGPathCreateMutable();
		CGPathMoveToPoint(_path, NULL, boxSize.width/2, boxSize.height+arrowHeight);	// arrow bottom
		CGPathAddLineToPoint(_path, NULL, boxSize.width/2-arrowWidth/2, boxSize.height);	// arrow top-left
		CGPathAddArcToPoint(_path, NULL, 0, boxSize.height, 0, 0, cornerRadius);	// bottom right corner
		CGPathAddArcToPoint(_path, NULL, 0, 0, boxSize.width, 0, cornerRadius);	// top left corner
		CGPathAddArcToPoint(_path, NULL, boxSize.width, 0, boxSize.width, boxSize.height, cornerRadius); // top right corner
		CGPathAddArcToPoint(_path, NULL, boxSize.width, boxSize.height, 0, boxSize.height, cornerRadius);	// bottom right corner
		CGPathAddLineToPoint(_path, NULL, boxSize.width/2+arrowWidth/2, boxSize.height );	// arrow top-right
		CGPathCloseSubpath(_path);
		CGRect viewRect = CGPathGetPathBoundingBox( _path );
		shapeLayer.path = _path;

		buttonRect = CGRectOffset( buttonRect, boxSize.width - buttonRect.size.width, 0 );
		button.frame = buttonRect;
		[self addSubview:button];

		textLayer.frame = CGRectMake(5, 5, boxSize.width - 5, boxSize.height - 5);

		self.frame = CGRectMake(0, 0, viewRect.size.width, viewRect.size.height);
	}
	return self;
}

- (void)disclosurePress:(id)sender
{
	_disclosurePress();
}

- (void) setPoint:(CGPoint)point
{
	// set bottom center at point
	CGRect rect = self.frame;
	rect.origin.x = point.x - rect.size.width / 2;
	rect.origin.y = point.y - rect.size.height - 3;
	self.frame = rect;
}


- (BOOL)pointInside:(CGPoint)point withEvent:(NSEvent *)event
{
#if TARGET_OS_IPHONE
	if ( ![super pointInside:point withEvent:event] )
		return NO;
	if ( ! CGPathContainsPoint( _path, NULL, point, NO) )
		return NO;
	return YES;
#else
	return NO;
#endif
}



- (void)dealloc
{
	CGPathRelease( _path );
}

@end
