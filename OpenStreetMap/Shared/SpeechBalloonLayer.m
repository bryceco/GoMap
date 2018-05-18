//
//  SpeechBalloonLayer.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 11/11/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "iosapi.h"
#import "SpeechBalloonLayer.h"

@implementation SpeechBalloonLayer
@synthesize text = _text;


static const CGFloat arrowWidth = 16;
static const CGFloat arrowHeight = 16;

-(id)init
{
	self = [super init];
	if ( self ) {
		self.fillColor = NSColor.blueColor.CGColor;
		self.strokeColor = NSColor.blackColor.CGColor;
#if TARGET_OS_IPHONE
		UIFont * font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
#else
		NSFont * font = [[NSFontManager sharedFontManager] convertFont:[NSFont labelFontOfSize:12] toHaveTrait:NSBoldFontMask];
#endif
		_textLayer = [CATextLayer layer];
		_textLayer.font = (__bridge CFTypeRef)font;
		_textLayer.fontSize = 12;
		_textLayer.alignmentMode = kCAAlignmentCenter;
		[self addSublayer:_textLayer];
	}
	return self;
}

-(void)redraw
{
	_textLayer.string = _text;
	CGSize size = _textLayer.preferredFrameSize;
	const CGFloat cornerRadius = 4;

	size.width += 10;

	CGRect rcSuper = self.superlayer.bounds;
	BOOL flipVertical	= self.position.y - rcSuper.origin.y < 4 * size.height;
	BOOL flipHorizontal = rcSuper.origin.x + rcSuper.size.width - self.position.x < size.width + 10;

	CGAffineTransform transform = CGAffineTransformIdentity;
	if ( flipVertical ) {
		transform.d = -1;
	}
	if ( flipHorizontal ) {
		transform.a = -1;
	}

	CGMutablePathRef path = CGPathCreateMutable();
	CGPathMoveToPoint(path, &transform, cornerRadius, 0);	// top left
	CGPathAddArcToPoint(path, &transform, size.width, 0, size.width, size.height, cornerRadius);	// top right
	CGPathAddArcToPoint(path, &transform, size.width, size.height, 0, size.height, cornerRadius);	// bottom right
	CGPathAddLineToPoint(path, &transform, 2*arrowWidth, size.height);	// arrow top-right
	CGPathAddLineToPoint(path, &transform, arrowWidth/2, size.height+arrowHeight);	// arrow bottom
	CGPathAddLineToPoint(path, &transform, arrowWidth, size.height);	// arrow top-left
	CGPathAddArcToPoint(path, &transform, 0, size.height, 0, 0, cornerRadius);	// bottom left
	CGPathAddArcToPoint(path, &transform, 0, 0, size.width, 0, cornerRadius);

	self.path = path;

	CGRect rc = CGPathGetBoundingBox( path );

	rc.origin = self.bounds.origin;
	CGSize offset = { 4, 12 };
	if ( flipVertical ) {
		offset.height -= 3 * rc.size.height;
	}
	if ( flipHorizontal ) {
		offset.width = -offset.width;
	}
	self.anchorPoint = CGPointMake( -offset.width/rc.size.width, 1+offset.height/rc.size.height );
	self.bounds = rc;

	if ( flipVertical ) {
		rc.origin.y -= size.height;
	}
	if ( flipHorizontal ) {
		rc.origin.x -= size.width;
	}
	_textLayer.frame = rc;

	CGPathRelease(path);
}

-(NSString *)text
{
	return _text;
}
-(void)setText:(NSString *)text
{
	_text = text;
	[self redraw];
}

@end
