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
#import "SearchController.h"

#import "ASIFormDataRequest.h"
#import "JSONKit.h"
#import "ZipArchive.h"

@interface LibraryController () <UINavigationControllerDelegate>

@property (nonatomic, retain) UILabel* updateLibraryProgressLabel;
@property (nonatomic, retain) NSArray* searchIndex;
@property (nonatomic, retain) SearchController* searchController;
@property (nonatomic, retain) UIViewController* searchStartController;

@end

@implementation LibraryController

- (id)initWithRoot
{
    self = [super initWithRootViewController:[[LibraryPageController alloc] initWithDirectory:@"" title:NSLocalizedString(@"Library", @"Library")]];
    if (self)
    {
        [self loadSearchIndex];
        self.searchController = [[SearchController alloc] init];
        self.searchStartController = nil;
        
        libraryRightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(updateLibrary)];
        
        self.librarySearchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width - 24, 44)];
        self.librarySearchBar.showsCancelButton = YES;
        self.librarySearchBar.delegate = self;
        
        self.updateLibraryProgressLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 11.0, self.view.frame.size.width, 21.0)];
        self.updateLibraryProgressLabel.backgroundColor = [UIColor clearColor];
        self.updateLibraryProgressLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:12];
        self.updateLibraryProgressLabel.textColor = [UIColor whiteColor];
        self.updateLibraryProgressLabel.text = @"";
        
        libraryToolbarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.librarySearchBar];
        
        self.tabBarItem.title = NSLocalizedString(@"Library", nil);
        self.tabBarItem.image = [UIImage imageNamed:@"tabbar_library.png"];
        
        self.toolbar.tintColor = [UIColor colorWithRed:43.0 / 255 green:43.0 / 255 blue:43.0 / 255 alpha:0.5];
        self.toolbarHidden = NO;
        
        self.delegate = self;
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
    libraryRightBarButtonItem.enabled = NO;
    
    libraryToolbarButtonItem.enabled = NO;
    libraryToolbarButtonItem.customView = self.updateLibraryProgressLabel;
    
    self.updateLibraryProgressLabel.text = @"Updating";
    
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
            libraryRightBarButtonItem.enabled = YES;
            
            libraryToolbarButtonItem.enabled = YES;
            libraryToolbarButtonItem.customView = self.librarySearchBar;
            
            [self loadSearchIndex];
            
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

- (void)loadSearchIndex
{
    NSString* searchJsonPath = [libraryDirectory stringByAppendingString:@"/search.json"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:searchJsonPath])
    {
        self.searchIndex = [[JSONDecoder decoder] objectWithData:[NSData dataWithContentsOfFile:searchJsonPath]];
    }
    else
    {
        self.searchIndex = [NSArray array];
    }
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [self stopSearch];
    
    if (self.searchStartController)
    {
        if ([self.viewControllers containsObject:self.searchStartController])
        {
            [self popToViewController:self.searchStartController animated:YES];
        }
        else
        {
            [self popToRootViewControllerAnimated:YES];
        }
        self.searchStartController = nil;
    }
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    searchText = [searchText lowercaseString];
    searchText = [searchText stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    NSMutableArray* results = [NSMutableArray arrayWithCapacity:100];
    if (![searchText isEqualToString:@""])
    {
        for (int i = 0; i < self.searchIndex.count; i++)
        {
            if ([self.searchIndex[i][@"key"] hasPrefix:searchText])
            {
                [results addObject:self.searchIndex[i][@"item"]];
                if (results.count == 100)
                {
                    break;
                }
            }
        }
    }
    [self.searchController setSearchQuery:searchText results:results];
    
    if ([self.viewControllers lastObject] != self.searchController)
    {
        self.searchStartController = [self.viewControllers lastObject];
    }
    
    if ([self.viewControllers containsObject:self.searchController])
    {
        [self popToViewController:self.searchController animated:NO];
    }
    else
    {
        [self pushViewController:self.searchController animated:NO];
    }
}

- (void)stopSearch
{
    self.librarySearchBar.text = @"";
    [self.librarySearchBar resignFirstResponder];
    [self.view endEditing:YES];
}


- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(nonnull UIViewController *)viewController animated:(BOOL)animated
{
    if (viewController != self.searchController)
    {
        [self stopSearch];
    }
}

@end
