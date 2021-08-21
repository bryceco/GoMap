//
//  EditorLayerGL.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/15/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

@class MapView;



@interface EditorLayerGL : CAEAGLLayer
{
	EAGLContext		*	_glContext;

	GLuint				_glFramebuffer;
	GLuint				_glColorRenderbuffer;
	GLuint				_glDepthRenderbuffer;

	MapView			*	_mapView;
}

-(id)initWithMapView:(MapView *)mapView;

@end
