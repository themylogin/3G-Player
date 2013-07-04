//
//  Controllers.h
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#ifndef _G_Player_Controllers_h
#define _G_Player_Controllers_h

#import "PlaylistController.h"
#import "LibraryController.h"

#import "MusicFileManager.h"

typedef struct {
    LibraryController* library;
    PlaylistController* playlist;
} _controllers;

extern _controllers controllers;

extern MusicFileManager* musicFileManager;

extern NSString* libraryDirectory;
extern NSString* playerUrl;

extern UIBarButtonItem* updateLibraryButton;

#endif
