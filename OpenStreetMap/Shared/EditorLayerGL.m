//
//  EditorLayerGL.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/15/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

#import <GLKit/GLKit.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
//#import <OpenGLES/ES2/gl.h>
//#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/EAGLDrawable.h>

#import <QuartzCore/QuartzCore.h>

#import "DLog.h"
#import "EditorLayerGL.h"
#import "MapView.h"



@implementation EditorLayerGL

-(id)initWithMapView:(MapView *)mapView;
{
	self = [super init];
	if ( self ) {

		// observe changes to geometry
		_mapView = mapView;
		[_mapView addObserver:self forKeyPath:@"screenFromMapTransform" options:0 context:NULL];


		self.opaque = YES;
		self.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking : @NO,
		kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8 };


		_glContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
		[EAGLContext setCurrentContext:_glContext];

		glGenFramebuffers(1, &_glFramebuffer);
		glBindFramebuffer(GL_FRAMEBUFFER, _glFramebuffer);
		glGenRenderbuffers(1, &_glColorRenderbuffer);
		glBindRenderbuffer(GL_RENDERBUFFER, _glColorRenderbuffer);
		[_glContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:self];
		glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _glColorRenderbuffer);
		glGenRenderbuffers(1, &_glDepthRenderbuffer);
		glBindRenderbuffer(GL_RENDERBUFFER, _glDepthRenderbuffer);
		glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _glDepthRenderbuffer);
		if(glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
		{
			DLog(@"worked");
		}
	}
	return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( object == _mapView && [keyPath isEqualToString:@"screenFromMapTransform"] )  {
		[self drawContent];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

-(void)setBounds:(CGRect)bounds
{
	[super setBounds:bounds];

	// Allocate color buffer backing based on the current layer size
    glBindRenderbuffer(GL_RENDERBUFFER, _glColorRenderbuffer);
    [_glContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:self];
	GLint backingWidth, backingHeight;
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);

	glGenRenderbuffers(1, &_glDepthRenderbuffer);
	glBindRenderbuffer(GL_RENDERBUFFER, _glDepthRenderbuffer);
	glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, backingWidth, backingHeight);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _glDepthRenderbuffer);

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
	{
        DLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    }

	[self drawContent];
}

typedef struct _Vertex3D {
	GLfloat	x;
	GLfloat	y;
	CGFloat	z;
} Vertex3D;

typedef struct _Triangle3D {
	Vertex3D	v1;
	Vertex3D	v2;
	Vertex3D	v3;
} Triangle3D;

Vertex3D Vertex3DMake( GLfloat	x, GLfloat	y, CGFloat	z )
{
	Vertex3D v = { x, y, z };
	return v;
}


- (void)drawScene
{
#if 0	// anti-alias lines
	//Bind both MSAA and View FrameBuffers.
	glBindFramebuffer(GL_READ_FRAMEBUFFER_APPLE, msaaFramebuffer);
	glBindFramebuffer(GL_DRAW_FRAMEBUFFER_APPLE, framebuffer );
	// Call a resolve to combine both buffers
	glResolveMultisampleFramebufferAPPLE();
	// Present final image to screen
	glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderBuffer);
	[_context presentRenderbuffer:GL_RENDERBUFFER];
#endif

	typedef struct {
		float Position[3];
		float Color[4];
	} Vertex;

	const Vertex Vertices[] = {
		{{1, -1, 0}, {1, 0, 0, 1}},
		{{1, 1, 0}, {0, 1, 0, 1}},
		{{-1, 1, 0}, {0, 0, 1, 1}},
		{{-1, -1, 0}, {0, 0, 0, 1}}
	};

	const GLubyte Indices[] = {
		0, 1, 2,
		2, 3, 0
	};

	GLuint _vertexBuffer;
	GLuint _indexBuffer;

	glClear(GL_DEPTH_BUFFER_BIT | GL_COLOR_BUFFER_BIT);

    glGenBuffers(1, &_vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(Vertices), Vertices, GL_STATIC_DRAW);

    glGenBuffers(1, &_indexBuffer);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _indexBuffer);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(Indices), Indices, GL_STATIC_DRAW);

	glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer);
	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _indexBuffer);

	glEnableVertexAttribArray(GLKVertexAttribPosition);
	glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), (const GLvoid *) offsetof(Vertex, Position));
	glEnableVertexAttribArray(GLKVertexAttribColor);
	glVertexAttribPointer(GLKVertexAttribColor, 4, GL_FLOAT, GL_FALSE, sizeof(Vertex), (const GLvoid *) offsetof(Vertex, Color));


	glDrawElements(GL_TRIANGLES, sizeof(Indices)/sizeof(Indices[0]), GL_UNSIGNED_BYTE, 0);


    glDeleteBuffers(1, &_vertexBuffer);
    glDeleteBuffers(1, &_indexBuffer);
}

- (void)drawContent
{
	// erase
	glBindFramebuffer(GL_FRAMEBUFFER, _glFramebuffer);
	glClearColor(1.0, 0.5, 0.2, 1.0);
	glClear(GL_COLOR_BUFFER_BIT);
//	glClear(GL_DEPTH_BUFFER_BIT | GL_COLOR_BUFFER_BIT);

	// get dimensions
	GLint	renderWidth, renderHeight;
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &renderWidth);
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &renderHeight);

	// draw
	[self drawScene];
	
	// discard
	const GLenum discards[]  = {GL_DEPTH_ATTACHMENT};
	glBindFramebuffer(GL_FRAMEBUFFER, _glFramebuffer);
	glDiscardFramebufferEXT(GL_FRAMEBUFFER,1,discards);

	// present
	glBindRenderbuffer(GL_RENDERBUFFER, _glColorRenderbuffer);
	[_glContext presentRenderbuffer:GL_RENDERBUFFER];
}

@end
