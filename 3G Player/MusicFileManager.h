//
//  MusicFileManager.h
//  3G Player
//
//  Created by Admin on 7/4/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <AVFoundation/AVFoundation.h>

typedef enum {
    MusicFileNotBuffered,
    MusicFileBuffering,
    MusicFileBuffered,
} MusicFileStateId;

typedef union {
    MusicFileStateId state;
    
    struct {
        MusicFileStateId state;
        float progress;
        bool isError;
    } buffering;
} MusicFileState;

@interface MusicFileManager : NSObject

- (id)init;

- (bool)item:(NSDictionary*)item1 isEqualToItem:(NSDictionary*)item2;

- (NSString*)absolutePath:(NSDictionary*)item;
- (NSString*)playPath:(NSDictionary*)musicFile;

- (MusicFileState)state:(NSDictionary*)musicFile;

- (void)buffer:(NSDictionary*)musicFile;
- (void)stopBuffering;

- (void)loadCover:(NSDictionary*)musicFile;
- (NSString*)coverPath:(NSDictionary*)musicFile;

- (void)remove:(NSDictionary*)fileOrDirectory;

- (void)notifyItemAdd:(NSDictionary*)item;
- (void)notifyItemPlay:(NSDictionary*)item;
- (NSArray*)listRecentItems;
- (NSArray*)listOldDirectories;
- (void)removeOldFiles;

- (NSString*)navigationPathForItem:(NSDictionary*)item;
- (NSDictionary*)itemForAbsolutePath:(NSString*)absolutePath;

@end
