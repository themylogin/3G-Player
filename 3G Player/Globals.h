//
//  Controllers.h
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#ifndef _G_Player_Controllers_h
#define _G_Player_Controllers_h

#import "CurrentController.h"
#import "LibraryController.h"
#import "InfoController.h"

#import "MusicFileManager.h"
#import "Scrobbler.h"

typedef struct {
    CurrentController* current;
    LibraryController* library;
    InfoController* info;
} _controllers;

extern _controllers controllers;

extern MusicFileManager* musicFileManager;
extern Scrobbler* scrobbler;

extern NSString* libraryDirectory;
extern NSString* playerUrl;

extern NSString* lastfmUsername;
extern NSString* lastfmPassword;

extern UIBarButtonItem* updateLibraryButton;
extern UIBarButtonItem* updateLibraryProgress;

#endif
