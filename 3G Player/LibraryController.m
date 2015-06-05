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
#import "JSONKit.h"
#import "ZipArchive.h"

@interface LibraryController ()

@property (nonatomic, retain) UILabel* updateLibraryProgressLabel;

@end

@implementation LibraryController

- (id)initWithRoot
{
    self = [super initWithRootViewController:[[LibraryPageController alloc] initWithDirectory:@"" title:NSLocalizedString(@"Library", @"Library")]];
    if (self)
    {
        updateLibraryButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(updateLibrary)];
        
        self.updateLibraryProgressLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 11.0, self.view.frame.size.width, 21.0f)];
        self.updateLibraryProgressLabel.backgroundColor = [UIColor clearColor];
        self.updateLibraryProgressLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:12];
        self.updateLibraryProgressLabel.textColor = [UIColor whiteColor];
        self.updateLibraryProgressLabel.text = @"";
        updateLibraryProgress = [[UIBarButtonItem alloc] initWithCustomView:self.updateLibraryProgressLabel];
        updateLibraryProgress.enabled = NO;
        
        self.tabBarItem.title = NSLocalizedString(@"Library", nil);
        self.tabBarItem.image = [UIImage imageNamed:@"tabbar_library.png"];
        
        self.toolbar.tintColor = [UIColor colorWithRed:43.0 / 255 green:43.0 / 255 blue:43.0 / 255 alpha:0.5];
        self.toolbarHidden = YES;
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
    [self updateLibraryWithSuccessCallback:^{}];
}

- (void)updateLibraryWithSuccessCallback:(void(^)())callback;
{
    updateLibraryButton.enabled = NO;
    self.updateLibraryProgressLabel.text = @"Updating";
    self.toolbarHidden = NO;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSString* libraryFile = [libraryDirectory stringByAppendingString:@"/library.zip"];
        [[NSFileManager defaultManager] removeItemAtPath:libraryFile error:nil];
        
        NSString* revision;
        NSString* revisionFile = [libraryDirectory stringByAppendingString:@"/revision.txt"];
        if ([[NSFileManager defaultManager] isReadableFileAtPath:revisionFile])
        {
            revision = [NSString stringWithContentsOfFile:revisionFile encoding:NSUTF8StringEncoding error:nil];
        }
        else
        {
            revision = @"";
        }
        
        NSURL* libraryUrl = [NSURL URLWithString:[playerUrl stringByAppendingString:[NSString stringWithFormat:@"/library?revision=%@", revision, nil]]];
        ASIFormDataRequest* libraryRequest = [ASIFormDataRequest requestWithURL:libraryUrl];
        [libraryRequest setShouldContinueWhenAppEntersBackground:YES];
        [libraryRequest setDownloadDestinationPath:libraryFile];
        [libraryRequest setBytesSentBlock:^(unsigned long long size, unsigned long long total) {
            self.updateLibraryProgressLabel.text = [NSString stringWithFormat:@"Sending library request: (%.0f%%)", (float)size / total * 100, nil];
        }];
        [libraryRequest setBytesReceivedBlock:^(unsigned long long size, unsigned long long total) {
            self.updateLibraryProgressLabel.text = [NSString stringWithFormat:@"Receiving library: (%.0f%%)", (float)size / total * 100, nil];
        }];
        [libraryRequest setTimeOutSeconds:120];
        [libraryRequest startSynchronous];
        if ([libraryRequest error] || [libraryRequest responseStatusCode] != 200)
        {
            NSString* errorDescription;
            if ([libraryRequest error])
            {
                errorDescription = [[libraryRequest error] localizedDescription];
            }
            else
            {
                errorDescription = [libraryRequest responseStatusMessage];
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
            dispatch_async(dispatch_get_main_queue(), ^{
                self.updateLibraryProgressLabel.text = [NSString stringWithFormat:@"Unpacking"];
            });
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
            updateLibraryButton.enabled = YES;
            self.toolbarHidden = YES;
            
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
            
            callback();
        });
    });
}

@end
