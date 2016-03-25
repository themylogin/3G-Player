//
//  KeepAliver.m
//  3G Player
//
//  Created by themylogin on 25/03/16.
//  Copyright © 2016 themylogin. All rights reserved.
//


#import "KeepAliver.h"

#import <MediaPlayer/MediaPlayer.h>

@interface KeepAliver ()

@property (nonatomic, retain) AVAudioPlayer*    player;

@end

@implementation KeepAliver

- (id)init
{
    NSURL* silenceUrl = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/silence.wav",
                                                [[NSBundle mainBundle] resourcePath]]];
    self.player = [[AVAudioPlayer alloc]
                   initWithContentsOfURL:silenceUrl
                   fileTypeHint:AVFileTypeWAVE error:nil];
    self.player.delegate = self;
    
    return self;
}

- (void)start
{
    [self startWithDuration:-1];
}

- (void)startWithDuration:(int)duration
{
    self.player.numberOfLoops = duration;
    [self.player play];
}

- (void)stop
{
    [self.player stop];
}

#pragma mark - AVAudioPlayer delegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
    return;
}

- (void)audioPlayerBeginInterruption:(AVAudioPlayer *)player
{
    [self.player pause];
}

- (void)audioPlayerEndInterruption:(AVAudioPlayer *)player withOptions:(NSUInteger)flags
{
    [self.player prepareToPlay];
    [self.player play];
}

@end
