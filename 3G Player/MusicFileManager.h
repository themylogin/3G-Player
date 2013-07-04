//
//  MusicFileManager.h
//  3G Player
//
//  Created by Admin on 7/4/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    NotBuffered,
    Buffering,
    Buffered,
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

- (MusicFileState)getState:(NSDictionary*)musicFile;
- (void)buffer:(NSDictionary*)musicFile;
- (void)stopBuffering;

@end
