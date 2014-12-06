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
    
    if ([[NSUserDefaults standardUserDefaults] mutableArrayValueForKey:@"lastFmQueue"] == nil)
    {
        [[NSUserDefaults standardUserDefaults] setObject:[NSMutableArray array] forKey:@"lastFmQueue"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
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
    [self _queueAction:@"scrobble"
              withFile:file
             arguments:[NSDictionary dictionaryWithObject:
                        [NSString stringWithFormat:@"%d", (int)[date timeIntervalSince1970]]
                                                   forKey:@"timestamp"]];
    [self flushQueue];
}

- (void)love:(NSDictionary*)file
{
    [self _queueAction:@"love"
              withFile:file
             arguments:[NSDictionary dictionary]];
    [self flushQueue];
}

- (void) _queueAction:(NSString*)action withFile:(NSDictionary*)file arguments:(NSDictionary*)arguments
{
    @synchronized([NSUserDefaults standardUserDefaults])
    {
        NSMutableDictionary* queueItem = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                          [file objectForKey:@"artist"], @"artist",
                                          [file objectForKey:@"title"], @"title",
                                          action, @"action",
                                          nil];
        [queueItem addEntriesFromDictionary:arguments];
        
        [[[NSUserDefaults standardUserDefaults] mutableArrayValueForKey:@"lastFmQueue"] addObject:queueItem];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    [self flushQueue];
}

- (void)flushQueue
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        @synchronized(self)
        {
            [self beAuthorized];
            if (!self.sessionKey)
            {
                return;
            }
            
            NSMutableArray* queue;
            @synchronized([NSUserDefaults standardUserDefaults])
            {
                NSMutableArray* storedQueue = [[NSUserDefaults standardUserDefaults] mutableArrayValueForKey:@"lastFmQueue"];
                if ([storedQueue count] == 0)
                {
                    return;
                }
                
                queue = [NSMutableArray arrayWithArray:storedQueue];
            }
    
            NSMutableDictionary* context = [[NSMutableDictionary alloc] init];
            for (NSDictionary* action in queue)
            {
                BOOL ok = [self _performAction:[action objectForKey:@"action"]
                                 withArguments:action
                                     inContext:context];
                if (ok)
                {
                    @synchronized([NSUserDefaults standardUserDefaults])
                    {
                        [[[NSUserDefaults standardUserDefaults] mutableArrayValueForKey:@"lastFmQueue"] removeObject:action];
                        [[NSUserDefaults standardUserDefaults] synchronize];
                    }
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [[NSNotificationCenter defaultCenter] postNotificationName:@"actionCompleted"
                                                                            object:self
                                                                          userInfo:action];
                    });
                }
            }
            [context release];
        }
    });
}

- (BOOL) _performAction:(NSString*)action withArguments:(NSDictionary*)arguments inContext:(NSMutableDictionary*)context
{
    if ([action isEqualToString:@"scrobble"])
    {
        NSArray* recentTracks = [context objectForKey:@"recentTracks"];
        if (!recentTracks)
        {
            recentTracks = [self getRecentTracks];
            if (!recentTracks)
            {
                recentTracks = (NSArray*)[NSNull null];
            }
            [context setObject:recentTracks forKey:@"recentTracks"];
        }
        if ([recentTracks isKindOfClass:[NSNull class]])
        {
            return NO;
        }
        
        for (NSDictionary* track in recentTracks)
        {
            if ([[[track objectForKey:@"date"] objectForKey:@"uts"]
                 isEqualToString:[arguments objectForKey:@"timestamp"]])
            {
                return YES;
            }
        }
        
        return [self doScrobble:arguments];
    }
    
    if ([action isEqualToString:@"love"])
    {
        FMEngine* fmEngine = [[FMEngine alloc] init];
        NSData* reply = [fmEngine dataForMethod:@"track.love"
                                withParameters:[NSDictionary dictionaryWithObjectsAndKeys:
                                                [arguments objectForKey:@"artist"], @"artist",
                                                [arguments objectForKey:@"title"], @"track",
                                                self.sessionKey, @"sk",
                                                _LASTFM_API_KEY_, @"api_key",
                                                nil]
                                   useSignature:YES
                                     httpMethod:POST_TYPE
                                          error:nil];
        if (reply)
        {
            NSDictionary* response = [[JSONDecoder decoder] objectWithData:reply];
            if ([[response objectForKey:@"status"] isEqualToString:@"ok"])
            {
                return YES;
            }
        }
        [fmEngine release];
    }
    
    return NO;
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

- (NSArray*)getRecentTracks
{
    FMEngine* fmEngine = [[FMEngine alloc] init];
    NSData* reply = [fmEngine dataForMethod:@"user.getRecentTracks" withParameters:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                                    self.sessionKeyUsername, @"user",
                                                                                    _LASTFM_API_KEY_, @"api_key",
                                                                                    nil] useSignature:NO httpMethod:GET_TYPE error:nil];
    if (reply)
    {
        NSDictionary* recentScrobbles = [[JSONDecoder decoder] objectWithData:reply];
        NSDictionary* recentTracks = [recentScrobbles objectForKey:@"recenttracks"];
        return [recentTracks objectForKey:@"track"];
    }
    else
    {
        return nil;
    }
}

- (BOOL)doScrobble:(NSDictionary*)scrobble
{
    FMEngine* fmEngine = [[FMEngine alloc] init];
    NSData* reply = [fmEngine dataForMethod:@"track.scrobble" withParameters:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                              [scrobble objectForKey:@"artist"], @"artist",
                                                                              [scrobble objectForKey:@"title"], @"track",
                                                                              [scrobble objectForKey:@"timestamp"], @"timestamp",
                                                                              self.sessionKey, @"sk",
                                                                              _LASTFM_API_KEY_, @"api_key",
                                                                              nil] useSignature:YES httpMethod:POST_TYPE error:nil];
    if (reply)
    {
        NSDictionary* response = [[JSONDecoder decoder] objectWithData:reply];
        if ([response objectForKey:@"scrobbles"])
        {
            return YES;
        }
    }
    
    return NO;
}

@end
