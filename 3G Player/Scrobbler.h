//
//  Scrobbler.h
//  3G Player
//
//  Created by Admin on 7/5/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Scrobbler : NSObject

- (id)init;
- (void)sendNowPlaying:(NSDictionary*)file;
- (void)scrobble:(NSDictionary*)file startedAt:(NSDate*)date;
- (void)love:(NSDictionary*)file;

- (int)queueSize;

@end
