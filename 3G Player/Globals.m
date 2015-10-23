//
//  Globals.c
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "Globals.h"

_controllers controllers;

MusicTableService* musicTableService;

MusicFileManager* musicFileManager;
Scrobbler* scrobbler;

NSString* libraryDirectory;
NSString* playerUrl;

int freeSpaceMb;

NSString* lastfmUsername;
NSString* lastfmPassword;

UIBarButtonItem* libraryRightBarButtonItem;
UIBarButtonItem* libraryToolbarButtonItem;
