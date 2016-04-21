//
//  LibraryController.m
//  3G Player
//
//  Created by Admin on 7/2/13.
//  Copyright (c) 2013 themylogin. All rights reserved.
//

#import "LibraryController.h"

#import "AppDelegate.h"
#import "Globals.h"
#import "LibraryPageController.h"
#import "SearchController.h"

#import "ASIHTTPRequest.h"
#import "ZipArchive.h"

@interface LibraryController () <UINavigationControllerDelegate>

@property (nonatomic, retain) NSDictionary* player;
@property (nonatomic, retain) NSString* libraryDirectory;

@property (nonatomic, retain) UILabel* updateLibraryProgressLabel;

@property (nonatomic, retain) NSArray* searchIndex;
@property (nonatomic, retain) SearchController* searchController;
@property (nonatomic, retain) UIViewController* searchStartController;

@end

@implementation LibraryController

- (id)initWithPlayer:(NSDictionary*)player;
{
    self = [super initWithRootViewController:[[LibraryPageController alloc]
                                              initWithPlayer:player
                                              directory:@""
                                              title:[player objectForKey:@"name"]]];
    if (self)
    {
        self.player = player;
        self.libraryDirectory = [librariesPath stringByAppendingString:
                                 [NSString stringWithFormat:@"/%@", [player objectForKey:@"name"]]];
        
        libraryRightBarButtonItem = [[UIBarButtonItem alloc]
                                     initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                     target:self
                                     action:@selector(updateLibrary)];
        
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
                                                   initWithTarget:self
                                                   action:@selector(longPress:)];
        [self.navigationBar addGestureRecognizer:longPress];
        
        [self loadSearchIndex];
        self.searchController = [[SearchController alloc] init];
        self.searchStartController = nil;
        
        self.librarySearchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width - 24, 44)];
        self.librarySearchBar.showsCancelButton = YES;
        self.librarySearchBar.placeholder = @"Search";
        self.librarySearchBar.delegate = self;
        libraryToolbarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.librarySearchBar];
        
        self.updateLibraryProgressLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 11, self.view.frame.size.width, 21)];
        self.updateLibraryProgressLabel.backgroundColor = [UIColor clearColor];
        self.updateLibraryProgressLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:12];
        self.updateLibraryProgressLabel.textColor = [UIColor whiteColor];
        self.updateLibraryProgressLabel.text = @"";
        
        self.tabBarItem.title = NSLocalizedString(@"Library", nil);
        self.tabBarItem.image = [UIImage imageNamed:@"Library"];
        
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

- (void)longPress:(UILongPressGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateBegan)
    {
        CGPoint longPressPoint = [sender locationInView:self.navigationController.navigationBar];
        
        CGRect titleRect = CGRectMake(0, 0, 0, 0);
        for (UIView* subview in self.navigationBar.subviews)
        {
            if ([NSStringFromClass(subview.class) isEqualToString:@"UINavigationItemView"])
            {
                titleRect = subview.frame;
                titleRect.size.height = 100;
            }
        }
        
        CGRect backButtonRect = CGRectMake(0, titleRect.origin.y, titleRect.origin.x, titleRect.size.height);
        
        if (CGRectContainsPoint(titleRect, longPressPoint))
        {
            [self showChangePlayerActionSheet];
        }
        
        if (CGRectContainsPoint(backButtonRect, longPressPoint))
        {
            [self popToRootViewControllerAnimated:YES];
        }
    }
}

#pragma mark - Change player

- (void)showChangePlayerActionSheet
{
    UIActionSheet* actionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Change server", nil)
                                                             delegate:self
                                                    cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:nil];

    for (int i = 0; i < players.count; i++)
    {
        [actionSheet addButtonWithTitle:[[players objectAtIndex:i] objectForKey:@"name"]];
    }
    
    actionSheet.cancelButtonIndex = 0;
    
    [actionSheet showInView:[self.view window]];
    [actionSheet release];
}

- (void)actionSheet:(UIActionSheet*)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex > 0)
    {
        [self changePlayer:[players objectAtIndex:buttonIndex - 1]];
    }
}

- (void)changePlayer:(NSDictionary*)player
{
    NSMutableArray* c = [NSMutableArray arrayWithArray:controllers.tabBar.viewControllers];
    controllers.library = [[LibraryController alloc] initWithPlayer:player];
    [c replaceObjectAtIndex:1 withObject:controllers.library];
    controllers.tabBar.viewControllers = c;
}

#pragma mark - Update library

- (void)updateLibrary
{
    [self updateLibraryWithSuccessCallback:^{}];
}

