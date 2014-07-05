//
//  FpsLabel.m
//  Go Map!!
//
//  Created by Bryce on 6/15/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import "FpsLabel.h"


const int FRAME_COUNT = 61;


@implementation FpsLabel
{
	int					_historyPos;
	CFTimeInterval		_history[ FRAME_COUNT ];	// average last 60 frames
	dispatch_source_t	_timer;
	CADisplayLink	*	_displayLink;
}

- (void)awakeFromNib
{
	[super awakeFromNib];

#if 0 && defined(DEBUG)
	_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLink)];
	[_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];

	dispatch_queue_t queue = dispatch_get_main_queue();
	_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
	if ( _timer ) {
		dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, NSEC_PER_SEC/2, NSEC_PER_SEC/5);
		dispatch_source_set_event_handler(_timer, ^{
			[self updateText];
		} );
		dispatch_resume(_timer);
	}
#else
	self.text = nil;
	[self removeFromSuperview];
#endif
}

- (void)dealloc
{
	dispatch_source_cancel( _timer );
}

- (void)displayLink
{
	[self frameUpdated];
}

- (void)updateText
{
	CFTimeInterval now = CACurrentMediaTime();

	// scan backward to see how many frames were drawn in the last second
	int frameCount = 0;
	int pos = _historyPos;
	CFTimeInterval prev = 0.0;
	do {
		if ( --pos < 0 )
			pos = FRAME_COUNT - 1;
		prev = _history[pos];
		++frameCount;
		if ( now - prev >= 1.0 )
			break;
	} while ( pos != _historyPos );

	CFTimeInterval average = frameCount / (now - prev);
	if ( average >= 10.0 )
		self.text = [NSString stringWithFormat:@"%.1f FPS", average];
	else
		self.text = [NSString stringWithFormat:@"%.2f FPS", average];
}

- (void)frameUpdated
{
#if defined(DEBUG)
	// add to history
	CFTimeInterval now = CACurrentMediaTime();
	_history[_historyPos++] = now;
	if ( _historyPos >= FRAME_COUNT )
		_historyPos = 0;

	[self updateText];
#endif
}

@end
