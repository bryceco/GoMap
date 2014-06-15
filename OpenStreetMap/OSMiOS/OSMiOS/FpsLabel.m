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
	int				_historyPos;
	CFTimeInterval	_history[ FRAME_COUNT ];	// average last 60 frames
}


- (void)frameUpdated
{
	CFTimeInterval now = CACurrentMediaTime();

	// scan backward to see how many frames were drawn in the last second
	int frameCount = 1;
	int pos = _historyPos;
	CFTimeInterval prev = 0.0;
	do {
		if ( --pos < 0 )
			pos = FRAME_COUNT - 1;
		prev = _history[pos];
		if ( now - prev >= 1.0 )
			break;
		++frameCount;
	} while ( pos != _historyPos );

	CFTimeInterval average = frameCount / (now - prev);
	if ( average >= 10.0 )
		self.text = [NSString stringWithFormat:@"%.1f FPS", average];
	else
		self.text = [NSString stringWithFormat:@"%.2f FPS", average];

	// add to history
	_history[_historyPos++] = now;
	if ( _historyPos >= FRAME_COUNT )
		_historyPos = 0;
}

@end
