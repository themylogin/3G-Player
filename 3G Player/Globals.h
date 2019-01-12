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
#import "RecentsController.h"
#import "InfoController.h"

#import "MusicTableService.h"

#import "MusicFileManager.h"
#import "Scrobbler.h"

#import "RecommendationsUtils.h"

extern NSString* librariesPath;

extern NSArray* players;
extern long leaveFreeSpaceMB;
extern NSString* lastFmUsername;
extern NSString* lastFmPassword;

extern MusicTableService* musicTableService;
extern MusicFileManager* musicFileManager;
extern Scrobbler* scrobbler;
extern RecommendationsUtils* recommendationsUtils;

typedef struct {
    UITabBarController* tabBar;
    CurrentController* current;
    LibraryController* library;
    RecentsController* recents;
    InfoController* info;
} _controllers;

extern _controllers controllers;

extern UIBarButtonItem* libraryRightBarButtonItem;
extern UIBarButtonItem* libraryToolbarButtonItem;

#endif