- (void)updateLibraryWithSuccessCallback:(void(^)())callback;
{
    libraryRightBarButtonItem.enabled = NO;
    
    libraryToolbarButtonItem.enabled = NO;
    libraryToolbarButtonItem.customView = self.updateLibraryProgressLabel;
    
    self.updateLibraryProgressLabel.text = @"Updating library...";
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSString* libraryFile = [self.libraryDirectory stringByAppendingString:@"/library.zip"];
        [[NSFileManager defaultManager] removeItemAtPath:libraryFile error:nil];
        
        NSString* revision;
        NSString* revisionFile = [self.libraryDirectory stringByAppendingString:@"/revision.txt"];
        if ([[NSFileManager defaultManager] isReadableFileAtPath:revisionFile])
        {
            revision = [NSString stringWithContentsOfFile:revisionFile encoding:NSUTF8StringEncoding error:nil];
        }
        else
        {
            revision = @"";
        }
        
        NSURL* libraryUrl = [NSURL URLWithString:[[self.player objectForKey:@"url"] stringByAppendingString:
                                                  [NSString stringWithFormat:@"/library?since-revision=%@", revision, nil]]];
        ASIHTTPRequest* libraryRequest = [ASIHTTPRequest requestWithURL:libraryUrl];
        [libraryRequest setShouldContinueWhenAppEntersBackground:YES];
        [libraryRequest setDownloadDestinationPath:libraryFile];
        __block unsigned long long totalBytesReceived = 0;
        [libraryRequest setBytesReceivedBlock:^(unsigned long long size, unsigned long long total) {
            totalBytesReceived += size;
            self.updateLibraryProgressLabel.text = [NSString stringWithFormat:@"Receiving library: (%.0f%%)",
                                                    (float)totalBytesReceived / total * 100, nil];
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
            [zipArchive UnzipFileTo:self.libraryDirectory overWrite:YES];
            [zipArchive UnzipCloseFile];
            [zipArchive release];
                        
            [[NSFileManager defaultManager] removeItemAtPath:libraryFile error:nil];            
            
            NSString* deleteDirectoriesFile = [self.libraryDirectory stringByAppendingString:@"/delete_directories.txt"];
            NSArray* deleteDirectories = [[NSString stringWithContentsOfFile:deleteDirectoriesFile encoding:NSASCIIStringEncoding error:nil] componentsSeparatedByString:@"\n"];
            for (NSString* directory in deleteDirectories)
            {
                if (![directory isEqualToString:@""])
                {
                    [[NSFileManager defaultManager]
                     removeItemAtPath:[self.libraryDirectory stringByAppendingString:
                                       [NSString stringWithFormat:@"/%@", directory]]
                     error:nil];
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
                    if (lastValidController)
                    {
                        [self popToViewController:lastValidController animated:YES];
                        break;
                    }
                }
            }
            
            callback();
        });
    });
}

#pragma mark - Navigate to item

- (void)navigateToItem:(NSDictionary*)item enter:(BOOL)enter
{
    if (![[[item objectForKey:@"player"] objectForKey:@"libraryPath"]
          isEqualToString:[self.player objectForKey:@"libraryPath"]])
    {
        [self changePlayer:[item objectForKey:@"player"]];
        [controllers.library navigateToItem:item enter:enter];
        return;
    }
    
    NSMutableArray* libraryControllers = [[NSMutableArray alloc] init];
    NSMutableArray* scrollTargets = [[NSMutableArray alloc] init];
    
    NSString* basePath = [librariesPath stringByAppendingString:
                          [[item objectForKey:@"player"] objectForKey:@"libraryPath"]];
    NSString* parent = [musicFileManager absolutePath:item];
    NSDictionary* scrollTarget = item;
    while (![(parent = [parent stringByDeletingLastPathComponent]) isEqualToString:basePath])
    {
        NSDictionary* parentItem = [musicFileManager itemForAbsolutePath:parent];
        if (parentItem != nil)
        {
            LibraryPageController* controller = [[LibraryPageController alloc]
                                                 initWithPlayer:[parentItem objectForKey:@"player"]
                                                 directory:[parentItem objectForKey:@"path"]
                                                 title:[parentItem objectForKey:@"name"]];
            [libraryControllers insertObject:controller atIndex:0];
            [scrollTargets insertObject:scrollTarget atIndex:0];
            scrollTarget = parentItem;
        }
    }
    
    [controllers.library popToRootViewControllerAnimated:NO];
    for (int i = 0; i < [libraryControllers count]; i++)
    {
        [controllers.library pushViewController:[libraryControllers objectAtIndex:i] animated:NO];
    }
    AppDelegate* delegate = (AppDelegate*)[[UIApplication sharedApplication] delegate];
    [delegate.tabBarController setSelectedViewController:controllers.library];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (int i = 0; i < [libraryControllers count]; i++)
        {
            [[libraryControllers objectAtIndex:i] scrollToItem:[scrollTargets objectAtIndex:i]];
        }
    });
    
    if (enter && [musicTableService isDirectory:item])
    {
        LibraryPageController* controller = [[LibraryPageController alloc]
                                             initWithPlayer:[item objectForKey:@"player"]
                                             directory:[item objectForKey:@"path"]
                                             title:[item objectForKey:@"name"]];
        [controllers.library pushViewController:controller animated:NO];
    }
}

#pragma mark - Search

- (void)loadSearchIndex
{
    NSString* searchJsonPath = [self.libraryDirectory stringByAppendingString:@"/search.json"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:searchJsonPath])
    {
        self.searchIndex = [NSJSONSerialization
                            JSONObjectWithData:[NSData dataWithContentsOfFile:searchJsonPath]
                            options:0
                            error:nil];
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
                NSMutableDictionary* item = [self.searchIndex[i][@"item"] mutableCopy];
                item[@"player"] = self.player;
                [results addObject:item];
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
