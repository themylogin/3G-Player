//
//  Globals.c
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "Globals.h"


NSString* librariesPath;
NSArray* players;

int leaveFreeSpace;

NSString* lastFmUsername;
NSString* lastFmPassword;

MusicTableService* musicTableService;
MusicFileManager* musicFileManager;
Scrobbler* scrobbler;
RecommendationsUtils* recommendationsUtils;

_controllers controllers;

UIBarButtonItem* libraryRightBarButtonItem;
UIBarButtonItem* libraryToolbarButtonItem;
