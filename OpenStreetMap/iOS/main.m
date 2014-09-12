//
//  main.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//
#include <signal.h>

#import <UIKit/UIKit.h>

#import "AppDelegate.h"

void mysighandler(int signal, struct __siginfo * info, void * ctx)
{

}

int main(int argc, char *argv[])
{
	struct sigaction mySigAction;
	mySigAction.sa_sigaction = mysighandler;
	mySigAction.sa_flags = SA_SIGINFO;
	sigemptyset(&mySigAction.sa_mask);
	sigaction(SIGQUIT, &mySigAction, NULL);
	sigaction(SIGILL, &mySigAction, NULL);
	sigaction(SIGTRAP, &mySigAction, NULL);
	sigaction(SIGABRT, &mySigAction, NULL);
	sigaction(SIGEMT, &mySigAction, NULL);
	sigaction(SIGFPE, &mySigAction, NULL);
	sigaction(SIGBUS, &mySigAction, NULL);
	sigaction(SIGSEGV, &mySigAction, NULL);
	sigaction(SIGSYS, &mySigAction, NULL);
	sigaction(SIGPIPE, &mySigAction, NULL);
	sigaction(SIGALRM, &mySigAction, NULL);
	sigaction(SIGXCPU, &mySigAction, NULL);
	sigaction(SIGXFSZ, &mySigAction, NULL);
	sigaction(0x91, &mySigAction, NULL);	// bad access


	@autoreleasepool {
	    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
	}
}
