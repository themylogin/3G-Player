//
//  Scrobbler.h
//  3G Player
//
//  Created by Admin on 7/5/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Scrobbler : NSObject

@property BOOL enabled;

- (id)init;

- (int)queueSize;

- (void)love:(NSDictionary*)file;
- (void)sendNowPlaying:(NSDictionary*)file;
- (void)scrobble:(NSDictionary*)file startedAt:(NSDate*)date;


@end
