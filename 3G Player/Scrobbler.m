//
//  Scrobbler.m
//  3G Player
//
//  Created by Admin on 7/5/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "Scrobbler.h"

#import "Globals.h"

#import "FMEngine.h"
#import "JSONKit.h"

@interface Scrobbler ()

@property (nonatomic, retain) NSString* sessionKey;
@property (nonatomic, retain) NSString* sessionKeyUsername;
@property (nonatomic, retain) NSString* sessionKeyPassword;

@property (nonatomic, retain) NSTimer* flushTimer;

@end

@implementation Scrobbler

- (id)init
{
    self.sessionKey = nil;
    self.sessionKeyUsername = nil;
    self.sessionKeyPassword = nil;
        
    self.flushTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(flushQueue) userInfo:nil repeats:YES];
    
    return self;
}

- (void)sendNowPlaying:(NSDictionary*)file
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{        
        [self beAuthorized];
        if (!self.sessionKey)
        {
            return;
        }
        
        FMEngine* fmEngine = [[FMEngine alloc] init];
        [fmEngine dataForMethod:@"track.updateNowPlaying" withParameters:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                          [file objectForKey:@"artist"], @"artist",
                                                                          [file objectForKey:@"title"], @"track",
                                                                          self.sessionKey, @"sk",
                                                                          _LASTFM_API_KEY_, @"api_key",
                                                                          nil] useSignature:YES httpMethod:POST_TYPE error:nil];
        [fmEngine release];
    });
}

- (void)scrobble:(NSDictionary*)file startedAt:(NSDate*)date
{
    [[[NSUserDefaults standardUserDefaults] mutableArrayValueForKey:@"scrobblerQueue"] addObject:[NSDictionary dictionaryWithObjectsAndKeys:[file objectForKey:@"artist"], @"artist", [file objectForKey:@"title"], @"title", date, @"startedAt", nil, nil]];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [self flushQueue];
}

- (void)flushQueue
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSMutableArray* queue = [[NSUserDefaults standardUserDefaults] mutableArrayValueForKey:@"scrobblerQueue"];
        if (![queue count])
        {
            return;
        }
    
        [self beAuthorized];
        if (!self.sessionKey)
        {
            return;
        }
    
        NSMutableArray* newQueue = [[NSMutableArray alloc] init];
        for (NSDictionary* scrobble in queue)
        {
            BOOL success = NO;
            FMEngine* fmEngine = [[FMEngine alloc] init];
            NSData* reply = [fmEngine dataForMethod:@"track.scrobble" withParameters:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                                      [scrobble objectForKey:@"artist"], @"artist",
                                                                                      [scrobble objectForKey:@"title"], @"track",
                                                                                      [NSString stringWithFormat:@"%d", (int)[[scrobble objectForKey:@"startedAt"] timeIntervalSince1970]], @"timestamp",
                                                                                      self.sessionKey, @"sk",
                                                                                      _LASTFM_API_KEY_, @"api_key",
                                                                                      nil] useSignature:YES httpMethod:POST_TYPE error:nil];
            if (reply)
            {
                NSDictionary* response = [[JSONDecoder decoder] objectWithData:reply];
                if ([response objectForKey:@"scrobbles"])
                {
                    success = YES;
                }
            }
            [fmEngine release];
            
            if (!success)
            {
                [newQueue addObject:scrobble];
            }
        }

        [[NSUserDefaults standardUserDefaults] setValue:newQueue forKey:@"scrobblerQueue"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    });
}

- (void)beAuthorized
{
    if (self.sessionKey && self.sessionKeyUsername && self.sessionKeyPassword && [self.sessionKeyUsername isEqualToString:lastfmUsername] && [self.sessionKeyPassword isEqualToString:lastfmPassword])
    {
        return;
    }
    
    self.sessionKey = nil;
    self.sessionKeyUsername = [lastfmUsername copy];
    self.sessionKeyPassword = [lastfmPassword copy];
    
    FMEngine* fmEngine = [[FMEngine alloc] init];
    NSString* authToken = [fmEngine generateAuthTokenFromUsername:self.sessionKeyUsername password:self.sessionKeyPassword];
    NSData* reply = [fmEngine dataForMethod:@"auth.getMobileSession" withParameters:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                                     self.sessionKeyUsername, @"username",
                                                                                     authToken, @"authToken",
                                                                                     _LASTFM_API_KEY_, @"api_key",
                                                                                     nil] useSignature:YES httpMethod:POST_TYPE error:nil];
    if (reply)
    {
        self.sessionKey = [[[[JSONDecoder decoder] objectWithData:reply] objectForKey:@"session"] objectForKey:@"key"];
    }
    [fmEngine release];
}

@end
