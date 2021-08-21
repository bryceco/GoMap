//
//  UndoManagerDump.c
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/28/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#if !TARGET_OS_IPHONE

#include <objc/objc-runtime.h>

#import "DLog.h"


void DumpUndoManager( NSUndoManager * undoManager )
{
	@try
	{
		id v1, v2;
		object_getInstanceVariable(undoManager, "_undoStack", (void **)&v1);
		object_getInstanceVariable(undoManager, "_redoStack", (void **)&v2);
		DLog( @"undo (%ld entries) %@", [v1 count], [v1 description] );
		DLog( @"redo (%ld entries) %@", [v2 count], [v2 description] );
	}
	@catch (NSException* e)
	{
	}
}

#endif
