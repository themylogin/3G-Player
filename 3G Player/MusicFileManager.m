//
//  MusicFileManager.m
//  3G Player
//
//  Created by Admin on 7/4/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "MusicFileManager.h"

#import "Globals.h"

@interface MusicFileManager ()

@property (nonatomic, retain) NSFileManager*        fileManager;
@property (nonatomic, retain) NSNotificationCenter* notificationCenter;

@property (nonatomic, retain) NSDictionary*     bufferingFile;
@property (nonatomic)         bool              bufferingIsError;
@property (nonatomic)         uint              bufferingExpectedLength;

@property (nonatomic, retain) NSURLConnection*  bufferingConnection;
@property (nonatomic, retain) NSFileHandle*     bufferingFileHandle;

@end

@implementation MusicFileManager

- (id)init
{
    self.fileManager = [NSFileManager defaultManager];
    self.notificationCenter = [NSNotificationCenter defaultCenter];
    
    self.bufferingFile = nil;
    self.bufferingIsError = false;
    self.bufferingExpectedLength = 0;
    
    self.bufferingConnection = nil;
    self.bufferingFileHandle = nil;
    
    return self;
}

- (MusicFileState)getState:(NSDictionary*)musicFile
{
    MusicFileState state;
    if ([self.fileManager fileExistsAtPath:[self filePath:musicFile]])
    {
        state.state = Buffered;
    }
    else if (self.bufferingFile && [[self.bufferingFile objectForKey:@"path"] isEqualToString:[musicFile objectForKey:@"path"]])
    {
        state.state = Buffering;
        
        NSString* incompletePath = [self incompleteFilePath:musicFile];
        unsigned long long fileSize = 0;
        if ([self.fileManager fileExistsAtPath:incompletePath])
        {
            fileSize = [[self.fileManager attributesOfItemAtPath:incompletePath error:nil] fileSize];
        }
        if (self.bufferingExpectedLength > 0 && fileSize > 0)
        {
            state.buffering.progress = (float)fileSize / (float)self.bufferingExpectedLength;
        }
        else
        {
            state.buffering.progress = 0.0;
        }
        
        state.buffering.isError = self.bufferingIsError;
    }
    else
    {
        state.state = NotBuffered;
    }
    return state;
}

- (void)buffer:(NSDictionary*)musicFile
{    
    if (self.bufferingFile)
    {
        if ([[self.bufferingFile objectForKey:@"path"] isEqualToString:[musicFile objectForKey:@"path"]])
        {
            return;
        }
        else
        {            
            [self stopBufferingConnection];
        }
    }
    
    self.bufferingFile = musicFile;
    self.bufferingIsError = false;
    self.bufferingExpectedLength = 0;
    
    [self startBufferingConnection:musicFile];    
    
    [self notifyStateChanged];
}

- (void)stopBuffering
{
    if (self.bufferingFile)
    {
        [self stopBufferingConnection];
        
        self.bufferingFile = nil;
        self.bufferingIsError = false;
        self.bufferingExpectedLength = 0;
        
        [self notifyStateChanged];
    }
}

- (void)startBufferingConnection:(NSDictionary*)musicFile
{
    [self stopBufferingConnection];
    
    NSString* url = [[playerUrl stringByAppendingString:@"/file?path="] stringByAppendingString:[musicFile objectForKey:@"url"]];
    NSString* incompletePath = [self incompleteFilePath:musicFile];
    if ([self.fileManager fileExistsAtPath:incompletePath])
    {
        unsigned long long fileSize = [[self.fileManager attributesOfItemAtPath:incompletePath error:nil] fileSize];
        if (fileSize > 0)
        {
            url = [url stringByAppendingFormat:@"&content_offset=%llu", fileSize];
        }
    }
    else
    {
        [self.fileManager createFileAtPath:incompletePath contents:nil attributes:nil];
    }
    
    self.bufferingFileHandle = [NSFileHandle fileHandleForWritingAtPath:incompletePath];
    [self.bufferingFileHandle seekToEndOfFile];
    
    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:15.0];
    self.bufferingConnection = [NSURLConnection connectionWithRequest:request delegate:self];
}

- (void)stopBufferingConnection
{
    if (self.bufferingConnection)
    {
        [self.bufferingConnection cancel];
        self.bufferingConnection = nil;
    }
    
    if (self.bufferingFileHandle)
    {
        [self.bufferingFileHandle closeFile];
        self.bufferingFileHandle = nil;
    }
}

#pragma mark - NSURLConnection delegate

- (void)connection:(NSURLConnection*)connection didFailWithError:(NSError *)error
{
    self.bufferingIsError = true;    
    [self performSelector:@selector(startBufferingConnection:) withObject:self.bufferingFile afterDelay:5.0];    
    
    [self notifyStateChanged];
}

- (void)connection:(NSURLConnection*)connection didReceiveResponse:(NSURLResponse *)response
{
    NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
    if ([httpResponse statusCode] != 200)
    {        
        self.bufferingIsError = true;
        [self performSelector:@selector(startBufferingConnection:) withObject:self.bufferingFile afterDelay:5.0];
    }
    else
    {
        self.bufferingIsError = false;
        self.bufferingExpectedLength = [[[httpResponse allHeaderFields] objectForKey:@"X-Expected-Content-Length"] intValue];
    }
    
    [self notifyStateChanged];
}

- (void)connection:(NSURLConnection*)connection didReceiveData:(NSData *)data
{
    [self.bufferingFileHandle writeData:data];
    
    [self notifyStateChanged];
}

- (void)connectionDidFinishLoading:(NSURLConnection*)connection
{
    if (self.bufferingConnection)
    {
        [self.bufferingConnection cancel];
        self.bufferingConnection = nil;
    }
    if (self.bufferingFileHandle)
    {
        [self.bufferingFileHandle closeFile];
        self.bufferingFileHandle = nil;
    }
    
    [self.fileManager moveItemAtPath:[self incompleteFilePath:self.bufferingFile] toPath:[self filePath:self.bufferingFile] error:nil];
    
    self.bufferingFile = nil;
    self.bufferingIsError = false;
    self.bufferingExpectedLength = 0;
    
    [self notifyStateChanged];
    [self notifyBufferingCompleted];
}

#pragma mark - Internals

- (NSString*)filePath:(NSDictionary*)musicFile
{
    return [[libraryDirectory stringByAppendingString:@"/"] stringByAppendingString:[musicFile objectForKey:@"path"]];
}

- (NSString*)incompleteFilePath:(NSDictionary*)musicFile
{
    return [[self filePath:musicFile] stringByAppendingString:@".incomplete"];
}

- (void)notifyStateChanged
{
    [self.notificationCenter postNotificationName:@"stateChanged" object:self];
}

- (void)notifyBufferingCompleted
{
    [self.notificationCenter postNotificationName:@"bufferingCompleted" object:self];
}

@end
