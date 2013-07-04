//
//  LibraryController.m
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "LibraryController.h"

#import "Globals.h"
#import "LibraryPageController.h"

#import "ASIFormDataRequest.h"
#import "LFCGzipUtility.h"
#import "ZipArchive.h"

@interface LibraryController ()

@end

@implementation LibraryController

- (id)init
{
    self = [super initWithRootViewController:[[LibraryPageController alloc] initWithDirectory:@"" title:NSLocalizedString(@"Library", @"Library")]];
    if (self)
    {
        updateLibraryButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(updateLibrary)];
        
        self.tabBarItem.title = NSLocalizedString(@"Library", nil);
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)updateLibrary
{
    [updateLibraryButton setEnabled:NO];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSMutableArray* clientDirectories = [[NSMutableArray alloc] init];
        NSDirectoryEnumerator* de = [[NSFileManager defaultManager] enumeratorAtPath:libraryDirectory];
        while (true)
        {
            NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
            
            NSString* file = [de nextObject];
            if (!file)
            {
                break;
            }
            
            if ([[[file pathComponents] lastObject] isEqualToString:@"index.json"])
            {
                NSMutableArray* dirComponents = [[file pathComponents] mutableCopy];
                [dirComponents removeLastObject];
                NSString* dir = [dirComponents componentsJoinedByString:@"/"];
                [dirComponents release];
                    
                NSString* checksum = [NSString stringWithContentsOfFile:[[[libraryDirectory stringByAppendingString:@"/"] stringByAppendingString:file] stringByAppendingString:@".checksum"] encoding:NSASCIIStringEncoding error:nil];
                    
                [clientDirectories addObject:[NSString stringWithFormat:@"%@ %@", dir, checksum, nil]];
            }
            
            [pool drain];
        }
        
        NSData* compressedClientDirectories = [LFCGzipUtility gzipData:[[clientDirectories componentsJoinedByString:@"\n"] dataUsingEncoding:NSASCIIStringEncoding]];
        [clientDirectories release];
        
        NSString* libraryFile = [libraryDirectory stringByAppendingString:@"/library.zip"];
        [[NSFileManager defaultManager] removeItemAtPath:libraryFile error:nil];
        
        NSURL* url = [NSURL URLWithString:[playerUrl stringByAppendingString:@"/library"]];
        ASIFormDataRequest* request = [ASIFormDataRequest requestWithURL:url];
        [request setData:compressedClientDirectories withFileName:@"client_directories.txt" andContentType:@"text/plain" forKey:@"library"];
        [request setDownloadDestinationPath:libraryFile];
        [request setTimeOutSeconds:3600.0];
        [request startSynchronous];
        if ([request error] || [request responseStatusCode] != 200)
        {
            NSString* errorDescription;
            if ([request error])
            {
                errorDescription = [[request error] localizedDescription];
            }
            else
            {
                errorDescription = [request responseStatusMessage];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertView* alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Library update error", nil)
                                                                message:errorDescription
                                                               delegate:nil
                                                      cancelButtonTitle:NSLocalizedString(@"OK", nil)
                                                      otherButtonTitles:nil];
                [alert show];
            });
        }
        else
        {
            ZipArchive* zipArchive = [[ZipArchive alloc] init];
            [zipArchive UnzipOpenFile:libraryFile];
            [zipArchive UnzipFileTo:libraryDirectory overWrite:YES];
            [zipArchive UnzipCloseFile];
            [zipArchive release];
                        
            [[NSFileManager defaultManager] removeItemAtPath:libraryFile error:nil];            
            
            NSString* deleteDirectoriesFile = [libraryDirectory stringByAppendingString:@"/delete_directories.txt"];
            NSArray* deleteDirectories = [[NSString stringWithContentsOfFile:deleteDirectoriesFile encoding:NSASCIIStringEncoding error:nil] componentsSeparatedByString:@"\n"];
            for (NSString* directory in deleteDirectories)
            {
                if (![directory isEqualToString:@""])
                {
                    [[NSFileManager defaultManager] removeItemAtPath:[[libraryDirectory stringByAppendingString:@"/"] stringByAppendingString:directory] error:nil];                    
                }
            }
            [[NSFileManager defaultManager] removeItemAtPath:deleteDirectoriesFile error:nil];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [updateLibraryButton setEnabled:YES];
            
            LibraryPageController* lastValidController = nil;
            for (LibraryPageController* controller in [self viewControllers])
            {
                if ([controller update])
                {
                    lastValidController = controller;
                }
                else
                {
                    [self popToViewController:lastValidController animated:YES];
                    break;
                }
            }
        });
    });
}

@end
