//
//  KeepAliver.h
//  3G Player
//
//  Created by themylogin on 25/03/16.
//  Copyright © 2016 themylogin. All rights reserved.
//


#import <Foundation/Foundation.h>

#import <AVFoundation/AVFoundation.h>

@interface KeepAliver : NSObject <AVAudioPlayerDelegate>

- (id)init;

- (void)start;
- (void)startWithDuration:(int)duration;
- (void)stop;

@end